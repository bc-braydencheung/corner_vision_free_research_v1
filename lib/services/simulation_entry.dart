import '../models/forecast_data.dart';
import '../models/hkjc_football.dart';
import '../models/simulation_draft.dart';
import 'corner_alerts.dart';
import 'hkjc_corner_model.dart';
import 'racing_alerts.dart';
import 'research_alerts.dart';

/// The pick a fixture card is offering, exactly as the card printed it.
///
/// The line, price and probabilities are read off the assessment the card
/// rendered, so the ledger cannot record a price the user never saw. Only a
/// cleared recommendation should be offered; [recommended] records which of the
/// two the row came from so an observation can never be counted as a pick.
SimulationDraft cornerSimulationDraft({
  required String leagueCode,
  required String leagueName,
  required HkjcFootballFixture fixture,
  required HkjcCornerRecommendation pick,
  required bool recommended,
  DateTime? capturedAt,
}) {
  final high = pick.direction == 'high';
  return SimulationDraft(
    sport: 'football',
    marketType: 'corners',
    matchId: fixture.matchId,
    leagueCode: leagueCode,
    leagueName: leagueName,
    homeTeam: fixture.homeTeam,
    awayTeam: fixture.awayTeam,
    startTime: fixture.kickOffTime,
    selectionLabel: '角球 ${pick.line.line.condition} ${pick.directionLabel}',
    direction: high ? 'over' : 'under',
    line: pick.line.line.line,
    odds: pick.odds,
    modelProbability: high
        ? pick.line.modelHighProbability
        : pick.line.modelLowProbability,
    marketProbability: high
        ? pick.line.marketHighProbability
        : pick.line.marketLowProbability,
    edge: pick.edge,
    confidence: pick.confidence,
    confidenceLabel: pick.confidenceLabel,
    recommended: recommended,
    pushProbability: pick.line.modelPushProbability,
    stakeFraction: pick.stakeFraction,
    marketSource: '馬會足球角球盤',
    marketCapturedAt: capturedAt,
  );
}

/// The pick a runner row is offering, priced off the stored win pool.
SimulationDraft racingSimulationDraft({
  required RacingRace race,
  required RacingRunner runner,
  required double marketOdds,
  required double marketProbability,
  DateTime? capturedAt,
}) {
  return SimulationDraft(
    sport: 'racing',
    marketType: 'win',
    matchId: race.raceId,
    leagueCode: 'HK',
    leagueName: '香港賽馬',
    homeTeam: runner.horseNameChinese.isNotEmpty
        ? runner.horseNameChinese
        : runner.horseName,
    awayTeam: '${race.venue}第${race.raceNumber}場',
    startTime: race.startTime,
    selectionLabel: '獨贏 ${runner.number} 號',
    direction: 'win',
    line: 0,
    odds: marketOdds,
    modelProbability: runner.winProbability,
    marketProbability: marketProbability,
    edge: runner.winProbability * marketOdds - 1,
    confidence: runner.confidenceScore,
    confidenceLabel: switch (runner.confidence) {
      'high' => '高',
      'medium' => '中',
      _ => '低',
    },
    recommended: runner.recommendation != 'no-prediction',
    selectionId: runner.horseId,
    stakeFraction: _quarterKelly(
      edge: runner.winProbability * marketOdds - 1,
      odds: marketOdds,
    ),
    marketSource: '馬會獨贏池',
    marketCapturedAt: capturedAt,
  );
}

/// The pick behind a summary-card row, whichever sport it came from.
///
/// Returns null for an alert shape this build does not know how to price, which
/// is better than guessing a line or a price for it.
SimulationDraft? simulationDraftFromAlert(ResearchAlert alert) {
  if (alert is CornerAlert) {
    return cornerSimulationDraft(
      leagueCode: alert.leagueCode,
      leagueName: alert.leagueName,
      fixture: alert.fixture,
      pick: alert.recommendation,
      recommended: true,
    );
  }
  if (alert is RacingAlert) {
    return racingSimulationDraft(
      race: alert.race,
      runner: alert.runner,
      marketOdds: alert.marketOdds,
      marketProbability: alert.marketProbability,
      capturedAt: alert.capturedAt,
    );
  }
  return null;
}

double _quarterKelly({required double edge, required double odds}) {
  final profit = odds - 1;
  if (profit <= 0 || edge <= 0) {
    return 0;
  }
  final fraction = edge / profit / 4;
  return fraction > 0.05 ? 0.05 : fraction;
}
