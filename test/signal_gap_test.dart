import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:flutter_test/flutter_test.dart';

HkjcFootballFixture _fixture(List<HkjcMarketLine> lines) => HkjcFootballFixture(
  matchId: 'm1',
  frontEndId: 'FB1',
  leagueCode: 'E0',
  tournamentCode: 'EPL',
  tournamentName: '英格蘭超級聯賽',
  kickOffTime: DateTime.utc(2026, 8, 22),
  status: 'PREEVENT',
  homeTeam: '主',
  awayTeam: '客',
  homeTeamEnglish: 'Home',
  awayTeamEnglish: 'Away',
  cornerLines: lines,
);

const _agreeing = [
  HkjcMarketLine(
    lineId: '1',
    condition: '9.5',
    line: 9.5,
    main: true,
    status: 'AVAILABLE',
    highOdds: 1.9,
    lowOdds: 1.9,
  ),
];

const _mispriced = [
  HkjcMarketLine(
    lineId: '1',
    condition: '8.5',
    line: 8.5,
    main: true,
    status: 'AVAILABLE',
    highOdds: 1.5,
    lowOdds: 2.5,
  ),
  HkjcMarketLine(
    lineId: '2',
    condition: '9.5',
    line: 9.5,
    main: false,
    status: 'AVAILABLE',
    highOdds: 3.2,
    lowOdds: 1.35,
  ),
];

void main() {
  const model = HkjcCornerModel();

  test('a declined fixture reports how far it is from a signal', () {
    final declined = model.assess(_fixture(_agreeing))!;
    final gap = declined.signalGap!;
    final watched = declined.observation!;

    expect(declined.recommendation, isNull);
    expect(gap.direction, watched.direction);
    expect(gap.condition, '9.5');
    expect(gap.odds, watched.odds);
    expect(gap.edge, watched.edge);
    expect(gap.requiredEdge, model.minimumEdge);
    expect(gap.modelProbability, closeTo(watched.winProbability, 1e-12));
    expect(gap.probabilityShortfall, greaterThan(0));
    expect(gap.edgeShortfall, closeTo(model.minimumEdge - gap.edge, 1e-12));
  });

  test('the required probability is exactly the threshold trigger point', () {
    final declined = model.assess(_fixture(_agreeing))!;
    final gap = declined.signalGap!;
    final line = declined.lines.single;
    final push = line.modelPushProbability;

    // Expected value of a side is `p * odds - 1 + push * (1 - odds / 2)`, so
    // feeding the required probability back in must land on the threshold.
    final expectedValueAtRequired =
        gap.requiredProbability * gap.odds - 1 + push * (1 - gap.odds / 2);
    expect(expectedValueAtRequired, closeTo(model.minimumEdge, 1e-9));
  });

  test('no gap is reported once a side clears the threshold', () {
    final recommended = model.assess(_fixture(_mispriced))!;

    expect(recommended.recommendation, isNotNull);
    expect(recommended.signalGap, isNull);
  });

  test('a tighter threshold shrinks the gap it has to close', () {
    final strict = const HkjcCornerModel(
      minimumEdge: 0.08,
    ).assess(_fixture(_agreeing))!.signalGap!;
    final loose = const HkjcCornerModel(
      minimumEdge: 0.01,
    ).assess(_fixture(_agreeing))!.signalGap!;

    expect(
      strict.probabilityShortfall,
      greaterThan(loose.probabilityShortfall),
    );
    expect(loose.requiredProbability, lessThan(strict.requiredProbability));
  });
}
