// lib/services/binary_manager.dart
// Extracts bundled binaries (yt-dlp) to the app data folder on first run.
// The asset is always named 'assets/binaries/yt-dlp' regardless of platform.
// On Windows, it is saved as 'yt-dlp.exe' after extraction.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class BinaryManager {
  BinaryManager._();
  static final instance = BinaryManager._();

  // Cached path after first extraction
  String? _ytDlpPath;

  // Returns the ready-to-use path, extracting the binary if needed
  Future<String?> get ytDlpPath async {
    _ytDlpPath ??= await _extract();
    return _ytDlpPath;
  }

  Future<String?> _extract() async {
    try {
      // Pick the right output filename per platform
      final outName = Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';

      final dir    = await getApplicationSupportDirectory();
      final binDir = Directory('${dir.path}/binaries');
      await binDir.create(recursive: true);

      final outFile = File('${binDir.path}/$outName');

      // Only extract once — skip if already present
      if (!outFile.existsSync()) {
        // Load the asset bundled at build time
        final data = await rootBundle.load('assets/binaries/yt-dlp');
        await outFile.writeAsBytes(data.buffer.asUint8List());
        debugPrint('[BinaryManager] Extracted yt-dlp to ${outFile.path}');
      }

      // Linux + Android need the execute bit set
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', outFile.path]);
      }

      return outFile.path;
    } catch (e) {
      debugPrint('[BinaryManager] Extraction failed: $e');
      return null;
    }
  }

  // Quick sanity check — runs yt-dlp --version
  Future<bool> isYtDlpAvailable() async {
    final path = await ytDlpPath;
    if (path == null) return false;
    try {
      final result = await Process.run(path, ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}