import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/pick_status.dart';
import 'package:edgewise/services/corner_alerts.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:edgewise/services/racing_alerts.dart';
import 'package:edgewise/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

const _line = HkjcCornerLineAssessment(
  line: HkjcMarketLine(
    lineId: '1',
    condition: '9.5',
    line: 9.5,
    main: true,
    status: 'AVAILABLE',
    highOdds: 2.0,
    lowOdds: 1.8,
  ),
  marketHighProbability: 0.47,
  marketLowProbability: 0.53,
  overround: 0.05,
  modelHighProbability: 0.58,
  modelPushProbability: 0,
  modelHighEdge: 0.16,
  modelLowEdge: -0.24,
  uncalibratedHighProbability: 0.57,
  calibratedHighProbability: 0.58,
);

const _pick = HkjcCornerRecommendation(
  line: _line,
  direction: 'high',
  odds: 2.0,
  edge: 0.16,
  winProbability: 0.58,
  confidence: 0.5,
);

HkjcCornerAssessment _assessment({
  HkjcCornerRecommendation? recommendation,
  HkjcCornerRecommendation? observation,
  bool drifting = false,
  bool suspended = false,
}) {
  return HkjcCornerAssessment(
    expectedCorners: 10,
    lines: const [_line],
    bestLine: _line,
    bestDirection: 'high',
    bestEdge: 0.16,
    lineDispersion: 0.1,
    averageOverround: 0.05,
    recommendation: recommendation,
    observation: observation,
    drifting: drifting,
    suspended: suspended,
  );
}

void main() {
  group('pick status', () {
    test('says what each level claims, and only verified counts as proven', () {
      expect(PickStatus.verified.label, '已驗證');
      expect(PickStatus.unverified.label, '未驗證');
      expect(PickStatus.insufficient.label, '資料不足');

      expect(PickStatus.verified.proven, isTrue);
      expect(PickStatus.unverified.proven, isFalse);
      expect(PickStatus.insufficient.proven, isFalse);

      // The three colours have to differ, or the levels are indistinguishable
      // on a card that shows no explanation.
      expect({
        AppPalette.status(PickStatus.verified),
        AppPalette.status(PickStatus.unverified),
        AppPalette.status(PickStatus.insufficient),
      }, hasLength(3));
    });

    test('a football pick is verified only when the audit backs it', () {
      expect(
        cornerPickStatus(
          assessment: _assessment(recommendation: _pick),
          audited: true,
        ),
        PickStatus.verified,
      );
      expect(
        cornerPickStatus(
          assessment: _assessment(recommendation: _pick),
          audited: false,
        ),
        PickStatus.unverified,
      );
      expect(
        cornerPickStatus(
          assessment: _assessment(observation: _pick),
          audited: true,
        ),
        PickStatus.unverified,
      );
    });

    test('a suspended or drifting football model reads as insufficient', () {
      expect(
        cornerPickStatus(
          assessment: _assessment(recommendation: _pick, suspended: true),
          audited: true,
        ),
        PickStatus.insufficient,
      );
      expect(
        cornerPickStatus(
          assessment: _assessment(recommendation: _pick, drifting: true),
          audited: true,
        ),
        PickStatus.insufficient,
      );
    });

    test('a closed racing gate leaves the pick unverified, not hidden', () {
      expect(
        racingPickStatus(
          declined: false,
          gateOpen: false,
          modelProbability: 0.3,
          marketProbability: 0.2,
          edge: 0.4,
        ),
        PickStatus.unverified,
      );
      expect(
        racingPickStatus(
          declined: false,
          gateOpen: true,
          modelProbability: 0.3,
          marketProbability: 0.2,
          edge: 0.4,
        ),
        PickStatus.verified,
      );
      expect(
        racingPickStatus(
          declined: false,
          gateOpen: true,
          modelProbability: 0.21,
          marketProbability: 0.2,
          edge: 0.001,
        ),
        PickStatus.unverified,
      );
      expect(
        racingPickStatus(
          declined: true,
          gateOpen: true,
          modelProbability: 0.3,
          marketProbability: 0.2,
          edge: 0.4,
        ),
        PickStatus.insufficient,
      );
    });
  });
}
