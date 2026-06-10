// lib/services/download_service.dart
// Routes extract() calls to the right backend based on platform + settings.
//
// Android/iOS:
//   mode=cobalt       → Cobalt only (fails if site unsupported)
//   mode=customApi    → Custom API only
//   mode=auto         → Cobalt first, falls back to Custom API
// Desktop:
//   always uses the local yt-dlp binary

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../config/krypton_config.dart';
import 'download_backend.dart';
import 'backends/cobalt_backend.dart';
import 'backends/local_backend.dart';
import 'backends/ytdlp_api_backend.dart';

class DownloadService {
  DownloadService._();
  static final instance = DownloadService._();

  // Resolve the correct backend for the current platform + config
  DownloadBackend _backend() {
    // Desktop always uses the local binary
    if (!Platform.isAndroid && !Platform.isIOS) {
      return LocalBinaryBackend();
    }

    final cfg = KryptonConfig.instance;

    switch (cfg.downloadBackend) {
      case DownloadBackendMode.cobalt:
        return CobaltBackend();
      case DownloadBackendMode.customApi:
        final url = cfg.customApiUrl;
        if (url.isEmpty) throw Exception('Custom API URL not configured');
        return YtDlpApiBackend(baseUrl: url);
      case DownloadBackendMode.auto:
        // Handled in extract() with fallback logic
        return CobaltBackend();
    }
  }

  // Extract a direct download URL from a page URL
  Future<ExtractResult> extract(String pageUrl, {String? preferredFormat}) async {
    // Desktop — no fallback needed
    if (!Platform.isAndroid && !Platform.isIOS) {
      return LocalBinaryBackend().extract(pageUrl, preferredFormat: preferredFormat);
    }

    final cfg = KryptonConfig.instance;

    // Auto mode: try Cobalt, fall back to custom API on failure
    if (cfg.downloadBackend == DownloadBackendMode.auto) {
      try {
        return await CobaltBackend().extract(pageUrl, preferredFormat: preferredFormat);
      } catch (e) {
        debugPrint('[DownloadService] Cobalt failed ($e), trying custom API…');
        final url = cfg.customApiUrl;
        if (url.isEmpty) rethrow; // no fallback configured
        return YtDlpApiBackend(baseUrl: url)
            .extract(pageUrl, preferredFormat: preferredFormat);
      }
    }

    return _backend().extract(pageUrl, preferredFormat: preferredFormat);
  }
}