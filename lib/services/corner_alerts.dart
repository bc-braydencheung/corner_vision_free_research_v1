import '../models/football_mobile.dart';
import '../models/hkjc_football.dart';
import '../models/team_news.dart';
import 'calibration_service.dart';
import 'corner_strength_service.dart';
import 'hkjc_corner_model.dart';
import 'hkjc_football_service.dart';
import 'market_anchor.dart';
import 'market_residual.dart';
import 'online_learning.dart';
import 'research_alerts.dart';
import 'two_stage_corner_model.dart';

/// One fixture the model is willing to back, kept with the league it sits in.
///
/// Reading every fixture of every league to find out whether anything cleared
/// the threshold is the thing this exists to remove: the same assessment the
/// fixture tile renders is surfaced once, at the top.
class CornerAlert implements ResearchAlert {
  const CornerAlert({
    required this.leagueCode,
    required this.leagueName,
    required this.fixture,
    required this.recommendation,
  });

  final String leagueCode;

  /// Display name of the league, or the league code when none is known.
  final String leagueName;
  final HkjcFootballFixture fixture;
  final HkjcCornerRecommendation recommendation;

  String get directionLabel => recommendation.directionLabel;
  String get condition => recommendation.line.line.condition;

  @override
  double get odds => recommendation.odds;

  @override
  double get edge => recommendation.edge;

  @override
  double get confidence => recommendation.confidence;

  @override
  String get confidenceLabel => recommendation.confidenceLabel;

  @override
  String get context => leagueName;

  @override
  String get subject => '${fixture.homeTeam} 對 ${fixture.awayTeam}';

  @override
  String get market => '角球 $condition $directionLabel';

  @override
  DateTime get startTime => fixture.kickOffTime;
}

/// Every recommendation across the HKJC leagues, best edge first.
///
/// The thresholds are untouched: a fixture only appears here when the same
/// [HkjcCornerModel] the tile uses returns a recommendation for it, so this
/// never invents a pick to keep the banner occupied. Fixtures whose kick-off
/// has passed are dropped, since their quote is no longer takeable. While
/// [suspended] is set — the forward-looking error audit is in its stop state —
/// the model returns no recommendation at all, so this list is empty by
/// construction rather than by a second rule kept in step with the tiles.
List<CornerAlert> buildCornerAlerts({
  required HkjcFootballSnapshot? snapshot,
  required Map<String, String> leagueNames,
  required DateTime asOf,
  MarketCalibration? calibration,
  CornerPriorTables priors = CornerPriorTables.empty,
  Map<String, FootballWeatherSnapshot> weather = const {},
  Map<String, TeamNewsSnapshot> teamNews = const {},
  OnlineLearningState? online,
  MarketAnchorState? anchor,
  MarketResidualState? residual,
  bool suspended = false,
}) {
  final current = snapshot;
  if (current == null) {
    return const [];
  }
  final alerts = <CornerAlert>[];
  for (final code in hkjcFootballProfiles.keys) {
    final strengths = priors.strengths[code];
    final shots = priors.shots[code];
    final joint = priors.joint[code];
    for (final fixture in current.forLeague(code)) {
      if (fixture.startedBy(asOf)) {
        continue;
      }
      final home = fixture.homeTeamEnglish.isEmpty
          ? fixture.homeTeam
          : fixture.homeTeamEnglish;
      final away = fixture.awayTeamEnglish.isEmpty
          ? fixture.awayTeam
          : fixture.awayTeamEnglish;
      final assessment = HkjcCornerModel(
        calibration: calibration,
        prior: combineCornerPriors(
          strengths?.priorFor(
            homeTeam: home,
            awayTeam: away,
            kickOff: fixture.kickOffTime,
          ),
          shots?.priorFor(
            homeTeam: home,
            awayTeam: away,
            kickOff: fixture.kickOffTime,
          ),
        ),
        weather: weather[fixture.matchId],
        online: online,
        anchor: anchor,
        residual: residual,
        joint: joint,
        homeNews: teamNews[fixture.homeTeam],
        awayNews: teamNews[fixture.awayTeam],
        suspended: suspended,
      ).assess(fixture);
      final pick = assessment?.recommendation;
      if (pick == null) {
        continue;
      }
      alerts.add(
        CornerAlert(
          leagueCode: code,
          leagueName: leagueNames[code] ?? code,
          fixture: fixture,
          recommendation: pick,
        ),
      );
    }
  }
  alerts.sort((a, b) => b.edge.compareTo(a.edge));
  return alerts;
}
