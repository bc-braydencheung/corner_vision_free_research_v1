import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/racing_mobile.dart';

/// One runner of a HKJC race meeting as published on the public racing pages.
class HkjcRacingRunner {
  const HkjcRacingRunner({
    required this.runnerNo,
    required this.horseCode,
    required this.nameChinese,
    required this.nameEnglish,
    required this.status,
    this.draw,
    this.handicapWeight,
    this.rating,
    this.lastSix = '',
    this.jockey = '',
    this.trainer = '',
    this.gearInfo = '',
    this.winOdds,
    this.finalPosition,
  });

  final String runnerNo;
  final String horseCode;
  final String nameChinese;
  final String nameEnglish;
  final String status;
  final int? draw;
  final double? handicapWeight;
  final double? rating;
  final String lastSix;
  final String jockey;
  final String trainer;
  final String gearInfo;
  final double? winOdds;
  final int? finalPosition;

  /// Withdrawn runners keep their number but must never be priced.
  bool get scratched {
    final normalised = status.toLowerCase();
    return normalised.contains('scratch') || normalised.contains('withdraw');
  }

  /// Key used in stored odds snapshots: the stable horse code when HKJC
  /// publishes one, otherwise the zero padded runner number.
  String get oddsKey =>
      horseCode.isEmpty ? runnerNo.padLeft(2, '0') : horseCode;
}

/// One race of a HKJC meeting with its public win pool.
class HkjcRacingRace {
  const HkjcRacingRace({
    required this.raceId,
    required this.raceNumber,
    required this.venueCode,
    required this.date,
    required this.status,
    this.postTime,
    this.distanceMetres = 0,
    this.going = '',
    this.surface = '',
    this.raceClass = '',
    this.runners = const [],
    this.winOdds = const {},
    this.placeOdds = const {},
    this.poolClosed = false,
  });

  final String raceId;
  final int raceNumber;
  final String venueCode;
  final String date;
  final String status;
  final DateTime? postTime;
  final int distanceMetres;
  final String going;
  final String surface;
  final String raceClass;
  final List<HkjcRacingRunner> runners;

  /// Win odds keyed by [HkjcRacingRunner.oddsKey].
  final Map<String, double> winOdds;
  final Map<String, double> placeOdds;

  /// `true` once HKJC stopped selling the pool, i.e. the quotes are final.
  final bool poolClosed;

  RacingOddsSnapshot? snapshot(DateTime capturedAt) {
    if (winOdds.length < 2) {
      return null;
    }
    return RacingOddsSnapshot(
      raceId: raceId,
      capturedAt: capturedAt,
      source: 'hkjc-win-pool',
      oddsByHorse: winOdds,
      raceTime: postTime,
      isFinal: poolClosed,
    );
  }
}

/// A public HKJC race meeting.
class HkjcRacingMeeting {
  const HkjcRacingMeeting({
    required this.date,
    required this.venueCode,
    required this.status,
    required this.races,
  });

  final String date;
  final String venueCode;
  final String status;
  final List<HkjcRacingRace> races;

  bool get open => status.toUpperCase() != 'CLOSED';
}

/// Read-only client for the public HKJC racing win/place pools.
///
/// Uses the same whitelisted GraphQL documents the public `bet.hkjc.com/ch/
/// racing` pages issue; only published prices, race cards and pool status are
/// read. The app never transmits a bet.
class HkjcRacingOddsService {
  HkjcRacingOddsService({
    this.endpoint = 'https://info.cld.hkjc.com/graphql/base/',
    this.minimumInterval = const Duration(milliseconds: 900),
  });

  static const _userAgent =
      'EdgeWise personal research mobile/1.0 '
      '(low-frequency cached access)';

  final String endpoint;
  final Duration minimumInterval;
  DateTime? _lastRequest;

  /// Meetings HKJC currently lists, most recent first.
  Future<List<({String date, String venueCode, String status})>>
  activeMeetings() async {
    final payload = await _post(meetingQuery, const {
      'date': '',
      'venueCode': '',
    });
    return parseActiveMeetings(payload);
  }

  /// Race cards and win/place pools of one meeting.
  Future<HkjcRacingMeeting?> meeting({
    required String date,
    required String venueCode,
  }) async {
    final card = await _post(meetingQuery, {
      'date': date,
      'venueCode': venueCode,
    });
    final parsed = parseMeeting(card, date: date, venueCode: venueCode);
    if (parsed == null || parsed.races.isEmpty) {
      return parsed;
    }
    final races = <HkjcRacingRace>[];
    for (final race in parsed.races) {
      final pools = await _post(poolQuery, {
        'date': date,
        'venueCode': venueCode,
        'raceNo': race.raceNumber,
        'oddsTypes': const ['WIN', 'PLA'],
      });
      races.add(withPools(race, pools));
    }
    return HkjcRacingMeeting(
      date: parsed.date,
      venueCode: parsed.venueCode,
      status: parsed.status,
      races: races,
    );
  }

  /// The meeting HKJC is currently selling, or `null` when there is none.
  Future<HkjcRacingMeeting?> currentMeeting() async {
    final meetings = await activeMeetings();
    if (meetings.isEmpty) {
      return null;
    }
    final open = meetings.where(
      (entry) => entry.status.toUpperCase() != 'CLOSED',
    );
    final selected = open.isNotEmpty ? open.first : meetings.first;
    return meeting(date: selected.date, venueCode: selected.venueCode);
  }

  List<({String date, String venueCode, String status})> parseActiveMeetings(
    Map<String, Object?> payload,
  ) {
    final meetings =
        ((payload['data'] as Map?)?['activeMeetings'] as List?) ?? const [];
    final parsed = <({String date, String venueCode, String status})>[];
    for (final entry in meetings) {
      final meeting = (entry as Map).cast<String, Object?>();
      final date = meeting['date'] as String? ?? '';
      final venueCode = meeting['venueCode'] as String? ?? '';
      if (date.isEmpty || venueCode.isEmpty) {
        continue;
      }
      parsed.add((
        date: date,
        venueCode: venueCode,
        status: meeting['status'] as String? ?? '',
      ));
    }
    parsed.sort((left, right) => right.date.compareTo(left.date));
    return parsed;
  }

  /// Parses the race cards of a `raceMeetings` payload.
  HkjcRacingMeeting? parseMeeting(
    Map<String, Object?> payload, {
    required String date,
    required String venueCode,
  }) {
    final meetings =
        ((payload['data'] as Map?)?['raceMeetings'] as List?) ?? const [];
    if (meetings.isEmpty) {
      return null;
    }
    final meeting = (meetings.first as Map).cast<String, Object?>();
    final meetingDate = meeting['date'] as String? ?? date;
    final meetingVenue = meeting['venueCode'] as String? ?? venueCode;
    final races = <HkjcRacingRace>[];
    for (final entry in (meeting['races'] as List?) ?? const []) {
      final race = (entry as Map).cast<String, Object?>();
      final raceNumber = (race['no'] as num?)?.toInt();
      if (raceNumber == null) {
        continue;
      }
      final track = (race['raceTrack'] as Map?)?.cast<String, Object?>();
      final trackName = track?['description_en'] as String? ?? '';
      final runners = <HkjcRacingRunner>[];
      for (final runnerEntry in (race['runners'] as List?) ?? const []) {
        final runner = (runnerEntry as Map).cast<String, Object?>();
        final horse = (runner['horse'] as Map?)?.cast<String, Object?>();
        final jockey = (runner['jockey'] as Map?)?.cast<String, Object?>();
        final trainer = (runner['trainer'] as Map?)?.cast<String, Object?>();
        runners.add(
          HkjcRacingRunner(
            runnerNo: runner['no'] as String? ?? '',
            horseCode: horse?['code'] as String? ?? '',
            nameChinese: runner['name_ch'] as String? ?? '',
            nameEnglish: runner['name_en'] as String? ?? '',
            status: runner['status'] as String? ?? '',
            draw: int.tryParse(runner['barrierDrawNumber'] as String? ?? ''),
            handicapWeight: double.tryParse(
              runner['handicapWeight'] as String? ?? '',
            ),
            rating: double.tryParse(runner['currentRating'] as String? ?? ''),
            lastSix: runner['last6run'] as String? ?? '',
            jockey: jockey?['name_ch'] as String? ?? '',
            trainer: trainer?['name_ch'] as String? ?? '',
            gearInfo: runner['gearInfo'] as String? ?? '',
            winOdds: double.tryParse(runner['winOdds'] as String? ?? ''),
            finalPosition: (runner['finalPosition'] as num?)?.toInt(),
          ),
        );
      }
      races.add(
        HkjcRacingRace(
          raceId: 'HK:$meetingDate:$meetingVenue:$raceNumber',
          raceNumber: raceNumber,
          venueCode: meetingVenue,
          date: meetingDate,
          status: race['status'] as String? ?? '',
          postTime: DateTime.tryParse(race['postTime'] as String? ?? ''),
          distanceMetres: (race['distance'] as num?)?.toInt() ?? 0,
          going: race['go_en'] as String? ?? '',
          surface: trackName.toUpperCase().contains('ALL WEATHER')
              ? 'AWT'
              : 'TURF',
          raceClass:
              race['claCode'] as String? ??
              race['raceClass_ch'] as String? ??
              race['raceClass_en'] as String? ??
              '',
          runners: runners,
          winOdds: {
            for (final runner in runners)
              if (!runner.scratched && (runner.winOdds ?? 0) > 1)
                runner.oddsKey: runner.winOdds!,
          },
          placeOdds: const {},
          poolClosed: false,
        ),
      );
    }
    races.sort((left, right) => left.raceNumber.compareTo(right.raceNumber));
    return HkjcRacingMeeting(
      date: meetingDate,
      venueCode: meetingVenue,
      status: meeting['status'] as String? ?? '',
      races: races,
    );
  }

  /// Merges a `pmPools` payload into [race], keeping the race card intact.
  HkjcRacingRace withPools(HkjcRacingRace race, Map<String, Object?> payload) {
    final meetings =
        ((payload['data'] as Map?)?['raceMeetings'] as List?) ?? const [];
    if (meetings.isEmpty) {
      return race;
    }
    final pools =
        (((meetings.first as Map).cast<String, Object?>()['pmPools'])
            as List?) ??
        const [];
    final keyByNumber = <String, String>{
      for (final runner in race.runners)
        runner.runnerNo.padLeft(2, '0'): runner.oddsKey,
    };
    final scratched = <String>{
      for (final runner in race.runners)
        if (runner.scratched) runner.runnerNo.padLeft(2, '0'),
    };
    var win = race.winOdds;
    var place = race.placeOdds;
    var closed = race.poolClosed;
    for (final poolEntry in pools) {
      final pool = (poolEntry as Map).cast<String, Object?>();
      final type = pool['oddsType'] as String? ?? '';
      if (type != 'WIN' && type != 'PLA') {
        continue;
      }
      final quotes = <String, double>{};
      for (final nodeEntry in (pool['oddsNodes'] as List?) ?? const []) {
        final node = (nodeEntry as Map).cast<String, Object?>();
        final number = (node['combString'] as String? ?? '').padLeft(2, '0');
        final odds = double.tryParse(node['oddsValue'] as String? ?? '');
        if (odds == null || odds <= 1 || scratched.contains(number)) {
          continue;
        }
        quotes[keyByNumber[number] ?? number] = odds;
      }
      if (quotes.isEmpty) {
        continue;
      }
      if (type == 'WIN') {
        win = quotes;
        closed =
            (pool['sellStatus'] as String? ?? '').toUpperCase() != 'AVAILABLE';
      } else {
        place = quotes;
      }
    }
    return HkjcRacingRace(
      raceId: race.raceId,
      raceNumber: race.raceNumber,
      venueCode: race.venueCode,
      date: race.date,
      status: race.status,
      postTime: race.postTime,
      distanceMetres: race.distanceMetres,
      going: race.going,
      surface: race.surface,
      raceClass: race.raceClass,
      runners: race.runners,
      winOdds: win,
      placeOdds: place,
      poolClosed: closed,
    );
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

  /// Whitelisted document used by the public racing pages for race cards.
  ///
  /// HKJC only accepts its own whitelisted documents, so this is byte-for-byte
  /// the document the public racing pages issue.
  static const meetingQuery = r'''
fragment raceFragment on Race {
  id
  no
  status
  raceName_en
  raceName_ch
  postTime
  country_en
  country_ch
  distance
  wageringFieldSize
  go_en
  go_ch
  ratingType
  raceTrack {
    description_en
    description_ch
  }
  raceCourse {
    description_en
    description_ch
    displayCode
  }
  claCode
  raceClass_en
  raceClass_ch
  judgeSigns {
    value_en
  }
}

fragment racingBlockFragment on RaceMeeting {
  jpEsts: pmPools(
    oddsTypes: [WIN, PLA, TCE, TRI, FF, QTT, DT, TT, SixUP]
    filters: ["jackpot", "estimatedDividend"]
  ) {
    leg {
      number
      races
    }
    oddsType
    jackpot
    estimatedDividend
    mergedPoolId
  }
  poolInvs: pmPools(
    oddsTypes: [WIN, PLA, QIN, QPL, CWA, CWB, CWC, IWN, FCT, TCE, TRI, FF, QTT, DBL, TBL, DT, TT, SixUP]
  ) {
    id
    leg {
      races
    }
  }
  penetrometerReadings(filters: ["first"]) {
    reading
    readingTime
  }
  hammerReadings(filters: ["first"]) {
    reading
    readingTime
  }
  changeHistories(filters: ["top3"]) {
    type
    time
    raceNo
    runnerNo
    horseName_ch
    horseName_en
    jockeyName_ch
    jockeyName_en
    scratchHorseName_ch
    scratchHorseName_en
    handicapWeight
    scrResvIndicator
  }
}

query raceMeetings($date: String, $venueCode: String) {
  timeOffset {
    rc
  }
  activeMeetings: raceMeetings {
    id
    venueCode
    date
    status
    races {
      no
      postTime
      status
      wageringFieldSize
    }
    poolInvs: pmPools(
      oddsTypes: [WIN, PLA, QIN, QPL, CWA, CWB, CWC, IWN, FCT, TCE, TRI, FF, QTT, DBL, TBL, DT, TT, SixUP]
    ) {
      status
    }
  }
  raceMeetings(date: $date, venueCode: $venueCode) {
    id
    status
    venueCode
    date
    totalNumberOfRace
    currentNumberOfRace
    dateOfWeek
    meetingType
    totalInvestment
    country {
      code
      namech
      nameen
      seq
    }
    races {
      ...raceFragment
      runners {
        id
        no
        standbyNo
        status
        name_ch
        name_en
        horse {
          id
          code
        }
        color
        barrierDrawNumber
        handicapWeight
        currentWeight
        currentRating
        internationalRating
        gearInfo
        racingColorFileName
        allowance
        trainerPreference
        last6run
        saddleClothNo
        trumpCard
        priority
        finalPosition
        deadHeat
        winOdds
        jockey {
          code
          name_en
          name_ch
        }
        trainer {
          code
          name_en
          name_ch
        }
      }
    }
    obSt: pmPools(oddsTypes: [WIN, PLA]) {
      leg {
        races
      }
      oddsType
      comingleStatus
    }
    poolInvs: pmPools(
      oddsTypes: [WIN, PLA, QIN, QPL, CWA, CWB, CWC, IWN, FCT, TCE, TRI, FF, QTT, DBL, TBL, DT, TT, SixUP]
    ) {
      id
      leg {
        number
        races
      }
      status
      sellStatus
      oddsType
      investment
      mergedPoolId
      lastUpdateTime
    }
    ...racingBlockFragment
    pmPools(oddsTypes: []) {
      id
    }
    jkcInstNo: foPools(oddsTypes: [JKC], filters: ["top"]) {
      instNo
    }
    tncInstNo: foPools(oddsTypes: [TNC], filters: ["top"]) {
      instNo
    }
  }
}''';

  /// Whitelisted document used by the public racing pages for win/place pools.
  static const poolQuery = r'''
query racing($date: String, $venueCode: String, $oddsTypes: [OddsType], $raceNo: Int) {
  raceMeetings(date: $date, venueCode: $venueCode) {
    pmPools(oddsTypes: $oddsTypes, raceNo: $raceNo) {
      id
      status
      sellStatus
      oddsType
      lastUpdateTime
      guarantee
      minTicketCost
      name_en
      name_ch
      leg {
        number
        races
      }
      cWinSelections {
        composite
        name_ch
        name_en
        starters
      }
      oddsNodes {
        combString
        oddsValue
        hotFavourite
        oddsDropValue
        bankerOdds {
          combString
          oddsValue
        }
      }
    }
  }
}''';
}
