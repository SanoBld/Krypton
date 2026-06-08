import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// KryptonLogger
//
// Lightweight structured logger for Krypton.
//   • Five severity levels: verbose / debug / info / warning / error
//   • In-memory ring buffer (last 500 entries) for live log viewer
//   • Optional persistent log file written to getApplicationSupportDirectory()
//   • Broadcast stream so UI widgets can reactively display new entries
//   • Release builds suppress verbose/debug output automatically
// ─────────────────────────────────────────────────────────────────────────────

// ── Log level ─────────────────────────────────────────────────────────────────

enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error;

  String get label {
    switch (this) {
      case LogLevel.verbose:
        return 'V';
      case LogLevel.debug:
        return 'D';
      case LogLevel.info:
        return 'I';
      case LogLevel.warning:
        return 'W';
      case LogLevel.error:
        return 'E';
    }
  }

  /// ANSI color codes for terminal output (debug builds only).
  String get ansiColor {
    switch (this) {
      case LogLevel.verbose:
        return '\x1B[37m'; // white
      case LogLevel.debug:
        return '\x1B[36m'; // cyan
      case LogLevel.info:
        return '\x1B[32m'; // green
      case LogLevel.warning:
        return '\x1B[33m'; // yellow
      case LogLevel.error:
        return '\x1B[31m'; // red
    }
  }

  static const String _reset = '\x1B[0m';
}

// ── Log entry ─────────────────────────────────────────────────────────────────

class LogEntry {
  const LogEntry({
    required this.level,
    required this.tag,
    required this.message,
    required this.timestamp,
    this.error,
    this.stackTrace,
  });

  final LogLevel level;

  /// Source identifier, e.g. "DownloadController", "ProcessRunner".
  final String tag;
  final String message;
  final DateTime timestamp;
  final Object? error;
  final StackTrace? stackTrace;

  String get formattedTime {
    final DateTime t = timestamp;
    final String h  = t.hour.toString().padLeft(2, '0');
    final String m  = t.minute.toString().padLeft(2, '0');
    final String s  = t.second.toString().padLeft(2, '0');
    final String ms = t.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// Single-line representation written to log file and console.
  String toLogLine() {
    final StringBuffer buf = StringBuffer();
    buf.write('${level.label}/$formattedTime [$tag] $message');
    if (error != null) buf.write(' | error: $error');
    if (stackTrace != null) buf.write('\n$stackTrace');
    return buf.toString();
  }

  @override
  String toString() => toLogLine();
}

// ── Logger ───────────────────────────────────────────────────────────────────

class KryptonLogger {
  KryptonLogger._();
  static final KryptonLogger instance = KryptonLogger._();

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Minimum level to process. Entries below this level are silently dropped.
  LogLevel minimumLevel = kReleaseMode ? LogLevel.info : LogLevel.verbose;

  /// Maximum number of entries kept in the in-memory buffer.
  static const int _ringBufferCapacity = 500;

  /// Whether to write entries to a persistent log file.
  bool persistToFile = !kReleaseMode;

  // ── Internal state ─────────────────────────────────────────────────────────

  final List<LogEntry> _buffer = [];
  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();

  IOSink? _fileSink;
  bool _fileReady = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Broadcast stream of all log entries. Safe to listen from UI widgets.
  Stream<LogEntry> get stream => _controller.stream;

  /// Immutable snapshot of the current in-memory ring buffer.
  List<LogEntry> get entries => List.unmodifiable(_buffer);

  /// Initializes the file sink. Call once during app startup (after
  /// WidgetsFlutterBinding.ensureInitialized()).
  Future<void> init() async {
    if (!persistToFile) return;
    try {
      final Directory dir = await getApplicationSupportDirectory();
      final File file = File('${dir.path}/krypton.log');
      _fileSink = file.openWrite(mode: FileMode.append);
      _fileReady = true;
      i('KryptonLogger', 'Log file ready: ${file.path}');
    } catch (e) {
      // File logging is non-critical; continue without it.
      _fileReady = false;
    }
  }

  /// Flushes and closes the file sink. Call during app shutdown.
  Future<void> dispose() async {
    await _fileSink?.flush();
    await _fileSink?.close();
    await _controller.close();
  }

  // ── Convenience methods ────────────────────────────────────────────────────

  void v(String tag, String message) =>
      _log(LogLevel.verbose, tag, message);

  void d(String tag, String message) =>
      _log(LogLevel.debug, tag, message);

  void i(String tag, String message) =>
      _log(LogLevel.info, tag, message);

  void w(String tag, String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.warning, tag, message,
          error: error, stackTrace: stackTrace);

  void e(String tag, String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.error, tag, message,
          error: error, stackTrace: stackTrace);

  // ── Buffer management ─────────────────────────────────────────────────────

  /// Clears all entries from the in-memory buffer.
  void clearBuffer() => _buffer.clear();

  /// Returns all entries filtered by [level] and optional [tag].
  List<LogEntry> filter({LogLevel? level, String? tag}) {
    return _buffer.where((e) {
      final bool levelMatch = level == null || e.level == level;
      final bool tagMatch =
          tag == null || e.tag.toLowerCase().contains(tag.toLowerCase());
      return levelMatch && tagMatch;
    }).toList();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minimumLevel.index) return;

    final LogEntry entry = LogEntry(
      level:      level,
      tag:        tag,
      message:    message,
      timestamp:  DateTime.now(),
      error:      error,
      stackTrace: stackTrace,
    );

    // Ring buffer — evict oldest when at capacity.
    if (_buffer.length >= _ringBufferCapacity) {
      _buffer.removeAt(0);
    }
    _buffer.add(entry);

    // Broadcast to listeners.
    if (!_controller.isClosed) {
      _controller.add(entry);
    }

    // Console output (debug builds only).
    if (kDebugMode) {
      final String colored =
          '${level.ansiColor}${entry.toLogLine()}${LogLevel._reset}';
      // ignore: avoid_print
      print(colored);
    }

    // File output.
    if (_fileReady && _fileSink != null) {
      _fileSink!.writeln(entry.toLogLine());
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Global accessor
// ─────────────────────────────────────────────────────────────────────────────

/// Global singleton accessor for convenience.
///
/// Usage:
/// ```dart
/// logger.i('MyWidget', 'Screen loaded');
/// logger.e('Converter', 'FFmpeg failed', error: e, stackTrace: st);
/// ```
KryptonLogger get logger => KryptonLogger.instance;

// ─────────────────────────────────────────────────────────────────────────────
// LogViewerWidget
//
// Lightweight live log viewer widget.
// Drop into a settings debug panel or a dedicated diagnostics screen.
// ─────────────────────────────────────────────────────────────────────────────

class LogViewerWidget extends StatefulWidget {
  const LogViewerWidget({super.key});

  @override
  State<LogViewerWidget> createState() => _LogViewerWidgetState();
}

class _LogViewerWidgetState extends State<LogViewerWidget> {
  final ScrollController _scroll = ScrollController();
  late final List<LogEntry> _entries;

  // Level filter; null = show all.
  LogLevel? _filterLevel;

  @override
  void initState() {
    super.initState();
    _entries = List.of(logger.entries);

    // Subscribe to new entries in real time.
    logger.stream.listen((entry) {
      if (!mounted) return;
      setState(() => _entries.add(entry));
      // Auto-scroll to bottom.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    final List<LogEntry> visible = _filterLevel == null
        ? _entries
        : _entries.where((e) => e.level == _filterLevel).toList();

    return Column(
      children: [
        // ── Filter chips ─────────────────────────────────────────────────────
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _chip('ALL', null, cs),
              ...LogLevel.values.map((l) => _chip(l.label, l, cs)),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── Log list ─────────────────────────────────────────────────────────
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    'No log entries',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(8),
                  itemCount: visible.length,
                  itemBuilder: (_, i) => _LogLine(entry: visible[i]),
                ),
        ),
        // ── Actions ───────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() {
                  _entries.clear();
                  logger.clearBuffer();
                }),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, LogLevel? level, ColorScheme cs) {
    final bool selected = _filterLevel == level;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filterLevel = level),
        selectedColor: cs.primaryContainer,
        labelStyle: TextStyle(
          fontSize: 12,
          color: selected ? cs.onPrimaryContainer : cs.onSurface,
        ),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});
  final LogEntry entry;

  Color _levelColor(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    switch (entry.level) {
      case LogLevel.verbose:
        return cs.onSurface.withValues(alpha: 0.4);
      case LogLevel.debug:
        return cs.tertiary;
      case LogLevel.info:
        return cs.primary;
      case LogLevel.warning:
        return Colors.amber;
      case LogLevel.error:
        return cs.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _levelColor(context);
    final TextTheme tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Level badge.
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:        color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.level.label,
              style: TextStyle(
                fontSize:   10,
                fontWeight: FontWeight.bold,
                color:      color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Timestamp.
          Text(
            entry.formattedTime,
            style: tt.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color:      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize:   10,
            ),
          ),
          const SizedBox(width: 6),
          // Tag.
          Text(
            '[${entry.tag}]',
            style: tt.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color:      color.withValues(alpha: 0.8),
              fontSize:   10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          // Message.
          Expanded(
            child: Text(
              entry.message + (entry.error != null ? ' — ${entry.error}' : ''),
              style: tt.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize:   10,
                color:      Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}