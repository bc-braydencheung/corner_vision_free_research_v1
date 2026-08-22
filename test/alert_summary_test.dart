import 'dart:ui' as ui;

import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/racing_mobile.dart';
import 'package:edgewise/services/alert_share_image.dart';
import 'package:edgewise/services/corner_alerts.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:edgewise/services/racing_alerts.dart';
import 'package:edgewise/services/research_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

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

HkjcFootballFixture _fixture({
  required String matchId,
  required String leagueCode,
  required DateTime kickOff,
  required List<HkjcMarketLine> lines,
  String home = '主隊',
  String away = '客隊',
  String status = 'PREEVENT',
}) => HkjcFootballFixture(
  matchId: matchId,
  frontEndId: matchId,
  leagueCode: leagueCode,
  tournamentCode: leagueCode,
  tournamentName: leagueCode,
  kickOffTime: kickOff,
  status: status,
  homeTeam: home,
  awayTeam: away,
  homeTeamEnglish: 'Home',
  awayTeamEnglish: 'Away',
  cornerLines: lines,
);

RacingRunner _runner({
  required String horseId,
  required int number,
  required double winProbability,
  String recommendation = 'model-view',
  String confidence = 'medium',
  double confidenceScore = 0.6,
}) => RacingRunner(
  horseId: horseId,
  horseName: 'Horse $number',
  horseNameChinese: '馬$number',
  number: number,
  draw: number,
  jockey: '騎師',
  trainer: '練馬師',
  winProbability: winProbability,
  placeProbability: winProbability * 2,
  fairWinOdds: 1 / winProbability,
  fairPlaceOdds: 0,
  confidence: confidence,
  confidenceScore: confidenceScore,
  recommendation: recommendation,
  factors: const [],
);

RacingRace _race({
  required String raceId,
  required DateTime startTime,
  required List<RacingRunner> runners,
  int raceNumber = 3,
}) => RacingRace(
  raceId: raceId,
  date: startTime,
  startTime: startTime,
  venue: '沙田',
  raceNumber: raceNumber,
  raceName: '研究盃',
  distanceMetres: 1200,
  surface: '草地',
  course: 'A',
  going: '好地',
  raceClass: '第四班',
  runners: runners,
);

RacingSummary _racing({
  required List<RacingRace> races,
  bool tradeEnabled = true,
  bool available = true,
}) => RacingSummary(
  available: available,
  status: 'ok',
  sourceNotice: '免費公開資料',
  races: races,
  model: RacingModelSummary(tradeEnabled: tradeEnabled),
);

void main() {
  final now = DateTime.utc(2026, 8, 20, 12);

  group('corner alerts', () {
    test('no snapshot yields nothing', () {
      expect(
        buildCornerAlerts(snapshot: null, leagueNames: const {}, asOf: now),
        isEmpty,
      );
    });

    test('a fixture the model declines is never surfaced', () {
      final alerts = buildCornerAlerts(
        snapshot: HkjcFootballSnapshot(
          capturedAt: now,
          fixtures: [
            _fixture(
              matchId: 'm1',
              leagueCode: 'E0',
              kickOff: now.add(const Duration(hours: 3)),
              lines: _agreeing,
            ),
          ],
        ),
        leagueNames: const {'E0': '英超'},
        asOf: now,
      );

      expect(alerts, isEmpty);
    });

    test('a recommended fixture is surfaced with its league and line', () {
      final fixture = _fixture(
        matchId: 'm1',
        leagueCode: 'SP1',
        kickOff: now.add(const Duration(hours: 3)),
        lines: _mispriced,
      );
      final alerts = buildCornerAlerts(
        snapshot: HkjcFootballSnapshot(capturedAt: now, fixtures: [fixture]),
        leagueNames: const {'SP1': '西甲'},
        asOf: now,
      );
      final expected = const HkjcCornerModel().assess(fixture)!.recommendation!;

      expect(alerts, hasLength(1));
      expect(alerts.single.leagueCode, 'SP1');
      expect(alerts.single.context, '西甲');
      expect(alerts.single.subject, '主隊 對 客隊');
      expect(
        alerts.single.market,
        '角球 ${expected.line.line.condition} '
        '${expected.directionLabel}',
      );
      expect(alerts.single.odds, expected.odds);
      expect(alerts.single.edge, expected.edge);
      expect(alerts.single.confidence, expected.confidence);
      expect(alerts.single.startTime, fixture.kickOffTime);
    });

    test('kicked-off fixtures are dropped and the rest sort by edge', () {
      final alerts = buildCornerAlerts(
        snapshot: HkjcFootballSnapshot(
          capturedAt: now,
          fixtures: [
            _fixture(
              matchId: 'started',
              leagueCode: 'E0',
              kickOff: now.subtract(const Duration(minutes: 1)),
              lines: _mispriced,
            ),
            _fixture(
              matchId: 'later',
              leagueCode: 'E0',
              kickOff: now.add(const Duration(hours: 5)),
              lines: _mispriced,
              home: '甲',
            ),
            _fixture(
              matchId: 'ligue',
              leagueCode: 'F1',
              kickOff: now.add(const Duration(hours: 2)),
              lines: _mispriced,
              home: '乙',
            ),
          ],
        ),
        leagueNames: const {'E0': '英超', 'F1': '法甲'},
        asOf: now,
      );

      expect(alerts.map((alert) => alert.fixture.matchId), ['later', 'ligue']);
      expect(alerts.first.edge, greaterThanOrEqualTo(alerts.last.edge));
    });

    test('an in-play fixture is dropped even before its kick-off time', () {
      final playing = _fixture(
        matchId: 'playing',
        leagueCode: 'E0',
        kickOff: now.add(const Duration(minutes: 30)),
        lines: _mispriced,
        status: 'FIRSTHALF',
      );

      expect(playing.startedBy(now), isTrue);
      expect(
        buildCornerAlerts(
          snapshot: HkjcFootballSnapshot(capturedAt: now, fixtures: [playing]),
          leagueNames: const {'E0': '英超'},
          asOf: now,
        ),
        isEmpty,
      );
    });

    test(
      'only fixtures still to kick off are offered for pre-match reading',
      () {
        final snapshot = HkjcFootballSnapshot(
          capturedAt: now,
          fixtures: [
            _fixture(
              matchId: 'ended',
              leagueCode: 'E0',
              kickOff: now.subtract(const Duration(hours: 3)),
              lines: _mispriced,
              status: 'RESULT',
            ),
            _fixture(
              matchId: 'playing',
              leagueCode: 'E0',
              kickOff: now.add(const Duration(minutes: 10)),
              lines: _mispriced,
              status: 'SECONDHALF',
            ),
            _fixture(
              matchId: 'open',
              leagueCode: 'E0',
              kickOff: now.add(const Duration(hours: 4)),
              lines: _mispriced,
            ),
          ],
        );

        expect(snapshot.forLeague('E0'), hasLength(3));
        expect(
          snapshot
              .upcomingForLeague('E0', asOf: now)
              .map((fixture) => fixture.matchId),
          ['open'],
        );
      },
    );
  });

  group('racing alerts', () {
    // Four quotes so the vig-free pool leaves the favourite well under the
    // model's own probability; the pool total is 0.95, so A sits at 0.3509.
    const pool = {'A': 3.0, 'B': 4.0, 'C': 5.0, 'D': 6.0};

    RacingOddsSnapshot snapshot({
      Map<String, double> odds = pool,
      String raceId = 'R1',
      bool isFinal = false,
      Duration age = const Duration(minutes: 5),
    }) => RacingOddsSnapshot(
      raceId: raceId,
      capturedAt: now.subtract(age),
      source: 'hkjc-win-pool',
      oddsByHorse: odds,
      isFinal: isFinal,
    );

    final race = _race(
      raceId: 'R1',
      startTime: now.add(const Duration(hours: 2)),
      runners: [
        _runner(horseId: 'A', number: 1, winProbability: 0.45),
        _runner(horseId: 'B', number: 2, winProbability: 0.2),
      ],
    );

    test('a closed trade gate produces nothing', () {
      expect(
        buildRacingAlerts(
          racing: _racing(races: [race], tradeEnabled: false),
          snapshots: [snapshot()],
          asOf: now,
        ),
        isEmpty,
      );
    });

    test('a race without a stored quote produces nothing', () {
      expect(
        buildRacingAlerts(
          racing: _racing(races: [race]),
          snapshots: const [],
          asOf: now,
        ),
        isEmpty,
      );
    });

    test('a final (post-race) quote is never used pre-race', () {
      expect(
        buildRacingAlerts(
          racing: _racing(races: [race]),
          snapshots: [snapshot(isFinal: true)],
          asOf: now,
        ),
        isEmpty,
      );
    });

    test('a runner priced above the pool is surfaced with its edge', () {
      final alerts = buildRacingAlerts(
        racing: _racing(races: [race]),
        snapshots: [snapshot()],
        asOf: now,
      );

      expect(alerts, hasLength(1));
      final alert = alerts.single;
      expect(alert.runner.horseId, 'A');
      expect(alert.odds, 3.0);
      expect(alert.edge, closeTo(0.45 * 3 - 1, 1e-12));
      expect(alert.marketProbability, closeTo((1 / 3) / 0.95, 1e-12));
      expect(alert.context, '沙田 第3場');
      expect(alert.subject, '1 馬1');
      expect(alert.market, '獨贏');
      expect(alert.confidenceLabel, '中');
    });

    test('an edge under the threshold and a declined runner are skipped', () {
      final alerts = buildRacingAlerts(
        racing: _racing(
          races: [
            _race(
              raceId: 'R1',
              startTime: now.add(const Duration(hours: 2)),
              runners: [
                // Above the flat pool's 0.3333 but only a 0.02 edge.
                _runner(horseId: 'A', number: 1, winProbability: 0.34),
                _runner(
                  horseId: 'B',
                  number: 2,
                  winProbability: 0.9,
                  recommendation: 'no-prediction',
                ),
              ],
            ),
          ],
        ),
        snapshots: [
          snapshot(odds: const {'A': 3.0, 'B': 3.0, 'C': 3.0}),
        ],
        asOf: now,
      );

      expect(alerts, isEmpty);
    });

    test('a race already off is dropped', () {
      expect(
        buildRacingAlerts(
          racing: _racing(
            races: [
              _race(
                raceId: 'R1',
                startTime: now.subtract(const Duration(minutes: 1)),
                runners: [
                  _runner(horseId: 'A', number: 1, winProbability: 0.45),
                ],
              ),
            ],
          ),
          snapshots: [snapshot()],
          asOf: now,
        ),
        isEmpty,
      );
    });

    test('the newest pre-race quote wins', () {
      final alerts = buildRacingAlerts(
        racing: _racing(races: [race]),
        snapshots: [
          snapshot(
            odds: const {'A': 2.0, 'B': 4.0, 'C': 5.0, 'D': 6.0},
            age: const Duration(hours: 4),
          ),
          snapshot(),
        ],
        asOf: now,
      );

      expect(alerts.single.odds, 3.0);
    });
  });

  group('sharing', () {
    final alert = buildRacingAlerts(
      racing: _racing(
        races: [
          _race(
            raceId: 'R1',
            startTime: now.add(const Duration(hours: 2)),
            runners: [_runner(horseId: 'A', number: 1, winProbability: 0.45)],
          ),
        ],
      ),
      snapshots: [
        RacingOddsSnapshot(
          raceId: 'R1',
          capturedAt: now,
          source: 'hkjc-win-pool',
          oddsByHorse: const {'A': 3.0, 'B': 4.0, 'C': 5.0, 'D': 6.0},
        ),
      ],
      asOf: now,
    ).single;

    test('the text names every pick and stays research-only', () {
      final text = buildAlertShareText(alerts: [alert], asOf: now);

      expect(text, contains('睿測'));
      expect(text, contains('沙田 第3場'));
      expect(text, contains('馬1'));
      expect(text, contains('獨贏 @3.00'));
      expect(text, contains('僅供研究，非投注建議。'));
    });

    test('no picks is stated outright rather than left blank', () {
      final text = buildAlertShareText(alerts: const [], asOf: now);

      expect(text, contains('今日無推介'));
      expect(text, isNot(contains('獨贏')));
    });

    testWidgets('the shared card renders as a PNG both ways', (tester) async {
      // PNG encoding is real asynchronous work, so it cannot run on the fake
      // clock the widget tester installs.
      await tester.runAsync(() async {
        final withPicks = await renderAlertShareImage(
          alerts: [alert],
          asOf: now,
        );
        final empty = await renderAlertShareImage(alerts: const [], asOf: now);

        for (final image in [withPicks, empty]) {
          expect(image.width, 3240);
          expect(image.height, greaterThan(1200));
          final decoded = await ui.instantiateImageCodec(image.bytes);
          final frame = await decoded.getNextFrame();
          expect(frame.image.width, image.width);
          expect(frame.image.height, image.height);
        }
        expect(withPicks.bytes.length, greaterThan(1000));
      });
    });
  });
}
