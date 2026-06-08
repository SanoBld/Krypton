// krypton_config.dart
// Persistent configuration layer for Krypton.
// Replaces Python config_manager.py using shared_preferences.

import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { fr, en }

class KryptonConfig {
  KryptonConfig._();
  static final KryptonConfig instance = KryptonConfig._();

  late SharedPreferences _prefs;

  // ── Keys ────────────────────────────────────────────────────────────────
  static const _kLanguage        = 'language';
  static const _kDownloadPath    = 'download_path';
  static const _kConvertPath     = 'convert_path';
  static const _kMaxWorkers      = 'max_workers';
  static const _kDynamicColor    = 'dynamic_color';
  static const _kPitchBlack      = 'pitch_black';

  // ── Init (call once in main) ────────────────────────────────────────────
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Language ────────────────────────────────────────────────────────────
  AppLanguage get language {
    final v = _prefs.getString(_kLanguage) ?? 'fr';
    return v == 'en' ? AppLanguage.en : AppLanguage.fr;
  }
  Future<void> setLanguage(AppLanguage lang) =>
      _prefs.setString(_kLanguage, lang.name);

  // ── Paths ───────────────────────────────────────────────────────────────
  String get downloadPath => _prefs.getString(_kDownloadPath) ?? '';
  Future<void> setDownloadPath(String p) => _prefs.setString(_kDownloadPath, p);

  String get convertPath => _prefs.getString(_kConvertPath) ?? '';
  Future<void> setConvertPath(String p) => _prefs.setString(_kConvertPath, p);

  // ── Workers ─────────────────────────────────────────────────────────────
  int get maxWorkers => _prefs.getInt(_kMaxWorkers) ?? 3;
  Future<void> setMaxWorkers(int n) => _prefs.setInt(_kMaxWorkers, n.clamp(1, 8));

  // ── Theme toggles ───────────────────────────────────────────────────────
  bool get useDynamicColor => _prefs.getBool(_kDynamicColor) ?? true;
  Future<void> setDynamicColor(bool v) => _prefs.setBool(_kDynamicColor, v);

  bool get usePitchBlack => _prefs.getBool(_kPitchBlack) ?? true;
  Future<void> setPitchBlack(bool v) => _prefs.setBool(_kPitchBlack, v);

  // ── Reset ───────────────────────────────────────────────────────────────
  Future<void> reset() => _prefs.clear();
}