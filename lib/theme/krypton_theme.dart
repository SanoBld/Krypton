// krypton_theme.dart
// Material 3 theme engine: Material You (Android) + Pitch-Black fallback.

import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';

// ── Pitch-Black palette constants ─────────────────────────────────────────
class KryptonColors {
  static const background = Color(0xFF000000);
  static const surface    = Color(0xFF0A0A0A);
  static const surfaceVar = Color(0xFF141414);
  static const onSurface  = Color(0xFFFFFFFF);
  static const muted      = Color(0xFF3A3A3A);
  static const neonAccent = Color(0xFF00E5FF); // cyan-neon focus indicator
  static const error      = Color(0xFFFF4444);
}

// ── Seed color used when dynamic color is unavailable ────────────────────
const _fallbackSeed = Color(0xFF00E5FF);

// ── Dark Pitch-Black ColorScheme ─────────────────────────────────────────
ColorScheme _pitchBlackScheme([ColorScheme? dynamic]) {
  final base = dynamic ??
      ColorScheme.fromSeed(seedColor: _fallbackSeed, brightness: Brightness.dark);

  return base.copyWith(
    brightness:       Brightness.dark,
    background:       KryptonColors.background,
    surface:          KryptonColors.surface,
    surfaceVariant:   KryptonColors.surfaceVar,
    onBackground:     KryptonColors.onSurface,
    onSurface:        KryptonColors.onSurface,
    outline:          KryptonColors.muted,
    primary:          dynamic?.primary ?? KryptonColors.neonAccent,
    onPrimary:        KryptonColors.background,
    error:            KryptonColors.error,
  );
}

// ── ThemeData builder ────────────────────────────────────────────────────
ThemeData _buildTheme(ColorScheme scheme) => ThemeData(
  useMaterial3:  true,
  colorScheme:   scheme,
  scaffoldBackgroundColor: scheme.background,
  appBarTheme: AppBarTheme(
    backgroundColor:  scheme.background,
    foregroundColor:  scheme.onSurface,
    elevation:        0,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(
      color:      scheme.onSurface,
      fontSize:   18,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  ),
  navigationRailTheme: NavigationRailThemeData(
    backgroundColor:         scheme.background,
    selectedIconTheme:       IconThemeData(color: scheme.primary),
    unselectedIconTheme:     IconThemeData(color: scheme.outline),
    selectedLabelTextStyle:  TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
    unselectedLabelTextStyle: TextStyle(color: scheme.outline),
    indicatorColor: scheme.primary.withOpacity(0.12),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor:    scheme.surface,
    indicatorColor:     scheme.primary.withOpacity(0.15),
    iconTheme: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.selected)) {
        return IconThemeData(color: scheme.primary);
      }
      return IconThemeData(color: scheme.outline);
    }),
    labelTextStyle: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.selected)) {
        return TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 12);
      }
      return TextStyle(color: scheme.outline, fontSize: 12);
    }),
  ),
  cardTheme: CardTheme(
    color:        scheme.surfaceVariant,
    elevation:    0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: KryptonColors.muted.withOpacity(0.3)),
    ),
    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled:      true,
    fillColor:   scheme.surfaceVariant,
    border:      OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   BorderSide(color: KryptonColors.muted),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   BorderSide(color: KryptonColors.muted),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   BorderSide(color: KryptonColors.neonAccent, width: 1.5),
    ),
    hintStyle: TextStyle(color: scheme.outline),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor:    scheme.primary,
      foregroundColor:    scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      elevation: 0,
    ),
  ),
  dividerTheme: DividerThemeData(color: KryptonColors.muted.withOpacity(0.4), thickness: 0.5),
  fontFamily: 'Inter',
);

// ── Public widget that provides the theme via DynamicColorBuilder ─────────
class KryptonThemeProvider extends StatelessWidget {
  final Widget Function(ThemeData theme) builder;
  final bool useDynamicColor;
  final bool usePitchBlack;

  const KryptonThemeProvider({
    super.key,
    required this.builder,
    this.useDynamicColor = true,
    this.usePitchBlack   = true,
  });

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        ColorScheme scheme;

        if (useDynamicColor && darkDynamic != null) {
          // Material You — harmonize with wallpaper palette
          scheme = usePitchBlack
              ? _pitchBlackScheme(darkDynamic)
              : darkDynamic;
        } else {
          // Pitch-black fallback
          scheme = _pitchBlackScheme();
        }

        return builder(_buildTheme(scheme));
      },
    );
  }
}