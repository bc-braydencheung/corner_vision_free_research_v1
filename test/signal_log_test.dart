import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/signal_change.dart';
import 'package:edgewise/services/signal_log.dart';
import 'package:flutter_test/flutter_test.dart';

List<HkjcMarketLine> _lines({double high = 1.9, double low = 1.9}) => [
  HkjcMarketLine(
    lineId: '2',
    condition: '9.5',
    line: 9.5,
    main: true,
    status: 'AVAILABLE',
    highOdds: high,
    lowOdds: low,
  ),
];

HkjcFootballFixture _fixture({
  required String matchId,
  required DateTime kickOff,
  List<HkjcMarketLine>? lines,
  String leagueCode = 'E0',
}) => HkjcFootballFixture(
  matchId: matchId,
  frontEndId: matchId,
  leagueCode: leagueCode,
  tournamentCode: leagueCode,
  tournamentName: leagueCode,
  kickOffTime: kickOff,
  status: 'PREEVENT',
  homeTeam: '主隊',
  awayTeam: '客隊',
  homeTeamEnglish: 'Arsenal',
  awayTeamEnglish: 'Chelsea',
  cornerLines: lines ?? _lines(),
);

HkjcFootballSnapshot _snapshot(
  DateTime capturedAt,
  List<HkjcFootballFixture> fixtures,
) => HkjcFootballSnapshot(capturedAt: capturedAt, fixtures: fixtures);

List<SignalChange> _log({
  required List<SignalChange> existing,
  required DateTime asOf,
  required DateTime kickOff,
  double high = 1.9,
  double low = 1.9,
  bool suspended = false,
  double minimumEdge = 0.02,
  String matchId = 'hkjc-1',
}) => updateSignalLog(
  existing: existing,
  snapshot: _snapshot(asOf, [
    _fixture(
      matchId: matchId,
      kickOff: kickOff,
      lines: _lines(high: high, low: low),
    ),
  ]),
  leagueNames: const {'E0': '英超'},
  asOf: asOf,
  suspended: suspended,
  minimumEdge: minimumEdge,
);

void main() {
  final now = DateTime.utc(2026, 8, 20, 12);
  final kickOff = now.add(const Duration(hours: 6));

  test('writes a reading of the side the card showed', () {
    final log = _log(existing: const [], asOf: now, kickOff: kickOff);
    expect(log, hasLength(1));
    final reading = log.single;
    expect(reading.matchId, 'hkjc-1');
    expect(reading.leagueName, '英超');
    expect(reading.line, 9.5);
    expect(reading.direction, anyOf('high', 'low'));
    expect(reading.odds, 1.9);
    expect(reading.modelProbability, greaterThan(0));
    expect(reading.modelProbability, lessThan(1));
    expect(reading.marketProbability, closeTo(0.5, 0.001));
    expect(reading.requiredEdge, greaterThan(0));
  });

  test('an unchanged refresh appends nothing', () {
    final first = _log(existing: const [], asOf: now, kickOff: kickOff);
    final second = _log(
      existing: first,
      asOf: now.add(const Duration(minutes: 20)),
      kickOff: kickOff,
    );
    expect(second, hasLength(1));
    expect(second.single.capturedAt, first.single.capturedAt);
  });

  test('a moved price appends a reading and keeps the old one', () {
    final first = _log(
      existing: const [],
      asOf: now,
      kickOff: kickOff,
      high: 2.1,
      low: 2.1,
    );
    final second = _log(
      existing: first,
      asOf: now.add(const Duration(minutes: 20)),
      kickOff: kickOff,
      high: 2.3,
      low: 2.3,
    );
    expect(second, hasLength(2));
    expect(second.first.odds, 2.1);
    expect(second.last.odds, 2.3);
    expect(second.last.capturedAt.isAfter(second.first.capturedAt), isTrue);
  });

  test('a withdrawn recommendation is recorded as a state change', () {
    // The same fixture at the same price, judged against a gate it cannot
    // clear: the reading has to say 觀察 while the earlier one still says 推介.
    final first = _log(
      existing: const [],
      asOf: now,
      kickOff: kickOff,
      high: 2.1,
      low: 2.1,
    );
    expect(first.single.recommended, isTrue);
    final second = _log(
      existing: first,
      asOf: now.add(const Duration(minutes: 30)),
      kickOff: kickOff,
      high: 2.1,
      low: 2.1,
      minimumEdge: 0.9,
    );
    expect(second, hasLength(2));
    expect(second.first.recommended, isTrue);
    expect(second.last.recommended, isFalse);
  });

  test('a started fixture is never read again', () {
    final log = _log(
      existing: const [],
      asOf: now,
      kickOff: now.subtract(const Duration(minutes: 5)),
    );
    expect(log, isEmpty);
  });

  test('readings of other fixtures are never touched', () {
    final first = _log(
      existing: const [],
      asOf: now,
      kickOff: kickOff,
      matchId: 'hkjc-1',
    );
    final second = _log(
      existing: first,
      asOf: now.add(const Duration(minutes: 20)),
      kickOff: kickOff,
      matchId: 'hkjc-2',
    );
    expect(second.map((change) => change.matchId), ['hkjc-1', 'hkjc-2']);
    expect(signalLogByMatch(second).keys, {'hkjc-1', 'hkjc-2'});
  });

  test('fixtures older than the retention window are dropped', () {
    final stale = _log(existing: const [], asOf: now, kickOff: kickOff).single;
    final log = updateSignalLog(
      existing: [stale],
      snapshot: null,
      leagueNames: const {},
      asOf: now.add(signalLogRetention).add(const Duration(days: 1)),
    );
    expect(log, isEmpty);
  });

  test('a suspended audit is recorded as an observation', () {
    final log = _log(
      existing: const [],
      asOf: now,
      kickOff: kickOff,
      high: 2.1,
      low: 2.1,
      suspended: true,
    );
    expect(log.single.recommended, isFalse);
  });

  test('a reading survives a round trip through json', () {
    final reading = _log(
      existing: const [],
      asOf: now,
      kickOff: kickOff,
    ).single;
    final restored = SignalChange.fromJson(reading.toJson());
    expect(restored.matchId, reading.matchId);
    expect(restored.capturedAt, reading.capturedAt);
    expect(restored.odds, reading.odds);
    expect(restored.modelProbability, reading.modelProbability);
    expect(restored.edge, reading.edge);
    expect(restored.recommended, reading.recommended);
    expect(restored.directionLabel, reading.directionLabel);
  });

  test('per fixture readings are capped but keep the first one', () {
    var log = _log(existing: const [], asOf: now, kickOff: kickOff);
    final first = log.single;
    for (var index = 1; index <= signalLogPerMatchLimit + 5; index++) {
      log = _log(
        existing: log,
        asOf: now.add(Duration(minutes: index)),
        kickOff: kickOff,
        high: 1.9 + index * 0.05,
        low: 1.9,
      );
    }
    expect(log, hasLength(signalLogPerMatchLimit));
    expect(log.first.capturedAt, first.capturedAt);
  });
}
