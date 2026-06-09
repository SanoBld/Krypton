// lib/main.dart
// Krypton — universal app entry point.
// Boot sequence: logger → config → updater → UI

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/krypton_config.dart';
import 'core/logger.dart';
import 'services/krypton_updater.dart';
import 'theme/krypton_theme.dart';
import 'screens/download/download_screen.dart';
import 'screens/convert/convert_screen.dart';
import 'screens/settings/settings_screen.dart';

// ── Bootstrap ────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Logger (non-blocking file init)
  await logger.init();

  // 2. Persistent config
  await KryptonConfig.instance.init();
  logger.i('main', 'Config loaded');

  // 3. Updater (reads PackageInfo)
  final updater = KryptonUpdater();
  await updater.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: KryptonConfig.instance),
        ChangeNotifierProvider.value(value: updater),
      ],
      child: const KryptonApp(),
    ),
  );

  // OTA check fires after first frame — never blocks the render pipeline
  WidgetsBinding.instance.addPostFrameCallback((_) {
    logger.i('main', 'Triggering OTA check');
    updater.checkAndUpdate();
  });
}

// ── Root widget ──────────────────────────────────────────────────────────────
class KryptonApp extends StatelessWidget {
  const KryptonApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Re-read theme toggles reactively so hot-switching works
    final cfg = context.watch<KryptonConfig>();

    return KryptonThemeProvider(
      useDynamicColor: cfg.dynamicColor,
      usePitchBlack:   true,
      builder: (theme) => MaterialApp(
        title:                      'Krypton',
        debugShowCheckedModeBanner: false,
        theme:                      theme,
        darkTheme:                  theme,
        themeMode:                  ThemeMode.dark,
        home:                       const _AdaptiveShell(),
      ),
    );
  }
}

// ── Tab registry ─────────────────────────────────────────────────────────────
class _Tab {
  final IconData icon;
  final IconData activeIcon;
  final String   label;
  final Widget   screen;

  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.screen,
  });
}

const _tabs = [
  _Tab(
    icon:       Icons.download_outlined,
    activeIcon: Icons.download_rounded,
    label:      'Download',
    screen:     DownloadScreen(),
  ),
  _Tab(
    icon:       Icons.transform_outlined,
    activeIcon: Icons.transform_rounded,
    label:      'Convert',
    screen:     ConvertScreen(),
  ),
  _Tab(
    icon:       Icons.settings_outlined,
    activeIcon: Icons.settings_rounded,
    label:      'Settings',
    screen:     SettingsScreen(),
  ),
];

// ── Adaptive shell ────────────────────────────────────────────────────────────
// < 600 dp  → Mobile  (NavigationBar  + bottom)
// ≥ 600 dp  → Desktop (NavigationRail + side)
// ≥ 1024 dp → Desktop extended rail
class _AdaptiveShell extends StatefulWidget {
  const _AdaptiveShell();

  @override
  State<_AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<_AdaptiveShell> {
  int _index = 0;

  // Keep screens alive across tab switches
  final _navigatorKeys = List.generate(
    _tabs.length,
    (_) => GlobalKey<NavigatorState>(),
  );

  @override
  Widget build(BuildContext context) {
    final width     = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 600;
    final isWide    = width >= 1024;

    return isDesktop
        ? _buildDesktop(isWide)
        : _buildMobile();
  }

  // ── Desktop ───────────────────────────────────────────────────────────────
  Widget _buildDesktop(bool extended) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex:         _index,
            onDestinationSelected: _onTap,
            extended:              extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: Padding(
              padding: EdgeInsets.symmetric(
                vertical: extended ? 20 : 12,
                horizontal: extended ? 12 : 0,
              ),
              child: extended
                  ? Row(children: [
                      Icon(Icons.bolt_rounded, color: cs.primary, size: 22),
                      const SizedBox(width: 10),
                      Text('Krypton',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: -0.3,
                          )),
                    ])
                  : Icon(Icons.bolt_rounded, color: cs.primary, size: 22),
            ),
            destinations: _tabs
                .map((t) => NavigationRailDestination(
                      icon:          Icon(t.icon),
                      selectedIcon:  Icon(t.activeIcon),
                      label:         Text(t.label),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                    ))
                .toList(),
          ),
          VerticalDivider(width: 1, color: cs.outline.withValues(alpha: 0.3)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: _tabs[_index].screen,
            ),
          ),
        ],
      ),
    );
  }

  // ── Mobile ────────────────────────────────────────────────────────────────
  Widget _buildMobile() {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _tabs.map((t) => t.screen).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex:           _index,
        onDestinationSelected:   _onTap,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: _tabs
            .map((t) => NavigationDestination(
                  icon:          Icon(t.icon),
                  selectedIcon:  Icon(t.activeIcon),
                  label:         t.label,
                ))
            .toList(),
      ),
    );
  }

  void _onTap(int i) => setState(() => _index = i);
}