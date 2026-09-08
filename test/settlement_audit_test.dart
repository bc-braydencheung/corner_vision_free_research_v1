import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/services/settlement_audit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an empty ledger has nothing to cross-check', () {
    final audit = auditSettlementSources(
      records: const [],
      hkjcTotals: const {},
      settlementResults: const [],
    );

    expect(audit.crossChecked, 0);
    expect(audit.hasConflicts, isFalse);
    expect(audit.message, contains('未有可雙軌核對'));
  });

  test('sources reporting the same count agree', () {
    final audit = auditSettlementSources(
      records: [_record(0)],
      hkjcTotals: const {'HK0': 11},
      settlementResults: [_freeResult(0, 11)],
    );

    expect(audit.agreed, 1);
    expect(audit.crossChecked, 1);
    expect(audit.hasConflicts, isFalse);
    expect(audit.conflictRecordIds, isEmpty);
  });

  test('sources reporting different counts are flagged, not adopted', () {
    final audit = auditSettlementSources(
      records: [_record(0)],
      hkjcTotals: const {'HK0': 11},
      settlementResults: [_freeResult(0, 9)],
    );

    expect(audit.agreed, 0);
    expect(audit.hasConflicts, isTrue);
    expect(audit.conflicts.single.hkjcTotal, 11);
    expect(audit.conflicts.single.datasetTotal, 9);
    expect(audit.conflictRecordIds, {'E0:0'});
    expect(audit.message, contains('不一致'));
    expect(audit.message, contains('暫不結算'));
  });

  test('one source alone is reported as such, never as agreement', () {
    final hkjcOnly = auditSettlementSources(
      records: [_record(0)],
      hkjcTotals: const {'HK0': 11},
      settlementResults: const [],
    );
    final freeOnly = auditSettlementSources(
      records: [_record(0)],
      hkjcTotals: const {},
      settlementResults: [_freeResult(0, 11)],
    );

    expect(hkjcOnly.hkjcOnly, 1);
    expect(hkjcOnly.crossChecked, 0);
    expect(hkjcOnly.hasConflicts, isFalse);
    expect(freeOnly.datasetOnly, 1);
    expect(freeOnly.crossChecked, 0);
    expect(freeOnly.message, contains('只有單一來源時不作核對'));
  });

  test('a free result filed a day apart still pairs', () {
    final audit = auditSettlementSources(
      records: [_record(0)],
      hkjcTotals: const {'HK0': 11},
      settlementResults: [_freeResult(0, 11, dayShift: 1)],
    );

    expect(audit.agreed, 1);
  });

  test('a physically impossible free count is not treated as a source', () {
    final audit = auditSettlementSources(
      records: [_record(0)],
      hkjcTotals: const {'HK0': 11},
      settlementResults: [_freeResult(0, 99)],
    );

    expect(audit.hasConflicts, isFalse);
    expect(audit.hkjcOnly, 1);
  });

  test('every record of a disputed fixture is flagged, counted once', () {
    final audit = auditSettlementSources(
      records: [
        _record(0),
        _record(0, version: 'v2'),
      ],
      hkjcTotals: const {'HK0': 11},
      settlementResults: [_freeResult(0, 9)],
    );

    expect(audit.conflicts.length, 2);
    expect(audit.crossChecked, 1);
    expect(audit.conflictRecordIds, {'E0:0', 'E0:0:v2'});
  });

  test('conflicts are reported newest first', () {
    final audit = auditSettlementSources(
      records: [_record(0), _record(3)],
      hkjcTotals: const {'HK0': 11, 'HK3': 8},
      settlementResults: [_freeResult(0, 9), _freeResult(3, 12)],
    );

    expect(audit.conflicts.length, 2);
    expect(audit.conflicts.first.matchId, 'HK3');
  });
}

ShadowForecast _record(int index, {String version = ''}) {
  final matchDate = DateTime.utc(2025, 3, 1).add(Duration(days: index));
  return ShadowForecast(
    id: version.isEmpty ? 'E0:$index' : 'E0:$index:$version',
    matchId: 'HK$index',
    leagueCode: 'E0',
    leagueName: '英超',
    homeTeam: 'Home $index',
    awayTeam: 'Away $index',
    matchDate: matchDate,
    capturedAt: matchDate.subtract(const Duration(hours: 3)),
    modelVersion: version.isEmpty ? 'test' : version,
    expectedTotalCorners: 9.8,
    referenceMae: 2.6,
    referenceBrier: 0.24,
    over9_5Probability: 0.55,
    marketOverProbability: 0.53,
  );
}

MatchResult _freeResult(int index, int total, {int dayShift = 0}) {
  final date = DateTime.utc(2025, 3, 1).add(Duration(days: index + dayShift));
  final day =
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  return MatchResult(
    matchId: 'E0:$day:Home $index:Away $index',
    actualTotalCorners: total,
  );
}
