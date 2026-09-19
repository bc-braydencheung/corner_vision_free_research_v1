import '../models/football_mobile.dart';
import '../models/hkjc_football.dart';
import '../models/pick_status.dart';
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
    required this.status,
  });

  final String leagueCode;

  /// Display name of the league, or the league code when none is known.
  final String leagueName;
  final HkjcFootballFixture fixture;
  final HkjcCornerRecommendation recommendation;

  @override
  final PickStatus status;

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

/// Proof standing behind the first choice a corner assessment offers.
///
/// Shared by the banner and the fixture card so the two cannot disagree about
/// the same fixture: only a pick that cleared the edge threshold while the
/// market audit says the model beats the market is green, and an assessment
/// made while the audit is suspended or the model is drifting is red however
/// good the number looks.
PickStatus cornerPickStatus({
  required HkjcCornerAssessment assessment,
  required bool audited,
}) {
  if (assessment.suspended || assessment.drifting) {
    return PickStatus.insufficient;
  }
  return assessment.recommendation != null && audited
      ? PickStatus.verified
      : PickStatus.unverified;
}

/// Every fixture's first choice across the HKJC leagues, best edge first.
///
/// Thresholds are not relaxed, they are labelled: a fixture that clears the
/// edge threshold while the model is audited as beating the market is
/// [PickStatus.verified], anything else the model merely prefers is
/// [PickStatus.unverified], and a fixture assessed while the audit is
/// suspended or the model is drifting is [PickStatus.insufficient]. A fixture
/// with no priceable corner line still yields nothing, since there is no
/// selection to name. Fixtures whose kick-off has passed are dropped, since
/// their quote is no longer takeable.
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
      if (assessment == null) {
        continue;
      }
      final pick = assessment.recommendation ?? assessment.observation;
      if (pick == null) {
        continue;
      }
      alerts.add(
        CornerAlert(
          leagueCode: code,
          leagueName: leagueNames[code] ?? code,
          fixture: fixture,
          recommendation: pick,
          status: cornerPickStatus(
            assessment: assessment,
            audited: calibration?.report.beatsBaseline ?? false,
          ),
        ),
      );
    }
  }
  alerts.sort((a, b) {
    final byStatus = a.status.index.compareTo(b.status.index);
    return byStatus != 0 ? byStatus : b.edge.compareTo(a.edge);
  });
  return alerts;
}
