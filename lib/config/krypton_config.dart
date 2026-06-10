// lib/config/krypton_config.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// App language options
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

// Download backend options (how to download videos on mobile)
enum DownloadBackendMode {
  cobalt,
  customApi,
  auto
}

class KryptonConfig extends ChangeNotifier {
  KryptonConfig._();

  static final KryptonConfig instance = KryptonConfig._();

  // Keys to save data in phone memory
  static const _kDownloadPath   = 'download_path';
  static const _kConvertPath    = 'convert_path';
  static const _kMaxWorkers     = 'max_workers';
  static const _kDynamicColor   = 'dynamic_color';
  static const _kLanguage       = 'language';
  static const _kBackend        = 'download_backend';
  static const _kCustomApi      = 'custom_api_url';

  // Current app settings
  SharedPreferences? _prefs;

  String _downloadPath = '';
  String _convertPath  = '';
  int _maxWorkers      = 3;
  bool _dynamicColor   = true;
  AppLanguage _language = AppLanguage.en;
  
  // New settings for the download backend
  DownloadBackendMode _downloadBackend = DownloadBackendMode.auto;
  String _customApiUrl = '';

  // Load all settings when the app starts
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    _downloadPath = _prefs?.getString(_kDownloadPath) ?? '';
    _convertPath  = _prefs?.getString(_kConvertPath)  ?? '';
    _maxWorkers   = _prefs?.getInt(_kMaxWorkers)      ?? 3;
    _dynamicColor = _prefs?.getBool(_kDynamicColor)   ?? true;

    // Load saved language or use English by default
    final String langName = _prefs?.getString(_kLanguage) ?? AppLanguage.en.name;
    _language = AppLanguage.values.firstWhere(
      (l) => l.name == langName,
      orElse: () => AppLanguage.en,
    );

    // Load saved download backend or use Auto by default
    final String backendName = _prefs?.getString(_kBackend) ?? DownloadBackendMode.auto.name;
    _downloadBackend = DownloadBackendMode.values.firstWhere(
      (b) => b.name == backendName,
      orElse: () => DownloadBackendMode.auto,
    );

    // Load custom API URL
    _customApiUrl = _prefs?.getString(_kCustomApi) ?? '';
  }

  // Getters (read settings)
  String get downloadPath               => _downloadPath;
  String get convertPath                => _convertPath;
  int get maxWorkers                    => _maxWorkers;
  bool get dynamicColor                 => _dynamicColor;
  AppLanguage get language              => _language;
  DownloadBackendMode get downloadBackend => _downloadBackend;
  String get customApiUrl               => _customApiUrl;

  // Setters (save settings and refresh screen)
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

  // Save chosen backend mode
  Future<void> setDownloadBackend(DownloadBackendMode v) async {
    _downloadBackend = v;
    await _prefs?.setString(_kBackend, v.name);
    notifyListeners();
  }

  // Save server URL
  Future<void> setCustomApiUrl(String v) async {
    _customApiUrl = v.trim();
    await _prefs?.setString(_kCustomApi, v.trim());
    notifyListeners();
  }
}