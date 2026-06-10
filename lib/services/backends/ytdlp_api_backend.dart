// lib/services/backends/ytdlp_api_backend.dart
// Calls a self-hosted yt-dlp REST API (see server/main.py).
// Full site support — whatever yt-dlp supports, the app supports.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../download_backend.dart';

class YtDlpApiBackend implements DownloadBackend {
  final String baseUrl; // e.g. 'http://192.168.1.100:8080'

  const YtDlpApiBackend({required this.baseUrl});

  @override
  String get name => 'Custom API';

  @override
  Future<ExtractResult> extract(String pageUrl, {String? preferredFormat}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/extract'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'url':    pageUrl,
        'format': preferredFormat ?? 'bestvideo+bestaudio/best',
      }),
    ).timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'API error ${res.statusCode}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return ExtractResult(
      url:      json['url']      as String,
      filename: json['filename'] as String,
      audioUrl: json['audioUrl'] as String?,
    );
  }
}