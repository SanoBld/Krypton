import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/krypton_config.dart';
import '../../core/logger.dart';
import '../../core/process_runner.dart';
import '../../services/krypton_updater.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen
//
// Full settings surface for Krypton. Sections:
//   1. Paths        — download & temp output directories
//   2. Downloads    — max concurrent workers
//   3. Appearance   — dynamic color toggle, language selector
//   4. Binaries     — yt-dlp / FFmpeg path validation
//   5. Updates      — manual OTA check (Android) / version info
//   6. Diagnostics  — live log viewer (debug builds only)
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _tag = 'SettingsScreen';

  bool? _ytdlpAvailable;
  bool? _ffmpegAvailable;
  bool _checkingBinaries = true;

  @override
  void initState() {
    super.initState();
    _checkBinaries();
  }

  Future<void> _checkBinaries() async {
    logger.d(_tag, 'Checking binary availability…');
    final bool yt = await processRunner.isBinaryAvailable('yt-dlp');
    final bool ff = await processRunner.isBinaryAvailable('ffmpeg');
    if (!mounted) return;
    setState(() {
      _ytdlpAvailable = yt;
      _ffmpegAvailable = ff;
      _checkingBinaries = false;
    });
    logger.i(_tag, 'yt-dlp=$yt, ffmpeg=$ff');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: _contentPadding(context),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SectionHeader(label: 'Paths'),
                _PathsSection(),
                const SizedBox(height: 24),
                _SectionHeader(label: 'Downloads'),
                _DownloadsSection(),
                const SizedBox(height: 24),
                _SectionHeader(label: 'Appearance'),
                _AppearanceSection(),
                const SizedBox(height: 24),
                _SectionHeader(label: 'Binaries'),
                _BinariesSection(
                  ytdlpAvailable: _ytdlpAvailable,
                  ffmpegAvailable: _ffmpegAvailable,
                  checking: _checkingBinaries,
                  onRecheck: _checkBinaries,
                ),
                const SizedBox(height: 24),
                _SectionHeader(label: 'Updates'),
                _UpdatesSection(),
                if (kDebugMode) ...[
                  const SizedBox(height: 24),
                  _SectionHeader(label: 'Diagnostics'),
                  _DiagnosticsSection(),
                ],
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SliverAppBar.large(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Settings',
        style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      ),
      expandedHeight: 100,
      pinned: true,
      automaticallyImplyLeading: false,
    );
  }

  EdgeInsets _contentPadding(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final double h = width > 900 ? (width - 800) / 2 : 16;
    return EdgeInsets.fromLTRB(h, 8, h, 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Paths
// ─────────────────────────────────────────────────────────────────────────────

class _PathsSection extends StatelessWidget {
  const _PathsSection();

  @override
  Widget build(BuildContext context) {
    final KryptonConfig config = KryptonConfig.instance;
    return _Card(
      children: [
        _PathTile(
          icon: Icons.download_for_offline_outlined,
          label: 'Download folder',
          value: config.downloadPath,
          onChanged: (path) async {
            await config.setDownloadPath(path);
            logger.i('Settings', 'Download path → $path');
          },
        ),
        const _Divider(),
        _PathTile(
          icon: Icons.swap_horiz_rounded,
          label: 'Conversion output folder',
          value: config.convertPath,
          onChanged: (path) async {
            await config.setConvertPath(path);
            logger.i('Settings', 'Convert path → $path');
          },
        ),
      ],
    );
  }
}

class _PathTile extends StatefulWidget {
  const _PathTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String value;
  final Future<void> Function(String) onChanged;

  @override
  State<_PathTile> createState() => _PathTileState();
}

class _PathTileState extends State<_PathTile> {
  String _current = '';

  @override
  void initState() {
    super.initState();
    _current = widget.value;
  }

  Future<void> _pick() async {
    final String? picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select ${widget.label}',
    );
    if (picked == null) return;
    await widget.onChanged(picked);
    if (mounted) setState(() => _current = picked);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(widget.icon, color: cs.primary),
      title: Text(widget.label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        _current.isEmpty ? 'Not set' : _current,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize:   12,
          color:      _current.isEmpty ? cs.error : cs.onSurfaceVariant,
          fontFamily: 'monospace',
        ),
      ),
      trailing: TextButton.icon(
        onPressed: _pick,
        icon: const Icon(Icons.folder_open_rounded, size: 16),
        label: const Text('Change'),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Downloads
// ─────────────────────────────────────────────────────────────────────────────

class _DownloadsSection extends StatefulWidget {
  const _DownloadsSection();

  @override
  State<_DownloadsSection> createState() => _DownloadsSectionState();
}

class _DownloadsSectionState extends State<_DownloadsSection> {
  late int _workers;

  @override
  void initState() {
    super.initState();
    _workers = KryptonConfig.instance.maxWorkers;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return _Card(
      children: [
        ListTile(
          leading: Icon(Icons.tune_rounded, color: cs.primary),
          title: const Text(
            'Max concurrent downloads',
            style: TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            '$_workers ${_workers == 1 ? 'worker' : 'workers'}',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              const Text('1', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value:      _workers.toDouble(),
                  min:        1,
                  max:        8,
                  divisions:  7,
                  label:      '$_workers',
                  onChanged:  (v) => setState(() => _workers = v.round()),
                  onChangeEnd: (v) async {
                    await KryptonConfig.instance.setMaxWorkers(v.round());
                    logger.i('Settings', 'Workers → ${v.round()}');
                  },
                ),
              ),
              const Text('8', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Appearance
// ─────────────────────────────────────────────────────────────────────────────

class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection();

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  late bool _dynamicColor;
  late AppLanguage _language;

  @override
  void initState() {
    super.initState();
    _dynamicColor = KryptonConfig.instance.dynamicColor;
    _language     = KryptonConfig.instance.language;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return _Card(
      children: [
        if (Platform.isAndroid) ...[
          SwitchListTile(
            secondary: Icon(Icons.palette_outlined, color: cs.primary),
            title: const Text(
              'Material You dynamic color',
              style: TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              'Harmonize UI with your wallpaper palette',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            value: _dynamicColor,
            onChanged: (v) async {
              setState(() => _dynamicColor = v);
              await KryptonConfig.instance.setDynamicColor(v);
              logger.i('Settings', 'Dynamic color → $v');
            },
          ),
          const _Divider(),
        ],
        ListTile(
          leading: Icon(Icons.language_rounded, color: cs.primary),
          title: const Text('Language', style: TextStyle(fontSize: 14)),
          trailing: DropdownButton<AppLanguage>(
            value:        _language,
            underline:    const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(12),
            items: const [
              DropdownMenuItem(value: AppLanguage.en, child: Text('English')),
              DropdownMenuItem(value: AppLanguage.fr, child: Text('Français')),
            ],
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _language = v);
              await KryptonConfig.instance.setLanguage(v);
              logger.i('Settings', 'Language → ${v.name}');
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Binaries
// ─────────────────────────────────────────────────────────────────────────────

class _BinariesSection extends StatelessWidget {
  const _BinariesSection({
    required this.ytdlpAvailable,
    required this.ffmpegAvailable,
    required this.checking,
    required this.onRecheck,
  });

  final bool? ytdlpAvailable;
  final bool? ffmpegAvailable;
  final bool checking;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        _BinaryTile(
          name:        'yt-dlp',
          description: 'Media downloader binary',
          available:   ytdlpAvailable,
          checking:    checking,
        ),
        const _Divider(),
        _BinaryTile(
          name:        'ffmpeg',
          description: 'Audio/video converter binary',
          available:   ffmpegAvailable,
          checking:    checking,
        ),
        const _Divider(),
        ListTile(
          dense: true,
          trailing: TextButton.icon(
            onPressed: checking ? null : onRecheck,
            icon:  const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Re-check'),
          ),
          title: Text(
            'Ensure both binaries are on your system PATH.',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _BinaryTile extends StatelessWidget {
  const _BinaryTile({
    required this.name,
    required this.description,
    required this.available,
    required this.checking,
  });

  final String name;
  final String description;
  final bool? available;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    Widget trailing;
    if (checking) {
      trailing = const SizedBox(
        width:  16,
        height: 16,
        child:  CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (available == true) {
      trailing = Icon(Icons.check_circle_rounded, color: Colors.green[400]);
    } else {
      trailing = Icon(Icons.cancel_rounded, color: cs.error);
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color:        cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          name == 'yt-dlp' ? '▶' : '⚙',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      title: Text(
        name,
        style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
      ),
      subtitle: Text(
        description,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
      ),
      trailing: trailing,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Updates
// ─────────────────────────────────────────────────────────────────────────────

class _UpdatesSection extends StatelessWidget {
  const _UpdatesSection();

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs         = Theme.of(context).colorScheme;
    final KryptonUpdater updater = context.watch<KryptonUpdater>();

    return _Card(
      children: [
        ListTile(
          leading: Icon(Icons.info_outline_rounded, color: cs.primary),
          title: const Text('Version', style: TextStyle(fontSize: 14)),
          trailing: Text(
            updater.currentVersion,
            style: TextStyle(
              color:      cs.onSurfaceVariant,
              fontSize:   13,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const _Divider(),
        if (Platform.isAndroid)
          _AndroidUpdateTile(updater: updater)
        else
          ListTile(
            leading: Icon(Icons.computer_rounded, color: cs.onSurfaceVariant),
            title: const Text(
              'Automatic updates',
              style: TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              'OTA updates are only available on Android.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _AndroidUpdateTile extends StatelessWidget {
  const _AndroidUpdateTile({required this.updater});
  final KryptonUpdater updater;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs    = Theme.of(context).colorScheme;
    final UpdateState state = updater.state;

    // Initialised to empty string — always overwritten by the switch below.
    String  subtitle = '';
    Widget? trailing;

    switch (state) {
      case UpdateState.idle:
        subtitle = 'Tap to check for a new version.';
        trailing = TextButton.icon(
          onPressed: updater.checkAndUpdate,
          icon:  const Icon(Icons.system_update_alt_rounded, size: 16),
          label: const Text('Check now'),
        );
        break;
      case UpdateState.checking:
        subtitle = 'Checking for updates…';
        trailing = const SizedBox(
          width:  18,
          height: 18,
          child:  CircularProgressIndicator(strokeWidth: 2),
        );
        break;
      case UpdateState.downloading:
        subtitle = 'Downloading update…';
        trailing = SizedBox(
          width: 120,
          child: LinearProgressIndicator(
            value:        updater.progress,
            borderRadius: BorderRadius.circular(4),
          ),
        );
        break;
      case UpdateState.installing:
        subtitle = 'Installing — follow the system prompt.';
        trailing = const Icon(Icons.install_mobile_rounded);
        break;
      case UpdateState.done:
        subtitle = 'You are running the latest version.';
        trailing = Icon(Icons.check_circle_rounded, color: Colors.green[400]);
        break;
      case UpdateState.error:
        subtitle = updater.errorMessage ?? 'Update check failed.';
        trailing = Icon(Icons.error_outline_rounded, color: cs.error);
        break;
    }

    return ListTile(
      leading: Icon(Icons.system_update_rounded, color: cs.primary),
      title:   const Text('Krypton update', style: TextStyle(fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
      ),
      trailing: trailing,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Diagnostics (debug builds only)
// ─────────────────────────────────────────────────────────────────────────────

class _DiagnosticsSection extends StatefulWidget {
  const _DiagnosticsSection();

  @override
  State<_DiagnosticsSection> createState() => _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends State<_DiagnosticsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return _Card(
      children: [
        ListTile(
          leading: Icon(Icons.bug_report_outlined, color: cs.tertiary),
          title:   const Text('Live log viewer', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            'Debug build only — last 500 entries.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          trailing: IconButton(
            icon:      Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
        ),
        if (_expanded)
          SizedBox(
            height: 320,
            child:  LogViewerWidget(),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize:      11,
          fontWeight:    FontWeight.w700,
          letterSpacing: 1.2,
          color:         cs.primary,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color:        cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height:    1,
      thickness: 0.6,
      indent:    16,
      color:     Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}