import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/marksix_mobile.dart';

/// Local storage for Mark Six data, stats, predictions, and corrections.
class MarkSixStore {
  MarkSixStore({Directory? directory}) : _directory = directory;

  Directory? _directory;
  bool _initialized = false;

  Future<Directory> _dir() async {
    if (!_initialized || _directory == null) {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        final appDir = await getApplicationDocumentsDirectory();
        _directory = Directory('${appDir.path}/marksix');
      } else {
        _directory = Directory('${Directory.current.path}/data/marksix');
      }
      if (!_directory!.existsSync()) {
        _directory!.createSync(recursive: true);
      }
      _initialized = true;
    }
    return _directory!;
  }

  Future<void> initialize() async {
    await _dir();
  }

  Future<Directory> storageDirectory() => _dir();

  // ---- Draws ----

  Future<List<MarkSixDraw>> loadDraws() async {
    final dir = await _dir();
    final file = File('${dir.path}/draws.json');
    if (!file.existsSync()) return [];
    try {
      final content = await file.readAsString();
      final list = json.decode(content) as List<Object?>;
      return list
          .map((e) => MarkSixDraw.fromJson((e as Map).cast<String, Object?>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDraws(List<MarkSixDraw> draws) async {
    final dir = await _dir();
    final file = File('${dir.path}/draws.json');
    final list = draws.map((d) => d.toJson()).toList();
    await file.writeAsString(json.encode(list));
  }

  Future<int> mergeDraws(List<MarkSixDraw> newDraws) async {
    final existing = await loadDraws();
    final existingNumbers = existing.map((d) => d.drawNumber).toSet();
    var added = 0;
    for (final draw in newDraws) {
      if (!existingNumbers.contains(draw.drawNumber)) {
        existing.add(draw);
        existingNumbers.add(draw.drawNumber);
        added++;
      }
    }
    existing.sort((a, b) => a.drawDate.compareTo(b.drawDate));
    await saveDraws(existing);
    return added;
  }

  // ---- Stats ----

  Future<MarkSixStats?> loadStats() async {
    final dir = await _dir();
    final file = File('${dir.path}/stats.json');
    if (!file.existsSync()) return null;
    try {
      final content = await file.readAsString();
      return MarkSixStats.fromJson(
        (json.decode(content) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStats(MarkSixStats stats) async {
    final dir = await _dir();
    final file = File('${dir.path}/stats.json');
    await file.writeAsString(json.encode(stats.toJson()));
  }

  // ---- Prediction ----

  Future<MarkSixPrediction?> loadPrediction() async {
    final dir = await _dir();
    final file = File('${dir.path}/prediction.json');
    if (!file.existsSync()) return null;
    try {
      final content = await file.readAsString();
      return MarkSixPrediction.fromJson(
        (json.decode(content) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> savePrediction(MarkSixPrediction prediction) async {
    final dir = await _dir();
    final file = File('${dir.path}/prediction.json');
    await file.writeAsString(json.encode({
      'recommendedNumbers': prediction.recommendedNumbers,
      'specialNumber': prediction.specialNumber,
      'confidence': prediction.confidence,
      'confidenceLabel': prediction.confidenceLabel,
      'modelVersion': prediction.modelVersion,
      'generatedAt': prediction.generatedAt,
      'factors': prediction.factors,
    }));
  }

  // ---- Corrections ----

  Future<List<MarkSixCorrection>> loadCorrections() async {
    final dir = await _dir();
    final file = File('${dir.path}/corrections.json');
    if (!file.existsSync()) return [];
    try {
      final content = await file.readAsString();
      final list = json.decode(content) as List<Object?>;
      return list
          .map((e) => MarkSixCorrection.fromJson(
              (e as Map).cast<String, Object?>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCorrections(List<MarkSixCorrection> corrections) async {
    final dir = await _dir();
    final file = File('${dir.path}/corrections.json');
    final list = corrections.map((c) => c.toJson()).toList();
    await file.writeAsString(json.encode(list));
  }

  Future<void> addCorrection(MarkSixCorrection correction) async {
    final existing = await loadCorrections();
    existing.add(correction);
    await saveCorrections(existing);
  }
}
