import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';

import '../models/football_mobile.dart';
import '../models/forecast_data.dart';
import 'football_mobile_engine.dart';
import 'football_store.dart';

class FootballSyncStatus {
  const FootballSyncStatus({
    required this.message,
    required this.hasNewResults,
    required this.newMatches,
    required this.fixturesChanged,
    required this.datasetVersion,
    required this.latestResults,
    this.marketSnapshotCount = 0,
    this.weatherSnapshotCount = 0,
    this.latestMarketCapturedAt,
    this.latestWeatherCapturedAt,
    this.job,
  });

  final String message;
  final bool hasNewResults;
  final int newMatches;
  final bool fixturesChanged;
  final String datasetVersion;
  final Map<String, String> latestResults;
  final int marketSnapshotCount;
  final int weatherSnapshotCount;
  final DateTime? latestMarketCapturedAt;
  final DateTime? latestWeatherCapturedAt;
  final FootballTrainingJob? job;
}

class FootballMobileLoad {
  const FootballMobileLoad({
    required this.leagues,
    required this.settlementResults,
    required this.status,
  });

  final List<LeagueForecastData> leagues;
  final List<MatchResult> settlementResults;
  final FootballSyncStatus status;
}

class FootballMobileService {
  FootballMobileService({
    FootballStore? store,
    FootballMobileEngine? engine,
    this.minimumInterval = const Duration(milliseconds: 350),
    this.baseUrl = 'https://www.football-data.co.uk/mmz4281',
    this.fixturesUrl = 'https://www.football-data.co.uk/fixtures.csv',
    this.firstSeasonYear = 2000,
  }) : store = store ?? FootballStore(),
       engine = engine ?? FootballMobileEngine();

  final FootballStore store;
  final FootballMobileEngine engine;
  final Duration minimumInterval;
  final String baseUrl;
  final String fixturesUrl;
  final int firstSeasonYear;
  DateTime? _lastRequest;

  Future<FootballMobileLoad> loadCached(
    List<LeagueForecastData> bundled,
  ) async {
    final dataset = await store.loadDataset();
    final model = await store.loadModel();
    final job = await store.loadJob();
    final needsTraining = await store.needsTraining();
    final oddsSnapshots = await store.loadOddsSnapshots();
    final weatherSnapshots = await store.loadWeatherSnapshots();
    final useMobile = model != null || dataset.fixtures.isNotEmpty;
    return FootballMobileLoad(
      leagues: useMobile
          ? engine.predictLeagues(
              bundled: bundled,
              dataset: dataset,
              model: model,
            )
          : bundled,
      settlementResults: _settlements(dataset),
      status: FootballSyncStatus(
        message: needsTraining
            ? '已載入手機足球資料 · 新賽果尚待重新訓練'
            : '已載入手機足球資料 · 開 App 後會檢查新賽果及賽程',
        hasNewResults: needsTraining,
        newMatches: 0,
        fixturesChanged: false,
        datasetVersion: dataset.datasetVersion,
        latestResults: _latestResults(dataset),
        marketSnapshotCount: oddsSnapshots.length,
        weatherSnapshotCount: weatherSnapshots.length,
        latestMarketCapturedAt: _latestOddsTimestamp(oddsSnapshots),
        latestWeatherCapturedAt: _latestWeatherTimestamp(weatherSnapshots),
        job: job,
      ),
    );
  }

  Future<FootballMobileLoad> sync(List<LeagueForecastData> bundled) async {
    final current = await store.loadDataset();
    final rowsById = {for (final row in current.rows) row.matchId: row};
    final downloaded = <FootballMatchRecord>[];
    var successfulSources = 0;
    for (final league in current.leagues) {
      for (final division in [league.code, league.supportCode]) {
        final rows = await _downloadLatestResults(
          division,
          current.trainedThrough(division),
        );
        if (rows != null) {
          downloaded.addAll(rows);
          successfulSources++;
        }
      }
    }
    if (successfulSources == 0) {
      throw const HttpException('No football result source was available.');
    }
    final additions = <FootballMatchRecord>[];
    var corrections = 0;
    for (final row in downloaded) {
      if (!row.isComplete) {
        continue;
      }
      final existing = rowsById[row.matchId];
      if (existing == null) {
        additions.add(row);
        rowsById[row.matchId] = row;
      } else if (_recordFingerprint(existing) != _recordFingerprint(row)) {
        rowsById[row.matchId] = row;
        corrections++;
      }
    }
    final downloadedFixtures = await _downloadFixtures(current.leagues);
    final fixtures = downloadedFixtures ?? current.fixtures;
    final oldFixtures = current.fixtures.map(_recordFingerprint).toSet();
    final newFixtures = fixtures.map(_recordFingerprint).toSet();
    final fixturesChanged =
        oldFixtures.length != newFixtures.length ||
        !oldFixtures.containsAll(newFixtures);
    final rows = rowsById.values.toList()..sort(_compareMatches);
    final resultsChanged = additions.isNotEmpty || corrections > 0;
    final dataset = MobileFootballDataset(
      schemaVersion: current.schemaVersion,
      datasetVersion: resultsChanged
          ? _datasetVersion(rows)
          : current.datasetVersion,
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      leagues: current.leagues,
      rows: rows,
      fixtures: fixtures,
    );
    if (resultsChanged || fixturesChanged) {
      await store.saveDataset(dataset);
    }
    if (resultsChanged) {
      await store.markTrainingNeeded();
    }
    final active = resultsChanged || fixturesChanged ? dataset : current;
    final model = await store.loadModel();
    final job = await store.loadJob();
    final needsTraining = await store.needsTraining();
    final oddsSnapshots = await store.loadOddsSnapshots();
    final weatherSnapshots = await store.loadWeatherSnapshots();
    final message = [
      if (additions.isEmpty && corrections == 0)
        '足球賽果是最新版本'
      else ...[
        if (additions.isNotEmpty) '已加入 ${additions.length} 場新足球賽果',
        if (corrections > 0) '已核實並修正 $corrections 場足球賽果',
      ],
      fixturesChanged ? '未來賽程已更新' : '未來賽程沒有變更',
      if (needsTraining) '新賽果尚待重新訓練',
    ].join(' · ');
    return FootballMobileLoad(
      leagues: engine.predictLeagues(
        bundled: bundled,
        dataset: active,
        model: model,
      ),
      settlementResults: _settlements(active),
      status: FootballSyncStatus(
        message: message,
        hasNewResults: needsTraining,
        newMatches: additions.length,
        fixturesChanged: fixturesChanged,
        datasetVersion: active.datasetVersion,
        latestResults: _latestResults(active),
        marketSnapshotCount: oddsSnapshots.length,
        weatherSnapshotCount: weatherSnapshots.length,
        latestMarketCapturedAt: _latestOddsTimestamp(oddsSnapshots),
        latestWeatherCapturedAt: _latestWeatherTimestamp(weatherSnapshots),
        job: job,
      ),
    );
  }

  static DateTime? _latestOddsTimestamp(List<FootballOddsSnapshot> snapshots) {
    if (snapshots.isEmpty) {
      return null;
    }
    return snapshots
        .map((snapshot) => snapshot.capturedAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);
  }

  static DateTime? _latestWeatherTimestamp(
    List<FootballWeatherSnapshot> snapshots,
  ) {
    if (snapshots.isEmpty) {
      return null;
    }
    return snapshots
        .map((snapshot) => snapshot.capturedAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);
  }

  Future<List<FootballMatchRecord>?> _downloadLatestResults(
    String division,
    String latestDate,
  ) async {
    final now = DateTime.now().toUtc();
    final currentStart = now.month >= 7 ? now.year : now.year - 1;
    final parsedLatest = DateTime.tryParse(latestDate);
    final firstStart = parsedLatest == null
        ? currentStart - 1
        : parsedLatest.month >= 7
        ? parsedLatest.year
        : parsedLatest.year - 1;
    final output = <FootballMatchRecord>[];
    var successful = false;
    for (var startYear = firstStart; startYear <= currentStart; startYear++) {
      final code =
          '${(startYear % 100).toString().padLeft(2, '0')}'
          '${((startYear + 1) % 100).toString().padLeft(2, '0')}';
      try {
        final body = await _get('$baseUrl/$code/$division.csv');
        output.addAll(parseFootballDataMatches(body, division: division));
        successful = true;
      } on HttpException catch (error) {
        if (!error.message.contains('404')) {
          continue;
        }
      } on Object {
        continue;
      }
    }
    return successful ? output : null;
  }

  Future<List<FootballMatchRecord>?> _downloadFixtures(
    List<FootballLeagueConfig> leagues,
  ) async {
    try {
      final target = leagues.map((league) => league.code).toSet();
      return parseFootballDataMatches(await _get(fixturesUrl))
          .where((row) => target.contains(row.division) && !row.isComplete)
          .toList();
    } on Object {
      return null;
    }
  }

  Future<String> _get(String url) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _getOnce(url);
      } on Object catch (error) {
        lastError = error;
        if (attempt == 2) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 450 * (attempt + 1)));
      }
    }
    throw lastError!;
  }

  Future<String> _getOnce(String url) async {
    final previous = _lastRequest;
    if (previous != null) {
      final wait = minimumInterval - DateTime.now().difference(previous);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }
    _lastRequest = DateTime.now();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.parse(url);
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'EdgeWise/6.0 (+https://www.football-data.co.uk/)',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Football-Data returned ${response.statusCode}',
          uri: uri,
        );
      }
      return await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
  }

  static List<MatchResult> _settlements(MobileFootballDataset dataset) {
    final target = dataset.leagues.map((league) => league.code).toSet();
    return dataset.rows
        .where((row) => target.contains(row.division))
        .toList()
        .reversed
        .take(3000)
        .map(
          (row) => MatchResult(
            matchId: row.matchId,
            actualTotalCorners: row.homeCorners! + row.awayCorners!,
          ),
        )
        .toList(growable: false);
  }

  static Map<String, String> _latestResults(MobileFootballDataset dataset) => {
    for (final league in dataset.leagues)
      league.code: dataset.trainedThrough(league.code),
  };

  static String _datasetVersion(List<FootballMatchRecord> rows) {
    var hash = 2166136261;
    for (final row in rows) {
      for (final codeUnit in _recordFingerprint(row).codeUnits) {
        hash = ((hash ^ codeUnit) * 16777619) & 0x7fffffff;
      }
    }
    return 'football-${rows.length}-${hash.toRadixString(16)}';
  }

  static String _recordFingerprint(FootballMatchRecord row) =>
      jsonEncode(row.toCompact());

  static int _compareMatches(
    FootballMatchRecord left,
    FootballMatchRecord right,
  ) {
    final date = left.date.compareTo(right.date);
    return date != 0 ? date : left.matchId.compareTo(right.matchId);
  }

  /// Bootstrap: download ALL historical football data from scratch.
  /// Reports progress via [onProgress] callback (0.0 to 1.0).
  Future<MobileFootballDataset?> bootstrap({
    required List<FootballLeagueConfig> leagues,
    void Function(double progress, String status)? onProgress,
  }) async {
    final divisions = <String>[];
    for (final league in leagues) {
      divisions.add(league.code);
      if (league.supportCode.isNotEmpty) divisions.add(league.supportCode);
    }
    final now = DateTime.now().toUtc();
    final currentStart = now.month >= 7 ? now.year : now.year - 1;
    final years = <int>[];
    for (var y = firstSeasonYear; y <= currentStart; y++) {
      years.add(y);
    }

    final totalTasks = divisions.length * years.length;
    var completed = 0;
    void report(String status) {
      completed++;
      onProgress?.call(completed / totalTasks, status);
    }

    final allRows = <FootballMatchRecord>[];
    var anySuccess = false;

    for (final division in divisions) {
      for (final startYear in years) {
        final code = '${(startYear % 100).toString().padLeft(2, '0')}'
            '${((startYear + 1) % 100).toString().padLeft(2, '0')}';
        try {
          final body = await _get('$baseUrl/$code/$division.csv');
          final rows = parseFootballDataMatches(body, division: division);
          if (rows.isNotEmpty) {
            allRows.addAll(rows);
            anySuccess = true;
          }
          report('$division $code: ${rows.length} matches');
        } on Object {
          report('$division $code: unavailable');
        }
      }
    }

    if (!anySuccess) return null;

    List<FootballMatchRecord> fixtures = [];
    try {
      fixtures = parseFootballDataMatches(await _get(fixturesUrl))
          .where((row) =>
              divisions.contains(row.division) && !row.isComplete)
          .toList();
    } on Object {
      // fixtures optional
    }

    allRows.sort((a, b) => a.date.compareTo(b.date));
    final dataset = MobileFootballDataset(
      schemaVersion: 2,
      datasetVersion: 'boot-${DateTime.now().millisecondsSinceEpoch}',
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      leagues: leagues,
      rows: allRows,
      fixtures: fixtures,
    );
    await store.saveDataset(dataset);
    return dataset;
  }
}

List<FootballMatchRecord> parseFootballDataMatches(
  String csvBody, {
  String? division,
}) {
  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(csvBody.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
  if (rows.isEmpty) {
    return [];
  }
  final headers = rows.first.map((value) => value.toString()).toList();
  int index(String name) => headers.indexOf(name);
  final divisionIndex = index('Div');
  final dateIndex = index('Date');
  final homeIndex = index('HomeTeam');
  final awayIndex = index('AwayTeam');
  if (dateIndex < 0 || homeIndex < 0 || awayIndex < 0) {
    return [];
  }
  String? value(List<dynamic> row, String name) {
    final position = index(name);
    if (position < 0 || position >= row.length) {
      return null;
    }
    final text = row[position].toString().trim();
    return text.isEmpty ? null : text;
  }

  double? number(List<dynamic> row, List<String> names) {
    for (final name in names) {
      final parsed = double.tryParse(value(row, name) ?? '');
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  final output = <FootballMatchRecord>[];
  for (final row in rows.skip(1)) {
    if (row.length <= awayIndex) {
      continue;
    }
    final date = _parseFootballDate(row[dateIndex].toString());
    final home = row[homeIndex].toString().trim();
    final away = row[awayIndex].toString().trim();
    final rowDivision = divisionIndex >= 0 && divisionIndex < row.length
        ? row[divisionIndex].toString().trim()
        : division;
    if (date == null ||
        home.isEmpty ||
        away.isEmpty ||
        rowDivision == null ||
        rowDivision.isEmpty) {
      continue;
    }
    String iso(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    output.add(
      FootballMatchRecord(
        division: rowDivision,
        date: iso(date),
        homeTeam: home,
        awayTeam: away,
        homeCorners: number(row, const ['HC'])?.toInt(),
        awayCorners: number(row, const ['AC'])?.toInt(),
        homeGoals: number(row, const ['FTHG'])?.toInt(),
        awayGoals: number(row, const ['FTAG'])?.toInt(),
        homeShots: number(row, const ['HS'])?.toInt(),
        awayShots: number(row, const ['AS'])?.toInt(),
        homeShotsOnTarget: number(row, const ['HST'])?.toInt(),
        awayShotsOnTarget: number(row, const ['AST'])?.toInt(),
        homeOdds: number(row, const ['AvgH', 'B365H']),
        drawOdds: number(row, const ['AvgD', 'B365D']),
        awayOdds: number(row, const ['AvgA', 'B365A']),
        over25Odds: number(row, const ['Avg>2.5', 'B365>2.5']),
        under25Odds: number(row, const ['Avg<2.5', 'B365<2.5']),
      ),
    );
  }
  return output;
}

DateTime? _parseFootballDate(String value) {
  final parts = value.trim().split('/');
  if (parts.length != 3) {
    return DateTime.tryParse(value.trim());
  }
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  var year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) {
    return null;
  }
  if (year < 100) {
    year += 2000;
  }
  return DateTime.utc(year, month, day);
}
