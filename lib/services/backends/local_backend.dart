// lib/services/backends/local_backend.dart
// Runs the bundled yt-dlp binary directly — desktop only (Linux, Windows).

import 'dart:convert';
import 'dart:io';
import '../download_backend.dart';
import '../binary_manager.dart';

class LocalBinaryBackend implements DownloadBackend {
  @override
  String get name => 'Local binary (yt-dlp)';

  @override
  Future<ExtractResult> extract(String pageUrl, {String? preferredFormat}) async {
    final ytDlp = await BinaryManager.instance.ytDlpPath;
    if (ytDlp == null) throw Exception('yt-dlp binary not found');

    final result = await Process.run(ytDlp, [
      '--dump-json',
      '--no-playlist',
      if (preferredFormat != null) ...['-f', preferredFormat],
      pageUrl,
    ]);

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString().trim());
    }

    final info = jsonDecode(result.stdout as String) as Map<String, dynamic>;

    // Direct URL — some sites return a single url, others a list of formats
    final directUrl = info['url'] as String? ??
        ((info['formats'] as List?)?.lastWhere(
          (_) => true,
          orElse: () => <String, dynamic>{},
        )['url'] as String? ?? '');

    if (directUrl.isEmpty) throw Exception('No direct URL found');

    final title = info['title'] as String? ?? 'download';
    final ext   = info['ext']   as String? ?? 'mp4';

    return ExtractResult(
      url:      directUrl,
      filename: '$title.$ext',
    );
  }
}