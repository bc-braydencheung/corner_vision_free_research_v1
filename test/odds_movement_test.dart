import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/services/odds_movement.dart';
import 'package:flutter_test/flutter_test.dart';

final _kickOff = DateTime.utc(2026, 9, 10, 19, 30);

FootballOddsSnapshot _corner({
  required Duration before,
  required double over,
  required double under,
  double line = 9.5,
  String matchId = 'FB1',
  bool inPlay = false,
}) => FootballOddsSnapshot(
  matchId: matchId,
  capturedAt: _kickOff.subtract(before),
  source: 'hkjc-chl',
  line: line,
  overOdds: over,
  underOdds: under,
  inPlay: inPlay,
);

Map<String, FixtureOddsMovement> _movements(
  List<FootballOddsSnapshot> snapshots, {
  Map<String, DateTime>? kickOffs,
}) => cornerMovements(
  snapshots: snapshots,
  kickOffs: kickOffs ?? {'FB1': _kickOff},
);

void main() {
  test('each horizon reads the last quote standing before it', () {
    final movement = _movements([
      _corner(before: const Duration(hours: 40), over: 1.90, under: 1.90),
      _corner(before: const Duration(hours: 25), over: 1.85, under: 1.95),
      _corner(before: const Duration(hours: 8), over: 1.80, under: 2.00),
      _corner(before: const Duration(hours: 2), over: 1.75, under: 2.05),
      _corner(before: const Duration(minutes: 20), over: 1.70, under: 2.10),
    ])['FB1']!.primary!;
    expect(
      movement.points.map((point) => point.horizon).toList(),
      cornerMovementHorizons,
    );
    // The 24h reading is the 25h-old quote, not the 8h one that came later.
    expect(
      movement.at(const Duration(hours: 24))!.capturedAt,
      _kickOff.subtract(const Duration(hours: 25)),
    );
    expect(
      movement.at(Duration.zero)!.capturedAt,
      _kickOff.subtract(const Duration(minutes: 20)),
    );
  });

  test('a market drifting to the over side reports one direction', () {
    final movement = _movements([
      _corner(before: const Duration(hours: 30), over: 2.10, under: 1.75),
      _corner(before: const Duration(hours: 7), over: 1.95, under: 1.90),
      _corner(before: const Duration(hours: 2), over: 1.85, under: 2.00),
      _corner(before: const Duration(minutes: 15), over: 1.75, under: 2.10),
    ])['FB1']!.primary!;
    expect(movement.hasMovement, isTrue);
    expect(movement.direction, 'over');
    expect(movement.total, greaterThan(0.05));
    expect(movement.segments.every((move) => move > 0), isTrue);
    expect(movement.steaming, isTrue);
  });

  test('a market that chopped both ways is not called steam', () {
    final movement = _movements([
      _corner(before: const Duration(hours: 30), over: 1.80, under: 2.00),
      _corner(before: const Duration(hours: 7), over: 2.05, under: 1.80),
      _corner(before: const Duration(hours: 2), over: 1.80, under: 2.00),
      _corner(before: const Duration(minutes: 15), over: 2.05, under: 1.80),
    ])['FB1']!.primary!;
    expect(movement.steaming, isFalse);
  });

  test('a single stored quote carries no movement', () {
    final movement = _movements([
      _corner(before: const Duration(hours: 3), over: 1.85, under: 1.95),
    ])['FB1']!;
    expect(movement.primary!.points, hasLength(1));
    expect(movement.hasMovement, isFalse);
    expect(movement.primary!.total, isNull);
  });

  test('one quote covering several horizons is not read as a zero move', () {
    // The market never requoted between 24h and kick-off, so the series holds
    // that single reading rather than three copies of it.
    final movement = _movements([
      _corner(before: const Duration(hours: 26), over: 1.85, under: 1.95),
    ])['FB1']!.primary!;
    expect(movement.points, hasLength(1));
    expect(movement.hasMovement, isFalse);
  });

  test('in-play and post-kick-off quotes are left out', () {
    final movement = _movements([
      _corner(before: const Duration(hours: 26), over: 1.85, under: 1.95),
      _corner(
        before: const Duration(minutes: -30),
        over: 1.40,
        under: 3.00,
        inPlay: true,
      ),
    ])['FB1']!.primary!;
    expect(movement.points, hasLength(1));
    expect(movement.hasMovement, isFalse);
  });

  test('an unusable price pair is dropped instead of clamped', () {
    final movement = _movements([
      _corner(before: const Duration(hours: 26), over: 0.5, under: 0.4),
      _corner(before: const Duration(hours: 2), over: 1.85, under: 1.95),
    ])['FB1']!.primary!;
    expect(movement.points, hasLength(1));
    expect(movement.at(const Duration(hours: 24)), isNull);
  });

  test('the deepest line is the one reported', () {
    final movement = _movements([
      _corner(before: const Duration(hours: 26), over: 1.85, under: 1.95),
      _corner(
        before: const Duration(hours: 26),
        over: 1.60,
        under: 2.30,
        line: 10.5,
      ),
      _corner(
        before: const Duration(hours: 2),
        over: 1.55,
        under: 2.40,
        line: 10.5,
      ),
    ])['FB1']!;
    expect(movement.primary!.line, 10.5);
    expect(movement.lines.map((line) => line.line).toList(), [9.5, 10.5]);
  });

  test('a fixture without a known kick-off is skipped', () {
    final movements = _movements([
      _corner(before: const Duration(hours: 2), over: 1.85, under: 1.95),
    ], kickOffs: const {});
    expect(movements, isEmpty);
  });

  test('coverage states how many fixtures can be measured at all', () {
    final movements = _movements(
      [
        _corner(before: const Duration(hours: 26), over: 2.05, under: 1.80),
        _corner(before: const Duration(hours: 2), over: 1.80, under: 2.00),
        _corner(
          before: const Duration(hours: 2),
          over: 1.85,
          under: 1.95,
          matchId: 'FB2',
        ),
      ],
      kickOffs: {'FB1': _kickOff, 'FB2': _kickOff},
    );
    final coverage = summariseMovementCoverage(movements);
    expect(coverage.fixtures, 2);
    expect(coverage.withMovement, 1);
    expect(coverage.steaming, 0);
    expect(coverage.meanAbsoluteMove, greaterThan(0.05));
    expect(coverage.summary, contains('1／2'));
  });

  test('an empty history reports no coverage rather than zero movement', () {
    final coverage = summariseMovementCoverage(const {});
    expect(coverage.fixtures, 0);
    expect(coverage.summary, '尚未儲存任何盤口快照');
  });
}
