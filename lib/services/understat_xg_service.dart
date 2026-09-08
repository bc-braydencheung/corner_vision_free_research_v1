import 'dart:convert';
import 'dart:io';

import '../models/football_mobile.dart';
import 'hkjc_shadow.dart';

/// Understat's own name for each division carried by the free history.
///
/// A division absent here simply never receives an expected-goals reading; it
/// is never filled in from a neighbouring league.
const understatLeagues = <String, String>{
  'E0': 'EPL',
  'SP1': 'La_liga',
  'D1': 'Bundesliga',
  'I1': 'Serie_A',
  'F1': 'Ligue_1',
};

/// Clubs the two feeds spell so differently that dropping punctuation is not
/// enough, keyed by the normalised Understat name.
///
/// Every value is still looked up in the division's own history before it is
/// used, so an entry naming a club that division does not carry is skipped like
/// any other unresolved name.
const _aliases = <String, String>{
  'manchestercity': 'Man City',
  'manchesterunited': 'Man United',
  'newcastleunited': 'Newcastle',
  'nottinghamforest': "Nott'm Forest",
  'wolverhamptonwanderers': 'Wolves',
  'westham': 'West Ham',
  'tottenham': 'Tottenham',
  'leedsunited': 'Leeds',
  'leicester': 'Leicester',
  'sheffieldunited': 'Sheffield United',
  'westbromwichalbion': 'West Brom',
  'atleticomadrid': 'Ath Madrid',
  'athleticclub': 'Ath Bilbao',
  'realsociedad': 'Sociedad',
  'realbetis': 'Betis',
  'realvalladolid': 'Valladolid',
  'realmadrid': 'Real Madrid',
  'celtavigo': 'Celta',
  'rayovallecano': 'Vallecano',
  'espanyol': 'Espanol',
  'deportivoalaves': 'Alaves',
  'realoviedo': 'Oviedo',
  'internazionale': 'Inter',
  'acmilan': 'Milan',
  'hellasverona': 'Verona',
  'parissaintgermain': 'Paris SG',
  'saintetienne': 'St Etienne',
  'bayernmunich': 'Bayern Munich',
  'borussiadortmund': 'Dortmund',
  'borussiamgladbach': "M'gladbach",
  'bayerleverkusen': 'Leverkusen',
  'eintrachtfrankfurt': 'Ein Frankfurt',
  'schalke04': 'Schalke 04',
  'werderbremen': 'Werder Bremen',
  'rbleipzig': 'RB Leipzig',
  'fcheidenheim': 'Heidenheim',
  'fckoln': 'FC Koln',
  'mainz05': 'Mainz',
  'hamburgersv': 'Hamburg',
};

/// One settled match as Understat publishes it.
class UnderstatXgRecord {
  const UnderstatXgRecord({
    required this.division,
    required this.date,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeXg,
    required this.awayXg,
  });

  final String division;

  /// Kick-off day in UTC, as `yyyy-MM-dd`.
  final String date;
  final String homeTeam;
  final String awayTeam;
  final double homeXg;
  final double awayXg;
}

/// What a merge managed to attach to the stored history.
class UnderstatXgCoverage {
  const UnderstatXgCoverage({
    required this.readings,
    required this.matched,
    required this.settledRows,
    required this.rowsWithXg,
  });

  /// Settled matches the free feed published.
  final int readings;

  /// Readings this run attached to a stored match.
  final int matched;

  /// Settled matches in the stored history of the covered divisions.
  final int settledRows;

  /// Stored matches that carry an expected-goals reading after the merge.
  final int rowsWithXg;

  /// Readings that could not be tied to a stored match, so were dropped.
  int get unmatched => readings - matched;

  double get fraction => settledRows == 0 ? 0 : rowsWithXg / settledRows;

  String get summary => settledRows == 0
      ? '尚未有已結算賽果，未能對應 xG'
      : '$rowsWithXg／$settledRows 場有 xG'
            '${unmatched > 0 ? ' · $unmatched 場讀數對不上，已略過' : ''}';
}

class UnderstatXgMerge {
  const UnderstatXgMerge({required this.dataset, required this.coverage});

  final MobileFootballDataset dataset;
  final UnderstatXgCoverage coverage;
}

/// Settled matches carried by one Understat league payload.
///
/// The feed publishes a fixture before it is played, so a row without both
/// readings is dropped rather than stored as a goalless performance.
List<UnderstatXgRecord> parseUnderstatLeagueData(
  String body, {
  required String division,
}) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const FormatException('Unexpected Understat payload.');
  }
  final dates = decoded['dates'];
  if (dates is! List) {
    throw const FormatException('Understat payload carries no matches.');
  }
  final output = <UnderstatXgRecord>[];
  for (final entry in dates) {
    if (entry is! Map) {
      continue;
    }
    if (entry['isResult'] != true) {
      continue;
    }
    final home = (entry['h'] as Map?)?['title'];
    final away = (entry['a'] as Map?)?['title'];
    final xg = entry['xG'];
    final stamp = entry['datetime'];
    if (home is! String || away is! String || xg is! Map || stamp is! String) {
      continue;
    }
    final homeXg = _number(xg['h']);
    final awayXg = _number(xg['a']);
    final date = DateTime.tryParse(stamp);
    if (homeXg == null || awayXg == null || date == null) {
      continue;
    }
    output.add(
      UnderstatXgRecord(
        division: division,
        date: date.toIso8601String().substring(0, 10),
        homeTeam: home,
        awayTeam: away,
        homeXg: homeXg,
        awayXg: awayXg,
      ),
    );
  }
  return output;
}

/// [dataset] with every reading that can be tied to a stored match attached.
///
/// Matching needs the division, both club names and a kick-off day within one
/// day of the stored one — the two feeds file a late kick-off on either side of
/// midnight. A reading whose clubs the division's history does not carry is
/// dropped, never stored under a name of its own.
UnderstatXgMerge mergeUnderstatXg({
  required MobileFootballDataset dataset,
  required List<UnderstatXgRecord> readings,
}) {
  final canonical = <String, String>{};
  for (final row in dataset.rows) {
    canonical['${row.division}:${normaliseTeamKey(row.homeTeam)}'] =
        row.homeTeam;
    canonical['${row.division}:${normaliseTeamKey(row.awayTeam)}'] =
        row.awayTeam;
  }
  final byKey = <String, UnderstatXgRecord>{};
  for (final reading in readings) {
    final home = _resolve(canonical, reading.division, reading.homeTeam);
    final away = _resolve(canonical, reading.division, reading.awayTeam);
    final date = DateTime.tryParse(reading.date);
    if (home == null || away == null || home == away || date == null) {
      continue;
    }
    for (final shift in const [0, -1, 1]) {
      final day = date
          .add(Duration(days: shift))
          .toIso8601String()
          .substring(0, 10);
      byKey.putIfAbsent('${reading.division}:$day:$home:$away', () => reading);
    }
  }
  final divisions = readings.map((reading) => reading.division).toSet();
  final rows = <FootballMatchRecord>[];
  final used = <UnderstatXgRecord>{};
  var settled = 0;
  var withXg = 0;
  for (final row in dataset.rows) {
    final tracked = divisions.contains(row.division);
    if (tracked && row.isComplete) {
      settled++;
    }
    final reading = row.homeXg == null ? byKey[row.matchId] : null;
    final merged = reading == null
        ? row
        : row.withXg(home: reading.homeXg, away: reading.awayXg);
    if (reading != null) {
      used.add(reading);
    }
    if (tracked && row.isComplete && merged.homeXg != null) {
      withXg++;
    }
    rows.add(merged);
  }
  final matched = used.length;
  if (matched == 0) {
    return UnderstatXgMerge(
      dataset: dataset,
      coverage: UnderstatXgCoverage(
        readings: readings.length,
        matched: 0,
        settledRows: settled,
        rowsWithXg: withXg,
      ),
    );
  }
  return UnderstatXgMerge(
    dataset: MobileFootballDataset(
      schemaVersion: dataset.schemaVersion,
      // The version has to move with the readings, or a training job resumed
      // from a checkpoint would keep training on the history without them.
      datasetVersion: '${dataset.datasetVersion}+xg$matched',
      generatedAt: dataset.generatedAt,
      leagues: dataset.leagues,
      rows: rows,
      fixtures: dataset.fixtures,
    ),
    coverage: UnderstatXgCoverage(
      readings: readings.length,
      matched: matched,
      settledRows: settled,
      rowsWithXg: withXg,
    ),
  );
}

/// Reads the free Understat expected-goals feed.
///
/// The feed is a public web page's own data call, not a supported API: it is
/// requested at most once per season per sync, and any failure leaves the
/// history exactly as it was rather than guessing a reading.
class UnderstatXgService {
  UnderstatXgService({
    this.fetchOverride,
    this.baseUrl = 'https://understat.com',
    this.minimumInterval = const Duration(milliseconds: 700),
  });

  /// Reader used instead of the network, for tests.
  final Future<String> Function(Uri uri)? fetchOverride;
  final String baseUrl;
  final Duration minimumInterval;
  DateTime? _lastRequest;

  /// Seasons to read, newest first, for a sync run at [asOf].
  ///
  /// Understat names a season by the year it starts in, and the free history
  /// only needs the rounds the model has not seen yet.
  static List<String> seasonsFor(DateTime asOf) {
    final start = asOf.month >= 7 ? asOf.year : asOf.year - 1;
    return ['$start', '${start - 1}'];
  }

  Future<List<UnderstatXgRecord>> fetchLeague({
    required String division,
    required String season,
  }) async {
    final league = understatLeagues[division];
    if (league == null) {
      return const [];
    }
    final body = await _fetch(
      Uri.parse('$baseUrl/main/getLeagueData/$league/$season'),
    );
    return parseUnderstatLeagueData(body, division: division);
  }

  /// Every reading the feed will give for [divisions], skipping any league or
  /// season the feed refuses rather than failing the whole sync.
  Future<List<UnderstatXgRecord>> fetchAll({
    required Iterable<String> divisions,
    required DateTime asOf,
  }) async {
    final output = <UnderstatXgRecord>[];
    for (final division in divisions.toSet()) {
      if (!understatLeagues.containsKey(division)) {
        continue;
      }
      for (final season in seasonsFor(asOf)) {
        try {
          output.addAll(await fetchLeague(division: division, season: season));
        } on Object {
          continue;
        }
      }
    }
    return output;
  }

  Future<String> _fetch(Uri uri) async {
    final override = fetchOverride;
    if (override != null) {
      return override(uri);
    }
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
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.userAgentHeader, 'EdgeWise/6.0');
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set(
        HttpHeaders.refererHeader,
        '$baseUrl/league/${uri.pathSegments.length > 2 ? uri.pathSegments[2] : ''}',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (response.statusCode != 200) {
        throw HttpException('${response.statusCode} for $uri');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}

double? _number(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

String? _resolve(Map<String, String> canonical, String division, String name) {
  final key = normaliseTeamKey(name);
  final alias = _aliases[key];
  return canonical['$division:$key'] ??
      (alias == null
          ? null
          : canonical['$division:${normaliseTeamKey(alias)}']);
}
