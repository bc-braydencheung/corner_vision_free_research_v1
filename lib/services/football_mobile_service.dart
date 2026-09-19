import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';

import '../models/football_mobile.dart';
import '../models/forecast_data.dart';
import 'football_mobile_engine.dart';
import 'football_store.dart';
import 'understat_xg_service.dart';

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
    this.xgCoverage,
    this.sourceTasks = const [],
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

  /// How much of the settled history carries a free expected-goals reading,
  /// null when this run never reached the feed.
  final UnderstatXgCoverage? xgCoverage;

  /// Per-file outcome of the last download, so a source that failed on its own
  /// stays visible instead of disappearing behind an overall success.
  final List<FootballSourceTask> sourceTasks;

  List<FootballSourceTask> get failedSources => sourceTasks
      .where((task) => task.status == FootballSourceTask.failed)
      .toList();
}

/// One division-season file: what landed, what was dropped, and why.
class FootballSourceTask {
  const FootballSourceTask({
    required this.division,
    required this.season,
    required this.status,
    this.rows = 0,
    this.droppedWithoutCorners = 0,
    this.error,
  });

  factory FootballSourceTask.fromJson(Map<String, Object?> json) =>
      FootballSourceTask(
        division: '${json['division']}',
        season: '${json['season']}',
        status: '${json['status']}',
        rows: (json['rows'] as num?)?.toInt() ?? 0,
        droppedWithoutCorners:
            (json['droppedWithoutCorners'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
      );

  /// `imported` rows landed, `noCorners` the file carries no corner columns,
  /// `missing` the season file does not exist, `failed` the fetch broke, and
  /// `skipped` an earlier run already landed it.
  static const imported = 'imported';
  static const noCorners = 'noCorners';
  static const missing = 'missing';
  static const failed = 'failed';
  static const skipped = 'skipped';

  final String division;
  final String season;
  final String status;
  final int rows;
  final int droppedWithoutCorners;
  final String? error;

  String get key => '$season/$division';

  Map<String, Object?> toJson() => {
    'division': division,
    'season': season,
    'status': status,
    'rows': rows,
    'droppedWithoutCorners': droppedWithoutCorners,
    if (error != null) 'error': error,
  };
}

/// The outcome of a history download, file by file.
///
/// A download that lands nineteen seasons and loses one is a partial success,
/// not a success: the failing files stay listed so the next run retries them.
class FootballDownloadReport {
  const FootballDownloadReport({
    required this.tasks,
    required this.rowsAdded,
    required this.pendingTasks,
    this.fixturesUpdated = false,
  });

  factory FootballDownloadReport.fromJson(Map<String, Object?> json) =>
      FootballDownloadReport(
        tasks: ((json['tasks'] as List<Object?>?) ?? const [])
            .map(
              (task) => FootballSourceTask.fromJson(
                (task as Map).cast<String, Object?>(),
              ),
            )
            .toList(growable: false),
        rowsAdded: (json['rowsAdded'] as num?)?.toInt() ?? 0,
        pendingTasks: (json['pendingTasks'] as num?)?.toInt() ?? 0,
        fixturesUpdated: json['fixturesUpdated'] == true,
      );

  final List<FootballSourceTask> tasks;
  final int rowsAdded;

  /// Files still to retry, so a resumable download never reads as finished.
  final int pendingTasks;
  final bool fixturesUpdated;

  int _count(String status) =>
      tasks.where((task) => task.status == status).length;

  int get imported => _count(FootballSourceTask.imported);
  int get missing => _count(FootballSourceTask.missing);
  int get failed => _count(FootballSourceTask.failed);
  int get withoutCorners => _count(FootballSourceTask.noCorners);
  int get droppedWithoutCorners =>
      tasks.fold(0, (sum, task) => sum + task.droppedWithoutCorners);
  bool get complete => pendingTasks == 0;

  List<FootballSourceTask> get failures =>
      tasks.where((task) => task.status == FootballSourceTask.failed).toList();

  String get summary => [
    '已匯入 $imported 個球季檔案 · 新增 $rowsAdded 場',
    if (droppedWithoutCorners > 0) '$droppedWithoutCorners 場無角球欄位已略過',
    if (withoutCorners > 0) '$withoutCorners 個檔案沒有角球欄位',
    if (missing > 0) '$missing 個球季檔案不存在',
    if (failed > 0)
      '$failed 個檔案下載失敗（${failures.take(3).map((task) => task.key).join('、')}）'
    else if (!complete)
      '仍有 $pendingTasks 個檔案未下載，可再按繼續',
  ].join(' · ');

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'rowsAdded': rowsAdded,
    'pendingTasks': pendingTasks,
    'fixturesUpdated': fixturesUpdated,
    'summary': summary,
    'tasks': tasks.map((task) => task.toJson()).toList(),
  };
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
    this.xgService,
    this.minimumInterval = const Duration(milliseconds: 350),
    this.baseUrl = 'https://www.football-data.co.uk/mmz4281',
    this.fixturesUrl = 'https://www.football-data.co.uk/fixtures.csv',
    this.firstSeasonYear = 2000,
  }) : store = store ?? FootballStore(),
       engine = engine ?? FootballMobileEngine();

  final FootballStore store;
  final FootballMobileEngine engine;

  /// Free expected-goals feed, left out when a caller wants the sync to touch
  /// nothing but the football-data files.
  final UnderstatXgService? xgService;
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
    final sourceTasks = <FootballSourceTask>[];
    var successfulSources = 0;
    for (final league in current.leagues) {
      for (final division in [league.code, league.supportCode]) {
        if (division.isEmpty) {
          continue;
        }
        final result = await _downloadLatestResults(
          division,
          current.trainedThrough(division),
        );
        sourceTasks.addAll(result.tasks);
        if (result.rows != null) {
          downloaded.addAll(result.rows!);
          successfulSources++;
        }
      }
    }
    await store.saveSourceReport(
      FootballDownloadReport(
        tasks: sourceTasks,
        rowsAdded: downloaded.length,
        pendingTasks: sourceTasks
            .where((task) => task.status == FootballSourceTask.failed)
            .length,
      ).toJson(),
    );
    if (successfulSources == 0) {
      throw HttpException(
        'No football result source was available: '
        '${sourceTasks.map((task) => '${task.key}=${task.status}').join(',')}',
      );
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
    var resultsChanged = additions.isNotEmpty || corrections > 0;
    var dataset = MobileFootballDataset(
      schemaVersion: current.schemaVersion,
      datasetVersion: resultsChanged
          ? _datasetVersion(rows)
          : current.datasetVersion,
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      leagues: current.leagues,
      rows: rows,
      fixtures: fixtures,
    );
    final xg = await _mergeXg(dataset);
    if (xg != null && xg.coverage.matched > 0) {
      dataset = xg.dataset;
      resultsChanged = true;
    }
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
    final failedDivisions = {
      for (final task in sourceTasks)
        if (task.status == FootballSourceTask.failed) task.division,
    }.toList()..sort();
    final message = [
      if (additions.isEmpty && corrections == 0)
        '足球賽果是最新版本'
      else ...[
        if (additions.isNotEmpty) '已加入 ${additions.length} 場新足球賽果',
        if (corrections > 0) '已核實並修正 $corrections 場足球賽果',
      ],
      fixturesChanged ? '未來賽程已更新' : '未來賽程沒有變更',
      if (xg != null) 'xG ${xg.coverage.summary}',
      if (failedDivisions.isNotEmpty)
        '${failedDivisions.join('、')}下載失敗，下次同步會再試',
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
        xgCoverage: xg?.coverage,
        sourceTasks: sourceTasks,
      ),
    );
  }

  /// [dataset] with the free expected-goals readings attached, or null when the
  /// feed could not be read at all.
  ///
  /// A feed that is down, moved or reshaped leaves the history untouched: the
  /// sync reports no coverage rather than training on a guessed reading.
  Future<UnderstatXgMerge?> _mergeXg(MobileFootballDataset dataset) async {
    final feed = xgService;
    if (feed == null) {
      return null;
    }
    try {
      final readings = await feed.fetchAll(
        divisions: dataset.leagues.map((league) => league.code),
        asOf: DateTime.now().toUtc(),
      );
      if (readings.isEmpty) {
        return null;
      }
      return mergeUnderstatXg(dataset: dataset, readings: readings);
    } on Object {
      return null;
    }
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

  Future<({List<FootballMatchRecord>? rows, List<FootballSourceTask> tasks})>
  _downloadLatestResults(String division, String latestDate) async {
    final now = DateTime.now().toUtc();
    final currentStart = now.month >= 7 ? now.year : now.year - 1;
    final parsedLatest = DateTime.tryParse(latestDate);
    final firstStart = parsedLatest == null
        ? currentStart - 1
        : parsedLatest.month >= 7
        ? parsedLatest.year
        : parsedLatest.year - 1;
    final output = <FootballMatchRecord>[];
    final tasks = <FootballSourceTask>[];
    var successful = false;
    for (var startYear = firstStart; startYear <= currentStart; startYear++) {
      final code = _seasonCode(startYear);
      try {
        final body = await _get('$baseUrl/$code/$division.csv');
        final parsed = parseFootballDataMatches(body, division: division);
        final usable = parsed.where((row) => row.isComplete).toList();
        output.addAll(usable);
        successful = true;
        tasks.add(
          FootballSourceTask(
            division: division,
            season: code,
            status: usable.isEmpty
                ? FootballSourceTask.noCorners
                : FootballSourceTask.imported,
            rows: usable.length,
            droppedWithoutCorners: parsed.length - usable.length,
          ),
        );
      } on HttpException catch (error) {
        final absent = error.message.contains('404');
        tasks.add(
          FootballSourceTask(
            division: division,
            season: code,
            status: absent
                ? FootballSourceTask.missing
                : FootballSourceTask.failed,
            error: error.message,
          ),
        );
      } on Object catch (error) {
        tasks.add(
          FootballSourceTask(
            division: division,
            season: code,
            status: FootballSourceTask.failed,
            error: '$error',
          ),
        );
      }
    }
    return (rows: successful ? output : null, tasks: tasks);
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
    final expected = Uri.parse(url).path;
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
      final landed = response.redirects.isEmpty
          ? uri
          : uri.resolveUri(response.redirects.last.location);
      if (landed.path != expected) {
        // mod_speling answers an absent season file with a near-miss name
        // (2627/SP1.csv -> 2627/P1.csv), which would import another league.
        throw HttpException(
          'Football-Data redirected $expected to ${landed.path}',
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

  /// Every division-season file the full history covers, in download order.
  List<({String division, String season})> _historyTasks(
    List<FootballLeagueConfig> leagues,
  ) {
    final divisions = <String>[];
    for (final league in leagues) {
      divisions.add(league.code);
      if (league.supportCode.isNotEmpty) {
        divisions.add(league.supportCode);
      }
    }
    final now = DateTime.now().toUtc();
    final currentStart = now.month >= 7 ? now.year : now.year - 1;
    return [
      for (final division in divisions)
        for (var year = firstSeasonYear; year <= currentStart; year++)
          (division: division, season: _seasonCode(year)),
    ];
  }

  static String _seasonCode(int startYear) =>
      '${(startYear % 100).toString().padLeft(2, '0')}'
      '${((startYear + 1) % 100).toString().padLeft(2, '0')}';

  /// Whether a started history download still has files to fetch.
  ///
  /// A store that never started one is not pending: the bundled seed already
  /// carries the history, so opening the app never triggers hundreds of
  /// requests on its own.
  Future<bool> historyDownloadPending(
    List<FootballLeagueConfig> leagues,
  ) async {
    final dataset = await store.loadDataset();
    if (dataset.rows.isEmpty) {
      return true;
    }
    final completed = await store.loadDownloadProgress();
    if (completed.isEmpty) {
      return false;
    }
    return completed.length < _historyTasks(leagues).length;
  }

  /// Downloads the full free history file by file, resuming where the last run
  /// stopped and landing each file as it arrives.
  ///
  /// Rows without corner counts are dropped here rather than stored: the whole
  /// model is about corners, and early seasons of several leagues carry no `HC`
  /// column at all, which used to reach the trainer as a null.
  Future<FootballDownloadReport> downloadHistory({
    required List<FootballLeagueConfig> leagues,
    void Function(double progress, String status)? onProgress,
    bool restart = false,
  }) async {
    if (restart) {
      await store.clearDownloadProgress();
    }
    final all = _historyTasks(leagues);
    final completed = await store.loadDownloadProgress();
    var dataset = await store.loadDataset();
    final rowsById = {for (final row in dataset.rows) row.matchId: row};
    final tasks = <FootballSourceTask>[];
    var rowsAdded = 0;
    var unlanded = 0;
    var index = 0;
    for (final task in all) {
      index++;
      final key = '${task.season}/${task.division}';
      if (completed.contains(key)) {
        tasks.add(
          FootballSourceTask(
            division: task.division,
            season: task.season,
            status: FootballSourceTask.skipped,
          ),
        );
        onProgress?.call(index / all.length, '$key 已下載');
        continue;
      }
      FootballSourceTask outcome;
      try {
        final body = await _get('$baseUrl/${task.season}/${task.division}.csv');
        final parsed = parseFootballDataMatches(body, division: task.division);
        final usable = parsed.where((row) => row.isComplete).toList();
        var added = 0;
        for (final row in usable) {
          if (rowsById.containsKey(row.matchId)) {
            continue;
          }
          rowsById[row.matchId] = row;
          added++;
        }
        rowsAdded += added;
        unlanded += added;
        outcome = FootballSourceTask(
          division: task.division,
          season: task.season,
          status: usable.isEmpty
              ? FootballSourceTask.noCorners
              : FootballSourceTask.imported,
          rows: added,
          droppedWithoutCorners: parsed.length - usable.length,
        );
        completed.add(key);
      } on HttpException catch (error) {
        // A season that predates a division is permanently absent, so it is
        // recorded as done; anything else is left for the next run to retry.
        final absent = error.message.contains('404');
        if (absent) {
          completed.add(key);
        }
        outcome = FootballSourceTask(
          division: task.division,
          season: task.season,
          status: absent
              ? FootballSourceTask.missing
              : FootballSourceTask.failed,
          error: error.message,
        );
      } on Object catch (error) {
        outcome = FootballSourceTask(
          division: task.division,
          season: task.season,
          status: FootballSourceTask.failed,
          error: '$error',
        );
      }
      tasks.add(outcome);
      onProgress?.call(
        index / all.length,
        '$key · ${outcome.status == FootballSourceTask.imported ? '${outcome.rows} 場' : outcome.status}',
      );
      if (unlanded >= 500) {
        dataset = await _land(dataset, rowsById, completed, leagues: leagues);
        unlanded = 0;
      }
    }
    var fixturesUpdated = false;
    final fixtures = await _downloadFixtures(dataset.leagues);
    if (fixtures != null) {
      fixturesUpdated = true;
    }
    dataset = await _land(
      dataset,
      rowsById,
      completed,
      leagues: leagues,
      fixtures: fixtures,
    );
    if (rowsAdded > 0) {
      await store.markTrainingNeeded();
    }
    final report = FootballDownloadReport(
      tasks: tasks,
      rowsAdded: rowsAdded,
      pendingTasks: all.length - completed.length,
      fixturesUpdated: fixturesUpdated,
    );
    await store.saveSourceReport(report.toJson());
    return report;
  }

  /// Writes what has arrived so far, so an interrupted download keeps it.
  Future<MobileFootballDataset> _land(
    MobileFootballDataset base,
    Map<String, FootballMatchRecord> rowsById,
    Set<String> completed, {
    required List<FootballLeagueConfig> leagues,
    List<FootballMatchRecord>? fixtures,
  }) async {
    final rows = rowsById.values.toList()..sort(_compareMatches);
    final dataset = MobileFootballDataset(
      schemaVersion: FootballStore.supportedSchemaVersion,
      datasetVersion: _datasetVersion(rows),
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      leagues: base.leagues.isEmpty ? leagues : base.leagues,
      rows: rows,
      fixtures: fixtures ?? base.fixtures,
    );
    await store.saveDataset(dataset);
    await store.saveDownloadProgress(completed);
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
    // A requested division never accepts another league's rows: football-data
    // answers a missing season file with a similarly named one.
    if (division != null && rowDivision != division) {
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
        referee: value(row, 'Referee'),
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
