import 'package:edgewise/services/provenance.dart';
import 'package:edgewise/services/walk_forward.dart';
import 'package:flutter_test/flutter_test.dart';

List<DateTime> dailyDates(int count) => [
  for (var day = 0; day < count; day++)
    DateTime.utc(2024, 1, 1).add(Duration(days: day)),
];

WalkForwardFoldMetrics metrics({
  double mae = 2.5,
  double baselineMae = 3.0,
  double brier = 0.20,
  double baselineBrier = 0.25,
  int samples = 50,
}) {
  return WalkForwardFoldMetrics(
    mae: mae,
    baselineMae: baselineMae,
    brier: brier,
    baselineBrier: baselineBrier,
    samples: samples,
  );
}

void main() {
  group('purgedWalkForwardFolds', () {
    test('returns nothing when the history is too short', () {
      expect(purgedWalkForwardFolds(dates: dailyDates(40)), isEmpty);
    });

    test('builds expanding windows that never overlap the test fold', () {
      final dates = dailyDates(600);
      final folds = purgedWalkForwardFolds(dates: dates);
      expect(folds, isNotEmpty);
      for (final fold in folds) {
        expect(fold.trainIndices.last, lessThan(fold.testIndices.first));
        expect(fold.trainEnd.isBefore(fold.testStart), isTrue);
      }
      for (var index = 1; index < folds.length; index++) {
        expect(
          folds[index].trainIndices.length,
          greaterThan(folds[index - 1].trainIndices.length),
        );
      }
    });

    test('purges training rows inside the purge window', () {
      final dates = dailyDates(600);
      final folds = purgedWalkForwardFolds(
        dates: dates,
        purge: const Duration(days: 10),
        embargo: Duration.zero,
      );
      for (final fold in folds) {
        expect(fold.purged, 10);
        expect(
          fold.testStart.difference(fold.trainEnd).inDays,
          greaterThanOrEqualTo(10),
        );
      }
    });

    test('embargoes test rows right after the boundary', () {
      final dates = dailyDates(600);
      final folds = purgedWalkForwardFolds(
        dates: dates,
        embargo: const Duration(days: 5),
      );
      for (final fold in folds) {
        expect(fold.embargoed, 5);
      }
    });

    test('a zero purge and embargo keeps every row', () {
      final folds = purgedWalkForwardFolds(
        dates: dailyDates(600),
        purge: Duration.zero,
        embargo: Duration.zero,
      );
      for (final fold in folds) {
        expect(fold.purged, 0);
        expect(fold.embargoed, 0);
      }
    });

    test('covers the whole tail in the last fold', () {
      final dates = dailyDates(600);
      final folds = purgedWalkForwardFolds(
        dates: dates,
        purge: Duration.zero,
        embargo: Duration.zero,
      );
      expect(folds.last.testIndices.last, dates.length - 1);
    });
  });

  group('runPurgedWalkForward', () {
    test('sorts rows before splitting them', () {
      final rows = [
        for (var day = 600; day > 0; day--)
          DateTime.utc(2024, 1, 1).add(Duration(days: day)),
      ];
      final seen = <DateTime>[];
      runPurgedWalkForward<DateTime>(
        rows: rows,
        dateOf: (row) => row,
        evaluate: (train, test) {
          seen.add(train.last);
          for (final row in test) {
            expect(row.isAfter(train.last), isTrue);
          }
          return metrics(samples: test.length);
        },
      );
      expect(seen, isNotEmpty);
    });

    test('aggregates fold metrics weighted by sample count', () {
      var call = 0;
      final report = runPurgedWalkForward<DateTime>(
        rows: dailyDates(600),
        dateOf: (row) => row,
        evaluate: (train, test) {
          call += 1;
          // A large late fold must dominate a small early one.
          return metrics(brier: call.isOdd ? 0.1 : 0.3, samples: 100 * call);
        },
      );
      expect(report.foldCount, greaterThanOrEqualTo(3));
      final weight = report.folds.fold<double>(
        0,
        (sum, fold) => sum + fold.samples,
      );
      final expected =
          report.folds.fold<double>(
            0,
            (sum, fold) => sum + fold.brier * fold.samples,
          ) /
          weight;
      expect(report.brier, closeTo(expected, 1e-9));
      expect(report.brier, greaterThan(0.2));
      expect(report.samples, weight.round());
    });

    test('skips folds the evaluator refuses', () {
      final report = runPurgedWalkForward<DateTime>(
        rows: dailyDates(600),
        dateOf: (row) => row,
        evaluate: (train, test) => null,
      );
      expect(report.foldCount, 0);
      expect(report.gatePassed, isFalse);
      expect(report.verdict, contains('樣本不足'));
    });
  });

  group('WalkForwardReport', () {
    test('an empty report never passes the gate', () {
      expect(WalkForwardReport.empty.gatePassed, isFalse);
      expect(WalkForwardReport.empty.skill, 0);
    });

    test('passes only when a majority of folds beat the baseline', () {
      final winning = WalkForwardReport(
        folds: [metrics(), metrics(), metrics(), metrics()],
        purgeDays: 10,
        embargoDays: 3,
        purgedRows: 40,
        embargoedRows: 12,
      );
      expect(winning.passedFolds, 4);
      expect(winning.gatePassed, isTrue);
      expect(winning.skill, closeTo(0.2, 1e-9));

      final split = WalkForwardReport(
        folds: [
          metrics(),
          metrics(mae: 3.4, brier: 0.31),
          metrics(mae: 3.4, brier: 0.31),
        ],
        purgeDays: 10,
        embargoDays: 3,
        purgedRows: 0,
        embargoedRows: 0,
      );
      expect(split.gatePassed, isFalse);
      expect(split.verdict, contains('未達放行門檻'));
    });

    test('a good average cannot rescue a minority of winning folds', () {
      final report = WalkForwardReport(
        folds: [
          metrics(mae: 0.2, brier: 0.01, samples: 400),
          metrics(mae: 3.9, brier: 0.40, samples: 20),
          metrics(mae: 3.9, brier: 0.40, samples: 20),
          metrics(mae: 3.9, brier: 0.40, samples: 20),
        ],
        purgeDays: 10,
        embargoDays: 3,
        purgedRows: 0,
        embargoedRows: 0,
      );
      expect(report.mae, lessThan(report.baselineMae));
      expect(report.gatePassed, isFalse);
    });

    test('survives a JSON round trip', () {
      final report = WalkForwardReport(
        folds: [metrics(), metrics(samples: 70)],
        purgeDays: 10,
        embargoDays: 3,
        purgedRows: 25,
        embargoedRows: 6,
      );
      final restored = WalkForwardReport.fromJson(report.toJson());
      expect(restored.foldCount, report.foldCount);
      expect(restored.brier, closeTo(report.brier, 1e-12));
      expect(restored.purgedRows, 25);
      expect(restored.embargoedRows, 6);
    });
  });

  group('digestOf', () {
    test('is independent of map key order', () {
      expect(
        digestOf({'a': 1, 'b': 2}),
        digestOf(<String, Object?>{'b': 2, 'a': 1}),
      );
    });

    test('changes when content changes', () {
      expect(digestOf({'a': 1}), isNot(digestOf({'a': 2})));
    });

    test('treats a whole double as its integer', () {
      expect(digestOf({'a': 3.0}), digestOf({'a': 3}));
    });

    test('is order sensitive for lists', () {
      expect(digestOf([1, 2]), isNot(digestOf([2, 1])));
    });
  });

  group('ProvenanceLedger', () {
    ProvenanceLedger seeded() {
      var ledger = const ProvenanceLedger();
      ledger = ledger.append(
        id: 'dataset:1',
        stage: ProvenanceStage.dataset,
        source: 'football-data',
        content: {'rows': 1200},
        recordedAt: DateTime.utc(2026, 1, 1),
      );
      return ledger.append(
        id: 'model:1',
        stage: ProvenanceStage.model,
        source: 'on-device',
        content: {'weights': 22},
        recordedAt: DateTime.utc(2026, 1, 2),
        inputs: const ['dataset:1'],
      );
    }

    test('links each entry to the one before it', () {
      final ledger = seeded();
      expect(ledger.entries.first.previousHash, '');
      expect(ledger.entries.last.previousHash, ledger.entries.first.chainHash);
      expect(ledger.intact, isTrue);
      expect(ledger.headHash, ledger.entries.last.chainHash);
    });

    test('detects a tampered entry', () {
      final ledger = seeded();
      final tampered = ProvenanceLedger(
        entries: [
          ProvenanceEntry(
            id: ledger.entries.first.id,
            stage: ledger.entries.first.stage,
            source: ledger.entries.first.source,
            recordedAt: ledger.entries.first.recordedAt,
            contentHash: digestOf({'rows': 999999}),
            previousHash: '',
          ),
          ledger.entries.last,
        ],
      );
      expect(tampered.intact, isFalse);
    });

    test('resolves a transitive lineage', () {
      var ledger = seeded();
      ledger = ledger.append(
        id: 'prediction:1',
        stage: ProvenanceStage.prediction,
        source: 'hkjc',
        content: {'p': 0.55},
        recordedAt: DateTime.utc(2026, 1, 3),
        inputs: const ['model:1'],
      );
      final lineage = ledger
          .lineageOf('prediction:1')
          .map((e) => e.id)
          .toList();
      expect(lineage, ['dataset:1', 'model:1', 'prediction:1']);
    });

    test('filters entries by stage', () {
      expect(seeded().ofStage(ProvenanceStage.model).single.id, 'model:1');
      expect(seeded().ofStage(ProvenanceStage.settlement), isEmpty);
    });

    test('drops the oldest entries past the limit but stays intact', () {
      var ledger = const ProvenanceLedger(limit: 3);
      for (var index = 0; index < 8; index++) {
        ledger = ledger.append(
          id: 'entry:$index',
          stage: ProvenanceStage.prediction,
          source: 'hkjc',
          content: {'index': index},
          recordedAt: DateTime.utc(2026, 1, 1).add(Duration(days: index)),
        );
      }
      expect(ledger.entries.length, 3);
      expect(ledger.entries.first.id, 'entry:5');
      expect(ledger.intact, isTrue);
    });

    test('survives a JSON round trip', () {
      final ledger = seeded();
      final restored = ProvenanceLedger.fromJson(ledger.toJson());
      expect(restored.entries.length, ledger.entries.length);
      expect(restored.headHash, ledger.headHash);
      expect(restored.intact, isTrue);
    });

    test('labels every stage in Chinese', () {
      for (final stage in ProvenanceStage.values) {
        expect(stage.label, isNotEmpty);
      }
    });
  });
}
