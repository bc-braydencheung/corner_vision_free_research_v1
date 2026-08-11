import 'dart:convert';
import 'dart:io';

import '../models/marksix_mobile.dart';
import 'marksix_engine.dart';
import 'marksix_store.dart';

/// Service layer for Mark Six data, stats, prediction, and self-correction.
class MarkSixService {
  MarkSixService({
    MarkSixStore? store,
    MarkSixEngine? engine,
    // Default: GitHub Pages auto-deploy. Change to your fork's URL if needed.
    this.dataSourceUrl = '',
  }) : store = store ?? MarkSixStore(),
       engine = engine ?? MarkSixEngine();

  final MarkSixStore store;
  final MarkSixEngine engine;
  final String dataSourceUrl;

  /// Returns the effective data source URL, trying environment variable first.
  String get effectiveSourceUrl {
    if (dataSourceUrl.isNotEmpty) return dataSourceUrl;
    // Auto-detect: if repo is forked, GitHub Pages URL follows this pattern.
    // Set MARK_SIX_DATA_URL environment or override dataSourceUrl.
    return const String.fromEnvironment(
      'MARK_SIX_DATA_URL',
      defaultValue: 'https://YOUR_USERNAME.github.io/corner_vision_free_research_v1/draws.json',
    );
  }

  // ---- Initialization ----

  Future<void> initialize() => store.initialize();

  /// Fetch ALL draws from the remote data source URL.
  Future<MarkSixSeedData?> fetchFromRemote(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'EdgeWise/1.0 (personal research)');
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = json.decode(body) as Map<String, Object?>;
        client.close();
        return MarkSixSeedData.fromJson(data);
      }
      client.close();
    } catch (_) {}
    return null;
  }

  /// Download all draws from remote and merge with local storage.
  Future<int> syncFromRemote({String? url}) async {
    final sourceUrl = url ?? effectiveSourceUrl;
    final seed = await fetchFromRemote(sourceUrl);
    if (seed == null || seed.draws.isEmpty) return 0;
    return store.mergeDraws(seed.draws);
  }

  /// Load bundled seed data and merge with local storage
  Future<MarkSixSeedData> loadSeed(MarkSixSeedData bundled) async {
    await store.initialize();
    final local = await store.loadDraws();
    if (local.isEmpty && bundled.draws.isNotEmpty) {
      await store.saveDraws(bundled.draws);
      return bundled;
    }
    if (local.isNotEmpty) {
      await store.mergeDraws(bundled.draws);
      final merged = await store.loadDraws();
      return bundled.withDraws(merged);
    }
    return bundled;
  }

  // ---- Statistics ----

  Future<MarkSixStats> computeAndSaveStats() async {
    final draws = await store.loadDraws();
    final stats = engine.computeStats(draws);
    await store.saveStats(stats);
    return stats;
  }

  Future<MarkSixStats?> loadCachedStats() => store.loadStats();

  // ---- Prediction ----

  Future<MarkSixPrediction> generatePrediction() async {
    final draws = await store.loadDraws();
    final prediction = engine.predict(draws);
    await store.savePrediction(prediction);
    return prediction;
  }

  Future<MarkSixPrediction?> loadCachedPrediction() => store.loadPrediction();

  // ---- Self-correction ----

  Future<MarkSixCorrection> runCorrection(MarkSixDraw actualDraw) async {
    final prediction = await store.loadPrediction();
    final history = await store.loadCorrections();
    if (prediction == null) {
      return MarkSixCorrection(
        drawDate: actualDraw.drawDate,
        predictedNumbers: const [],
        actualNumbers: actualDraw.numbers,
        matches: 0,
      );
    }
    final correction = engine.correct(
      prediction: prediction,
      actualDraw: actualDraw,
      history: history,
    );
    await store.addCorrection(correction);
    return correction;
  }

  Future<List<MarkSixCorrection>> loadCorrections() =>
      store.loadCorrections();

  // ---- Backtest ----

  Future<List<MarkSixCorrection>> runBacktest({int minTraining = 100}) async {
    final draws = await store.loadDraws();
    final results = engine.backtest(draws, minTraining: minTraining);
    if (results.isNotEmpty) {
      await store.saveCorrections(results);
    }
    return results;
  }

  /// Try to discover the working API endpoint by testing common patterns.
  Future<String?> discoverApiEndpoint() async {
    final candidates = <String>[
      'https://bet.hkjc.com/marksix/Results/GetResults?sd=20260101&ed=20260131&lang=ch',
      'https://bet.hkjc.com/marksix/GetJSONResult?sd=20260101&ed=20260131&lang=ch',
      'https://bet.hkjc.com/marksix/api/Results/Search?startDate=2026-01-01&endDate=2026-01-31&lang=ch',
      'https://bet.hkjc.com/marksix/api/Result/GetResult?drawDate=2026-01-01&lang=ch',
      'https://bet.hkjc.com/marksix/result/getResult?sd=20260101&ed=20260131',
    ];
    for (final url in candidates) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 8);
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('User-Agent',
            'EdgeWise/1.0 (personal research)');
        request.headers.set('Accept', 'application/json');
        final response = await request.close();
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          if (body.contains('{') || body.contains('[')) {
            try {
              json.decode(body);
              client.close();
              return url;
            } catch (_) {}
          }
        }
        client.close();
      } catch (_) {}
    }
    return null;
  }

  /// Fetch new draws from API since a given date.
  Future<List<MarkSixDraw>> fetchNewDraws({
    required String apiUrl, required String sinceDate,
  }) async {
    final now = DateTime.now().toString().substring(0, 10);
    final url = apiUrl
        .replaceAll('20260101', sinceDate.replaceAll('-', ''))
        .replaceAll('20260131', now.replaceAll('-', ''))
        .replaceAll('2026-01-01', sinceDate)
        .replaceAll('2026-01-31', now);
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'EdgeWise/1.0 (personal research)');
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = json.decode(body) as Map<String, Object?>;
        final items = (data['results'] ?? data['data'] ??
            data['Result'] ?? data['draws'] ?? []) as List<Object?>?;
        if (items != null) {
          return items
              .map((e) => MarkSixDraw.fromJson(
                  (e as Map).cast<String, Object?>()))
              .toList();
        }
      }
      client.close();
    } catch (_) {}
    return [];
  }
}
