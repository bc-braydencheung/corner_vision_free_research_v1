import '../models/forecast_data.dart';
import '../models/shadow_forecast.dart';
import 'hkjc_shadow.dart';

/// One fixture whose two free result sources report different corner counts.
class SettlementConflict {
  const SettlementConflict({
    required this.recordId,
    required this.matchId,
    required this.leagueCode,
    required this.homeTeam,
    required this.awayTeam,
    required this.matchDate,
    required this.hkjcTotal,
    required this.datasetTotal,
  });

  final String recordId;
  final String matchId;
  final String leagueCode;
  final String homeTeam;
  final String awayTeam;
  final DateTime matchDate;

  /// Count read from the HKJC feed or its stored reading.
  final int hkjcTotal;

  /// Count of the free football-data history for the same fixture.
  final int datasetTotal;

  String get label => '$homeTeam 對 $awayTeam';
}

/// What cross-checking the two free result sources found.
class SettlementAudit {
  const SettlementAudit({
    required this.agreed,
    required this.hkjcOnly,
    required this.datasetOnly,
    required this.conflicts,
  });

  static const empty = SettlementAudit(
    agreed: 0,
    hkjcOnly: 0,
    datasetOnly: 0,
    conflicts: <SettlementConflict>[],
  );

  /// Fixtures both sources reported, with the same count.
  final int agreed;

  /// Fixtures only the HKJC side could settle.
  final int hkjcOnly;

  /// Fixtures only the free history could settle.
  final int datasetOnly;

  /// Fixtures both sources reported, with different counts.
  final List<SettlementConflict> conflicts;

  int get crossChecked =>
      agreed + {for (final conflict in conflicts) conflict.matchId}.length;

  bool get hasConflicts => conflicts.isNotEmpty;

  Set<String> get conflictRecordIds => {
    for (final conflict in conflicts) conflict.recordId,
  };

  String get message {
    if (crossChecked == 0 && hkjcOnly == 0 && datasetOnly == 0) {
      return '未有可雙軌核對的已完場賽事。';
    }
    if (hasConflicts) {
      return '$crossChecked 場可雙軌核對，其中 ${conflicts.length} 場馬會與免費歷史角球數不一致，'
          '已標記並暫不結算；單一來源另有 ${hkjcOnly + datasetOnly} 場。';
    }
    return '$crossChecked 場雙軌核對一致；單一來源 ${hkjcOnly + datasetOnly} 場（'
        '馬會 $hkjcOnly、免費歷史 $datasetOnly），只有單一來源時不作核對。';
  }
}

/// Cross-checks the HKJC corner counts against the free football-data history.
///
/// The two sources are read off different feeds and paired only through the
/// explicit bridge key, so a mismatch means one of them is wrong about this
/// fixture. Adopting either count would silently feed a wrong outcome into
/// calibration, the market gate and the simulated account, so a disagreeing
/// fixture is reported and left unsettled until the sources agree.
SettlementAudit auditSettlementSources({
  required List<ShadowForecast> records,
  required Map<String, int> hkjcTotals,
  required List<MatchResult> settlementResults,
}) {
  final dataset = datasetCornerTotals(settlementResults);
  var agreed = 0;
  var hkjcOnly = 0;
  var datasetOnly = 0;
  final conflicts = <SettlementConflict>[];
  final counted = <String>{};
  for (final record in records) {
    final hkjc = hkjcTotals[record.matchId];
    final free = datasetCornerTotalFor(dataset, record);
    if (hkjc == null && free == null) {
      continue;
    }
    // A fixture can hold one record per model version; the sources are a
    // property of the fixture, so it is only counted once, while every record
    // of a disagreeing fixture is reported so none of them is settled.
    final first = counted.add(record.matchId);
    if (hkjc == null) {
      if (first) {
        datasetOnly++;
      }
      continue;
    }
    if (free == null) {
      if (first) {
        hkjcOnly++;
      }
      continue;
    }
    if (hkjc == free) {
      if (first) {
        agreed++;
      }
      continue;
    }
    conflicts.add(
      SettlementConflict(
        recordId: record.id,
        matchId: record.matchId,
        leagueCode: record.leagueCode,
        homeTeam: record.homeTeam,
        awayTeam: record.awayTeam,
        matchDate: record.matchDate,
        hkjcTotal: hkjc,
        datasetTotal: free,
      ),
    );
  }
  conflicts.sort((left, right) => right.matchDate.compareTo(left.matchDate));
  return SettlementAudit(
    agreed: agreed,
    hkjcOnly: hkjcOnly,
    datasetOnly: datasetOnly,
    conflicts: conflicts,
  );
}
