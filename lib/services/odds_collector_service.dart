import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../models/football_mobile.dart';
import '../models/hkjc_football.dart';
import '../models/racing_mobile.dart';
import 'football_store.dart';
import 'hkjc_football_service.dart';
import 'hkjc_racing_odds_service.dart';
import 'market_timeline.dart';
import 'racing_store.dart';

const oddsCollectorTask = 'ai.devin.corner.EdgeWise.oddsCollector';
const oddsCollectorUniqueName = oddsCollectorTask;

/// Result of one collection pass, reported in the research health page.
class OddsCollectionReport {
  const OddsCollectionReport({
    required this.footballCaptured,
    required this.racingCaptured,
    required this.footballStored,
    required this.racingStored,
    required this.note,
    this.latestFootballCapture,
    this.latestRacingCapture,
  });

  static const empty = OddsCollectionReport(
    footballCaptured: 0,
    racingCaptured: 0,
    footballStored: 0,
    racingStored: 0,
    note: '',
  );

  /// Quotes appended during this pass.
  final int footballCaptured;
  final int racingCaptured;

  /// Total quotes retained in the local time series.
  final int footballStored;
  final int racingStored;
  final String note;
  final DateTime? latestFootballCapture;
  final DateTime? latestRacingCapture;

  bool get hasHistory => footballStored > 0 || racingStored > 0;
}

/// Appends every HKJC quote the app sees to an append-only local time series.
///
/// The quotes themselves are public and free, but nobody publishes their
/// history: recording them with a capture time is what makes the opening quote,
/// the closing quote and the drift between them available for research. Nothing
/// is ever overwritten, so a stored series can always be replayed.
class OddsCollectorService {
  OddsCollectorService({
    FootballStore? footballStore,
    RacingStore? racingStore,
    HkjcFootballService? footballService,
    HkjcRacingOddsService? racingService,
    this.horizon = const Duration(hours: 60),
    this.minimumGap = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : footballStore = footballStore ?? FootballStore(),
       racingStore = racingStore ?? RacingStore(),
       footballService = footballService ?? HkjcFootballService(),
       racingService = racingService ?? HkjcRacingOddsService(),
       _now = now ?? DateTime.now;

  final FootballStore footballStore;
  final RacingStore racingStore;
  final HkjcFootballService footballService;
  final HkjcRacingOddsService racingService;

  /// Only fixtures kicking off within this window are tracked.
  final Duration horizon;

  /// A line is re-recorded only when the quote moved or this much time passed.
  final Duration minimumGap;
  final DateTime Function() _now;

  /// Fetches the current HKJC quotes and appends the new ones.
  Future<OddsCollectionReport> collect() async {
    final notes = <String>[];
    var football = 0;
    var racing = 0;
    try {
      final snapshot = await footballService.load();
      football = await recordFootball(snapshot);
    } on Object catch (error) {
      notes.add('足球盤口收集失敗（${error.runtimeType}）');
    }
    try {
      final meeting = await racingService.currentMeeting();
      if (meeting != null) {
        racing = await recordRacing(meeting);
      }
    } on Object catch (error) {
      notes.add('賽馬賠率收集失敗（${error.runtimeType}）');
    }
    final storedFootball = await footballStore.loadOddsSnapshots();
    final storedRacing = await racingStore.loadOddsSnapshots();
    return OddsCollectionReport(
      footballCaptured: football,
      racingCaptured: racing,
      footballStored: storedFootball.length,
      racingStored: storedRacing.length,
      note: notes.join('；'),
      latestFootballCapture: _latest(
        storedFootball.map((snapshot) => snapshot.capturedAt),
      ),
      latestRacingCapture: _latest(
        storedRacing.map((snapshot) => snapshot.capturedAt),
      ),
    );
  }

  /// Appends the corner (`CHL`) quotes of the fixtures inside [horizon].
  ///
  /// Only pre-match quotes are recorded: the store keeps a pre-match series
  /// for CLV and rejects anything priced on corners already on the pitch, so
  /// offering it an in-play quote would fail the whole pass.
  Future<int> recordFootball(HkjcFootballSnapshot snapshot) async {
    final now = _now().toUtc();
    final existing = await footballStore.loadOddsSnapshots();
    final timelines = cornerTimelines(existing);
    var appended = 0;
    for (final fixture in snapshot.fixtures) {
      final kickOff = fixture.kickOffTime.toUtc();
      if (fixture.startedBy(_now()) || kickOff.isAfter(now.add(horizon))) {
        continue;
      }
      final lines = timelines[fixture.matchId] ?? const <CornerLineTimeline>[];
      for (final line in fixture.cornerLines) {
        final over = line.highOdds;
        final under = line.lowOdds;
        if (over == null || under == null || over <= 1 || under <= 1) {
          continue;
        }
        final previous = lines
            .where((timeline) => timeline.line == line.line)
            .map((timeline) => timeline.latest)
            .whereType<FootballOddsSnapshot>()
            .lastOrNull;
        if (previous != null && !_movedEnough(previous, over, under, now)) {
          continue;
        }
        final record = FootballOddsSnapshot(
          matchId: fixture.matchId,
          capturedAt: now,
          source: 'hkjc-chl',
          line: line.line,
          overOdds: over,
          underOdds: under,
          marketId: line.lineId,
          eventName: '${fixture.homeTeam} vs ${fixture.awayTeam}',
          marketName: '角球大細 ${line.condition}',
          marketTime: fixture.kickOffTime,
          inPlay: false,
          isClosing: kickOff.difference(now) < const Duration(minutes: 15),
        );
        try {
          await footballStore.saveOddsSnapshot(record);
        } on FormatException {
          // One quote the append-only store refuses must not cost the pass
          // the quotes of every other fixture.
          continue;
        }
        appended++;
      }
    }
    return appended;
  }

  /// Appends the win pool of every race of [meeting] that is still open.
  Future<int> recordRacing(HkjcRacingMeeting meeting) async {
    final now = _now().toUtc();
    final existing = await racingStore.loadOddsSnapshots();
    var appended = 0;
    for (final race in meeting.races) {
      final candidate = race.snapshot(now);
      if (candidate == null || !_storable(candidate, now)) {
        continue;
      }
      final timeline = raceTimeline(race.raceId, existing);
      final previous = timeline.snapshots.lastOrNull;
      if (previous != null && !_poolMoved(previous, candidate, now)) {
        continue;
      }
      try {
        await racingStore.saveOddsSnapshot(candidate);
      } on FormatException {
        continue;
      }
      appended++;
    }
    return appended;
  }

  /// A live quote is only meaningful when it is known to precede the start.
  bool _storable(RacingOddsSnapshot candidate, DateTime now) {
    if (candidate.isFinal) {
      return true;
    }
    final start = candidate.raceTime?.toUtc();
    return start != null && now.isBefore(start);
  }

  bool _movedEnough(
    FootballOddsSnapshot previous,
    double over,
    double under,
    DateTime now,
  ) {
    if (now.difference(previous.capturedAt.toUtc()) >= minimumGap) {
      return true;
    }
    return (previous.overOdds - over).abs() > 0.001 ||
        (previous.underOdds - under).abs() > 0.001;
  }

  bool _poolMoved(
    RacingOddsSnapshot previous,
    RacingOddsSnapshot candidate,
    DateTime now,
  ) {
    if (now.difference(previous.capturedAt.toUtc()) >= minimumGap) {
      return true;
    }
    if (previous.oddsByHorse.length != candidate.oddsByHorse.length) {
      return true;
    }
    for (final entry in candidate.oddsByHorse.entries) {
      final before = previous.oddsByHorse[entry.key];
      if (before == null || (before - entry.value).abs() > 0.001) {
        return true;
      }
    }
    return false;
  }

  static DateTime? _latest(Iterable<DateTime> times) {
    DateTime? latest;
    for (final time in times) {
      if (latest == null || time.isAfter(latest)) {
        latest = time;
      }
    }
    return latest;
  }

  /// Closing-line grades of the corner selections stored in [predictions].
  ///
  /// Each entry is one recommendation the app displayed; grading it against the
  /// closing quote needs no result, so the feedback arrives before kick-off.
  List<ClosingLineValue> gradeAgainstClosing({
    required List<FootballOddsSnapshot> stored,
    required List<
      ({
        String matchId,
        double line,
        bool over,
        double modelProbability,
        double takenOdds,
        DateTime kickOff,
      })
    >
    predictions,
  }) {
    final timelines = cornerTimelines(stored);
    final graded = <ClosingLineValue>[];
    for (final prediction in predictions) {
      final lines = timelines[prediction.matchId];
      if (lines == null) {
        continue;
      }
      final timeline = lines
          .where((entry) => (entry.line - prediction.line).abs() < 0.01)
          .firstOrNull;
      final close = timeline?.closing(prediction.kickOff);
      if (close == null) {
        continue;
      }
      final fair = twoWayFairProbabilities(close.overOdds, close.underOdds);
      if (fair == null) {
        continue;
      }
      graded.add(
        ClosingLineValue(
          modelProbability: prediction.modelProbability,
          takenOdds: prediction.takenOdds,
          closingOdds: prediction.over ? close.overOdds : close.underOdds,
          closingFairProbability: prediction.over ? fair.over : fair.under,
        ),
      );
    }
    return graded;
  }
}

/// Registers the periodic background collection of HKJC quotes.
class OddsCollectorCoordinator {
  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Captures quotes roughly every half hour, which is frequent enough to see
  /// line movement yet far below any reasonable public-access rate limit.
  static Future<void> schedule({
    Duration frequency = const Duration(minutes: 30),
  }) async {
    if (!_supported) {
      return;
    }
    await Workmanager().registerPeriodicTask(
      oddsCollectorUniqueName,
      oddsCollectorTask,
      frequency: Duration(minutes: max(frequency.inMinutes, 15)),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<OddsCollectionReport> collectNow() =>
      OddsCollectorService().collect();
}
