// krypton_updater.dart
// Silent OTA updater for Android builds.
// Queries GitHub Releases, downloads the APK, and triggers native install.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

// ── Remote manifest model ────────────────────────────────────────────────
class _ReleaseManifest {
  final int    versionCode;
  final String versionName;
  final String apkUrl;
  const _ReleaseManifest({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
  });

  factory _ReleaseManifest.fromJson(Map<String, dynamic> j) {
    // Compatible with both a custom JSON manifest AND GitHub Releases API.
    // Custom JSON shape: { "version_code": 12, "version_name": "1.2.0", "apk_url": "..." }
    // GitHub shape parses assets[0].browser_download_url as apk_url.
    final String apkUrl = j['apk_url'] as String? ??
        ((j['assets'] as List?)?.firstWhere(
          (a) => (a['name'] as String).endsWith('.apk'),
          orElse: () => {'browser_download_url': ''},
        )['browser_download_url'] as String? ?? '');

    return _ReleaseManifest(
      versionCode: j['version_code'] as int? ?? 0,
      versionName: j['version_name'] as String? ??
          ((j['tag_name'] as String?)?.replaceAll('v', '') ?? '0.0.0'),
      apkUrl: apkUrl,
    );
  }
}

// ── Update states for UI consumption ────────────────────────────────────
enum UpdateStatus { idle, checking, downloading, installing, upToDate, error }

class UpdateState {
  final UpdateStatus status;
  final double       progress; // 0.0–1.0
  final String?      message;
  const UpdateState(this.status, {this.progress = 0, this.message});
}

// ── Main service ─────────────────────────────────────────────────────────
class KryptonUpdater extends ChangeNotifier {
  static const _manifestUrl =
      'https://api.github.com/repos/YOUR_ORG/krypton/releases/latest';

  UpdateState _state = const UpdateState(UpdateStatus.idle);
  UpdateState get state => _state;

  void _emit(UpdateState s) { _state = s; notifyListeners(); }

  /// Call once at startup. No-op on non-Android platforms.
  Future<void> checkAndUpdate() async {
    if (!Platform.isAndroid) return;

    try {
      _emit(const UpdateState(UpdateStatus.checking));

      // 1. Fetch remote manifest
      final res = await http.get(
        Uri.parse(_manifestUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final manifest = _ReleaseManifest.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );

      // 2. Compare with installed version
      final info        = await PackageInfo.fromPlatform();
      final localCode   = int.tryParse(info.buildNumber) ?? 0;

      if (manifest.versionCode <= localCode) {
        _emit(const UpdateState(UpdateStatus.upToDate));
        return;
      }

      if (manifest.apkUrl.isEmpty) throw Exception('No APK URL in manifest');

      // 3. Download APK to cache
      _emit(const UpdateState(UpdateStatus.downloading, progress: 0));
      final dir     = await getTemporaryDirectory();
      final apkPath = '${dir.path}/krypton_update.apk';

      final sink   = File(apkPath).openWrite();
      final dlRes  = await http.Client().send(http.Request('GET', Uri.parse(manifest.apkUrl)));
      final total  = dlRes.contentLength ?? 1;
      int received = 0;

      await for (final chunk in dlRes.stream) {
        sink.add(chunk);
        received += chunk.length;
        _emit(UpdateState(UpdateStatus.downloading, progress: received / total));
      }
      await sink.close();

      // 4. Trigger native install intent
      _emit(const UpdateState(UpdateStatus.installing));
      OtaUpdate().execute(apkPath).listen(
        (event) {
          if (event.status == OtaStatus.INSTALLING) {
            _emit(const UpdateState(UpdateStatus.installing));
          }
        },
        onError: (e) => _emit(UpdateState(UpdateStatus.error, message: e.toString())),
      );

    } catch (e, st) {
      debugPrint('[KryptonUpdater] $e\n$st');
      _emit(UpdateState(UpdateStatus.error, message: e.toString()));
    }
  }
}