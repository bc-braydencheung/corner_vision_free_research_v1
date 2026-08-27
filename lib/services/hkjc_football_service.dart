import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/hkjc_football.dart';

/// Public HKJC football tournament profiles tracked by the app.
///
/// The keys are the football-data league codes already used everywhere else in
/// the app; the values are the `tournid` of the public HKJC pages, e.g.
/// `https://bet.hkjc.com/ch/football/home?tournid=50000051` for the EPL.
const hkjcFootballProfiles = <String, String>{
  'E0': '50000051',
  'SP1': '50000100',
  'F1': '50000058',
  'I1': '50000069',
  'D1': '50000063',
};

/// Low-frequency read-only client for HKJC football fixtures and corner pools.
///
/// HKJC only accepts its own whitelisted GraphQL documents, so the two queries
/// below are byte-for-byte the ones the public betting site issues.
class HkjcFootballService {
  HkjcFootballService({
    this.endpoint = 'https://info.cld.hkjc.com/graphql/base/',
    this.refreshInterval = const Duration(minutes: 20),
    this.maximumCacheAge = const Duration(hours: 6),
    this.minimumInterval = const Duration(milliseconds: 800),
    Directory? directory,
  }) : _directoryOverride = directory;

  static const _userAgent =
      'EdgeWise personal research mobile/1.0 '
      '(low-frequency cached access)';

  /// Head-to-head, total goals hi/lo and corner hi/lo pools.
  static const oddsTypes = <String>['HAD', 'HIL', 'CHL'];

  final String endpoint;

  /// Minimum age of the cache before the network is touched again.
  final Duration refreshInterval;

  /// Age past which the cache no longer stands in for the HKJC card.
  ///
  /// HKJC drops a fixture from its list once it has been settled, so an old
  /// cache still holds matches HKJC no longer offers. Showing them as HKJC
  /// fixtures would invent a market, so a cache this stale is reported as a
  /// failed update instead of being displayed.
  final Duration maximumCacheAge;
  final Duration minimumInterval;
  final Directory? _directoryOverride;
  DateTime? _lastRequest;

  Future<Directory> _directory() async {
    final override = _directoryOverride;
    if (override != null) {
      if (!override.existsSync()) {
        await override.create(recursive: true);
      }
      return override;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/edgewise_hkjc_football');
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _cacheFile() async =>
      File('${(await _directory()).path}/fixtures.json');

  /// Reads the cached snapshot, or `null` when there is none to read.
  Future<HkjcFootballSnapshot?> loadCached() async {
    try {
      final file = await _cacheFile();
      if (!file.existsSync()) {
        return null;
      }
      return HkjcFootballSnapshot.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>(),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _save(HkjcFootballSnapshot snapshot) async {
    try {
      final file = await _cacheFile();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      await temporary.rename(file.path);
    } on Object {
      // Cache is a convenience only; a failed write must not hide the data.
    }
  }

  /// Returns the cached snapshot, refreshing it from HKJC when it is stale.
  ///
  /// A network failure keeps the cached snapshot; only its [
  /// HkjcFootballSnapshot.note] reports the error so the UI stays populated.
  Future<HkjcFootballSnapshot> load({bool force = false}) async {
    final cached = await loadCached();
    final fresh =
        cached != null &&
        DateTime.now().difference(cached.capturedAt) < refreshInterval;
    if (cached != null && fresh && !force) {
      return cached;
    }
    try {
      final snapshot = await fetch();
      await _save(snapshot);
      return snapshot;
    } on Object catch (error) {
      if (cached != null) {
        final age = DateTime.now().difference(cached.capturedAt);
        if (age > maximumCacheAge) {
          return HkjcFootballSnapshot(
            capturedAt: cached.capturedAt,
            fixtures: const [],
            note:
                '馬會更新失敗（${_errorLabel(error)}），'
                '上次快取已超過 ${maximumCacheAge.inHours} 小時，'
                '不再顯示可能已完場的賽事',
          );
        }
        return HkjcFootballSnapshot(
          capturedAt: cached.capturedAt,
          fixtures: cached.fixtures,
          note: '馬會更新失敗（${_errorLabel(error)}），顯示上次快取',
        );
      }
      return HkjcFootballSnapshot(
        capturedAt: DateTime.now(),
        fixtures: const [],
        note: '未能連接馬會賽事資料（${_errorLabel(error)}）',
      );
    }
  }

  /// Fetches fixtures and pools for the tracked tournaments.
  Future<HkjcFootballSnapshot> fetch() async {
    final tournaments = await _tournamentIds();
    if (tournaments.isEmpty) {
      return HkjcFootballSnapshot(
        capturedAt: DateTime.now(),
        fixtures: const [],
        note: '馬會暫未開放英超／西甲／法甲／意甲／德甲賽事',
      );
    }
    final payload = await _post(matchListQuery, {
      'startIndex': null,
      'endIndex': null,
      'startDate': null,
      'endDate': null,
      'matchIds': null,
      'tournIds': tournaments.keys.toList(),
      'fbOddsTypes': oddsTypes,
      'fbOddsTypesM': oddsTypes,
      'inplayOnly': false,
      'featuredMatchesOnly': false,
      'frontEndIds': null,
      'earlySettlementOnly': false,
      'showAllMatch': true,
    });
    return HkjcFootballSnapshot(
      capturedAt: DateTime.now(),
      fixtures: parseMatches(payload, tournaments),
      note: '',
    );
  }

  /// Final corner counts from the public HKJC results page.
  ///
  /// HKJC drops a match from the fixture list within hours of full time, so a
  /// bet keyed to it can otherwise never settle. The results page keeps the
  /// paid-out match for days under the same match id, which makes it the only
  /// free source that can still settle such a bet.
  Future<List<HkjcCornerResult>> fetchCornerResults() async {
    final payload = await _post(matchResultsQuery, const {
      'startDate': null,
      'endDate': null,
      'startIndex': 1,
      'endIndex': null,
      'teamId': null,
    });
    return parseCornerResults(payload, observedAt: DateTime.now());
  }

  /// Corner result of the corner pool, taken at the stage HKJC pays out on.
  ///
  /// A match carries one row per result type and stage, and the running rows
  /// of a match still in progress sit beside the final one, so only the final
  /// stage of the corner type is read. Goals share the shape of corners, so
  /// reading the wrong type would settle corner bets on the score.
  List<HkjcCornerResult> parseCornerResults(
    Map<String, Object?> payload, {
    required DateTime observedAt,
  }) {
    final matches =
        ((payload['data'] as Map?)?['matches'] as List?) ?? const [];
    final results = <HkjcCornerResult>[];
    for (final entry in matches) {
      final match = (entry as Map).cast<String, Object?>();
      final matchId = match['id'] as String? ?? '';
      final kickOff = DateTime.tryParse(
        match['kickOffTime'] as String? ?? '',
      )?.toLocal();
      if (matchId.isEmpty || kickOff == null) {
        continue;
      }
      int? home;
      int? away;
      for (final resultEntry in (match['results'] as List?) ?? const []) {
        final result = (resultEntry as Map).cast<String, Object?>();
        if ((result['resultType'] as num?)?.toInt() != _cornerResultType ||
            (result['stageId'] as num?)?.toInt() != _finalStageId) {
          continue;
        }
        home = (result['homeResult'] as num?)?.toInt();
        away = (result['awayResult'] as num?)?.toInt();
      }
      if (home == null || away == null) {
        continue;
      }
      results.add(
        HkjcCornerResult(
          matchId: matchId,
          kickOffTime: kickOff,
          homeCorner: home,
          awayCorner: away,
          status: match['status'] as String? ?? '',
          observedAt: observedAt,
        ),
      );
    }
    return results;
  }

  /// Result type of the corner pools, as opposed to goals or bookings.
  static const _cornerResultType = 2;

  /// Stage HKJC settles a full-time pool on, after any running stage.
  static const _finalStageId = 5;

  /// Maps the current tournament ids to app league codes.
  ///
  /// The `tournid` in the public URL is a stable `nameProfileId`, while the
  /// `matches` query needs the id of the season currently on sale.
  Future<Map<String, String>> _tournamentIds() async {
    final payload = await _post(tournamentListQuery, const {});
    final tournaments =
        ((payload['data'] as Map?)?['tournamentList'] as List?) ?? const [];
    final profiles = <String, String>{};
    for (final entry in tournaments) {
      final tournament = (entry as Map).cast<String, Object?>();
      final profileId = tournament['nameProfileId'] as String? ?? '';
      final id = tournament['id'] as String? ?? '';
      for (final league in hkjcFootballProfiles.entries) {
        if (league.value == profileId && id.isNotEmpty) {
          profiles[id] = league.key;
        }
      }
    }
    return profiles;
  }

  /// Converts a `matchList` payload into fixtures for the tracked leagues.
  List<HkjcFootballFixture> parseMatches(
    Map<String, Object?> payload,
    Map<String, String> tournamentLeagues,
  ) {
    final matches =
        ((payload['data'] as Map?)?['matches'] as List?) ?? const [];
    final fixtures = <HkjcFootballFixture>[];
    for (final entry in matches) {
      final match = (entry as Map).cast<String, Object?>();
      final tournament =
          (match['tournament'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{};
      final leagueCode =
          tournamentLeagues[tournament['id'] as String? ?? ''] ??
          hkjcFootballProfiles.entries
              .where(
                (league) =>
                    league.value ==
                    (tournament['nameProfileId'] as String? ?? ''),
              )
              .map((league) => league.key)
              .firstOrNull;
      if (leagueCode == null) {
        continue;
      }
      final pools = (match['foPools'] as List?) ?? const [];
      final corner = <HkjcMarketLine>[];
      final goals = <HkjcMarketLine>[];
      HkjcMatchOdds? matchOdds;
      for (final poolEntry in pools) {
        final pool = (poolEntry as Map).cast<String, Object?>();
        final lines = (pool['lines'] as List?) ?? const [];
        switch (pool['oddsType'] as String? ?? '') {
          case 'CHL':
            corner.addAll(lines.map(_parseHiLoLine));
          case 'HIL':
            goals.addAll(lines.map(_parseHiLoLine));
          case 'HAD':
            matchOdds = _parseMatchOdds(lines);
        }
      }
      corner.sort((a, b) => a.line.compareTo(b.line));
      goals.sort((a, b) => a.line.compareTo(b.line));
      final result =
          (match['runningResult'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{};
      final home = (match['homeTeam'] as Map?)?.cast<String, Object?>();
      final away = (match['awayTeam'] as Map?)?.cast<String, Object?>();
      fixtures.add(
        HkjcFootballFixture(
          matchId: match['id'] as String? ?? '',
          frontEndId: match['frontEndId'] as String? ?? '',
          leagueCode: leagueCode,
          tournamentCode: tournament['code'] as String? ?? '',
          tournamentName: tournament['name_ch'] as String? ?? '',
          kickOffTime:
              DateTime.tryParse(
                match['kickOffTime'] as String? ?? '',
              )?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
          status: match['status'] as String? ?? '',
          homeTeam: home?['name_ch'] as String? ?? '',
          awayTeam: away?['name_ch'] as String? ?? '',
          homeTeamEnglish: home?['name_en'] as String? ?? '',
          awayTeamEnglish: away?['name_en'] as String? ?? '',
          matchOdds: matchOdds,
          cornerLines: corner,
          goalLines: goals,
          homeCorner: (result['homeCorner'] as num?)?.toInt(),
          awayCorner: (result['awayCorner'] as num?)?.toInt(),
        ),
      );
    }
    fixtures.sort((a, b) => a.kickOffTime.compareTo(b.kickOffTime));
    return fixtures;
  }

  static HkjcMarketLine _parseHiLoLine(Object? entry) {
    final line = (entry as Map).cast<String, Object?>();
    final condition = line['condition'] as String? ?? '';
    final parts = condition
        .split('/')
        .map((part) => double.tryParse(part.trim()))
        .whereType<double>()
        .toList();
    double? high;
    double? low;
    for (final combinationEntry
        in (line['combinations'] as List?) ?? const []) {
      final combination = (combinationEntry as Map).cast<String, Object?>();
      final odds = double.tryParse(combination['currentOdds'] as String? ?? '');
      switch (combination['str'] as String? ?? '') {
        case 'H':
          high = odds;
        case 'L':
          low = odds;
      }
    }
    return HkjcMarketLine(
      lineId: line['lineId'] as String? ?? '',
      condition: condition,
      line: parts.isEmpty ? 0 : parts.reduce((a, b) => a + b) / parts.length,
      main: line['main'] as bool? ?? false,
      status: line['status'] as String? ?? '',
      highOdds: high,
      lowOdds: low,
    );
  }

  static HkjcMatchOdds? _parseMatchOdds(List<Object?> lines) {
    if (lines.isEmpty) {
      return null;
    }
    final line = (lines.first as Map).cast<String, Object?>();
    double? home;
    double? draw;
    double? away;
    for (final combinationEntry
        in (line['combinations'] as List?) ?? const []) {
      final combination = (combinationEntry as Map).cast<String, Object?>();
      final odds = double.tryParse(combination['currentOdds'] as String? ?? '');
      switch (combination['str'] as String? ?? '') {
        case 'H':
          home = odds;
        case 'D':
          draw = odds;
        case 'A':
          away = odds;
      }
    }
    return HkjcMatchOdds(home: home, draw: draw, away: away);
  }

  Future<Map<String, Object?>> _post(
    String query,
    Map<String, Object?> variables,
  ) async {
    final previous = _lastRequest;
    if (previous != null) {
      final wait = minimumInterval - DateTime.now().difference(previous);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }
    _lastRequest = DateTime.now();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.refererHeader, 'https://bet.hkjc.com/');
      request.add(
        utf8.encode(jsonEncode({'query': query, 'variables': variables})),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'HKJC returned ${response.statusCode}',
          uri: Uri.parse(endpoint),
        );
      }
      final body = await utf8.decoder.bind(response).join();
      final payload = (jsonDecode(body) as Map).cast<String, Object?>();
      final errors = payload['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = (errors.first as Map).cast<String, Object?>();
        throw HttpException('HKJC GraphQL: ${first['message']}');
      }
      return payload;
    } finally {
      client.close(force: true);
    }
  }

  static String _errorLabel(Object error) {
    if (error is SocketException) {
      return '網絡連線失敗';
    }
    if (error is TimeoutException) {
      return '連線逾時';
    }
    if (error is HttpException) {
      return error.message;
    }
    if (error is FormatException) {
      return '回應格式不符';
    }
    return error.runtimeType.toString();
  }

  /// Whitelisted document used by `bet.hkjc.com` to list tournaments.
  static const tournamentListQuery = '''

    query tournamentList {
      tournamentList {
        id
        code
        frontEndId
        nameProfileId
        isInteractiveServiceAvailable
        name_ch
        name_en
        sequence
      }
    }
  ''';

  /// Whitelisted document used by `bet.hkjc.com` for its results page.
  static const matchResultsQuery = r'''

    query matchResults($startDate: String, $endDate: String, $startIndex: Int,$endIndex: Int,$teamId: String) {
      matchNumByDate(startDate: $startDate, endDate: $endDate, teamId: $teamId) {
        total
      }
      matches: matchResult(startDate: $startDate, endDate: $endDate, startIndex: $startIndex,endIndex: $endIndex, teamId: $teamId) {
        id
        status
        frontEndId
        matchDayOfWeek
        matchNumber
        matchDate
        kickOffTime
        sequence
        homeTeam {
          id
          name_en
          name_ch
        }
        awayTeam {
          id
          name_en
          name_ch
        }
        tournament {
          code
          name_en
          name_ch      
        }
        results {
          homeResult
          awayResult
          ttlCornerResult
          resultConfirmType
          payoutConfirmed
          stageId
          resultType
          sequence
        }
        poolInfo {
          payoutRefundPools
          refundPools
          ntsInfo
          entInfo
          definedPools
          ngsInfo {
            str
            name_en
            name_ch
            instNo
          }
          agsInfo {
            str
            name_en
            name_ch
            }
        }
      }
    }
  ''';

  /// Whitelisted document used by `bet.hkjc.com` to list matches and pools.
  static const matchListQuery = r'''
      query matchList($startIndex: Int, $endIndex: Int,$startDate: String, $endDate: String, $matchIds: [String], $tournIds: [String], $fbOddsTypes: [FBOddsType]!, $fbOddsTypesM: [FBOddsType]!, $inplayOnly: Boolean, $featuredMatchesOnly: Boolean, $frontEndIds: [String], $earlySettlementOnly: Boolean, $showAllMatch: Boolean) {
        matches(startIndex: $startIndex,endIndex: $endIndex, startDate: $startDate, endDate: $endDate, matchIds: $matchIds, tournIds: $tournIds, fbOddsTypes: $fbOddsTypesM, inplayOnly: $inplayOnly, featuredMatchesOnly: $featuredMatchesOnly, frontEndIds: $frontEndIds, earlySettlementOnly: $earlySettlementOnly, showAllMatch: $showAllMatch) {
          id
          frontEndId
          matchDate
          kickOffTime
          status
          updateAt
          sequence
          esIndicatorEnabled
          homeTeam {
            id
            name_en
            name_ch
          }
          awayTeam {
            id
            name_en
            name_ch
          }
          tournament {
            id
            frontEndId
            nameProfileId
            isInteractiveServiceAvailable
            code
            name_en
            name_ch
          }
          isInteractiveServiceAvailable
          inplayDelay
          venue {
            code
            name_en
            name_ch
          }
          tvChannels {
            code
            name_en
            name_ch
          }
          liveEvents {
            id
            code
          }
          featureStartTime
          featureMatchSequence
          poolInfo {
            normalPools
            inplayPools
            sellingPools
            ntsInfo
            entInfo
            definedPools
            ngsInfo {
              str
              name_en
              name_ch
              instNo
            }
            agsInfo {
              str
              name_en
              name_ch
            }
          }
          runningResult {
            homeScore
            awayScore
            corner
            homeCorner
            awayCorner
          }
          runningResultExtra {
            homeScore
            awayScore
            corner
            homeCorner
            awayCorner
          }
          adminOperation {
            remark {
              typ
            }
          }
          foPools(fbOddsTypes: $fbOddsTypes) {
            id
            status
            oddsType
            instNo
            inplay
            name_ch
            name_en
            updateAt
            expectedSuspendDateTime
            lines {
              lineId
              status
              condition
              main
              combinations {
                combId
                str
                status
                offerEarlySettlement
                currentOdds
                selections {
                  selId
                  str
                  name_ch
                  name_en
                }
              }
            }
          }
        }
      }
      ''';
}
