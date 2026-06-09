// lib/services/krypton_updater.dart
//
// Silent OTA updater for Android builds.
// API consumed by SettingsScreen:
//   • state          → UpdateState (enum)
//   • progress       → double 0.0–1.0
//   • currentVersion → String
//   • errorMessage   → String?
//   • checkAndUpdate → Future<void>  (also usable as VoidCallback)

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

// ── State enum ───────────────────────────────────────────────────────────────
enum UpdateState { idle, checking, downloading, installing, done, error }

// ── Remote manifest ──────────────────────────────────────────────────────────
class _ReleaseManifest {
  final int    versionCode;
  final String apkUrl;

  const _ReleaseManifest({required this.versionCode, required this.apkUrl});

  factory _ReleaseManifest.fromJson(Map<String, dynamic> j) {
    // Supports GitHub Releases API shape.
    final String apkUrl = j['apk_url'] as String? ??
        ((j['assets'] as List?)?.firstWhere(
          (a) => (a['name'] as String).endsWith('.apk'),
          orElse: () => {'browser_download_url': ''},
        )['browser_download_url'] as String? ?? '');

    return _ReleaseManifest(
      versionCode: j['version_code'] as int? ?? 0,
      apkUrl:      apkUrl,
    );
  }
}

// ── Service ──────────────────────────────────────────────────────────────────
class KryptonUpdater extends ChangeNotifier {
  static const _manifestUrl =
      'https://api.github.com/repos/YOUR_ORG/krypton/releases/latest';

  // ── Public state ─────────────────────────────────────────────────────────
  UpdateState _state          = UpdateState.idle;
  double      _progress       = 0.0;
  String      _currentVersion = '';
  String?     _errorMessage;

  UpdateState get state          => _state;
  double      get progress       => _progress;
  String      get currentVersion => _currentVersion;
  String?     get errorMessage   => _errorMessage;

  // ── Init ─────────────────────────────────────────────────────────────────
  /// Call once at startup to populate [currentVersion].
  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _currentVersion = '1.0.0+1';
    }
  }

  // ── Core ─────────────────────────────────────────────────────────────────
  /// Checks for a new release and installs it silently on Android.
  /// No-op on non-Android platforms.
  Future<void> checkAndUpdate() async {
    if (!Platform.isAndroid) return;
    if (_state == UpdateState.checking || _state == UpdateState.downloading) return;

    _set(UpdateState.checking);

    try {
      // 1. Fetch manifest
      final res = await http.get(
        Uri.parse(_manifestUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final manifest = _ReleaseManifest.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );

      // 2. Compare version
      final info      = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(info.buildNumber) ?? 0;

      if (manifest.versionCode <= localCode || manifest.apkUrl.isEmpty) {
        _set(UpdateState.done);
        return;
      }

      // 3. Download APK
      _set(UpdateState.downloading, progress: 0);
      final dir     = await getTemporaryDirectory();
      final apkPath = '${dir.path}/krypton_update.apk';
      final sink    = File(apkPath).openWrite();

      final dlRes  = await http.Client().send(http.Request('GET', Uri.parse(manifest.apkUrl)));
      final total  = dlRes.contentLength ?? 1;
      int received = 0;

      await for (final chunk in dlRes.stream) {
        sink.add(chunk);
        received += chunk.length;
        _set(UpdateState.downloading, progress: received / total);
      }
      await sink.close();

      // 4. Trigger install
      _set(UpdateState.installing);
      OtaUpdate().execute(apkPath).listen(
        (event) {
          if (event.status == OtaStatus.INSTALLING) _set(UpdateState.installing);
        },
        onError: (e) => _setError(e.toString()),
      );

    } catch (e, st) {
      debugPrint('[KryptonUpdater] $e\n$st');
      _setError(e.toString());
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  void _set(UpdateState s, {double progress = 0}) {
    _state    = s;
    _progress = progress;
    notifyListeners();
  }

  void _setError(String msg) {
    _state        = UpdateState.error;
    _errorMessage = msg;
    notifyListeners();
  }
}