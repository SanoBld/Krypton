// lib/services/krypton_updater.dart
//
// OTA update service for Krypton (Android only).
//
// Flow:
//   idle ──► checking ──► idle          (no update found)
//                     ──► downloading   (update available)
//                              ──► installing
//                                       ──► done
//   Any step ──► error  (on failure)
//
// Uses the GitHub Releases API to find the latest version, downloads the APK,
// and triggers installation via an Intent. Requires:
//   - package_info_plus
//   - http
//   - path_provider
//   - android_intent_plus  (or open_file_plus) for APK install intent

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

// ── UpdateState enum ──────────────────────────────────────────────────────────

enum UpdateState {
  idle,
  checking,
  downloading,
  installing,
  done,
  error,
}

// ── KryptonUpdater ────────────────────────────────────────────────────────────

class KryptonUpdater extends ChangeNotifier {
  // ── Configuration ──────────────────────────────────────────────────────────

  /// GitHub repo in the form "owner/repo".
  static const String _repo = 'SanoBld/Krypton';

  /// GitHub Releases API endpoint.
  static const String _apiUrl =
      'https://api.github.com/repos/$_repo/releases/latest';

  // ── Internal state ─────────────────────────────────────────────────────────

  UpdateState _state        = UpdateState.idle;
  String      _currentVersion = '—';
  double      _progress     = 0.0;
  String?     _errorMessage;
  String?     _latestVersion;
  String?     _apkDownloadUrl;

  // ── Public getters ─────────────────────────────────────────────────────────

  UpdateState get state          => _state;
  String      get currentVersion => _currentVersion;
  double      get progress       => _progress;
  String?     get errorMessage   => _errorMessage;
  String?     get latestVersion  => _latestVersion;

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Fetches the current app version from the package manifest.
  /// Call once at startup.
  Future<void> init() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;
    notifyListeners();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Checks for a newer release on GitHub. If one is found, downloads and
  /// triggers installation automatically.
  Future<void> checkAndUpdate() async {
    if (_state != UpdateState.idle) return;
    _setState(UpdateState.checking);

    try {
      // ── 1. Query latest release ────────────────────────────────────────────
      final http.Response response = await http
          .get(Uri.parse(_apiUrl), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return _fail('GitHub API returned ${response.statusCode}');
      }

      // Parse manually to avoid adding dart:convert + json_serializable deps
      // beyond what is already in the project.
      final String body = response.body;
      final String? tagName     = _extractJson(body, 'tag_name');
      final String? downloadUrl = _extractApkUrl(body);

      if (tagName == null) return _fail('Could not parse release tag.');

      _latestVersion = tagName.replaceFirst(RegExp(r'^v'), '');

      // ── 2. Compare versions ────────────────────────────────────────────────
      if (!_isNewer(_latestVersion!, _currentVersion)) {
        _setState(UpdateState.done);
        return;
      }

      if (downloadUrl == null) {
        return _fail('No APK asset found in latest release.');
      }
      _apkDownloadUrl = downloadUrl;

      // ── 3. Download APK ────────────────────────────────────────────────────
      _setState(UpdateState.downloading);
      _progress = 0.0;
      notifyListeners();

      final Directory dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final File apkFile = File('${dir.path}/krypton_update.apk');

      final http.StreamedResponse stream =
          await http.Client().send(http.Request('GET', Uri.parse(downloadUrl)));

      final int total = stream.contentLength ?? 0;
      int received = 0;
      final List<int> bytes = [];

      await for (final List<int> chunk in stream.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0) {
          _progress = received / total;
          notifyListeners();
        }
      }

      await apkFile.writeAsBytes(bytes, flush: true);

      // ── 4. Trigger install intent ──────────────────────────────────────────
      _setState(UpdateState.installing);
      await _installApk(apkFile);
    } catch (e) {
      _fail(e.toString());
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setState(UpdateState s) {
    _state = s;
    notifyListeners();
  }

  void _fail(String message) {
    _errorMessage = message;
    _setState(UpdateState.error);
    if (kDebugMode) debugPrint('[KryptonUpdater] Error: $message');
  }

  /// Parses a top-level string value from raw JSON without a full JSON parser.
  String? _extractJson(String body, String key) {
    final RegExp re = RegExp('"$key":\\s*"([^"]+)"');
    return re.firstMatch(body)?.group(1);
  }

  /// Finds the first .apk browser_download_url in the assets array.
  String? _extractApkUrl(String body) {
    final RegExp re = RegExp(r'"browser_download_url":\s*"([^"]+\.apk)"');
    return re.firstMatch(body)?.group(1);
  }

  /// Returns true if [candidate] is strictly greater than [current].
  /// Compares dot-separated integer segments (e.g. "1.2.3" > "1.2.2").
  bool _isNewer(String candidate, String current) {
    final List<int> c = _segments(candidate);
    final List<int> v = _segments(current);
    final int len = c.length > v.length ? c.length : v.length;
    for (int i = 0; i < len; i++) {
      final int ci = i < c.length ? c[i] : 0;
      final int vi = i < v.length ? v[i] : 0;
      if (ci > vi) return true;
      if (ci < vi) return false;
    }
    return false;
  }

  List<int> _segments(String version) =>
      version.split('.').map((s) => int.tryParse(s) ?? 0).toList();

  /// Opens the APK file for installation using the platform's package installer.
  /// Requires `android.permission.REQUEST_INSTALL_PACKAGES` in AndroidManifest
  /// and a FileProvider authority configured for the app.
  Future<void> _installApk(File apkFile) async {
    // Use open_file_plus or android_intent_plus — whichever is in pubspec.
    // This stub delegates to whichever helper is present in the project.
    // Replace with the actual call once the dependency is confirmed.
    if (kDebugMode) {
      debugPrint('[KryptonUpdater] Install APK: ${apkFile.path}');
    }
    // Example with open_file_plus:
    //   await OpenFile.open(apkFile.path);
    //
    // Example with android_intent_plus:
    //   await AndroidIntent(
    //     action: 'action_view',
    //     data: Uri.file(apkFile.path).toString(),
    //     type: 'application/vnd.android.package-archive',
    //   ).launch();
  }

  /// Resets back to idle so the user can retry after an error.
  void reset() {
    _state        = UpdateState.idle;
    _errorMessage = null;
    _progress     = 0.0;
    notifyListeners();
  }
}