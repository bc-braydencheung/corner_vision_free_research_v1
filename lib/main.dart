import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/feature_ablation.dart';
import 'models/football_mobile.dart';
import 'models/forecast_data.dart';
import 'models/hkjc_football.dart';
import 'models/racing_mobile.dart';
import 'models/simulated_trade.dart';
import 'services/data_service.dart';
import 'services/feature_ablation_service.dart';
import 'services/football_mobile_service.dart';
import 'services/football_store.dart';
import 'services/online_learning.dart';
import 'services/provenance.dart';
import 'services/provenance_service.dart';
import 'services/online_learning_service.dart';
import 'services/weather_service.dart';
import 'services/football_training_service.dart';
import 'services/hkjc_football_service.dart';
import 'services/hkjc_mobile_service.dart';
import 'services/calibration_service.dart';
import 'services/corner_strength_model.dart';
import 'services/two_stage_corner_model.dart';
import 'services/walk_forward.dart';
import 'models/team_news.dart';
import 'services/bivariate_corner_model.dart';
import 'services/corner_strength_service.dart';
import 'services/market_anchor.dart';
import 'services/market_anchor_service.dart';
import 'services/odds_collector_service.dart';
import 'services/racing_store.dart';
import 'services/racing_training_service.dart';
import 'services/research_backup_service.dart';
import 'services/shadow_service.dart';
import 'services/source_contract.dart';
import 'services/simulation_service.dart';
import 'services/team_news_service.dart';
import 'widgets/hkjc_corner_section.dart';
import 'widgets/research_health_view.dart';
import 'widgets/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RacingTrainingCoordinator.initialize();
  runApp(const EdgeWiseApp());
}

class EdgeWiseApp extends StatelessWidget {
  const EdgeWiseApp({this.dataService = const DataService(), super.key});

  final DataService dataService;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF42E695);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '睿測 EdgeWise',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xFF10251D),
        ),
        scaffoldBackgroundColor: const Color(0xFF06150F),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      home: ForecastDashboard(dataService: dataService),
    );
  }
}

class ForecastDashboard extends StatefulWidget {
  const ForecastDashboard({required this.dataService, super.key});

  final DataService dataService;

  @override
  State<ForecastDashboard> createState() => _ForecastDashboardState();
}

class _ForecastDashboardState extends State<ForecastDashboard> {
  final SimulationService _simulationService = SimulationService();
  final ResearchBackupService _backupService = ResearchBackupService();
  ForecastLoadResult? _result;
  List<SimulatedTrade> _trades = [];
  Object? _error;
  bool _loading = true;
  bool _syncingFootball = false;
  bool _syncingRacing = false;
  String _sport = 'football';
  String _leagueCode = 'E0';
  int _section = 0;
  FootballSyncStatus? _footballStatus;
  FootballTrainingJob? _footballTrainingJob;
  Timer? _footballTrainingTimer;
  final HkjcFootballService _hkjcFootballService = HkjcFootballService();
  final OddsCollectorService _oddsCollector = OddsCollectorService();
  HkjcFootballSnapshot? _hkjcFootball;
  bool _loadingHkjcFootball = false;
  OddsCollectionReport? _oddsCollection;
  bool _collectingOdds = false;
  final FeatureAblationService _ablationService = FeatureAblationService();
  FeatureAblationReport? _ablation;
  bool _runningAblation = false;
  final CalibrationService _calibrationService = CalibrationService();
  CalibrationState? _calibration;
  final OnlineLearningService _onlineLearningService = OnlineLearningService();
  OnlineLearningState? _onlineLearning;
  final MarketAnchorService _marketAnchorService = MarketAnchorService();
  MarketAnchorState? _marketAnchor;
  final ProvenanceService _provenanceService = ProvenanceService();
  ProvenanceLedger? _provenance;
  final CornerStrengthService _cornerStrengthService = CornerStrengthService();
  CornerPriorTables _cornerPriors = CornerPriorTables.empty;
  Map<String, WalkForwardReport> _walkForward = const {};
  final WeatherService _weatherService = WeatherService();
  final FootballStore _footballStore = FootballStore();
  Map<String, FootballWeatherSnapshot> _footballWeather = const {};
  final TeamNewsService _teamNewsService = TeamNewsService();
  Map<String, TeamNewsSnapshot> _teamNews = const {};
  RacingSyncStatus? _racingStatus;
  RacingTrainingJob? _trainingJob;
  Timer? _trainingTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _footballTrainingTimer?.cancel();
    _trainingTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.dataService.load();
      var trades = await _simulationService.load();
      trades = await _simulationService.settle(
        trades,
        result.data.settlementResults,
        racingResults: result.data.racing.results,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _trades = trades;
        _footballStatus = result.footballStatus;
        _footballTrainingJob = result.footballStatus?.job;
        _racingStatus = result.racingStatus;
        _trainingJob = result.racingStatus?.job;
        if (!result.data.leagues.any((league) => league.code == _leagueCode)) {
          _leagueCode = result.data.leagues.first.code;
        }
        _loading = false;
      });
      _watchFootballTraining();
      _watchTraining();
      unawaited(_syncMobileSources());
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _syncMobileSources() async {
    // The HKJC card is the first thing the football tab shows and depends on
    // nothing else, so its fetch starts immediately instead of queueing behind
    // the football-data download; the mirror check runs alongside it because it
    // only refreshes an already-painted model.
    final fixtures = _refreshHkjcFootball();
    final remoteModel = widget.dataService.fetchRemoteModel();
    // Every audit layer reads local storage only, so it is computed before the
    // remaining network work: the research page fills in seconds.
    await _refreshCalibration();
    await _loadAblation();
    await _refreshCornerStrengths(force: false);
    await fixtures;
    await _refreshFootball();
    await _refreshRacing();
    await _applyRemoteModel(remoteModel);
    try {
      await _collectOdds();
    } on Object {
      // Quote history collection is best effort.
    }
    await _refreshCalibration();
    await _refreshCornerStrengths();
    await _refreshFootballWeather();
    await _refreshTeamNews();
  }

  /// Merges the mirrored full model into the already-painted dashboard.
  Future<void> _applyRemoteModel(
    Future<MirrorFetchResult<ForecastData>?> pending,
  ) async {
    try {
      final fetched = await pending;
      final current = _result;
      if (current == null) {
        return;
      }
      final refreshed = await widget.dataService.applyRemote(current, fetched);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = refreshed;
        _footballStatus = refreshed.footballStatus ?? _footballStatus;
        _racingStatus = refreshed.racingStatus ?? _racingStatus;
      });
    } on Object {
      // The bundled model already carries the app; a mirror check is optional.
    }
  }

  /// Reads the free HKJC pre-match availability notes.
  ///
  /// They only widen the count distribution, so an unpublished or unreachable
  /// note leaves every forecast exactly where it was.
  Future<void> _refreshTeamNews() async {
    try {
      final notes = await _teamNewsService.latest();
      if (!mounted || notes.isEmpty) {
        return;
      }
      setState(() => _teamNews = notes);
    } on Object {
      // Availability notes are an uncertainty input only.
    }
  }

  /// Appends the free Open-Meteo kick-off forecast of every HKJC fixture.
  ///
  /// The forecast only widens the count distribution, so a missing venue or an
  /// unreachable feed simply leaves the model where it was.
  Future<void> _refreshFootballWeather() async {
    final snapshot = _hkjcFootball;
    if (snapshot == null) {
      return;
    }
    try {
      final now = DateTime.now();
      for (final fixture in snapshot.fixtures) {
        final wait = fixture.kickOffTime.difference(now);
        if (wait.isNegative || wait > const Duration(days: 3)) {
          continue;
        }
        final forecast = await _weatherService.footballForecast(fixture);
        if (forecast != null) {
          await _footballStore.saveWeatherSnapshot(forecast);
        }
      }
      final stored = await _footballStore.loadWeatherSnapshots();
      final latest = <String, FootballWeatherSnapshot>{};
      for (final forecast in stored) {
        final previous = latest[forecast.matchId];
        if (previous == null ||
            forecast.capturedAt.isAfter(previous.capturedAt)) {
          latest[forecast.matchId] = forecast;
        }
      }
      if (!mounted) {
        return;
      }
      setState(() => _footballWeather = latest);
    } on Object {
      // Weather is an uncertainty input only; failing is harmless.
    }
  }

  /// Refits the time-varying team corner strengths from the local history.
  Future<void> _refreshCornerStrengths({bool force = true}) async {
    try {
      final tables = await _cornerStrengthService.tables(force: force);
      if (!mounted) {
        return;
      }
      setState(() => _cornerPriors = tables);
    } on Object {
      // The prior is optional; the market model still stands without it.
    }
  }

  /// Refits every market's calibrator on its settled outcomes.
  Future<void> _refreshCalibration() async {
    try {
      final records = await ShadowService().load();
      final state = await _calibrationService.evaluate(records);
      final online = await _onlineLearningService.update(records);
      final anchor = await _marketAnchorService.update(records);
      if (!mounted) {
        return;
      }
      final model = await FootballStore().loadModel();
      final ledger = await _provenanceService.record(
        dataset: await FootballStore().loadDataset(),
        model: model,
        calibration: state,
        online: online,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _calibration = state;
        _onlineLearning = online;
        _marketAnchor = anchor;
        _provenance = ledger;
        _walkForward = _walkForwardOf(model);
      });
    } on Object {
      // Calibration is an audit layer; a failure must not block the app.
    }
  }

  Map<String, WalkForwardReport> _walkForwardOf(MobileFootballModel? model) => {
    for (final league in model?.leagues ?? const <MobileFootballLeagueModel>[])
      if (league.walkForward != null) league.code: league.walkForward!,
  };

  /// Rereads the walk-forward reports a finished training run just wrote.
  Future<void> _refreshWalkForward() async {
    try {
      final model = await FootballStore().loadModel();
      if (!mounted) {
        return;
      }
      setState(() => _walkForward = _walkForwardOf(model));
    } on Object {
      // The validation card is optional; a failure must not block the app.
    }
  }

  /// Appends one HKJC quote sample to the append-only local time series.
  Future<void> _collectOdds() async {
    if (_collectingOdds) {
      return;
    }
    setState(() => _collectingOdds = true);
    try {
      final report = await _oddsCollector.collect();
      if (!mounted) {
        return;
      }
      setState(() => _oddsCollection = report);
    } finally {
      if (mounted) {
        setState(() => _collectingOdds = false);
      }
    }
  }

  /// Measures every feature's out-of-fold contribution on demand.
  ///
  /// One walk-forward per feature is far too heavy for a refresh, so this only
  /// runs when asked, and the previously stored report stays visible meanwhile.
  Future<void> _runAblation() async {
    if (_runningAblation) {
      return;
    }
    setState(() => _runningAblation = true);
    try {
      final report = await _ablationService.run();
      if (!mounted) {
        return;
      }
      setState(() => _ablation = report);
    } finally {
      if (mounted) {
        setState(() => _runningAblation = false);
      }
    }
  }

  Future<void> _loadAblation() async {
    try {
      final report = await _ablationService.load();
      if (mounted && report != null) {
        setState(() => _ablation = report);
      }
    } on Object {
      // A stored attribution report is optional.
    }
  }

  Future<void> _refreshHkjcFootball({bool force = false}) async {
    if (_loadingHkjcFootball) {
      return;
    }
    setState(() => _loadingHkjcFootball = true);
    try {
      final snapshot = await _hkjcFootballService.load(force: force);
      try {
        await _oddsCollector.recordFootball(snapshot);
      } on Object {
        // Recording the quote history must never break the fixture list.
      }
      if (!mounted) {
        return;
      }
      setState(() => _hkjcFootball = snapshot);
    } finally {
      if (mounted) {
        setState(() => _loadingHkjcFootball = false);
      }
    }
  }

  Future<void> _refreshFootball() async {
    final current = _result;
    if (current == null || _syncingFootball) {
      return;
    }
    setState(() => _syncingFootball = true);
    try {
      final refreshed = await widget.dataService.refreshFootball(current);
      final trades = await _simulationService.settle(
        _trades,
        refreshed.data.settlementResults,
        racingResults: refreshed.data.racing.results,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = refreshed;
        _trades = trades;
        _footballStatus = refreshed.footballStatus;
        _footballTrainingJob = refreshed.footballStatus?.job;
      });
      _watchFootballTraining();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('足球更新暫時不可用，已保留舊資料')));
      }
    } finally {
      if (mounted) {
        setState(() => _syncingFootball = false);
      }
    }
  }

  Future<void> _refreshRacing({bool force = false}) async {
    final current = _result;
    if (current == null || _syncingRacing) {
      return;
    }
    setState(() => _syncingRacing = true);
    try {
      final refreshed = await widget.dataService.refreshRacing(
        current,
        force: force,
      );
      var trades = await _simulationService.settle(
        _trades,
        refreshed.data.settlementResults,
        racingResults: refreshed.data.racing.results,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = refreshed;
        _trades = trades;
        _racingStatus = refreshed.racingStatus;
        _trainingJob = refreshed.racingStatus?.job;
      });
      _watchTraining();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('香港賽馬更新暫時不可用，已保留舊資料')));
      }
    } finally {
      if (mounted) {
        setState(() => _syncingRacing = false);
      }
    }
  }

  void _watchTraining() {
    _trainingTimer?.cancel();
    final job = _trainingJob;
    if (job == null || !job.isUnfinished) {
      return;
    }
    _trainingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final latest = await RacingStore().loadJob();
      if (!mounted || latest == null) {
        return;
      }
      final wasRunning = _trainingJob?.isUnfinished ?? false;
      setState(() => _trainingJob = latest);
      if (wasRunning && !latest.isUnfinished) {
        _trainingTimer?.cancel();
        await _reloadRacingCache();
      }
    });
  }

  void _watchFootballTraining() {
    _footballTrainingTimer?.cancel();
    final job = _footballTrainingJob;
    if (job == null || !job.isUnfinished) {
      return;
    }
    _footballTrainingTimer = Timer.periodic(const Duration(seconds: 1), (
      _,
    ) async {
      final latest = await FootballStore().loadJob();
      if (!mounted || latest == null) {
        return;
      }
      final wasRunning = _footballTrainingJob?.isUnfinished ?? false;
      setState(() => _footballTrainingJob = latest);
      if (wasRunning && !latest.isUnfinished) {
        _footballTrainingTimer?.cancel();
        await _reloadFootballCache();
        await _refreshWalkForward();
      }
    });
  }

  Future<void> _reloadFootballCache() async {
    final current = _result;
    if (current == null) {
      return;
    }
    final refreshed = await widget.dataService.reloadFootballCache(current);
    if (!mounted) {
      return;
    }
    setState(() {
      _result = refreshed;
      _footballStatus = refreshed.footballStatus;
      _footballTrainingJob = refreshed.footballStatus?.job;
    });
  }

  Future<void> _reloadRacingCache() async {
    final current = _result;
    if (current == null) {
      return;
    }
    final refreshed = await widget.dataService.reloadRacingCache(current);
    if (!mounted) {
      return;
    }
    setState(() {
      _result = refreshed;
      _racingStatus = refreshed.racingStatus;
      _trainingJob = refreshed.racingStatus?.job;
    });
  }

  Future<void> _startTraining() async {
    final existing = await RacingStore().loadJob();
    var restart = false;
    if (existing != null &&
        (existing.isUnfinished || existing.status == 'failed')) {
      if (!mounted) {
        return;
      }
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('發現上次訓練進度'),
          content: Text(
            '已保存 ${existing.progress.toStringAsFixed(0)}%：${existing.stage}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'restart'),
              child: const Text('以最新資料重開'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'continue'),
              child: const Text('繼續上次訓練'),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') {
        return;
      }
      restart = choice == 'restart';
    }
    final job = await RacingTrainingCoordinator.start(restart: restart);
    if (!mounted) {
      return;
    }
    setState(() => _trainingJob = job);
    _watchTraining();
  }

  Future<void> _startFootballTraining() async {
    final existing = await FootballStore().loadJob();
    var restart = false;
    if (existing != null &&
        (existing.isUnfinished || existing.status == 'failed')) {
      if (!mounted) {
        return;
      }
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('發現上次足球訓練進度'),
          content: Text(
            '已保存 ${existing.progress.toStringAsFixed(0)}%：${existing.stage}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'restart'),
              child: const Text('以最新資料重開'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'continue'),
              child: const Text('繼續上次訓練'),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') {
        return;
      }
      restart = choice == 'restart';
    }
    final job = await FootballTrainingCoordinator.start(restart: restart);
    if (!mounted) {
      return;
    }
    setState(() => _footballTrainingJob = job);
    _watchFootballTraining();
  }

  Future<void> _pauseFootballTraining() async {
    await FootballTrainingCoordinator.pause();
    if (!mounted) return;
    final job = await FootballStore().loadJob();
    setState(() => _footballTrainingJob = job);
  }

  Future<void> _resumeFootballTraining() async {
    await FootballTrainingCoordinator.resume();
    if (!mounted) return;
    final job = await FootballStore().loadJob();
    setState(() => _footballTrainingJob = job);
    _watchFootballTraining();
  }

  Future<void> _pauseRacingTraining() async {
    await RacingTrainingCoordinator.pause();
    if (!mounted) return;
    final job = await RacingStore().loadJob();
    setState(() => _trainingJob = job);
  }

  Future<void> _resumeRacingTraining() async {
    await RacingTrainingCoordinator.resume();
    if (!mounted) return;
    final job = await RacingStore().loadJob();
    setState(() => _trainingJob = job);
    _watchTraining();
  }

  Future<void> _exportBackup() async {
    final encoded = await _backupService.export(_trades);
    await Clipboard.setData(ClipboardData(text: encoded));
    if (mounted) {
      _showMessage('研究備份已複製到剪貼簿。');
    }
  }

  Future<void> _exportReport() async {
    try {
      final report = await _backupService.report(_trades);
      await Clipboard.setData(ClipboardData(text: report));
      if (mounted) {
        _showMessage('研究報告已複製；包含逐注、分季ROI、校準、回撤及bootstrap。');
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('研究報告產生失敗：$error');
      }
    }
  }

  Future<void> _importBackup() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final encoded = clipboard?.text;
    if (encoded == null || encoded.trim().isEmpty) {
      _showMessage('剪貼簿沒有可復原的備份。');
      return;
    }
    try {
      final imported = await _backupService.import(encoded);
      if (!mounted) {
        return;
      }
      setState(() => _trades = imported.trades);
      await _refresh();
      if (mounted) {
        _showMessage(
          '已復原${imported.trades.length}筆交易、'
          '${imported.shadowForecasts}筆shadow預測及'
          '${imported.oddsImported + imported.weatherImported + imported.racingOddsImported}筆新快照；'
          '${imported.modelsRestored}個模型、'
          '${imported.checkpointsRestored}個可配對checkpoint。',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('復原失敗：$error');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section,
        onDestinationSelected: (value) => setState(() => _section = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: '分析',
          ),
          NavigationDestination(
            icon: Icon(Icons.health_and_safety_outlined),
            selectedIcon: Icon(Icons.health_and_safety),
            label: '研究健康',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E3325), Color(0xFF06150F)],
          ),
        ),
        child: SafeArea(
          child: switch ((_loading, result, _error)) {
            (true, _, _) => const Center(child: CircularProgressIndicator()),
            (false, null, final error?) => _ErrorView(
              error: error,
              onRetry: _refresh,
            ),
            (false, final loaded?, _) => Column(
              children: [
                _Header(onRefresh: _refresh),
                if (_section == 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'football',
                            icon: Icon(Icons.sports_soccer),
                            label: Text('足球'),
                          ),
                          ButtonSegment(
                            value: 'racing',
                            icon: Icon(Icons.sports),
                            label: Text('賽馬'),
                          ),
                        ],
                        selected: {_sport},
                        onSelectionChanged: (selection) {
                          setState(() => _sport = selection.first);
                        },
                      ),
                    ),
                  ),
                Expanded(
                  child: _section == 2
                      ? const SettingsPage()
                      : _section == 1
                      ? ResearchHealthView(
                          data: loaded.data,
                          footballStatus: _footballStatus,
                          racingStatus: _racingStatus,
                          shadowHealth: loaded.shadowHealth,
                          sourceErrors: loaded.sourceErrors,
                          mirrorHealth: loaded.mirrorHealth,
                          walkForward: _walkForward,
                          trades: _trades,
                          onExportReport: _exportReport,
                          onExportBackup: _exportBackup,
                          onImportBackup: _importBackup,
                          footballTrainingJob: _footballTrainingJob,
                          footballSyncing: _syncingFootball,
                          calibration: _calibration,
                          onlineLearning: _onlineLearning,
                          marketAnchor: _marketAnchor,
                          provenance: _provenance,
                          oddsCollection: _oddsCollection,
                          collectingOdds: _collectingOdds,
                          onCollectOdds: _collectOdds,
                          ablation: _ablation,
                          runningAblation: _runningAblation,
                          onRunAblation: _runAblation,
                          onRefreshFootball: _refreshFootball,
                          onTrainFootball: _startFootballTraining,
                          onPauseFootballTraining: _pauseFootballTraining,
                          onResumeFootballTraining: _resumeFootballTraining,
                        )
                      : _sport == 'football'
                      ? _FootballView(
                          result: loaded,
                          leagueCode: _leagueCode,
                          hkjcFootball: _hkjcFootball,
                          cornerCalibration: _calibration?.footballCorners,
                          cornerStrengths: _cornerPriors.strengths[_leagueCode],
                          shotCorners: _cornerPriors.shots[_leagueCode],
                          cornerJoint: _cornerPriors.joint[_leagueCode],
                          teamNews: _teamNews,
                          footballWeather: _footballWeather,
                          onlineLearning: _onlineLearning,
                          marketAnchor: _marketAnchor,
                          hkjcLoading: _loadingHkjcFootball,
                          onRefreshHkjc: () =>
                              _refreshHkjcFootball(force: true),
                          onLeagueChanged: (code) {
                            setState(() => _leagueCode = code);
                          },
                        )
                      : _RacingView(
                          racing: loaded.data.racing,
                          status: _racingStatus,
                          trainingJob: _trainingJob,
                          syncing: _syncingRacing,
                          onRefresh: () => _refreshRacing(force: true),
                          onTrain: _startTraining,
                          onPause: _pauseRacingTraining,
                          onResume: _resumeRacingTraining,
                        ),
                ),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

class _FootballView extends StatelessWidget {
  const _FootballView({
    required this.result,
    required this.leagueCode,
    required this.hkjcFootball,
    required this.hkjcLoading,
    required this.onRefreshHkjc,
    this.cornerCalibration,
    this.cornerStrengths,
    this.shotCorners,
    this.cornerJoint,
    this.teamNews = const {},
    this.footballWeather = const {},
    this.onlineLearning,
    this.marketAnchor,
    required this.onLeagueChanged,
  });

  final ForecastLoadResult result;
  final String leagueCode;
  final HkjcFootballSnapshot? hkjcFootball;
  final bool hkjcLoading;
  final Future<void> Function() onRefreshHkjc;
  final MarketCalibration? cornerCalibration;
  final CornerStrengthTable? cornerStrengths;
  final ShotCornerTable? shotCorners;
  final BivariateCornerFit? cornerJoint;
  final Map<String, TeamNewsSnapshot> teamNews;
  final Map<String, FootballWeatherSnapshot> footballWeather;
  final OnlineLearningState? onlineLearning;
  final MarketAnchorState? marketAnchor;
  final ValueChanged<String> onLeagueChanged;

  @override
  Widget build(BuildContext context) {
    final data = result.data;
    final leagues = data.leagues
        .where((item) => hkjcFootballProfiles.containsKey(item.code))
        .toList();
    return RefreshIndicator(
      onRefresh: onRefreshHkjc,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in leagues) ...[
                  ChoiceChip(
                    label: Text(item.name),
                    selected: item.code == leagueCode,
                    onSelected: (_) => onLeagueChanged(item.code),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          HkjcCornerSection(
            snapshot: hkjcFootball,
            leagueCode: leagueCode,
            loading: hkjcLoading,
            onRefresh: onRefreshHkjc,
            calibration: cornerCalibration,
            strengths: cornerStrengths,
            shotCorners: shotCorners,
            weather: footballWeather,
            online: onlineLearning,
            anchor: marketAnchor,
            joint: cornerJoint,
            teamNews: teamNews,
          ),
          const SizedBox(height: 18),
          _Disclaimer(text: data.disclaimer),
        ],
      ),
    );
  }
}

class _RacingView extends StatelessWidget {
  const _RacingView({
    required this.racing,
    required this.status,
    required this.trainingJob,
    required this.syncing,
    required this.onRefresh,
    required this.onTrain,
    required this.onPause,
    required this.onResume,
  });

  final RacingSummary racing;
  final RacingSyncStatus? status;
  final RacingTrainingJob? trainingJob;
  final bool syncing;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onTrain;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      children: [
        _RacingUpdateCard(
          status: status,
          job: trainingJob,
          syncing: syncing,
          onRefresh: onRefresh,
          onTrain: onTrain,
          onPause: onPause,
          onResume: onResume,
        ),
        const SizedBox(height: 14),
        _RacingModelCard(racing: racing),
        const SizedBox(height: 18),
        if (!racing.available)
          const Text('尚未產生足夠歷史資料，暫不展示預測。')
        else if (racing.races.isEmpty)
          const Text('模型已建立，但目前沒有已公布的下一個本地賽馬日排位。')
        else
          for (final race in racing.races) ...[
            _RacingRaceCard(
              race: race,
              tradeEnabled: racing.model.tradeEnabled,
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }
}

class _RacingUpdateCard extends StatelessWidget {
  const _RacingUpdateCard({
    required this.status,
    required this.job,
    required this.syncing,
    required this.onRefresh,
    required this.onTrain,
    required this.onPause,
    required this.onResume,
  });

  final RacingSyncStatus? status;
  final RacingTrainingJob? job;
  final bool syncing;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onTrain;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;

  @override
  Widget build(BuildContext context) {
    final running = job?.status == 'queued' || job?.status == 'training';
    final paused = job?.isPaused ?? false;
    final canTrain =
        status?.hasNewResults == true ||
        job?.status == 'failed' ||
        running ||
        paused;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_sync, color: Color(0xFF4FC3F7)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  syncing ? '正在低頻檢查 HKJC 更新…' : status?.message ?? '手機快取已載入',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '檢查賽馬更新',
                onPressed: syncing ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (status != null)
            Text(
              '最新完整賽果：${status!.latestResultDate}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.52),
                fontSize: 11,
              ),
            ),
          if (job != null && (running || job!.status == 'failed')) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: job!.progress / 100),
            const SizedBox(height: 7),
            Text(
              '${job!.stage} · ${job!.progress.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
            if (job!.error.isNotEmpty)
              Text(
                job!.error,
                style: const TextStyle(color: Color(0xFFFFC857), fontSize: 11),
              ),
          ],
          if (running) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPause,
                icon: const Icon(Icons.pause),
                label: const Text('暫停訓練'),
              ),
            ),
          ],
          if (paused) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('繼續'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onTrain,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新開始'),
                  ),
                ),
              ],
            ),
          ],
          if (canTrain && !running && !paused) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onTrain,
                icon: const Icon(Icons.model_training),
                label: Text(job?.status == 'failed' ? '繼續上次訓練' : '重新訓練模型'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RacingModelCard extends StatelessWidget {
  const _RacingModelCard({required this.racing});

  final RacingSummary racing;

  @override
  Widget build(BuildContext context) {
    final model = racing.model;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sports, color: Color(0xFFFFC857), size: 30),
              SizedBox(width: 10),
              Text(
                '香港賽馬個人研究模型',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(racing.status),
          if (model.trainingRaces > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(
                  label: model.candidateLabel,
                  color: const Color(0xFFB491FF),
                ),
                if (model.tradePolicyStatus.isNotEmpty)
                  _Pill(
                    label: model.tradeEnabled ? '市場交易閘門已通過' : '市場交易閘門未通過',
                    color: model.tradeEnabled
                        ? const Color(0xFF42E695)
                        : const Color(0xFFFFC857),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${model.trainingRaces}場訓練 · ${model.holdoutRaces}場留出；'
              'Log Loss、校準及季節覆蓋請到「研究健康」查看。',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 11,
              ),
            ),
          ],
          if (model.tradePolicyReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              model.tradePolicyReason,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            racing.sourceNotice,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _RacingRaceCard extends StatelessWidget {
  const _RacingRaceCard({required this.race, required this.tradeEnabled});

  final RacingRace race;
  final bool tradeEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF0D241A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${race.venue} 第${race.raceNumber}場 · '
            '${race.distanceMetres}米 ${race.surface}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          if (race.raceName.isNotEmpty)
            Text(
              '${race.raceName}${race.going.isEmpty ? '' : ' · ${race.going}'}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          const SizedBox(height: 13),
          for (final runner in race.runners) ...[
            _RunnerRow(runner: runner, tradeEnabled: tradeEnabled),
            if (runner != race.runners.last)
              Divider(color: Colors.white.withValues(alpha: 0.06)),
          ],
        ],
      ),
    );
  }
}

class _RunnerRow extends StatelessWidget {
  const _RunnerRow({required this.runner, required this.tradeEnabled});

  final RacingRunner runner;
  final bool tradeEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC857).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${runner.number}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  runner.horseNameChinese.isNotEmpty
                      ? runner.horseNameChinese
                      : runner.horseName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (runner.horseNameEnglish.isNotEmpty &&
                    runner.horseNameEnglish != runner.horseNameChinese)
                  Text(
                    runner.horseNameEnglish,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 11,
                    ),
                  ),
                Text(
                  '${runner.jockey} · ${runner.trainer} · 檔${runner.draw}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontSize: 10,
                  ),
                ),
                Text(
                  '獨贏 ${(runner.winProbability * 100).toStringAsFixed(1)}% · '
                  '位置 ${(runner.placeProbability * 100).toStringAsFixed(1)}% · '
                  '公平 ${runner.fairWinOdds.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF42E695),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            children: [
              _Pill(
                label: !tradeEnabled
                    ? 'No bet'
                    : runner.recommendation == 'no-prediction'
                    ? '不預測'
                    : '模型參考',
                color: !tradeEnabled
                    ? const Color(0xFF7F8C8D)
                    : runner.recommendation == 'no-prediction'
                    ? const Color(0xFFFFC857)
                    : const Color(0xFF42E695),
              ),
              if (runner.recommendation == 'no-prediction')
                const Text(
                  '信心不足',
                  style: TextStyle(
                    color: Color(0xFFFFC857),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF42E695),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.query_stats,
              color: Color(0xFF052018),
              size: 29,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '睿測',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.7,
                ),
              ),
              Text(
                '足球角球 · 賽馬 · 機率分析',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
              ),
            ],
          ),
          const Spacer(),
          IconButton.filledTonal(
            tooltip: '檢查更新',
            onPressed: onRefresh,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 16,
          color: Colors.white.withValues(alpha: 0.42),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$text 所有買入均為虛擬模擬，不涉及真實金錢。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              height: 1.45,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 52, color: Color(0xFFFFC857)),
            const SizedBox(height: 16),
            const Text(
              '未能載入預測資料',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重試'),
            ),
          ],
        ),
      ),
    );
  }
}
