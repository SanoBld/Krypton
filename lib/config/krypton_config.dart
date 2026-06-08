// lib/config/krypton_config.dart
//
// Persistent app configuration backed by SharedPreferences.
// All setters are async and call notifyListeners() so that widgets
// built with context.watch<KryptonConfig>() rebuild automatically.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Language enum ─────────────────────────────────────────────────────────────

enum AppLanguage {
  en,
  fr;

  String get displayName {
    switch (this) {
      case AppLanguage.en:
        return 'English';
      case AppLanguage.fr:
        return 'Français';
    }
  }
}

// ── KryptonConfig ─────────────────────────────────────────────────────────────

class KryptonConfig extends ChangeNotifier {
  KryptonConfig._();

  static final KryptonConfig instance = KryptonConfig._();

  // ── SharedPreferences keys ────────────────────────────────────────────────

  static const _kDownloadPath  = 'download_path';
  static const _kConvertPath   = 'convert_path';
  static const _kMaxWorkers    = 'max_workers';
  static const _kDynamicColor  = 'dynamic_color';
  static const _kLanguage      = 'language';

  // ── Internal state ────────────────────────────────────────────────────────

  SharedPreferences? _prefs;

  String       _downloadPath  = '';
  String       _convertPath   = '';
  int          _maxWorkers    = 3;
  bool         _dynamicColor  = true;
  AppLanguage  _language      = AppLanguage.en;

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Call once at app startup, before the widget tree is built.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    _downloadPath = _prefs!.getString(_kDownloadPath)  ?? '';
    _convertPath  = _prefs!.getString(_kConvertPath)   ?? '';
    _maxWorkers   = _prefs!.getInt(_kMaxWorkers)       ?? 3;
    _dynamicColor = _prefs!.getBool(_kDynamicColor)    ?? true;

    final String langName = _prefs!.getString(_kLanguage) ?? AppLanguage.en.name;
    _language = AppLanguage.values.firstWhere(
      (l) => l.name == langName,
      orElse: () => AppLanguage.en,
    );
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  String      get downloadPath  => _downloadPath;
  String      get convertPath   => _convertPath;
  int         get maxWorkers    => _maxWorkers;
  bool        get dynamicColor  => _dynamicColor;
  AppLanguage get language      => _language;

  // ── Setters ───────────────────────────────────────────────────────────────

  Future<void> setDownloadPath(String v) async {
    _downloadPath = v;
    await _prefs?.setString(_kDownloadPath, v);
    notifyListeners();
  }

  Future<void> setConvertPath(String v) async {
    _convertPath = v;
    await _prefs?.setString(_kConvertPath, v);
    notifyListeners();
  }

  Future<void> setMaxWorkers(int v) async {
    _maxWorkers = v.clamp(1, 8);
    await _prefs?.setInt(_kMaxWorkers, _maxWorkers);
    notifyListeners();
  }

  Future<void> setDynamicColor(bool v) async {
    _dynamicColor = v;
    await _prefs?.setBool(_kDynamicColor, v);
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage v) async {
    _language = v;
    await _prefs?.setString(_kLanguage, v.name);
    notifyListeners();
  }
}