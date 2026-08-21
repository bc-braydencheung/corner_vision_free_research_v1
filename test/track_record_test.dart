import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/services/track_record.dart';
import 'package:flutter_test/flutter_test.dart';

final _kickOff = DateTime.utc(2026, 8, 15, 19);

void main() {
  test('an entry carries the quote that was on screen at capture time', () {
    final report = buildTrackRecord(
      forecasts: [_forecast(probability: 0.62, actual: 12)],
      stored: [
        // Captured after the forecast: using it would be an after-the-fact
        // price, so the earlier quote has to be the taken one.
        _quote(minutesBeforeKickOff: 30, overOdds: 2.4, underOdds: 1.6),
        _quote(minutesBeforeKickOff: 240, overOdds: 1.95, underOdds: 1.85),
        _quote(minutesBeforeKickOff: 600, overOdds: 1.80, underOdds: 2.00),
      ],
      asOf: _kickOff.add(const Duration(hours: 3)),
    );

    final entry = report.entries.single;
    expect(entry.takenOdds, 1.95);
    expect(entry.takenAt, _kickOff.subtract(const Duration(minutes: 240)));
    expect(entry.direction, 'high');
    expect(entry.closingOdds, 2.4);
    // 1.95 taken against a 2.40 close is a worse price, so negative CLV.
    expect(entry.closingLineValue, closeTo(1.95 / 2.4 - 1, 1e-9));
    expect(entry.won, isTrue);
    expect(entry.profitUnits, closeTo(0.95, 1e-9));
  });

  test('the model side follows the expected value of each side', () {
    final report = buildTrackRecord(
      forecasts: [_forecast(probability: 0.30, actual: 6)],
      stored: [_quote(minutesBeforeKickOff: 240)],
      asOf: _kickOff.add(const Duration(hours: 3)),
    );

    final entry = report.entries.single;
    expect(entry.direction, 'low');
    expect(entry.modelProbability, closeTo(0.70, 1e-9));
    expect(entry.won, isTrue);
  });

  test('a forecast with no stored quote is refused, not guessed', () {
    final report = buildTrackRecord(
      forecasts: [_forecast(probability: 0.62, actual: 12)],
      stored: [_quote(minutesBeforeKickOff: 30)],
      asOf: _kickOff.add(const Duration(hours: 3)),
    );

    expect(report.entries, isEmpty);
    expect(report.skipped[TrackRecordSkip.noTakenQuote], 1);
    expect(report.recommended, 0);
    expect(report.verdict, contains('未出過推介'));
  });

  test('a fixture that has not kicked off has no closing quote', () {
    final report = buildTrackRecord(
      forecasts: [_forecast(probability: 0.62)],
      stored: [_quote(minutesBeforeKickOff: 240)],
      asOf: _kickOff.subtract(const Duration(hours: 1)),
    );

    final entry = report.entries.single;
    expect(entry.closingOdds, isNull);
    expect(entry.closingLineValue, isNull);
    expect(entry.settled, isFalse);
    expect(report.verdict, contains('尚未有已結算賽果'));
  });

  test('only sides that cleared the threshold count as recommendations', () {
    // 0.51 at 1.95 is a negative expected value, so the fixture is only
    // watched: it must not enter the hit rate.
    final report = buildTrackRecord(
      forecasts: [_forecast(probability: 0.51, actual: 12)],
      stored: [_quote(minutesBeforeKickOff: 240)],
      asOf: _kickOff.add(const Duration(hours: 3)),
    );

    expect(report.entries.single.recommended, isFalse);
    expect(report.recommended, 0);
    expect(report.settled, 0);
    expect(report.hitRate, 0);
  });

  test('the summary keeps prediction quality apart from price quality', () {
    final forecasts = <ShadowForecast>[];
    final stored = <FootballOddsSnapshot>[];
    for (var index = 0; index < 30; index++) {
      final kickOff = _kickOff.add(Duration(days: index));
      // Every fixture goes over, and the model always leans over, so hit rate
      // and Brier are decided while the closing price stays worse than taken.
      forecasts.add(
        _forecast(
          probability: 0.70,
          actual: 12,
          matchId: 'm$index',
          kickOff: kickOff,
        ),
      );
      stored.add(
        _quote(
          matchId: 'm$index',
          kickOff: kickOff,
          minutesBeforeKickOff: 240,
          overOdds: 2.0,
          underOdds: 1.8,
        ),
      );
      stored.add(
        _quote(
          matchId: 'm$index',
          kickOff: kickOff,
          minutesBeforeKickOff: 20,
          overOdds: 1.7,
          underOdds: 2.1,
        ),
      );
    }

    final report = buildTrackRecord(
      forecasts: forecasts,
      stored: stored,
      asOf: _kickOff.add(const Duration(days: 40)),
    );

    expect(report.recommended, 30);
    expect(report.settled, 30);
    expect(report.hitRate, 1);
    expect(report.brierSamples, 30);
    expect(report.brier, lessThan(report.marketBrier));
    expect(report.beatsMarketBrier, isTrue);
    expect(report.clvSamples, 30);
    expect(report.meanClosingLineValue, closeTo(2.0 / 1.7 - 1, 1e-9));
    expect(report.beatsClosing, isTrue);
    expect(report.netUnits, closeTo(30, 1e-9));
    // Nothing lost, so the unit curve never fell.
    expect(report.maximumDrawdownUnits, 0);
  });

  test('a recorded pick is graded on its own line and price', () {
    final report = buildTrackRecord(
      forecasts: [
        _forecast(
          probability: null,
          actual: 12,
          pick: const ShadowPick(
            line: 10.5,
            direction: 'high',
            odds: 2.1,
            modelProbability: 0.56,
            marketProbability: 0.5,
            edge: 0.176,
            recommended: true,
          ),
        ),
      ],
      // Only a 9.5 series exists, and it starts after the forecast: neither
      // may stop the recorded 10.5 pick from entering the ledger.
      stored: [_quote(minutesBeforeKickOff: 30)],
      asOf: _kickOff.add(const Duration(hours: 3)),
    );

    final entry = report.entries.single;
    expect(entry.line, 10.5);
    expect(entry.takenOdds, 2.1);
    expect(entry.modelProbability, 0.56);
    expect(entry.won, isTrue);
    expect(entry.closingOdds, isNull);
    expect(report.recommended, 1);
    expect(report.hitRate, 1);
  });

  test('a recorded observation never counts as a recommendation', () {
    final report = buildTrackRecord(
      forecasts: [
        _forecast(
          probability: null,
          actual: 12,
          pick: const ShadowPick(
            line: 10.5,
            direction: 'high',
            odds: 2.1,
            modelProbability: 0.47,
            marketProbability: 0.5,
            edge: -0.013,
            recommended: false,
          ),
        ),
      ],
      stored: const [],
      asOf: _kickOff.add(const Duration(hours: 3)),
    );

    expect(report.entries.single.recommended, isFalse);
    expect(report.recommended, 0);
  });

  test('the closing price of the pick line is used when it exists', () {
    final report = buildTrackRecord(
      forecasts: [
        _forecast(
          probability: null,
          actual: 12,
          pick: const ShadowPick(
            line: 9.5,
            direction: 'high',
            odds: 2.0,
            modelProbability: 0.6,
            marketProbability: 0.5,
            edge: 0.2,
            recommended: true,
          ),
        ),
      ],
      stored: [_quote(minutesBeforeKickOff: 20, overOdds: 1.7, underOdds: 2.1)],
      asOf: _kickOff.add(const Duration(hours: 3)),
    );

    final entry = report.entries.single;
    expect(entry.closingOdds, 1.7);
    expect(entry.closingLineValue, closeTo(2.0 / 1.7 - 1, 1e-9));
  });

  test('a forecast with neither a pick nor a 9.5 probability is refused', () {
    final report = buildTrackRecord(
      forecasts: [_forecast(probability: null)],
      stored: [_quote(minutesBeforeKickOff: 240)],
      asOf: _kickOff.add(const Duration(hours: 3)),
    );

    expect(report.entries, isEmpty);
    expect(report.skipped[TrackRecordSkip.noShownSide], 1);
  });

  test('a legacy forecast without stored Chinese names is still shown in '
      'Chinese', () {
    final report = buildTrackRecord(
      forecasts: [_forecast(probability: 0.62, actual: 12, english: true)],
      stored: [_quote(minutesBeforeKickOff: 240)],
      asOf: _kickOff.add(const Duration(hours: 3)),
    );

    final entry = report.entries.single;
    expect(entry.homeTeam, '阿仙奴');
    expect(entry.awayTeam, '車路士');
  });

  test('the drawdown is measured in fixture order', () {
    final forecasts = <ShadowForecast>[];
    final stored = <FootballOddsSnapshot>[];
    // Three losses then two wins: the trough is three units deep, which is
    // only visible when the entries are replayed oldest first.
    const results = [6, 6, 6, 12, 12];
    for (var index = 0; index < results.length; index++) {
      final kickOff = _kickOff.add(Duration(days: index));
      forecasts.add(
        _forecast(
          probability: 0.70,
          actual: results[index],
          matchId: 'm$index',
          kickOff: kickOff,
        ),
      );
      stored.add(
        _quote(
          matchId: 'm$index',
          kickOff: kickOff,
          minutesBeforeKickOff: 240,
          overOdds: 2.0,
          underOdds: 1.8,
        ),
      );
    }

    final report = buildTrackRecord(
      forecasts: forecasts,
      stored: stored,
      asOf: _kickOff.add(const Duration(days: 40)),
    );

    expect(report.maximumDrawdownUnits, closeTo(3, 1e-9));
    expect(report.netUnits, closeTo(-1, 1e-9));
    expect(
      report.entries.first.matchDate.isAfter(report.entries.last.matchDate),
      isTrue,
    );
  });
}

ShadowForecast _forecast({
  required double? probability,
  int? actual,
  String matchId = 'match-1',
  DateTime? kickOff,
  ShadowPick? pick,
  bool english = false,
}) {
  final start = kickOff ?? _kickOff;
  return ShadowForecast(
    id: '$matchId-forecast',
    matchId: matchId,
    leagueCode: 'E0',
    leagueName: '英超',
    homeTeam: english ? 'Arsenal' : '阿仙奴',
    awayTeam: english ? 'Chelsea' : '車路士',
    matchDate: start,
    capturedAt: start.subtract(const Duration(minutes: 200)),
    modelVersion: 'test',
    expectedTotalCorners: 10,
    over9_5Probability: probability,
    pick: pick,
    referenceMae: 2.7,
    referenceBrier: 0.25,
    actualTotalCorners: actual,
    settledAt: actual == null ? null : start.add(const Duration(hours: 2)),
  );
}

FootballOddsSnapshot _quote({
  required int minutesBeforeKickOff,
  String matchId = 'match-1',
  DateTime? kickOff,
  double overOdds = 1.95,
  double underOdds = 1.85,
}) {
  final start = kickOff ?? _kickOff;
  return FootballOddsSnapshot(
    matchId: matchId,
    capturedAt: start.subtract(Duration(minutes: minutesBeforeKickOff)),
    source: 'HKJC',
    line: 9.5,
    overOdds: overOdds,
    underOdds: underOdds,
  );
}
