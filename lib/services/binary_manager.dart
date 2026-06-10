// lib/services/binary_manager.dart
// Extracts bundled binaries (yt-dlp, ffmpeg) to the app data folder on first run.
// All assets are named without extension; on Windows they are saved as .exe after extraction.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class BinaryManager {
  BinaryManager._();
  static final instance = BinaryManager._();

  String? _ytDlpPath;
  String? _ffmpegPath;

  // Returns the ready-to-use path to yt-dlp
  Future<String?> get ytDlpPath async {
    _ytDlpPath ??= await _extract('yt-dlp');
    return _ytDlpPath;
  }

  // Returns the ready-to-use path to ffmpeg
  Future<String?> get ffmpegPath async {
    _ffmpegPath ??= await _extract('ffmpeg');
    return _ffmpegPath;
  }

  Future<String?> _extract(String name) async {
    try {
      final outName = Platform.isWindows ? '$name.exe' : name;
      final dir     = await getApplicationSupportDirectory();
      final binDir  = Directory('${dir.path}/binaries');
      await binDir.create(recursive: true);

      final outFile = File('${binDir.path}/$outName');

      // Only extract once — skip if already present
      if (!outFile.existsSync()) {
        final data = await rootBundle.load('assets/binaries/$name');
        await outFile.writeAsBytes(data.buffer.asUint8List());
        debugPrint('[BinaryManager] Extracted $name → ${outFile.path}');
      }

      // Linux + Android need the execute bit
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', outFile.path]);
      }

      return outFile.path;
    } catch (e) {
      debugPrint('[BinaryManager] Failed to extract $name: $e');
      return null;
    }
  }

  // Runs yt-dlp --version to confirm the binary works
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

  // Runs ffmpeg -version to confirm the binary works
  Future<bool> isFfmpegAvailable() async {
    final path = await ffmpegPath;
    if (path == null) return false;
    try {
      final result = await Process.run(path, ['-version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}