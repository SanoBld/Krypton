import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// ProcessRunner
//
// Central wrapper around dart:io Process for spawning yt-dlp and FFmpeg
// binaries. Provides:
//   • Streaming stdout/stderr lines via broadcast StreamController
//   • Progress parsing helpers (FFmpeg time= / yt-dlp [download] %)
//   • Cancellation via process.kill()
//   • Structured result type [ProcessResult]
// ─────────────────────────────────────────────────────────────────────────────

// ── Result ───────────────────────────────────────────────────────────────────

/// Outcome of a completed process execution.
class ProcessResult {
  const ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// True when the process exited cleanly.
  bool get success => exitCode == 0;

  @override
  String toString() =>
      'ProcessResult(exitCode: $exitCode, success: $success)';
}

// ── Progress event ────────────────────────────────────────────────────────────

/// Parsed progress event emitted during a long-running process.
class ProcessProgress {
  const ProcessProgress({
    required this.rawLine,
    this.percent,
    this.speed,
    this.eta,
  });

  /// Original unparsed line from stdout/stderr.
  final String rawLine;

  /// Download or encode completion percentage [0.0 – 1.0], if parsed.
  final double? percent;

  /// Transfer or encode speed as a human-readable string (e.g. "2.3 MiB/s").
  final String? speed;

  /// Estimated time remaining as a human-readable string (e.g. "00:01:23").
  final String? eta;
}

// ── Exceptions ────────────────────────────────────────────────────────────────

/// Thrown when a required binary (yt-dlp / ffmpeg) is not found on PATH.
class BinaryNotFoundException implements Exception {
  const BinaryNotFoundException(this.binary);
  final String binary;

  @override
  String toString() =>
      'BinaryNotFoundException: "$binary" was not found on PATH. '
      'Please install it and ensure it is accessible.';
}

/// Thrown when a process exits with a non-zero code and [throwOnError] is true.
class ProcessException implements Exception {
  const ProcessException({
    required this.binary,
    required this.exitCode,
    required this.stderr,
  });

  final String binary;
  final int exitCode;
  final String stderr;

  @override
  String toString() =>
      'ProcessException: "$binary" exited with code $exitCode.\n$stderr';
}

// ── Runner ───────────────────────────────────────────────────────────────────

class ProcessRunner {
  ProcessRunner._();
  static final ProcessRunner instance = ProcessRunner._();

  // Active process handle; kept for cancellation support.
  Process? _activeProcess;

  // ── Binary resolution ──────────────────────────────────────────────────────

  /// Returns the resolved executable path for [binary].
  /// On Windows, appends ".exe" when no explicit extension is present.
  /// Throws [BinaryNotFoundException] if the binary cannot be located.
  Future<String> resolveBinary(String binary) async {
    final String exe =
        Platform.isWindows && !binary.contains('.') ? '$binary.exe' : binary;

    // 1. Check if already an absolute path.
    if (File(exe).existsSync()) return exe;

    // 2. Walk PATH entries.
    final String? pathEnv = Platform.environment['PATH'];
    if (pathEnv != null) {
      final List<String> dirs = pathEnv.split(Platform.isWindows ? ';' : ':');
      for (final String dir in dirs) {
        final File candidate = File('$dir${Platform.pathSeparator}$exe');
        if (candidate.existsSync()) return candidate.path;
      }
    }

    throw BinaryNotFoundException(binary);
  }

  /// Verifies that [binary] is available on the system.
  Future<bool> isBinaryAvailable(String binary) async {
    try {
      await resolveBinary(binary);
      return true;
    } on BinaryNotFoundException {
      return false;
    }
  }

  // ── Core execution ─────────────────────────────────────────────────────────

  /// Runs [binary] with [args] and returns a [ProcessResult].
  ///
  /// - [workingDirectory]: working dir for the subprocess.
  /// - [environment]: additional env variables merged with the system env.
  /// - [throwOnError]: if true, throws [ProcessException] on non-zero exit.
  Future<ProcessResult> run(
    String binary,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool throwOnError = false,
  }) async {
    final String resolved = await resolveBinary(binary);

    final ProcessResult result = await _runProcess(
      resolved,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );

    if (throwOnError && !result.success) {
      throw ProcessException(
        binary: binary,
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }

    return result;
  }

  /// Runs [binary] with [args] and streams stdout/stderr line-by-line.
  ///
  /// Returns a [Stream] of [ProcessProgress] events. The stream closes when
  /// the process exits. Use [cancel] to terminate early.
  ///
  /// Automatically parses yt-dlp `[download] X%` and FFmpeg `time=` lines
  /// into structured [ProcessProgress] objects.
  Stream<ProcessProgress> stream(
    String binary,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async* {
    final String resolved = await resolveBinary(binary);

    final Process process = await Process.start(
      resolved,
      args,
      workingDirectory: workingDirectory,
      environment: {
        ...Platform.environment,
        if (environment != null) ...environment,
      },
      runInShell: false,
    );

    _activeProcess = process;

    // Merge stdout and stderr into a single ordered stream.
    final StreamController<String> lines = StreamController<String>();

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(lines.add, onDone: () {});

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(lines.add);

    await for (final String line in lines.stream) {
      yield _parseLine(line);
    }

    await process.exitCode;
    _activeProcess = null;
  }

  // ── Cancellation ──────────────────────────────────────────────────────────

  /// Kills the currently active streaming process, if any.
  void cancel() {
    _activeProcess?.kill(ProcessSignal.sigterm);
    _activeProcess = null;
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  /// Internal blocking runner that collects stdout and stderr into strings.
  Future<ProcessResult> _runProcess(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final Process process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: {
        ...Platform.environment,
        if (environment != null) ...environment,
      },
      runInShell: false,
    );

    final List<String> stdoutLines = [];
    final List<String> stderrLines = [];

    await Future.wait([
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(stdoutLines.add),
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(stderrLines.add),
    ]);

    final int code = await process.exitCode;

    return ProcessResult(
      exitCode: code,
      stdout: stdoutLines.join('\n'),
      stderr: stderrLines.join('\n'),
    );
  }

  // ── Progress parsers ───────────────────────────────────────────────────────

  /// Attempts to parse known progress formats from a raw output line.
  ProcessProgress _parseLine(String line) {
    // yt-dlp format: [download]  42.3% of 128.00MiB at 2.30MiB/s ETA 00:50
    final Match? ytdlp = _ytdlpProgressRegex.firstMatch(line);
    if (ytdlp != null) {
      return ProcessProgress(
        rawLine: line,
        percent: double.tryParse(ytdlp.group(1) ?? '') != null
            ? double.parse(ytdlp.group(1)!) / 100.0
            : null,
        speed: ytdlp.group(2),
        eta: ytdlp.group(3),
      );
    }

    // FFmpeg format: frame=  120 fps= 25 ... time=00:00:04.80 bitrate=...
    final Match? ffmpeg = _ffmpegProgressRegex.firstMatch(line);
    if (ffmpeg != null) {
      return ProcessProgress(
        rawLine: line,
        eta: ffmpeg.group(1), // "time=" value used as progress indicator
      );
    }

    return ProcessProgress(rawLine: line);
  }

  // yt-dlp: capture percent, speed, eta
  static final RegExp _ytdlpProgressRegex = RegExp(
    r'\[download\]\s+([\d.]+)%.*?at\s+([\d.]+\s*\w+/s)\s+ETA\s+(\S+)',
    caseSensitive: false,
  );

  // FFmpeg: capture time= value
  static final RegExp _ffmpegProgressRegex = RegExp(
    r'time=(\d{2}:\d{2}:\d{2}\.\d+)',
    caseSensitive: false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Convenience top-level getters
// ─────────────────────────────────────────────────────────────────────────────

/// Global singleton accessor.
ProcessRunner get processRunner => ProcessRunner.instance;