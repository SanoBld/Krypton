// lib/services/download_backend.dart
// Abstract interface all download backends must implement.

// Result returned by any backend
class ExtractResult {
  final String url;       // direct download URL
  final String filename;  // suggested filename with extension
  final String? audioUrl; // separate audio stream (if any)

  const ExtractResult({
    required this.url,
    required this.filename,
    this.audioUrl,
  });
}

abstract class DownloadBackend {
  // Extract a direct download URL from a page URL
  Future<ExtractResult> extract(String pageUrl, {String? preferredFormat});

  // Human-readable name shown in settings
  String get name;
}