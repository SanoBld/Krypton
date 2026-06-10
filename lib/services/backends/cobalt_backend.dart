// lib/services/backends/cobalt_backend.dart
// Uses the public Cobalt API (cobalt.tools) — supports ~25 sites.
// No binary, no server needed. Rate-limited on the public instance.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../download_backend.dart';

class CobaltBackend implements DownloadBackend {
  static const _baseUrl = 'https://api.cobalt.tools/';

  @override
  String get name => 'Cobalt (built-in)';

  @override
  Future<ExtractResult> extract(String pageUrl, {String? preferredFormat}) async {
    final res = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept':       'application/json',
      },
      body: jsonEncode({
        'url':           pageUrl,
        'downloadMode':  preferredFormat == 'audio' ? 'audio' : 'auto',
        'videoQuality':  '1080',
        'audioFormat':   'mp3',
        'filenameStyle': 'basic',
      }),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw Exception('Cobalt HTTP ${res.statusCode}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final status = json['status'] as String? ?? '';

    // Cobalt returns tunnel, redirect, or picker
    if (status == 'tunnel' || status == 'redirect') {
      return ExtractResult(
        url:      json['url'] as String,
        filename: json['filename'] as String? ?? _guessFilename(pageUrl),
      );
    }

    // picker = multiple streams (e.g. video + audio separate)
    if (status == 'picker') {
      final items = (json['picker'] as List?) ?? [];
      final video = items.firstWhere(
        (i) => i['type'] == 'video',
        orElse: () => items.first,
      );
      final audio = items.firstWhere(
        (i) => i['type'] == 'audio',
        orElse: () => null,
      );
      return ExtractResult(
        url:      video['url'] as String,
        filename: json['filename'] as String? ?? _guessFilename(pageUrl),
        audioUrl: audio?['url'] as String?,
      );
    }

    // error or rateLimited
    final msg = json['error']?['code'] ?? json['text'] ?? status;
    throw Exception('Cobalt error: $msg');
  }

  String _guessFilename(String url) {
    final uri  = Uri.tryParse(url);
    final host = uri?.host.replaceFirst('www.', '') ?? 'download';
    return '$host.mp4';
  }
}