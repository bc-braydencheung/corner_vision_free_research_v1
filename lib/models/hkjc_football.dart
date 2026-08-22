/// HKJC football (soccer) fixtures and corner hi/lo pools.
///
/// The data comes from the same public GraphQL endpoint that serves
/// `bet.hkjc.com/ch/football/home?tournid=...`. Only fixtures, market lines and
/// displayed odds are stored; the app never places or transmits any bet.
library;

/// A single hi/lo line of a corner (`CHL`) or total goals (`HIL`) pool.
class HkjcMarketLine {
  const HkjcMarketLine({
    required this.lineId,
    required this.condition,
    required this.line,
    required this.main,
    required this.status,
    required this.highOdds,
    required this.lowOdds,
  });

  factory HkjcMarketLine.fromJson(Map<String, Object?> json) => HkjcMarketLine(
    lineId: json['lineId'] as String? ?? '',
    condition: json['condition'] as String? ?? '',
    line: (json['line'] as num?)?.toDouble() ?? 0,
    main: json['main'] as bool? ?? false,
    status: json['status'] as String? ?? '',
    highOdds: (json['highOdds'] as num?)?.toDouble(),
    lowOdds: (json['lowOdds'] as num?)?.toDouble(),
  );

  final String lineId;

  /// Raw HKJC condition, e.g. `9.5` or the split line `9.5/10.0`.
  final String condition;

  /// Numeric handicap; the average of both halves for a split line.
  final double line;
  final bool main;
  final String status;
  final double? highOdds;
  final double? lowOdds;

  bool get available => status == 'AVAILABLE' && hasOdds;
  bool get hasOdds => highOdds != null && lowOdds != null;

  /// Both halves of a split line, or the single line when not split.
  List<double> get components {
    final parts = condition
        .split('/')
        .map((part) => double.tryParse(part.trim()))
        .whereType<double>()
        .toList();
    return parts.isEmpty ? [line] : parts;
  }

  Map<String, Object?> toJson() => {
    'lineId': lineId,
    'condition': condition,
    'line': line,
    'main': main,
    'status': status,
    'highOdds': highOdds,
    'lowOdds': lowOdds,
  };
}

/// Home/draw/away odds of the `HAD` pool.
class HkjcMatchOdds {
  const HkjcMatchOdds({
    required this.home,
    required this.draw,
    required this.away,
  });

  factory HkjcMatchOdds.fromJson(Map<String, Object?> json) => HkjcMatchOdds(
    home: (json['home'] as num?)?.toDouble(),
    draw: (json['draw'] as num?)?.toDouble(),
    away: (json['away'] as num?)?.toDouble(),
  );

  final double? home;
  final double? draw;
  final double? away;

  bool get complete => home != null && draw != null && away != null;

  Map<String, Object?> toJson() => {'home': home, 'draw': draw, 'away': away};
}

/// HKJC match statuses in which no ball has been kicked yet.
const preEventStatuses = <String>{'PREEVENT', 'NEXTMATCH', 'DEFINED', ''};

/// One HKJC fixture with the pools this app displays.
class HkjcFootballFixture {
  const HkjcFootballFixture({
    required this.matchId,
    required this.frontEndId,
    required this.leagueCode,
    required this.tournamentCode,
    required this.tournamentName,
    required this.kickOffTime,
    required this.status,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeTeamEnglish,
    required this.awayTeamEnglish,
    this.matchOdds,
    this.cornerLines = const [],
    this.goalLines = const [],
    this.homeCorner,
    this.awayCorner,
  });

  factory HkjcFootballFixture.fromJson(Map<String, Object?> json) =>
      HkjcFootballFixture(
        matchId: json['matchId'] as String? ?? '',
        frontEndId: json['frontEndId'] as String? ?? '',
        leagueCode: json['leagueCode'] as String? ?? '',
        tournamentCode: json['tournamentCode'] as String? ?? '',
        tournamentName: json['tournamentName'] as String? ?? '',
        kickOffTime:
            DateTime.tryParse(
              json['kickOffTime'] as String? ?? '',
            )?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        status: json['status'] as String? ?? '',
        homeTeam: json['homeTeam'] as String? ?? '',
        awayTeam: json['awayTeam'] as String? ?? '',
        homeTeamEnglish: json['homeTeamEnglish'] as String? ?? '',
        awayTeamEnglish: json['awayTeamEnglish'] as String? ?? '',
        matchOdds: json['matchOdds'] == null
            ? null
            : HkjcMatchOdds.fromJson(
                (json['matchOdds'] as Map).cast<String, Object?>(),
              ),
        cornerLines: _lines(json['cornerLines']),
        goalLines: _lines(json['goalLines']),
        homeCorner: (json['homeCorner'] as num?)?.toInt(),
        awayCorner: (json['awayCorner'] as num?)?.toInt(),
      );

  final String matchId;
  final String frontEndId;

  /// Football-data style league code used by the rest of the app (`E0`, `SP1`).
  final String leagueCode;
  final String tournamentCode;
  final String tournamentName;
  final DateTime kickOffTime;
  final String status;
  final String homeTeam;
  final String awayTeam;
  final String homeTeamEnglish;
  final String awayTeamEnglish;
  final HkjcMatchOdds? matchOdds;
  final List<HkjcMarketLine> cornerLines;
  final List<HkjcMarketLine> goalLines;
  final int? homeCorner;
  final int? awayCorner;

  bool get hasCornerMarket => cornerLines.any((line) => line.hasOdds);

  /// Whether play has begun, so the quotes already price corners on the pitch.
  ///
  /// A pre-match model must never be read against an in-play price, so a
  /// fixture counts as started once HKJC leaves its pre-event status or once
  /// its kick-off time has passed, whichever comes first.
  bool startedBy(DateTime asOf) =>
      !kickOffTime.isAfter(asOf) || !preEventStatuses.contains(status);

  HkjcMarketLine? get mainCornerLine {
    final withOdds = cornerLines.where((line) => line.hasOdds).toList();
    if (withOdds.isEmpty) {
      return null;
    }
    return withOdds.firstWhere(
      (line) => line.main,
      orElse: () => withOdds.first,
    );
  }

  static List<HkjcMarketLine> _lines(Object? value) => value is List
      ? value
            .map(
              (item) => HkjcMarketLine.fromJson(
                (item as Map).cast<String, Object?>(),
              ),
            )
            .toList()
      : const [];

  Map<String, Object?> toJson() => {
    'matchId': matchId,
    'frontEndId': frontEndId,
    'leagueCode': leagueCode,
    'tournamentCode': tournamentCode,
    'tournamentName': tournamentName,
    'kickOffTime': kickOffTime.toIso8601String(),
    'status': status,
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    'homeTeamEnglish': homeTeamEnglish,
    'awayTeamEnglish': awayTeamEnglish,
    'matchOdds': matchOdds?.toJson(),
    'cornerLines': cornerLines.map((line) => line.toJson()).toList(),
    'goalLines': goalLines.map((line) => line.toJson()).toList(),
    'homeCorner': homeCorner,
    'awayCorner': awayCorner,
  };
}

/// Cached snapshot of the HKJC fixtures for the tracked tournaments.
class HkjcFootballSnapshot {
  const HkjcFootballSnapshot({
    required this.capturedAt,
    required this.fixtures,
    this.note = '',
  });

  factory HkjcFootballSnapshot.fromJson(Map<String, Object?> json) =>
      HkjcFootballSnapshot(
        capturedAt:
            DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        fixtures: (json['fixtures'] as List? ?? const [])
            .map(
              (item) => HkjcFootballFixture.fromJson(
                (item as Map).cast<String, Object?>(),
              ),
            )
            .toList(),
        note: json['note'] as String? ?? '',
      );

  final DateTime capturedAt;
  final List<HkjcFootballFixture> fixtures;
  final String note;

  List<HkjcFootballFixture> forLeague(String leagueCode) =>
      fixtures.where((fixture) => fixture.leagueCode == leagueCode).toList()
        ..sort((a, b) => a.kickOffTime.compareTo(b.kickOffTime));

  /// Fixtures of the league that have not kicked off yet, in kick-off order.
  List<HkjcFootballFixture> upcomingForLeague(
    String leagueCode, {
    required DateTime asOf,
  }) => forLeague(
    leagueCode,
  ).where((fixture) => !fixture.startedBy(asOf)).toList();

  Map<String, Object?> toJson() => {
    'capturedAt': capturedAt.toIso8601String(),
    'fixtures': fixtures.map((fixture) => fixture.toJson()).toList(),
    'note': note,
  };
}
