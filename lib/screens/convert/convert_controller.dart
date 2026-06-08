// lib/screens/convert/convert_controller.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../config/krypton_config.dart';

enum ConvertStatus { idle, running, done, error }

class ConvertJob {
  final String inputPath;
  final String outputFormat;
  String status;
  double progress; // FFmpeg doesn't always give %, kept for future parsing
  String log;

  ConvertJob({required this.inputPath, required this.outputFormat})
      : status   = 'En attente',
        progress = 0,
        log      = '';
}

class ConvertController extends ChangeNotifier {
  final _jobs = <ConvertJob>[];
  List<ConvertJob> get jobs => List.unmodifiable(_jobs);

  ConvertStatus _state = ConvertStatus.idle;
  ConvertStatus get state => _state;

  String _selectedFormat = 'mp4';
  String get selectedFormat => _selectedFormat;
  void setFormat(String f) { _selectedFormat = f; notifyListeners(); }

  static const supportedFormats = ['mp4', 'mp3', 'mkv', 'webm', 'avi', 'flac', 'wav'];

  void addFiles(List<String> paths) {
    for (final p in paths) {
      _jobs.add(ConvertJob(inputPath: p, outputFormat: _selectedFormat));
    }
    notifyListeners();
  }

  void removeJob(int index) { _jobs.removeAt(index); notifyListeners(); }

  void clearAll() { _jobs.clear(); _state = ConvertStatus.idle; notifyListeners(); }

  Future<void> startAll() async {
    if (_jobs.isEmpty) return;
    _state = ConvertStatus.running;
    notifyListeners();

    final cfg       = KryptonConfig.instance;
    final outDir    = cfg.convertPath.isNotEmpty ? cfg.convertPath : '.';
    final workers   = cfg.maxWorkers;

    for (int i = 0; i < _jobs.length; i += workers) {
      final batch = _jobs.sublist(i, (i + workers).clamp(0, _jobs.length));
      await Future.wait(batch.map((j) => _convertOne(j, outDir)));
    }

    _state = ConvertStatus.done;
    notifyListeners();
  }

  Future<void> _convertOne(ConvertJob job, String outDir) async {
    job.status = 'Conversion…';
    notifyListeners();

    try {
      final inputFile  = File(job.inputPath);
      final baseName   = inputFile.uri.pathSegments.last
          .replaceAll(RegExp(r'\.[^.]+$'), '');
      final outputPath = '$outDir/$baseName.${job.outputFormat}';

      final process = await Process.start('ffmpeg', [
        '-y',
        '-i', job.inputPath,
        '-progress', 'pipe:1',
        outputPath,
      ]);

      process.stdout
          .transform(const SystemEncoding().decoder)
          .listen((line) {
        job.log += line;
        // FFmpeg progress lines: out_time_ms=123456
        if (line.startsWith('progress=end')) {
          job.progress = 1.0;
        }
        notifyListeners();
      });

      process.stderr
          .transform(const SystemEncoding().decoder)
          .listen((line) { job.log += line; notifyListeners(); });

      final code = await process.exitCode;
      job.status   = code == 0 ? 'Terminé ✓' : 'Erreur (code $code)';
      job.progress = code == 0 ? 1.0 : job.progress;
    } catch (e) {
      job.status = 'Erreur: $e';
    }
    notifyListeners();
  }
}