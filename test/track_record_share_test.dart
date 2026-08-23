import 'dart:ui' as ui;

import 'package:edgewise/services/track_record.dart';
import 'package:edgewise/services/track_record_share.dart';
import 'package:edgewise/services/track_record_share_image.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 8, 20, 12);

TrackRecordEntry _entry({
  required String matchId,
  required DateTime matchDate,
  bool recommended = true,
  int? actualTotalCorners,
  double takenOdds = 1.95,
}) {
  return TrackRecordEntry(
    matchId: matchId,
    leagueName: '英超',
    homeTeam: 'Arsenal',
    awayTeam: 'Chelsea',
    line: 9.5,
    matchDate: matchDate,
    capturedAt: matchDate.subtract(const Duration(hours: 6)),
    direction: 'high',
    modelProbability: 0.58,
    marketProbability: 0.51,
    takenOdds: takenOdds,
    takenAt: matchDate.subtract(const Duration(hours: 6)),
    edge: 0.05,
    recommended: recommended,
    closingOdds: 1.85,
    closingProbability: 0.53,
    actualTotalCorners: actualTotalCorners,
  );
}

TrackRecordReport _report({
  List<TrackRecordEntry> entries = const [],
  int recommended = 0,
  int settled = 0,
  int hits = 0,
  int brierSamples = 0,
  int clvSamples = 0,
}) {
  return TrackRecordReport(
    entries: entries,
    skipped: const {},
    recommended: recommended,
    settled: settled,
    hits: hits,
    brier: 0.2312,
    marketBrier: 0.2451,
    brierSamples: brierSamples,
    meanClosingLineValue: 0.0143,
    beatClosingRate: 0.62,
    clvSamples: clvSamples,
    netUnits: 1.85,
    maximumDrawdownUnits: 0.95,
  );
}

void main() {
  group('track record share text', () {
    test('an empty ledger says so instead of printing a rate', () {
      final text = buildTrackRecordShareText(report: _report(), asOf: _now);

      expect(text, contains('睿測 · 至今紀錄'));
      expect(text, contains('推介 0 個'));
      expect(text, contains('命中率：未有已結算賽果'));
      expect(text, contains('Brier：樣本不足'));
      expect(text, contains('平均 CLV：樣本不足'));
      expect(text, contains('僅供研究，非投注建議'));
      expect(text, contains('研究單位不代表金額'));
    });

    test('a settled ledger prints the measured figures', () {
      final text = buildTrackRecordShareText(
        report: _report(
          entries: [
            _entry(
              matchId: 'hkjc-1',
              matchDate: _now.subtract(const Duration(days: 1)),
              actualTotalCorners: 11,
            ),
          ],
          recommended: 24,
          settled: 24,
          hits: 13,
          brierSamples: 24,
          clvSamples: 20,
        ),
        asOf: _now,
      );

      expect(text, contains('推介 24 個，已結算 24 個'));
      expect(text, contains('命中率 54.2%'));
      expect(text, contains('Brier 模型 0.2312 ／ 盤口 0.2451'));
      expect(text, contains('平均 CLV 1.43%（20 個樣本）'));
      expect(text, contains('累計研究單位 1.85'));
    });
  });

  group('track record share image', () {
    testWidgets('renders at share resolution both empty and filled', (
      tester,
    ) async {
      // PNG encoding is real asynchronous work, so it cannot run on the fake
      // clock the widget tester installs.
      await tester.runAsync(() async {
        final empty = await renderTrackRecordShareImage(
          report: _report(),
          asOf: _now,
        );
        final filled = await renderTrackRecordShareImage(
          report: _report(
            entries: [
              for (var index = 0; index < trackRecordShareEntries + 3; index++)
                _entry(
                  matchId: 'hkjc-$index',
                  matchDate: _now.subtract(Duration(days: index + 1)),
                  actualTotalCorners: index.isEven ? 12 : 7,
                ),
            ],
            recommended: 8,
            settled: 8,
            hits: 4,
            brierSamples: 8,
            clvSamples: 8,
          ),
          asOf: _now,
        );

        for (final image in [empty, filled]) {
          expect(image.width, 3240);
          expect(image.height, greaterThan(1200));
          final decoded = await ui.instantiateImageCodec(image.bytes);
          final frame = await decoded.getNextFrame();
          expect(frame.image.width, image.width);
          expect(frame.image.height, image.height);
        }
        expect(filled.height, greaterThan(empty.height));
      });
    });

    test('the listed recommendations stay clear of the disclaimers', () {
      for (var count = 0; count <= trackRecordShareEntries; count++) {
        final layout = trackRecordShareLayout(
          _report(
            entries: [
              for (var index = 0; index < count; index++)
                _entry(
                  matchId: 'hkjc-$index',
                  matchDate: _now.subtract(Duration(days: index + 1)),
                  actualTotalCorners: 12,
                ),
            ],
            recommended: count,
            settled: count,
            hits: count,
            brierSamples: count,
            clvSamples: count,
          ),
        );

        expect(layout.contentBottom, lessThanOrEqualTo(layout.footerTop));
      }
    });

    test('only the newest recommendations are listed', () {
      final report = _report(
        entries: [
          for (var index = 0; index < trackRecordShareEntries + 4; index++)
            _entry(
              matchId: 'hkjc-$index',
              matchDate: _now.subtract(Duration(days: index + 1)),
            ),
          _entry(
            matchId: 'observation',
            matchDate: _now.subtract(const Duration(hours: 30)),
            recommended: false,
          ),
        ],
        recommended: trackRecordShareEntries + 4,
      );

      final listed = trackRecordShareListing(report);

      expect(listed.length, trackRecordShareEntries);
      expect(listed.every((entry) => entry.recommended), isTrue);
      expect(listed.first.matchId, 'hkjc-0');
      expect(
        listed.map((entry) => entry.matchDate),
        orderedEquals([
          for (var index = 0; index < trackRecordShareEntries; index++)
            _now.subtract(Duration(days: index + 1)),
        ]),
      );
    });
  });
}
