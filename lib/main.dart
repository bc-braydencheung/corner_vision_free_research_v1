import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/feature_ablation.dart';
import 'models/football_mobile.dart';
import 'models/forecast_data.dart';
import 'models/hkjc_football.dart';
import 'models/racing_mobile.dart';
import 'models/shadow_forecast.dart';
import 'models/signal_change.dart';
import 'models/simulated_trade.dart';
import 'models/simulation_draft.dart';
import 'services/alert_share.dart';
import 'services/corner_alerts.dart';
import 'services/data_service.dart';
import 'services/feature_ablation_service.dart';
import 'services/football_mobile_engine.dart';
import 'services/football_mobile_service.dart';
import 'services/football_store.dart';
import 'services/market_residual.dart';
import 'services/market_residual_service.dart';
import 'services/online_learning.dart';
import 'services/provenance.dart';
import 'services/provenance_service.dart';
import 'services/online_learning_service.dart';
import 'services/weather_service.dart';
import 'services/football_training_service.dart';
import 'services/hkjc_corner_model.dart';
import 'services/hkjc_football_service.dart';
import 'services/hkjc_mobile_service.dart';
import 'services/hkjc_shadow.dart';
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
import 'services/racing_alerts.dart';
import 'services/racing_store.dart';
import 'services/research_alerts.dart';
import 'services/racing_training_service.dart';
import 'services/research_backup_service.dart';
import 'services/shadow_service.dart';
import 'services/signal_log.dart';
import 'services/signal_log_service.dart';
import 'services/simulation_backup_service.dart';
import 'services/simulation_entry.dart';
import 'services/simulation_ledger.dart';
import 'services/simulation_service.dart';
import 'services/simulation_share.dart';
import 'services/staked_selections.dart';
import 'services/team_news_service.dart';
import 'services/track_record.dart';
import 'services/track_record_share.dart';
import 'widgets/alert_summary_card.dart';
import 'widgets/back_to_top.dart';
import 'widgets/hkjc_corner_section.dart';
import 'widgets/research_health_view.dart';
import 'widgets/scroll_focus.dart';
import 'widgets/settings_page.dart';
import 'widgets/simulation_account.dart';
import 'widgets/simulation_sheet.dart';
import 'widgets/track_record_view.dart';

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
  ShadowHealth? _shadowHealth;
  bool _loadingHkjcFootball = false;
  OddsCollectionReport? _oddsCollection;
  bool _collectingOdds = false;
  final FeatureAblationService _ablationService = FeatureAblationService();
  FeatureAblationReport? _ablation;
  bool _runningAblation = false;
  String? _ablationError;
  final CalibrationService _calibrationService = CalibrationService();
  CalibrationState? _calibration;
  final OnlineLearningService _onlineLearningService = OnlineLearningService();
  OnlineLearningState? _onlineLearning;
  final MarketAnchorService _marketAnchorService = MarketAnchorService();
  MarketAnchorState? _marketAnchor;
  final MarketResidualService _marketResidualService = MarketResidualService();
  MarketResidualState? _marketResidual;
  TrackRecordReport? _trackRecord;
  List<SignalChange> _signalLog = const [];
  final ProvenanceService _provenanceService = ProvenanceService();
  ProvenanceLedger? _provenance;
  final CornerStrengthService _cornerStrengthService = CornerStrengthService();
  CornerPriorTables _cornerPriors = CornerPriorTables.empty;
  Map<String, WalkForwardReport> _walkForward = const {};
  Map<String, List<String>> _keptFeatures = const {};
  final WeatherService _weatherService = WeatherService();
  final FootballStore _footballStore = FootballStore();
  Map<String, FootballWeatherSnapshot> _footballWeather = const {};
  final TeamNewsService _teamNewsService = TeamNewsService();
  Map<String, TeamNewsSnapshot> _teamNews = const {};
  RacingSyncStatus? _racingStatus;
  RacingTrainingJob? _trainingJob;
  Timer? _trainingTimer;

  /// Locally stored HKJC win-pool quotes, the market side of a racing pick.
  List<RacingOddsSnapshot> _racingOdds = const [];
  bool _sharingAlerts = false;

  /// The card a tapped pick asked to be shown, cleared while browsing.
  AlertFocus _focus = AlertFocus.none;
  final AlertShareService _alertShare = const AlertShareService();
  bool _sharingRecord = false;
  final TrackRecordShareService _recordShare = const TrackRecordShareService();

  /// Simulated-account starting balance, as the user last set it.
  double _bankroll = SimulationService.defaultBankroll;
  final SimulationShareService _simulationShare =
      const SimulationShareService();
  final SimulationBackupService _simulationBackup =
      const SimulationBackupService();

  /// Set while a simulated-account share, export or import is running.
  bool _simulationBusy = false;

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
      final bankroll = await _simulationService.loadBankroll();
      // Settling needs the local result history, which is read as part of the
      // source sync below: the ledger is shown as stored so the first frame
      // does not wait on it.
      final trades = await _simulationService.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _trades = trades;
        _bankroll = bankroll;
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
    // Every audit layer reads local storage only, so it is computed before the
    // network work instead of after it: the research page fills in seconds.
    await _refreshCalibration();
    await _loadAblation();
    await _loadRacingOdds();
    await _refreshCornerStrengths(force: false);
    await _refreshFootball();
    await _refreshHkjcFootball();
    await _refreshRacing();
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

  /// Rereads the stored win-pool quotes the racing picks are measured against.
  Future<void> _loadRacingOdds() async {
    try {
      final snapshots = await RacingStore().loadOddsSnapshots();
      if (!mounted) {
        return;
      }
      setState(() => _racingOdds = snapshots);
    } on Object {
      // Without a stored quote a race simply carries no pick.
    }
  }

  /// Whether the forward-looking error audit is telling us to stop picking.
  ///
  /// The same flag reaches the alert builder and the fixture cards, so a stopped
  /// audit cannot keep issuing picks in one place while the other says stop.
  bool get _picksSuspended => _shadowHealth?.suspendTrading ?? false;

  /// Picks that cleared the model gate, so no fixture has to be opened to know.
  ///
  /// Both models are asked exactly as the detail tiles ask them; this only
  /// gathers what they already return.
  List<ResearchAlert> _alerts(ForecastLoadResult loaded) => [
    ...buildCornerAlerts(
      snapshot: _hkjcFootball,
      leagueNames: {
        for (final league in loaded.data.leagues) league.code: league.name,
      },
      asOf: DateTime.now(),
      calibration: _calibration?.footballCorners,
      priors: _cornerPriors,
      weather: _footballWeather,
      teamNews: _teamNews,
      online: _onlineLearning,
      anchor: _marketAnchor,
      residual: _marketResidual,
      suspended: _picksSuspended,
    ),
    ...buildRacingAlerts(
      racing: loaded.data.racing,
      snapshots: _racingOdds,
      asOf: DateTime.now(),
    ),
  ];

  /// Racing picks that carry a stored quote, keyed by race and saddle number.
  ///
  /// Only a runner the alert builder priced can be recorded: without a stored
  /// win-pool quote there is no price to bet at, and inventing one would put a
  /// figure in the ledger that the market never showed.
  Map<String, SimulationDraft> _racingDrafts(List<ResearchAlert> alerts) => {
    for (final alert in alerts.whereType<RacingAlert>())
      '${alert.race.raceId}#${alert.runner.number}': racingSimulationDraft(
        race: alert.race,
        runner: alert.runner,
        marketOdds: alert.marketOdds,
        marketProbability: alert.marketProbability,
        capturedAt: alert.capturedAt,
      ),
  };

  /// Draws the picks as one card image and opens the system share sheet.
  Future<void> _shareAlerts(List<ResearchAlert> alerts) async {
    if (_sharingAlerts) {
      return;
    }
    setState(() => _sharingAlerts = true);
    try {
      await _alertShare.share(alerts: alerts, asOf: DateTime.now());
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分享失敗：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _sharingAlerts = false);
      }
    }
  }

  /// Draws the public record as one card image and opens the share sheet.
  Future<void> _shareTrackRecord() async {
    final record = _trackRecord;
    if (_sharingRecord || record == null) {
      return;
    }
    setState(() => _sharingRecord = true);
    try {
      await _recordShare.share(report: record, asOf: DateTime.now());
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分享失敗：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _sharingRecord = false);
      }
    }
  }

  /// Jumps straight to the fixture or race the tapped pick is about.
  ///
  /// Selecting the league alone still left the fixture somewhere below the
  /// fold, so the id is held here and the card that owns it scrolls itself into
  /// view and outlines itself.
  void _openAlert(ResearchAlert alert) {
    setState(() {
      switch (alert) {
        case CornerAlert():
          _sport = 'football';
          _leagueCode = alert.leagueCode;
          _focus = _focus.onFixture(alert.fixture.matchId);
        case RacingAlert():
          _sport = 'racing';
          _focus = _focus.onRace(alert.race.raceId);
        default:
          return;
      }
    });
  }

  /// Forgets the card a pick asked for, so browsing never navigates by itself.
  ///
  /// Leaving the target set made a league or sport switch replay the last jump:
  /// the card is rebuilt with the same id and reveals itself although the user
  /// only changed league. Navigation therefore belongs to the tap alone.
  void _clearFocus() => _focus = _focus.browsing;

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

  /// Corner counts read from HKJC while the fixtures were still listed.
  Future<List<HkjcCornerResult>> _storedCornerReadings() async {
    try {
      return await _footballStore.loadHkjcCornerResults();
    } on Object {
      // A missing local history only means nothing was read yet.
      return const [];
    }
  }

  /// Records the HKJC fixtures the corner model prices and settles the finished
  /// ones, so every stored forecast shares its key with the stored quotes.
  Future<List<ShadowForecast>> _updateHkjcShadow() async {
    final service = ShadowService();
    final stored = await service.load();
    final loaded = _result;
    if (loaded == null) {
      return stored;
    }
    final updated = updateHkjcShadow(
      existing: stored,
      snapshot: _hkjcFootball,
      leagueNames: {
        for (final league in loaded.data.leagues) league.code: league.name,
      },
      references: {
        for (final league in loaded.data.leagues)
          league.code: ShadowModelReference(
            version:
                '${league.model.selectedCandidate}:${league.model.trainedThrough}',
            mae: league.model.maeTotalCorners,
            brier: league.model.brierOver9_5,
          ),
      },
      asOf: DateTime.now(),
      settlementResults: loaded.data.settlementResults,
      observedResults: await _storedCornerReadings(),
      trades: _trades,
      calibration: _calibration?.footballCorners,
      priors: _cornerPriors,
      weather: _footballWeather,
      teamNews: _teamNews,
      online: _onlineLearning,
      anchor: _marketAnchor,
      residual: _marketResidual,
    );
    final settled = stored.where((r) => r.actualTotalCorners != null).length;
    final settledNow = updated
        .where((r) => r.actualTotalCorners != null)
        .length;
    final picked = stored.where((r) => r.pick?.recommended ?? false).length;
    final pickedNow = updated.where((r) => r.pick?.recommended ?? false).length;
    if (updated.length != stored.length ||
        settledNow != settled ||
        pickedNow != picked) {
      try {
        await service.save(updated);
      } on Object {
        return stored;
      }
    }
    final health = service.evaluate(updated);
    if (mounted) {
      setState(() => _shadowHealth = health);
    }
    return updated;
  }

  /// Appends a reading of every fixture card whose shown signal moved.
  ///
  /// Kept apart from the shadow ledger on purpose: the ledger is graded,
  /// settled and read by every learner, while this is a display-side audit
  /// trail, so a reading can never change what the model is fitted on.
  Future<List<SignalChange>> _updateSignalLog() async {
    final service = SignalLogService();
    final stored = await service.load();
    final loaded = _result;
    if (loaded == null) {
      return stored;
    }
    final updated = updateSignalLog(
      existing: stored,
      snapshot: _hkjcFootball,
      leagueNames: {
        for (final league in loaded.data.leagues) league.code: league.name,
      },
      asOf: DateTime.now(),
      calibration: _calibration?.footballCorners,
      priors: _cornerPriors,
      weather: _footballWeather,
      teamNews: _teamNews,
      online: _onlineLearning,
      anchor: _marketAnchor,
      residual: _marketResidual,
      suspended: _picksSuspended,
    );
    if (updated.length == stored.length) {
      return stored;
    }
    try {
      await service.save(updated);
    } on Object {
      return stored;
    }
    return updated;
  }

  /// Refits every market's calibrator on its settled outcomes.
  Future<void> _refreshCalibration() async {
    try {
      final records = await _updateHkjcShadow();
      final signalLog = await _updateSignalLog();
      final state = await _calibrationService.evaluate(records);
      final oddsSnapshots = await _footballStore.loadOddsSnapshots();
      final online = await _onlineLearningService.update(
        records,
        oddsSnapshots: oddsSnapshots,
      );
      final trackRecord = buildTrackRecord(
        forecasts: records,
        stored: oddsSnapshots,
        asOf: DateTime.now(),
      );
      final anchor = await _marketAnchorService.update(records);
      final residual = await _marketResidualService.update(records);
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
        _marketResidual = residual;
        _trackRecord = trackRecord;
        _signalLog = signalLog;
        _provenance = ledger;
        _walkForward = _walkForwardOf(model);
        _keptFeatures = _keptFeaturesOf(model);
      });
    } on Object {
      // Calibration is an audit layer; a failure must not block the app.
    }
  }

  Map<String, WalkForwardReport> _walkForwardOf(MobileFootballModel? model) => {
    for (final league in model?.leagues ?? const <MobileFootballLeagueModel>[])
      if (league.walkForward != null) league.code: league.walkForward!,
  };

  /// Feature names each released league model is actually allowed to read.
  Map<String, List<String>> _keptFeaturesOf(MobileFootballModel? model) => {
    for (final league in model?.leagues ?? const <MobileFootballLeagueModel>[])
      if (league.selectedFeatures.isNotEmpty)
        league.code: [
          for (final index in league.selectedFeatures)
            if (index >= 0 && index < footballFeatureNames.length)
              footballFeatureNames[index],
        ],
  };

  /// Rereads the walk-forward reports a finished training run just wrote.
  Future<void> _refreshWalkForward() async {
    try {
      final model = await FootballStore().loadModel();
      if (!mounted) {
        return;
      }
      setState(() {
        _walkForward = _walkForwardOf(model);
        _keptFeatures = _keptFeaturesOf(model);
      });
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
      await _loadRacingOdds();
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
    setState(() {
      _runningAblation = true;
      _ablationError = null;
    });
    try {
      final report = await _ablationService.run();
      if (!mounted) {
        return;
      }
      setState(() => _ablation = report);
    } on Object catch (error) {
      // A failed attribution run has to say so instead of looking untouched.
      if (mounted) {
        setState(() => _ablationError = '$error');
      }
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
        await _oddsCollector.recordResults(snapshot);
        await _oddsCollector.recordFootball(snapshot);
      } on Object {
        // Recording the quote history must never break the fixture list.
      }
      try {
        await _oddsCollector.recordPublishedResults();
      } on Object {
        // The results page is a second source; failing it settles nothing new.
      }
      if (!mounted) {
        return;
      }
      setState(() => _hkjcFootball = snapshot);
      await _settleSimulation();
    } finally {
      if (mounted) {
        setState(() => _loadingHkjcFootball = false);
      }
    }
  }

  /// Settles simulated bets against the corner counts HKJC has published.
  ///
  /// HKJC fixtures carry the corner totals of the very match a bet was keyed
  /// to, so they settle a bet days before the free CSV results arrive.
  Future<void> _settleSimulation() async {
    final loaded = _result;
    if (loaded == null || _trades.isEmpty) {
      return;
    }
    final trades = await _simulationService.settle(
      _trades,
      loaded.data.settlementResults,
      racingResults: loaded.data.racing.results,
      hkjcCornerTotals: await _footballCornerTotals(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _trades = trades);
  }

  /// Corner counts a simulated football bet can be settled from.
  ///
  /// A bet is keyed by HKJC match id, but HKJC removes a match from its list
  /// within hours of full time, so the live snapshot alone leaves a finished
  /// bet waiting forever. The stored readings keep the count that was read
  /// while the fixture was still listed, and the shadow ledger adds the counts
  /// it settled on, including the free result reached through the explicit
  /// bridge, so a bet stays settleable long after the fixture is gone.
  Future<Map<String, int>> _footballCornerTotals() async {
    final now = DateTime.now();
    final totals = <String, int>{};
    totals.addAll(
      observedCornerTotals(await _storedCornerReadings(), asOf: now),
    );
    try {
      totals.addAll(shadowCornerTotals(await ShadowService().load()));
    } on Object {
      // A missing local history must not stop the live feed from settling.
    }
    totals.addAll(hkjcCornerTotals(snapshot: _hkjcFootball, asOf: now));
    return totals;
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
        hkjcCornerTotals: await _footballCornerTotals(),
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
        hkjcCornerTotals: await _footballCornerTotals(),
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

  /// Opens stake entry for a pick, at the price the card published.
  ///
  /// The drawdown stop is the same one the account states: once the simulated
  /// equity is 15% below its peak, no further bets are accepted.
  Future<void> _openSimulationSheet(SimulationDraft draft) async {
    if (!draft.recommended) {
      _showMessage('此場只作觀察，未達推介門檻，不可加入模擬戶口。');
      return;
    }
    if (StakedSelections.of(_trades).holdsDraft(draft)) {
      _showMessage('此選項已在模擬戶口，不重複記錄同一注。');
      return;
    }
    final ledger = buildSimulationLedger(trades: _trades, bankroll: _bankroll);
    if (ledger.maximumDrawdown >= 0.15) {
      _showMessage('最大回撤已達15%，模擬戶口停止新增下注。');
      return;
    }
    if (ledger.available <= 0) {
      _showMessage('可用餘額不足；可在模擬戶口頁調整本金或等未結算下注結算。');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1F17),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SimulationSheet(
        draft: draft,
        balance: ledger.balance,
        available: ledger.available,
        onConfirm: (stake) => unawaited(_addSimulationTrade(draft, stake)),
      ),
    );
  }

  Future<void> _addSimulationTrade(SimulationDraft draft, double stake) async {
    final trade = draft.toTrade(stake: stake, now: DateTime.now());
    final trades = [..._trades, trade];
    await _simulationService.save(trades);
    if (!mounted) {
      return;
    }
    setState(() => _trades = trades);
    _showMessage(
      '已加入模擬戶口：${trade.selectionText} @ '
      '${trade.odds.toStringAsFixed(2)}，注碼 ${stake.toStringAsFixed(2)}（虛擬）。',
    );
  }

  Future<void> _shareSimulationTrade(SimulatedTrade trade) async {
    await _runSimulationAction(
      () => _simulationShare.shareTrade(trade: trade, asOf: DateTime.now()),
    );
  }

  Future<void> _shareSimulationLedger() async {
    await _runSimulationAction(
      () => _simulationShare.shareLedger(
        trades: _trades,
        ledger: buildSimulationLedger(trades: _trades, bankroll: _bankroll),
        asOf: DateTime.now(),
      ),
    );
  }

  Future<void> _exportSimulation() async {
    await _runSimulationAction(() async {
      await _simulationBackup.export(
        trades: _trades,
        bankroll: _bankroll,
        asOf: DateTime.now(),
      );
      if (mounted) {
        _showMessage('已匯出 ${_trades.length} 筆模擬記錄（JSON）。');
      }
    });
  }

  /// Replaces the ledger with a picked export file, or refuses it outright.
  Future<void> _importSimulation() async {
    await _runSimulationAction(() async {
      final SimulationImport? imported;
      try {
        imported = await _simulationBackup.importFromFile();
      } on SimulationImportException catch (error) {
        if (mounted) {
          _showMessage('匯入失敗：${error.message}');
        }
        return;
      }
      if (imported == null) {
        return;
      }
      await _simulationService.save(imported.trades);
      final bankroll = imported.bankroll;
      if (bankroll != null) {
        await _simulationService.saveBankroll(bankroll);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _trades = imported!.trades;
        if (bankroll != null) {
          _bankroll = bankroll;
        }
      });
      await _settleSimulation();
      if (mounted) {
        _showMessage('已匯入 ${imported.trades.length} 筆模擬記錄。');
      }
    });
  }

  /// Drops every simulated bet; research snapshots and forecasts are untouched.
  Future<void> _clearSimulation() async {
    await _simulationService.clear();
    if (!mounted) {
      return;
    }
    setState(() => _trades = []);
    _showMessage('已刪除全部模擬下注記錄（研究紀錄與快照不受影響）。');
  }

  Future<void> _setBankroll(double bankroll) async {
    await _simulationService.saveBankroll(bankroll);
    if (!mounted) {
      return;
    }
    setState(() => _bankroll = bankroll);
  }

  Future<void> _runSimulationAction(Future<void> Function() action) async {
    if (_simulationBusy) {
      return;
    }
    setState(() => _simulationBusy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        _showMessage('操作失敗：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _simulationBusy = false);
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
        onDestinationSelected: (value) => setState(() {
          _section = value;
          _clearFocus();
        }),
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
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '至今紀錄',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: '模擬戶口',
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
                          setState(() {
                            _sport = selection.first;
                            _clearFocus();
                          });
                        },
                      ),
                    ),
                  ),
                Expanded(
                  child: _section == 4
                      ? const SettingsPage()
                      : _section == 3
                      ? SimulationAccount(
                          trades: _trades,
                          bankroll: _bankroll,
                          busy: _simulationBusy,
                          onShareTrade: (trade) =>
                              unawaited(_shareSimulationTrade(trade)),
                          onShareAll: () => unawaited(_shareSimulationLedger()),
                          onExport: () => unawaited(_exportSimulation()),
                          onImport: () => unawaited(_importSimulation()),
                          onClear: () => unawaited(_clearSimulation()),
                          onBankrollChanged: (value) =>
                              unawaited(_setBankroll(value)),
                        )
                      : _section == 2
                      ? TrackRecordView(
                          report: _trackRecord,
                          signalLog: _signalLog,
                          sharing: _sharingRecord,
                          onShare: _shareTrackRecord,
                        )
                      : _section == 1
                      ? ResearchHealthView(
                          data: loaded.data,
                          footballStatus: _footballStatus,
                          racingStatus: _racingStatus,
                          shadowHealth: _shadowHealth ?? loaded.shadowHealth,
                          sourceErrors: loaded.sourceErrors,
                          mirrorHealth: loaded.mirrorHealth,
                          walkForward: _walkForward,
                          keptFeatures: _keptFeatures,
                          trades: _trades,
                          onExportReport: _exportReport,
                          onExportBackup: _exportBackup,
                          onImportBackup: _importBackup,
                          footballTrainingJob: _footballTrainingJob,
                          footballSyncing: _syncingFootball,
                          calibration: _calibration,
                          onlineLearning: _onlineLearning,
                          marketAnchor: _marketAnchor,
                          marketResidual: _marketResidual,
                          provenance: _provenance,
                          oddsCollection: _oddsCollection,
                          collectingOdds: _collectingOdds,
                          onCollectOdds: _collectOdds,
                          ablation: _ablation,
                          ablationError: _ablationError,
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
                          alerts: _alerts(loaded),
                          sharingAlerts: _sharingAlerts,
                          onShareAlerts: _shareAlerts,
                          onOpenAlert: _openAlert,
                          focusMatchId: _focus.matchId,
                          focusRequest: _focus.request,
                          picksSuspended: _picksSuspended,
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
                          marketResidual: _marketResidual,
                          hkjcLoading: _loadingHkjcFootball,
                          staked: StakedSelections.of(_trades),
                          onAddSimulation: (fixture, pick) => unawaited(
                            _openSimulationSheet(
                              cornerSimulationDraft(
                                leagueCode: _leagueCode,
                                leagueName: loaded.data.leagues
                                    .firstWhere(
                                      (league) => league.code == _leagueCode,
                                    )
                                    .name,
                                fixture: fixture,
                                pick: pick,
                                recommended: true,
                                capturedAt: _hkjcFootball?.capturedAt,
                              ),
                            ),
                          ),
                          onRefreshHkjc: () =>
                              _refreshHkjcFootball(force: true),
                          onLeagueChanged: (code) {
                            setState(() {
                              _leagueCode = code;
                              _clearFocus();
                            });
                          },
                        )
                      : _RacingView(
                          racing: loaded.data.racing,
                          alerts: _alerts(loaded),
                          alertsLoading: _loadingHkjcFootball,
                          sharingAlerts: _sharingAlerts,
                          onShareAlerts: _shareAlerts,
                          onOpenAlert: _openAlert,
                          simulationDrafts: _racingDrafts(_alerts(loaded)),
                          staked: StakedSelections.of(_trades),
                          onAddSimulation: (draft) =>
                              unawaited(_openSimulationSheet(draft)),
                          focusRaceId: _focus.raceId,
                          focusRequest: _focus.request,
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
    required this.alerts,
    required this.sharingAlerts,
    required this.onShareAlerts,
    required this.onOpenAlert,
    required this.focusMatchId,
    required this.focusRequest,
    required this.picksSuspended,
    required this.leagueCode,
    required this.hkjcFootball,
    required this.hkjcLoading,
    required this.onRefreshHkjc,
    required this.onAddSimulation,
    required this.staked,
    this.cornerCalibration,
    this.cornerStrengths,
    this.shotCorners,
    this.cornerJoint,
    this.teamNews = const {},
    this.footballWeather = const {},
    this.onlineLearning,
    this.marketAnchor,
    this.marketResidual,
    required this.onLeagueChanged,
  });

  final ForecastLoadResult result;

  /// Cross-league picks shown before any fixture is opened.
  final List<ResearchAlert> alerts;
  final bool sharingAlerts;
  final ValueChanged<List<ResearchAlert>> onShareAlerts;
  final ValueChanged<ResearchAlert> onOpenAlert;

  /// Fixture a tapped pick pointed at, if any.
  final String? focusMatchId;

  /// Bumped by every pick tap, so repeating the same pick navigates again.
  final int focusRequest;

  /// Whether the forward-looking error audit has stopped new picks.
  final bool picksSuspended;
  final String leagueCode;
  final HkjcFootballSnapshot? hkjcFootball;
  final bool hkjcLoading;
  final Future<void> Function() onRefreshHkjc;

  /// Records a fixture's cleared pick in the simulated account.
  final void Function(HkjcFootballFixture, HkjcCornerRecommendation)
  onAddSimulation;

  /// Picks the simulated account already holds, so cards can mark them.
  final StakedSelections staked;
  final MarketCalibration? cornerCalibration;
  final CornerStrengthTable? cornerStrengths;
  final ShotCornerTable? shotCorners;
  final BivariateCornerFit? cornerJoint;
  final Map<String, TeamNewsSnapshot> teamNews;
  final Map<String, FootballWeatherSnapshot> footballWeather;
  final OnlineLearningState? onlineLearning;
  final MarketAnchorState? marketAnchor;

  /// Learned deviation from the quoted price, when it has been measured.
  final MarketResidualState? marketResidual;
  final ValueChanged<String> onLeagueChanged;

  @override
  Widget build(BuildContext context) {
    final data = result.data;
    final leagues = data.leagues
        .where((item) => hkjcFootballProfiles.containsKey(item.code))
        .toList();
    return BackToTopScroller(
      builder: (context, controller) => RefreshIndicator(
        onRefresh: onRefreshHkjc,
        child: ListView(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            AlertSummaryCard(
              alerts: alerts,
              loading: hkjcLoading || hkjcFootball == null,
              sharing: sharingAlerts,
              onShare: () => onShareAlerts(alerts),
              onSelect: onOpenAlert,
              staked: staked,
            ),
            const SizedBox(height: 14),
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
              residual: marketResidual,
              joint: cornerJoint,
              teamNews: teamNews,
              focusMatchId: focusMatchId,
              focusRequest: focusRequest,
              suspended: picksSuspended,
              onAddSimulation: onAddSimulation,
              staked: staked,
            ),
            const SizedBox(height: 18),
            _Disclaimer(text: data.disclaimer),
          ],
        ),
      ),
    );
  }
}

class _RacingView extends StatelessWidget {
  const _RacingView({
    required this.racing,
    required this.alerts,
    required this.alertsLoading,
    required this.sharingAlerts,
    required this.onShareAlerts,
    required this.onOpenAlert,
    required this.simulationDrafts,
    required this.staked,
    required this.onAddSimulation,
    required this.focusRaceId,
    required this.focusRequest,
    required this.status,
    required this.trainingJob,
    required this.syncing,
    required this.onRefresh,
    required this.onTrain,
    required this.onPause,
    required this.onResume,
  });

  final RacingSummary racing;

  /// The same cross-sport picks the football page shows, so either page answers
  /// "is there anything today" on its own.
  final List<ResearchAlert> alerts;
  final bool alertsLoading;
  final bool sharingAlerts;
  final ValueChanged<List<ResearchAlert>> onShareAlerts;
  final ValueChanged<ResearchAlert> onOpenAlert;

  /// Recordable picks keyed by `raceId#saddleNumber`.
  final Map<String, SimulationDraft> simulationDrafts;

  /// Picks the simulated account already holds, so rows can mark them.
  final StakedSelections staked;

  /// Records one of [simulationDrafts] in the simulated account.
  final ValueChanged<SimulationDraft> onAddSimulation;

  /// Race a tapped pick pointed at, if any.
  final String? focusRaceId;

  /// Bumped by every pick tap, so repeating the same pick navigates again.
  final int focusRequest;
  final RacingSyncStatus? status;
  final RacingTrainingJob? trainingJob;
  final bool syncing;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onTrain;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;

  @override
  Widget build(BuildContext context) {
    return BackToTopScroller(
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        children: [
          AlertSummaryCard(
            alerts: alerts,
            loading: alertsLoading,
            sharing: sharingAlerts,
            onShare: () => onShareAlerts(alerts),
            onSelect: onOpenAlert,
            staked: staked,
          ),
          const SizedBox(height: 14),
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
              ScrollFocusTarget(
                key: ValueKey('focus-${race.raceId}'),
                focused: race.raceId == focusRaceId,
                request: focusRequest,
                child: _RacingRaceCard(
                  race: race,
                  tradeEnabled: racing.model.tradeEnabled,
                  focused: race.raceId == focusRaceId,
                  focusRequest: focusRequest,
                  simulationDrafts: simulationDrafts,
                  staked: staked,
                  onAddSimulation: onAddSimulation,
                ),
              ),
              const SizedBox(height: 14),
            ],
        ],
      ),
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

/// One race, collapsed to its verdict until it is opened.
class _RacingRaceCard extends StatefulWidget {
  const _RacingRaceCard({
    required this.race,
    required this.tradeEnabled,
    required this.simulationDrafts,
    required this.staked,
    required this.onAddSimulation,
    this.focused = false,
    this.focusRequest = 0,
  });

  final RacingRace race;
  final bool tradeEnabled;

  /// Recordable picks keyed by `raceId#saddleNumber`.
  final Map<String, SimulationDraft> simulationDrafts;

  /// Picks the simulated account already holds.
  final StakedSelections staked;
  final ValueChanged<SimulationDraft> onAddSimulation;

  /// Outlines the card so the race a pick pointed at is unmistakable.
  final bool focused;

  /// Bumped by every pick tap, so a repeated tap reopens this card.
  final int focusRequest;

  @override
  State<_RacingRaceCard> createState() => _RacingRaceCardState();
}

class _RacingRaceCardState extends State<_RacingRaceCard> {
  late bool _expanded = widget.focused;

  @override
  void didUpdateWidget(_RacingRaceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (shouldReopenForFocus(
      focused: widget.focused,
      wasFocused: oldWidget.focused,
      request: widget.focusRequest,
      previousRequest: oldWidget.focusRequest,
    )) {
      _expanded = true;
    }
  }

  /// Runners the model is willing to price, mirroring the runner pill.
  int get _backed => widget.tradeEnabled
      ? widget.race.runners
            .where((runner) => runner.recommendation != 'no-prediction')
            .length
      : 0;

  @override
  Widget build(BuildContext context) {
    final race = widget.race;
    final focused = widget.focused;
    final tradeEnabled = widget.tradeEnabled;
    final start = race.startTime.toLocal();
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF0D241A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: focused
              ? const Color(0xFF42E695)
              : Colors.white.withValues(alpha: 0.07),
          width: focused ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${start.month}/${start.day} '
                        '${start.hour.toString().padLeft(2, '0')}:'
                        '${start.minute.toString().padLeft(2, '0')}'
                        ' · ${race.venue} 第${race.raceNumber}場 · '
                        '${race.distanceMetres}米 ${race.surface}',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (race.raceName.isNotEmpty)
                        Text(
                          '${race.raceName}'
                          '${race.going.isEmpty ? '' : ' · ${race.going}'}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      if (!_expanded) ...[
                        const SizedBox(height: 4),
                        Text(
                          _backed == 0 ? '不建議' : '模型參考 $_backed 匹',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: _backed == 0
                                ? const Color(0xFF7F8C8D)
                                : const Color(0xFF42E695),
                          ),
                        ),
                      ],
                      if (widget.staked.holdsMatch(race.raceId))
                        const Text(
                          '已入模擬戶口',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6FA8FF),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 13),
            for (final runner in race.runners) ...[
              _RunnerRow(
                runner: runner,
                tradeEnabled: tradeEnabled,
                draft:
                    widget.simulationDrafts['${race.raceId}#${runner.number}'],
                staked: widget.staked,
                onAddSimulation: widget.onAddSimulation,
              ),
              if (runner != race.runners.last)
                Divider(color: Colors.white.withValues(alpha: 0.06)),
            ],
          ],
        ],
      ),
    );
  }
}

class _RunnerRow extends StatelessWidget {
  const _RunnerRow({
    required this.runner,
    required this.tradeEnabled,
    required this.onAddSimulation,
    this.draft,
    this.staked = StakedSelections.empty,
  });

  final RacingRunner runner;
  final bool tradeEnabled;

  /// This runner's recordable pick, when a stored quote priced one.
  final SimulationDraft? draft;

  /// Picks the simulated account already holds.
  final StakedSelections staked;
  final ValueChanged<SimulationDraft> onAddSimulation;

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
              // Only a formal pick may be recorded: an unpredicted runner has
              // no recommendation to stake.
              if (tradeEnabled && draft != null && draft!.recommended)
                if (staked.holdsDraft(draft!))
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text(
                      '已入模擬戶口',
                      style: TextStyle(
                        color: Color(0xFF6FA8FF),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () => onAddSimulation(draft!),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFF42E695),
                    ),
                    icon: const Icon(Icons.add_chart, size: 14),
                    label: const Text(
                      '模擬戶口',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
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
