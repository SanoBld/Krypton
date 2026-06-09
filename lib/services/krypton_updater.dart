// lib/services/krypton_updater.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

// Update lifecycle states
enum UpdateState { idle, checking, downloading, installing, done, error }

// Data from the GitHub release
class _ReleaseManifest {
  final int versionCode;
  final String apkUrl;

  const _ReleaseManifest({required this.versionCode, required this.apkUrl});

  factory _ReleaseManifest.fromJson(Map<String, dynamic> j) {
    // Try direct key first, then parse GitHub assets array
    final String apkUrl = j['apk_url'] as String? ??
        ((j['assets'] as List?)?.firstWhere(
              (a) => (a['name'] as String).endsWith('.apk'),
              orElse: () => {'browser_download_url': ''},
            )['browser_download_url'] as String? ??
            '');

    return _ReleaseManifest(
      versionCode: j['version_code'] as int? ?? 0,
      apkUrl: apkUrl,
    );
  }
}

class KryptonUpdater extends ChangeNotifier {
  static const _manifestUrl =
      'https://api.github.com/repos/YOUR_ORG/krypton/releases/latest';

  // Public state
  UpdateState _state = UpdateState.idle;
  double _progress = 0.0;
  String _currentVersion = '';
  String? _errorMessage;

  UpdateState get state => _state;
  double get progress => _progress;
  String get currentVersion => _currentVersion;
  String? get errorMessage => _errorMessage;

  // Load version string from the app package
  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _currentVersion = '1.0.0+1';
    }
  }

  // Check for a new release and install it — Android only
  Future<void> checkAndUpdate() async {
    // Skip on non-Android platforms
    if (!Platform.isAndroid) return;

    // Prevent double-run
    if (_state == UpdateState.checking ||
        _state == UpdateState.downloading) return;

    _set(UpdateState.checking);

    try {
      // Step 1 — fetch the latest release from GitHub
      final res = await http.get(
        Uri.parse(_manifestUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final manifest = _ReleaseManifest.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );

      // Step 2 — compare remote version code with local build number
      final info = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(info.buildNumber) ?? 0;

      if (manifest.versionCode <= localCode || manifest.apkUrl.isEmpty) {
        _set(UpdateState.done); // already up to date
        return;
      }

      // Step 3 — download the APK to the temp directory
      _set(UpdateState.downloading, progress: 0);
      final dir = await getTemporaryDirectory();
      final apkPath = '${dir.path}/krypton_update.apk';
      final sink = File(apkPath).openWrite();

      final dlRes = await http.Client()
          .send(http.Request('GET', Uri.parse(manifest.apkUrl)));
      final total = dlRes.contentLength ?? 1;
      int received = 0;

      await for (final chunk in dlRes.stream) {
        sink.add(chunk);
        received += chunk.length;
        _set(UpdateState.downloading, progress: received / total);
      }
      await sink.close();

      // Step 4 — hand the APK to the system installer
      _set(UpdateState.installing);
      await OpenFilex.open(apkPath); // triggers Android package installer
      _set(UpdateState.done);
    } catch (e, st) {
      debugPrint('[KryptonUpdater] $e\n$st');
      _setError(e.toString());
    }
  }

  // Set state + notify
  void _set(UpdateState s, {double progress = 0}) {
    _state = s;
    _progress = progress;
    notifyListeners();
  }

  // Set error state + notify
  void _setError(String msg) {
    _state = UpdateState.error;
    _errorMessage = msg;
    notifyListeners();
  }
}