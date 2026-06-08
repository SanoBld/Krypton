// lib/screens/download/download_controller.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../config/krypton_config.dart';

enum DownloadStatus { idle, running, paused, done, error }

class DownloadItem {
  final String   url;
  String         status;
  double         progress; // 0.0–1.0
  String         log;

  DownloadItem({required this.url})
      : status   = 'En attente',
        progress = 0,
        log      = '';
}

class DownloadController extends ChangeNotifier {
  final _items = <DownloadItem>[];
  List<DownloadItem> get items => List.unmodifiable(_items);

  DownloadStatus _state = DownloadStatus.idle;
  DownloadStatus get state => _state;

  String _urlInput = '';
  set urlInput(String v) => _urlInput = v;

  // ── Add URLs (one per line) ─────────────────────────────────────────
  void addUrls(String raw) {
    final urls = raw
        .split('\n')
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    for (final u in urls) {
      _items.add(DownloadItem(url: u));
    }
    notifyListeners();
  }

  void removeItem(int index) {
    _items.removeAt(index);
    notifyListeners();
  }

  void clearAll() {
    _items.clear();
    _state = DownloadStatus.idle;
    notifyListeners();
  }

  // ── Launch queue ────────────────────────────────────────────────────
  Future<void> startQueue() async {
    if (_items.isEmpty) return;
    _state = DownloadStatus.running;
    notifyListeners();

    final cfg        = KryptonConfig.instance;
    final outputDir  = cfg.downloadPath.isNotEmpty ? cfg.downloadPath : '.';
    final maxWorkers = cfg.maxWorkers;

    // Process in batches of maxWorkers
    for (int i = 0; i < _items.length; i += maxWorkers) {
      final batch = _items.sublist(
        i,
        (i + maxWorkers).clamp(0, _items.length),
      );
      await Future.wait(batch.map((item) => _downloadOne(item, outputDir)));
    }

    _state = DownloadStatus.done;
    notifyListeners();
  }

  Future<void> _downloadOne(DownloadItem item, String outputDir) async {
    item.status   = 'Téléchargement…';
    item.progress = 0;
    notifyListeners();

    try {
      final process = await Process.start('yt-dlp', [
        '--newline',
        '--progress',
        '-o', '$outputDir/%(title)s.%(ext)s',
        item.url,
      ]);

      // Parse stdout for progress lines
      process.stdout
          .transform(const SystemEncoding().decoder)
          .listen((line) {
        item.log += line;
        // yt-dlp progress format: [download]  42.3% of ...
        final match = RegExp(r'\[download\]\s+([\d.]+)%').firstMatch(line);
        if (match != null) {
          item.progress = double.tryParse(match.group(1)!) ?? 0 / 100;
        }
        notifyListeners();
      });

      process.stderr
          .transform(const SystemEncoding().decoder)
          .listen((line) { item.log += '[ERR] $line'; notifyListeners(); });

      final code = await process.exitCode;
      item.status   = code == 0 ? 'Terminé ✓' : 'Erreur (code $code)';
      item.progress = code == 0 ? 1.0 : item.progress;
    } catch (e) {
      item.status = 'Erreur: $e';
    }
    notifyListeners();
  }
}