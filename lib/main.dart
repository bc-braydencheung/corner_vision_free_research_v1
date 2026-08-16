import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/football_mobile.dart';
import 'models/forecast_data.dart';
import 'marksix_lab/lab_view.dart';
import 'models/marksix_mobile.dart';
import 'models/racing_mobile.dart';
import 'models/simulated_trade.dart';
import 'services/data_service.dart';
import 'services/football_mobile_service.dart';
import 'services/football_store.dart';
import 'services/football_training_service.dart';
import 'services/hkjc_mobile_service.dart';
import 'services/racing_store.dart';
import 'services/racing_training_service.dart';
import 'services/research_backup_service.dart';
import 'services/simulation_service.dart';
import 'widgets/prediction_card.dart';
import 'services/marksix_service.dart';
import 'widgets/racing_trade_sheet.dart';
import 'widgets/research_health_view.dart';
import 'widgets/settings_page.dart';
import 'widgets/simulation_account.dart';
import 'widgets/trade_sheet.dart';

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
  double _footballBootstrapProgress = -1;
  String _footballBootstrapStatus = '';
  String _sport = 'football';
  String _leagueCode = 'E0';
  int _section = 0;
  FootballSyncStatus? _footballStatus;
  FootballTrainingJob? _footballTrainingJob;
  Timer? _footballTrainingTimer;
  RacingSyncStatus? _racingStatus;
  RacingTrainingJob? _trainingJob;
  Timer? _trainingTimer;

  // Mark Six state
  final MarkSixService _marksixService = MarkSixService();
  List<MarkSixDraw> _marksixDraws = [];
  MarkSixStats? _marksixStats;
  MarkSixPrediction? _marksixPrediction;
  List<MarkSixCorrection> _marksixCorrections = [];
  bool _marksixLoading = false;
  String _marksixViewMode = 'stats';
  String _marksixEngineMode = 'stats';
  int _marksixBacktestDone = 0;
  int _marksixBacktestTotal = 0;

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
      unawaited(_initMarksix());
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
    await _refreshFootball();
    await _refreshRacing();
  }

  Future<void> _refreshFootball() async {
    final current = _result;
    if (current == null || _syncingFootball) {
      return;
    }
    setState(() => _syncingFootball = true);
    try {
      final refreshed = await widget.dataService.refreshFootball(
        current,
        onBootstrapProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _footballBootstrapProgress = progress;
              _footballBootstrapStatus = status;
            });
          }
        },
      );
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

  // ---- Mark Six ----

  Future<void> _initMarksix() async {
    if (_marksixLoading) return;
    setState(() => _marksixLoading = true);
    try {
      await _marksixService.initialize();
      // First try to load from local storage
      var draws = await _marksixService.store.loadDraws();
      if (draws.isEmpty) {
        // No local data - try remote mirror
        final count = await _marksixService.syncFromRemote();
        if (count > 0) {
          draws = await _marksixService.store.loadDraws();
        }
      }
      final stats = await _marksixService.computeAndSaveStats();
      final prediction = await _marksixService.loadCachedPrediction();
      if (!mounted) return;
      setState(() {
        _marksixDraws = draws;
        _marksixStats = stats;
        _marksixPrediction = prediction;
      });
    } catch (_) {
      // Show empty state
    } finally {
      if (mounted) setState(() => _marksixLoading = false);
    }
  }

  Future<void> _refreshMarksixStats() async {
    final stats = await _marksixService.computeAndSaveStats();
    if (!mounted) return;
    setState(() => _marksixStats = stats);
  }

  Future<void> _generateMarksixPrediction() async {
    setState(() => _marksixLoading = true);
    try {
      final prediction = await _marksixService.generatePrediction();
      if (!mounted) return;
      setState(() {
        _marksixPrediction = prediction;
        _marksixViewMode = 'prediction';
      });
    } finally {
      if (mounted) setState(() => _marksixLoading = false);
    }
  }

  Future<void> _runMarksixBacktest() async {
    setState(() => _marksixLoading = true);
    try {
      _marksixBacktestDone = 0;
      _marksixBacktestTotal = 0;
      final corrections = await _marksixService.runBacktest(
        minTraining: 50,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _marksixBacktestDone = done;
              _marksixBacktestTotal = total;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _marksixCorrections = corrections;
        _marksixViewMode = 'prediction';
      });
      if (corrections.isNotEmpty) {
        final avgMatches =
            corrections.map((c) => c.matches).reduce((a, b) => a + b) /
            corrections.length;
        _showMessage('回測完成：${corrections.length}期，平均命中$avgMatches個號碼');
      }
    } finally {
      if (mounted) setState(() => _marksixLoading = false);
    }
  }

  Future<void> _syncMarksixFromApi() async {
    setState(() => _marksixLoading = true);
    try {
      final count = await _marksixService.syncFromRemote();
      if (!mounted) return;
      if (count == 0) {
        _showMessage('沒有新賽果，已是最新。');
        return;
      }
      final allDraws = await _marksixService.store.loadDraws();
      final stats = await _marksixService.computeAndSaveStats();
      setState(() {
        _marksixDraws = allDraws;
        _marksixStats = stats;
      });
      _showMessage('已下載 $count 期新賽果！共 ${allDraws.length} 期');
    } catch (e) {
      if (mounted) _showMessage('同步失敗：$e');
    } finally {
      if (mounted) setState(() => _marksixLoading = false);
    }
  }

  double get _availableBalance {
    return _simulationService.riskSummary(_trades).available;
  }

  Future<void> _addTrade(SimulatedTrade trade) async {
    final updated = [..._trades, trade];
    await _simulationService.save(updated);
    if (!mounted) {
      return;
    }
    setState(() => _trades = updated);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已加入不可修改的模擬戶口記錄')));
  }

  Future<void> _showTradeSheet(MatchPrediction prediction) async {
    if (!prediction.tradeEligible) {
      _showMessage(prediction.tradeReason);
      return;
    }
    final league = _result?.data.league(prediction.leagueCode);
    if (league?.model.historicalDriftStatus == 'stop') {
      _showMessage('近期歷史誤差已達停止門檻，不能新增模擬交易。');
      return;
    }
    if (_result?.shadowHealth.suspendTrading ?? false) {
      _showMessage('前瞻模型漂移已達停止門檻，不能新增模擬交易。');
      return;
    }
    final risk = _simulationService.riskSummary(
      _trades,
      eventDate: prediction.date,
    );
    if (risk.stopped) {
      _showMessage(risk.reason);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => TradeSheet(
        prediction: prediction,
        availableBalance: _availableBalance,
        maximumStake: risk.maximumNewStake,
        onBuy: _addTrade,
      ),
    );
  }

  Future<void> _showRacingTradeSheet(
    RacingRace race,
    RacingRunner runner,
    String modelVersion,
  ) async {
    final racingModel = _result?.data.racing.model;
    if (racingModel == null || !racingModel.tradeEnabled) {
      _showMessage(
        racingModel?.tradePolicyReason.isNotEmpty == true
            ? racingModel!.tradePolicyReason
            : '賽馬市場交易閘門未通過，只顯示研究預測。',
      );
      return;
    }
    final risk = _simulationService.riskSummary(
      _trades,
      eventDate: race.startTime,
    );
    if (risk.stopped) {
      _showMessage(risk.reason);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => RacingTradeSheet(
        race: race,
        runner: runner,
        modelVersion: modelVersion,
        availableBalance: _availableBalance,
        maximumStake: risk.maximumNewStake,
        onBuy: _addTrade,
      ),
    );
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
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: '模擬戶口',
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
                          ButtonSegment(
                            value: 'marksix',
                            icon: Icon(Icons.casino),
                            label: Text('六合彩'),
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
                  child: _section == 3
                      ? const SettingsPage()
                      : _section == 2
                      ? ResearchHealthView(
                          data: loaded.data,
                          footballStatus: _footballStatus,
                          racingStatus: _racingStatus,
                          shadowHealth: loaded.shadowHealth,
                          sourceErrors: loaded.sourceErrors,
                          trades: _trades,
                          onExportReport: _exportReport,
                          onExportBackup: _exportBackup,
                          onImportBackup: _importBackup,
                        )
                      : _section == 1
                      ? SimulationAccount(trades: _trades)
                      : _sport == 'football'
                      ? _FootballView(
                          result: loaded,
                          leagueCode: _leagueCode,
                          status: _footballStatus,
                          trainingJob: _footballTrainingJob,
                          syncing: _syncingFootball,
                          bootstrapProgress: _footballBootstrapProgress,
                          bootstrapStatus: _footballBootstrapStatus,
                          onLeagueChanged: (code) {
                            setState(() => _leagueCode = code);
                          },
                          onRefresh: _refreshFootball,
                          onTrain: _startFootballTraining,
                          onPause: _pauseFootballTraining,
                          onResume: _resumeFootballTraining,
                          onSimulate: _showTradeSheet,
                        )
                      : _sport == 'marksix'
                      ? Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                              child: SegmentedButton<String>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(
                                    value: 'stats',
                                    icon: Icon(Icons.insights),
                                    label: Text('統計模式'),
                                  ),
                                  ButtonSegment(
                                    value: 'lab',
                                    icon: Icon(Icons.science),
                                    label: Text('顛覆模式'),
                                  ),
                                ],
                                selected: {_marksixEngineMode},
                                onSelectionChanged: (selection) {
                                  setState(
                                    () => _marksixEngineMode = selection.first,
                                  );
                                },
                              ),
                            ),
                            Expanded(
                              child: _marksixEngineMode == 'lab'
                                  ? const MarkSixLabView()
                                  : _MarkSixView(
                                      draws: _marksixDraws,
                                      stats: _marksixStats,
                                      prediction: _marksixPrediction,
                                      corrections: _marksixCorrections,
                                      loading: _marksixLoading,
                                      viewMode: _marksixViewMode,
                                      onRefreshStats: _refreshMarksixStats,
                                      onGeneratePrediction:
                                          _generateMarksixPrediction,
                                      onRunBacktest: _runMarksixBacktest,
                                      onViewModeChanged: (mode) {
                                        setState(() => _marksixViewMode = mode);
                                      },
                                      onSyncFromApi: _syncMarksixFromApi,
                                      backtestDone: _marksixBacktestDone,
                                      backtestTotal: _marksixBacktestTotal,
                                    ),
                            ),
                          ],
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
                          onSimulate: _showRacingTradeSheet,
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
    required this.status,
    required this.trainingJob,
    required this.syncing,
    this.bootstrapProgress = -1,
    this.bootstrapStatus = '',
    required this.onLeagueChanged,
    required this.onRefresh,
    required this.onTrain,
    required this.onPause,
    required this.onResume,
    required this.onSimulate,
  });

  final ForecastLoadResult result;
  final String leagueCode;
  final FootballSyncStatus? status;
  final FootballTrainingJob? trainingJob;
  final bool syncing;
  final double bootstrapProgress;
  final String bootstrapStatus;
  final ValueChanged<String> onLeagueChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onTrain;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final ValueChanged<MatchPrediction> onSimulate;

  @override
  Widget build(BuildContext context) {
    final data = result.data;
    final league = data.league(leagueCode);
    final predictions = league.forecasts.isNotEmpty
        ? league.forecasts
        : league.recentBacktests;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          // Bootstrap progress indicator
          if (bootstrapProgress >= 0)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF42E695).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF42E695).withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_download,
                        size: 18,
                        color: Color(0xFF42E695),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          bootstrapProgress >= 1.0
                              ? '下載完成！'
                              : '手機直接從 football-data.co.uk 下載數據',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      Text(
                        '${(bootstrapProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF42E695),
                        ),
                      ),
                    ],
                  ),
                  if (bootstrapProgress < 1.0) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: bootstrapProgress,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        color: const Color(0xFF42E695),
                      ),
                    ),
                    if (bootstrapStatus.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bootstrapStatus,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          _FootballUpdateCard(
            status: status,
            job: trainingJob,
            syncing: syncing,
            onRefresh: onRefresh,
            onTrain: onTrain,
            onPause: onPause,
            onResume: onResume,
          ),
          const SizedBox(height: 13),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in data.leagues) ...[
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
          _ModelCard(league: league),
          const SizedBox(height: 22),
          Row(
            children: [
              Text(
                league.forecasts.isNotEmpty ? '未來賽事' : '最近候選外評估',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (league.forecasts.isEmpty)
                const _Pill(label: '等待新賽程', color: Color(0xFFFFC857)),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            league.status,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.56)),
          ),
          const SizedBox(height: 14),
          for (final prediction in predictions) ...[
            PredictionCard(
              prediction: prediction,
              onSimulate:
                  prediction.mode == 'forecast' &&
                      prediction.recommendation != 'no-prediction' &&
                      prediction.tradeEligible
                  ? () => onSimulate(prediction)
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 10),
          _Disclaimer(text: data.disclaimer),
        ],
      ),
    );
  }
}

class _FootballUpdateCard extends StatelessWidget {
  const _FootballUpdateCard({
    required this.status,
    required this.job,
    required this.syncing,
    required this.onRefresh,
    required this.onTrain,
    required this.onPause,
    required this.onResume,
  });

  final FootballSyncStatus? status;
  final FootballTrainingJob? job;
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
    final latest = status?.latestResults.entries
        .map((entry) => '${entry.key} ${entry.value}')
        .join(' · ');
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
                  syncing ? '正在檢查五大聯賽賽果及賽程…' : status?.message ?? '手機足球快取已載入',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '檢查足球更新',
                onPressed: syncing ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (latest != null && latest.isNotEmpty)
            Text(
              '最新完整賽果：$latest',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.52),
                fontSize: 11,
              ),
            ),
          const SizedBox(height: 5),
          Text(
            '市場快照 ${status?.marketSnapshotCount ?? 0} · '
            '賽前天氣快照 ${status?.weatherSnapshotCount ?? 0} · '
            '未有真實角球盤前只作統計研究',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          if (job != null) ...[
            const SizedBox(height: 12),
            if (running)
              LinearProgressIndicator(
                value: (job!.progress / 100).clamp(0.0, 1.0),
              ),
            const SizedBox(height: 7),
            Text(
              '${job!.stage} · ${job!.progress.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
            if (job!.error != null && job!.error!.isNotEmpty)
              Text(
                job!.error!,
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
                label: Text(job?.status == 'failed' ? '繼續上次訓練' : '重新訓練五大聯賽模型'),
              ),
            ),
          ],
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
    required this.onSimulate,
  });

  final RacingSummary racing;
  final RacingSyncStatus? status;
  final RacingTrainingJob? trainingJob;
  final bool syncing;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onTrain;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final void Function(RacingRace, RacingRunner, String) onSimulate;

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
              modelVersion: racing.modelVersion,
              tradeEnabled: racing.model.tradeEnabled,
              onSimulate: onSimulate,
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
  const _RacingRaceCard({
    required this.race,
    required this.modelVersion,
    required this.tradeEnabled,
    required this.onSimulate,
  });

  final RacingRace race;
  final String modelVersion;
  final bool tradeEnabled;
  final void Function(RacingRace, RacingRunner, String) onSimulate;

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
            _RunnerRow(
              race: race,
              runner: runner,
              modelVersion: modelVersion,
              tradeEnabled: tradeEnabled,
              onSimulate: onSimulate,
            ),
            if (runner != race.runners.last)
              Divider(color: Colors.white.withValues(alpha: 0.06)),
          ],
        ],
      ),
    );
  }
}

class _RunnerRow extends StatelessWidget {
  const _RunnerRow({
    required this.race,
    required this.runner,
    required this.modelVersion,
    required this.tradeEnabled,
    required this.onSimulate,
  });

  final RacingRace race;
  final RacingRunner runner;
  final String modelVersion;
  final bool tradeEnabled;
  final void Function(RacingRace, RacingRunner, String) onSimulate;

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
              FilledButton.tonal(
                onPressed:
                    !tradeEnabled || runner.recommendation == 'no-prediction'
                    ? null
                    : () => onSimulate(race, runner, modelVersion),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(
                  !tradeEnabled
                      ? 'No bet'
                      : runner.recommendation == 'no-prediction'
                      ? '不預測'
                      : '模擬',
                ),
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

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.league});

  final LeagueForecastData league;

  @override
  Widget build(BuildContext context) {
    final model = league.model;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph, color: Color(0xFF42E695)),
              const SizedBox(width: 9),
              Text(
                '${league.name}模型健康度',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const Spacer(),
              Flexible(
                child: _Pill(
                  label: model.selectedCandidateLabel,
                  color: const Color(0xFFB491FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Pill(
            label: model.tradeEnabled ? '市場交易閘門已通過' : '市場交易閘門未通過',
            color: model.tradeEnabled
                ? const Color(0xFF42E695)
                : const Color(0xFFFFC857),
          ),
          const SizedBox(height: 17),
          Text(
            '${model.trainingMatches}場訓練 · ${model.holdoutMatches}場留出 · '
            '訓練至 ${model.trainedThrough}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'MAE、Brier、漂移及資料來源請到「研究健康」查看。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
            ),
          ),
          if (model.tradePolicyReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              model.tradePolicyReason,
              style: const TextStyle(color: Color(0xFFFFC857), fontSize: 10),
            ),
          ],
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

// ---- Mark Six View ----

class _MarkSixView extends StatelessWidget {
  const _MarkSixView({
    required this.draws,
    required this.stats,
    required this.prediction,
    required this.corrections,
    required this.loading,
    required this.viewMode,
    required this.onRefreshStats,
    required this.onGeneratePrediction,
    required this.onRunBacktest,
    required this.onViewModeChanged,
    required this.onSyncFromApi,
    this.backtestDone = 0,
    this.backtestTotal = 0,
  });

  final List<MarkSixDraw> draws;
  final MarkSixStats? stats;
  final MarkSixPrediction? prediction;
  final List<MarkSixCorrection> corrections;
  final bool loading;
  final String viewMode;
  final VoidCallback onRefreshStats;
  final VoidCallback onGeneratePrediction;
  final VoidCallback onRunBacktest;
  final ValueChanged<String> onViewModeChanged;
  final VoidCallback onSyncFromApi;
  final int backtestDone;
  final int backtestTotal;

  @override
  Widget build(BuildContext context) {
    if (loading && draws.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async => onRefreshStats(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          // Cloud sync banner
          if (draws.isEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC857).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFFC857).withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_download,
                        size: 18,
                        color: Color(0xFFFFC857),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loading ? '正在從雲端下載數據...' : '尚未載入六合彩數據',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '點擊下方按鈕從 GitHub Pages 鏡像下載\n1993年至今全部六合彩賽果',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  if (loading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFFC857),
                      ),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: onSyncFromApi,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('從雲端下載全部數據'),
                    ),
                  ],
                ],
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF42E695).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF42E695).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_done,
                    size: 16,
                    color: Color(0xFF42E695),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已載入 ${draws.length} 期數據',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: loading ? null : onSyncFromApi as VoidCallback?,
                    icon: loading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 14),
                    label: Text(
                      loading ? '同步中' : '檢查更新',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

          // Action buttons
          Row(
            children: [
              _ActionChip(
                icon: Icons.refresh,
                label: '統計',
                selected: viewMode == 'stats',
                onTap: () => onViewModeChanged('stats'),
              ),
              const SizedBox(width: 6),
              _ActionChip(
                icon: Icons.list_alt,
                label: '賽果',
                selected: viewMode == 'results',
                onTap: () => onViewModeChanged('results'),
              ),
              const SizedBox(width: 6),
              _ActionChip(
                icon: Icons.psychology,
                label: '預測',
                selected: viewMode == 'prediction',
                onTap: () => onViewModeChanged('prediction'),
              ),
              const Spacer(),
              Text(
                '${draws.length}期',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Content by mode
          if (stats != null && viewMode == 'stats') ...[
            _StatsDashboard(stats: stats!),
          ] else if (viewMode == 'results') ...[
            if (draws.isEmpty)
              const _EmptyState(message: '尚未載入六合彩數據\n請用 Python 爬蟲下載歷史賽果'),
            for (final draw in draws.reversed.take(20)) _DrawCard(draw: draw),
            if (draws.length > 20)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '顯示最近20期（共${draws.length}期）',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ),
          ] else if (viewMode == 'prediction') ...[
            _PredictionPanel(
              prediction: prediction,
              corrections: corrections,
              onGenerate: onGeneratePrediction,
              onBacktest: onRunBacktest,
              backtestDone: backtestDone,
              backtestTotal: backtestTotal,
            ),
          ],

          const SizedBox(height: 20),
          _Disclaimer(text: '六合彩為完全隨機遊戲，所有統計及預測僅供個人研究參考，不構成投注建議。'),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF42E695).withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF42E695).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? const Color(0xFF42E695) : Colors.white54,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF42E695) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Stats Dashboard ----

class _StatsDashboard extends StatelessWidget {
  const _StatsDashboard({required this.stats});
  final MarkSixStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📊 統計概覽',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        // Key metrics row
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatCard(
              label: '總期數',
              value: '${stats.totalDraws}',
              color: const Color(0xFF42E695),
            ),
            _StatCard(
              label: '奇偶比',
              value: stats.oddEvenRatio.toStringAsFixed(2),
              color: const Color(0xFF7FD1FF),
            ),
            _StatCard(
              label: '平均總和',
              value: stats.avgSum.toStringAsFixed(0),
              color: const Color(0xFFB491FF),
            ),
            _StatCard(
              label: '連號率',
              value: '${(stats.consecutiveRate * 100).toStringAsFixed(0)}%',
              color: const Color(0xFFFFC857),
            ),
            _StatCard(
              label: '平均頭獎',
              value: '\$${(stats.topPrizeAvg / 10000).toStringAsFixed(0)}萬',
              color: const Color(0xFFFF8FA3),
            ),
            _StatCard(
              label: '平均投注額',
              value: '\$${(stats.avgTurnover / 1000000).toStringAsFixed(0)}M',
              color: const Color(0xFF42E695),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Hot numbers
        const Text(
          '🔥 近期熱號',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _NumberBalls(numbers: stats.hotNumbers, color: const Color(0xFFFF8FA3)),
        const SizedBox(height: 16),
        // Cold numbers
        const Text(
          '❄️ 近期冷號',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _NumberBalls(
          numbers: stats.coldNumbers,
          color: const Color(0xFF7FD1FF),
        ),
        const SizedBox(height: 20),
        // Frequency grid
        const Text(
          '📈 號碼頻率分佈',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _FrequencyGrid(frequency: stats.numberFrequency),
        const SizedBox(height: 12),
        Text(
          '日期範圍：${stats.dateRange}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberBalls extends StatelessWidget {
  const _NumberBalls({required this.numbers, required this.color});
  final List<int> numbers;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final n in numbers)
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.5),
                  color.withValues(alpha: 0.25),
                ],
              ),
              border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
      ],
    );
  }
}

class _FrequencyGrid extends StatelessWidget {
  const _FrequencyGrid({required this.frequency});
  final Map<String, int> frequency;

  @override
  Widget build(BuildContext context) {
    final maxFreq = frequency.values.isEmpty ? 1 : frequency.values.reduce(max);
    final entries = frequency.entries.toList()
      ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));

    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final entry in entries)
          Container(
            width: 27,
            height: 34,
            decoration: BoxDecoration(
              color: _heatColor(entry.value, maxFreq).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  '${entry.value}',
                  style: TextStyle(
                    fontSize: 8,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _heatColor(int value, int max) {
    final ratio = max > 0 ? value / max : 0.0;
    if (ratio > 0.8) return const Color(0xFFFF8FA3);
    if (ratio > 0.6) return const Color(0xFFFFC857);
    if (ratio > 0.35) return const Color(0xFF42E695);
    return const Color(0xFF7FD1FF);
  }
}

// ---- Draw Card ----

class _DrawCard extends StatelessWidget {
  const _DrawCard({required this.draw});
  final MarkSixDraw draw;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF0D241A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pill(label: draw.drawNumber, color: const Color(0xFFB491FF)),
              const SizedBox(width: 8),
              Text(
                draw.drawDate,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (draw.totalTurnover > 0)
                _Pill(
                  label:
                      '總投注: \$${(draw.totalTurnover / 1000000).toStringAsFixed(1)}M',
                  color: const Color(0xFF42E695),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              ...draw.numbers.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFFFF8FA3), Color(0x66FF8FA3)],
                      ),
                      border: Border.all(
                        color: const Color(0xFFFF8FA3).withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$n',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFF42E695), Color(0x6642E695)],
                  ),
                  border: Border.all(
                    color: const Color(0xFF42E695).withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '特',
                      style: TextStyle(fontSize: 8, color: Colors.white54),
                    ),
                    Text(
                      '${draw.specialNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (draw.prizes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(color: Colors.white.withValues(alpha: 0.06)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in draw.prizes.take(4))
                  Text(
                    '${p.name}: \$${_fmt(p.prizePerUnit)} (${_units(p.winningUnits)}注)',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  String _units(double u) => (u / 10) == (u / 10).roundToDouble()
      ? (u / 10).toStringAsFixed(0)
      : (u / 10).toStringAsFixed(1);
}

class _PredictionPanel extends StatelessWidget {
  const _PredictionPanel({
    required this.prediction,
    required this.corrections,
    required this.onGenerate,
    required this.onBacktest,
    this.backtestDone = 0,
    this.backtestTotal = 0,
  });
  final MarkSixPrediction? prediction;
  final List<MarkSixCorrection> corrections;
  final VoidCallback onGenerate;
  final VoidCallback onBacktest;
  final int backtestDone;
  final int backtestTotal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🎯 AI 預測',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('產生預測'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onBacktest,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('回測評估'),
              ),
            ),
          ],
        ),

        // Backtest progress indicator
        if (backtestTotal > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                '回測中 $backtestDone/$backtestTotal',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: backtestDone / backtestTotal,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
          ),
        ],

        const SizedBox(height: 16),
        if (prediction != null &&
            prediction!.recommendedNumbers.isNotEmpty) ...[
          Center(
            child: _Pill(
              label:
                  '信心: ${prediction!.confidenceLabel == 'high'
                      ? '高'
                      : prediction!.confidenceLabel == 'medium'
                      ? '中'
                      : '低'} (${prediction!.confidence.toStringAsFixed(0)}%)',
              color: prediction!.confidenceLabel == 'high'
                  ? const Color(0xFF42E695)
                  : prediction!.confidenceLabel == 'medium'
                  ? const Color(0xFFFFC857)
                  : const Color(0xFFFF8FA3),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '推介號碼',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 8,
            children: [
              ...prediction!.recommendedNumbers.map(
                (n) => Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFFFF8FA3), Color(0x66FF8FA3)],
                    ),
                    border: Border.all(
                      color: const Color(0xFFFF8FA3).withValues(alpha: 0.7),
                      width: 2.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$n',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFF42E695), Color(0x6642E695)],
                  ),
                  border: Border.all(
                    color: const Color(0xFF42E695).withValues(alpha: 0.7),
                    width: 2.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '特',
                      style: TextStyle(fontSize: 9, color: Colors.white70),
                    ),
                    Text(
                      '${prediction!.specialNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Per-number reasoning
          if (prediction!.numberReasoning.isNotEmpty) ...[
            const Text(
              '推介邏輯',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final entry in prediction!.numberReasoning.entries)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0xFFFF8FA3), Color(0x66FF8FA3)],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${entry.key}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.value['主因'] as String? ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF42E695),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '頻率${entry.value['頻率貢獻'] ?? '-'} · 馬可夫${entry.value['馬可夫貢獻'] ?? '-'}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${((double.tryParse((entry.value['機率'] as String?) ?? '0') ?? 0) * 100).toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
          ],

          // Pattern-based prediction (parallel)
          if (prediction!.patternNumbers.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFB491FF).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFB491FF).withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.grid_view,
                        size: 16,
                        color: Color(0xFFB491FF),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '結構模式預測',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB491FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    prediction!.patternReasoning['reason'] as String? ?? '',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 6,
                    children: [
                      ...prediction!.patternNumbers.map(
                        (n) => Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFFB491FF), Color(0x66B491FF)],
                            ),
                            border: Border.all(
                              color: const Color(
                                0xFFB491FF,
                              ).withValues(alpha: 0.7),
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$n',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [Color(0xFF42E695), Color(0x6642E695)],
                          ),
                          border: Border.all(
                            color: const Color(
                              0xFF42E695,
                            ).withValues(alpha: 0.7),
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${prediction!.patternSpecial}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          ...prediction!.factors.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $f',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ] else if (prediction?.confidenceLabel == 'insufficient') ...[
          const _EmptyState(message: '數據不足，需至少50期歷史數據'),
        ],
        if (corrections.isNotEmpty) ...[
          const SizedBox(height: 24),

          // Best prediction ever
          _buildBestMatch(corrections),

          const SizedBox(height: 16),
          const Text(
            '📋 修正記錄',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final c in corrections.reversed.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${c.drawDate}: 命中${c.matches}/6 (累積: ${(c.rollingAccuracy * 100).toStringAsFixed(0)}%)',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFC857).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber,
                size: 16,
                color: Color(0xFFFFC857),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '六合彩為完全隨機遊戲。AI預測僅供統計研究，不構成投注建議。',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _buildBestMatch(List<MarkSixCorrection> corrections) {
    if (corrections.isEmpty) return const SizedBox.shrink();
    final best = corrections.reduce((a, b) => a.matches > b.matches ? a : b);
    if (best.matches == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF42E695).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF42E695).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events,
                size: 16,
                color: Color(0xFFFFC857),
              ),
              const SizedBox(width: 6),
              Text(
                '最高命中 · ${best.drawDate} · ${best.matches}/6',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFFC857),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '預測',
            style: TextStyle(fontSize: 10, color: Colors.white38),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              ...best.predictedNumbers.map(
                (n) => Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF8FA3).withValues(alpha: 0.3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$n',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF8FA3),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '實際',
            style: TextStyle(fontSize: 10, color: Colors.white38),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              ...best.actualNumbers.map(
                (n) => Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF42E695).withValues(alpha: 0.3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$n',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF42E695),
                    ),
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
