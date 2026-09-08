/// What a self-check of the HKJC payloads concluded.
class HkjcContractReport {
  const HkjcContractReport({required this.status, required this.message});

  /// Everything the app reads was present and readable.
  static const ok = HkjcContractReport(status: 'ok', message: '');

  /// `ok`, `changed` (HKJC's payload no longer carries what the app reads) or
  /// `closed` (the payload is intact and HKJC simply has nothing on sale).
  final String status;

  /// Empty when [status] is `ok`.
  final String message;

  bool get interfaceChanged => status == 'changed';

  bool get marketClosed => status == 'closed';
}

/// Field the app reads out of every tournament row.
const _tournamentFields = <String>['id', 'nameProfileId'];

/// Fields the app reads out of every match row.
const _matchFields = <String>['id', 'kickOffTime', 'homeTeam', 'awayTeam'];

/// Checks the tournament list before its ids are used.
///
/// HKJC changing a field name or a profile id looks exactly like an empty card
/// once the ids fail to match: both end in zero fixtures. The distinction
/// matters because one is ours to fix and the other is simply the off-season,
/// so the payload is inspected rather than only its result.
HkjcContractReport checkTournamentList(
  Map<String, Object?> payload, {
  required Map<String, String> profiles,
  required Map<String, String> resolved,
}) {
  final list = (payload['data'] as Map?)?['tournamentList'];
  if (list is! List) {
    return const HkjcContractReport(
      status: 'changed',
      message: '馬會介面變更：賽事列表回應沒有 tournamentList，請更新查詢',
    );
  }
  if (list.isEmpty) {
    return const HkjcContractReport(status: 'closed', message: '馬會暫未開放任何足球賽事');
  }
  final rows = [
    for (final entry in list)
      if (entry is Map) entry.cast<String, Object?>(),
  ];
  if (rows.isEmpty) {
    return const HkjcContractReport(
      status: 'changed',
      message: '馬會介面變更：賽事列表項目不是物件，請更新查詢',
    );
  }
  final missing = _tournamentFields
      .where((field) => rows.every((row) => row[field] == null))
      .toList();
  if (missing.isNotEmpty) {
    return HkjcContractReport(
      status: 'changed',
      message: '馬會介面變更：賽事列表缺少 ${missing.join('、')}，請更新查詢',
    );
  }
  if (resolved.isEmpty) {
    return HkjcContractReport(
      status: 'changed',
      message:
          '馬會介面變更：追蹤的 ${profiles.length} 個聯賽編號'
          '（${profiles.values.join('、')}）在馬會賽事列表中一個都對不上，'
          '可能已改編號',
    );
  }
  return HkjcContractReport.ok;
}

/// Checks a merged `matchList` payload before its matches are parsed.
///
/// [fixtures] is how many fixtures the parser produced, so a payload that
/// carries matches the app cannot read is reported as an interface change
/// instead of an empty card.
HkjcContractReport checkMatchList(
  Map<String, Object?> payload, {
  required int fixtures,
  required int cornerPools,
}) {
  final matches = (payload['data'] as Map?)?['matches'];
  if (matches is! List) {
    return const HkjcContractReport(
      status: 'changed',
      message: '馬會介面變更：賽程回應沒有 matches，請更新查詢',
    );
  }
  if (matches.isEmpty) {
    return const HkjcContractReport(status: 'closed', message: '馬會暫未開放追蹤聯賽的賽事');
  }
  final rows = [
    for (final entry in matches)
      if (entry is Map) entry.cast<String, Object?>(),
  ];
  final missing = _matchFields
      .where((field) => rows.every((row) => row[field] == null))
      .toList();
  if (rows.isEmpty || missing.isNotEmpty) {
    return HkjcContractReport(
      status: 'changed',
      message:
          '馬會介面變更：賽程 ${matches.length} 場缺少 '
          '${rows.isEmpty ? '可讀欄位' : missing.join('、')}，請更新查詢',
    );
  }
  if (fixtures == 0) {
    return HkjcContractReport(
      status: 'changed',
      message: '馬會介面變更：收到 ${matches.length} 場賽事但一場都解不出來，請更新解析',
    );
  }
  if (rows.every((row) => row['foPools'] == null)) {
    return const HkjcContractReport(
      status: 'changed',
      message: '馬會介面變更：賽程沒有 foPools 賠率欄位，請更新查詢',
    );
  }
  if (cornerPools == 0) {
    return HkjcContractReport(
      status: 'closed',
      message: '馬會 $fixtures 場賽事之中未開角球大細盤',
    );
  }
  return HkjcContractReport.ok;
}
