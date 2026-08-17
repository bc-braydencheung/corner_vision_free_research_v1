import 'package:flutter/material.dart';

import '../models/football_mobile.dart';
import '../models/hkjc_football.dart';
import '../services/calibration_service.dart';
import '../models/team_news.dart';
import '../services/bivariate_corner_model.dart';
import '../services/corner_strength_model.dart';
import '../services/hkjc_corner_model.dart';
import '../services/hkjc_football_service.dart';
import '../services/market_anchor.dart';
import '../services/online_learning.dart';
import '../services/two_stage_corner_model.dart';

const _accent = Color(0xFF42E695);
const _purple = Color(0xFFB491FF);
const _blue = Color(0xFF6FA8FF);
const _amber = Color(0xFFFFC857);
const _grey = Color(0xFF7F8C8D);

/// Shows the HKJC fixtures, corner hi/lo odds, vig-free odds and the model
/// reading for the league currently selected in the football view.
class HkjcCornerSection extends StatelessWidget {
  const HkjcCornerSection({
    required this.snapshot,
    required this.leagueCode,
    required this.loading,
    required this.onRefresh,
    this.calibration,
    this.strengths,
    this.shotCorners,
    this.weather = const {},
    this.online,
    this.anchor,
    this.joint,
    this.teamNews = const {},
    super.key,
  });

  final HkjcFootballSnapshot? snapshot;
  final String leagueCode;
  final bool loading;
  final Future<void> Function() onRefresh;

  /// Corner-market calibration; absent until enough matches have settled.
  final MarketCalibration? calibration;

  /// Time-varying team corner strengths of this league, when fitted.
  final CornerStrengthTable? strengths;

  /// Two-stage shots/conversion/referee fit of this league, when fitted.
  final ShotCornerTable? shotCorners;

  /// Free kick-off forecasts keyed by HKJC match id.
  final Map<String, FootballWeatherSnapshot> weather;

  /// Online learning state of the corner market, when it has been replayed.
  final OnlineLearningState? online;

  /// Hedge-learned market anchor, when it has been measured.
  final MarketAnchorState? anchor;

  /// Measured home/away corner covariance of this league, when fitted.
  final BivariateCornerFit? joint;

  /// Free HKJC availability notes, keyed by the Chinese club name.
  final Map<String, TeamNewsSnapshot> teamNews;

  static String _homeName(HkjcFootballFixture fixture) =>
      fixture.homeTeamEnglish.isEmpty
      ? fixture.homeTeam
      : fixture.homeTeamEnglish;

  static String _awayName(HkjcFootballFixture fixture) =>
      fixture.awayTeamEnglish.isEmpty
      ? fixture.awayTeam
      : fixture.awayTeamEnglish;

  @override
  Widget build(BuildContext context) {
    if (!hkjcFootballProfiles.containsKey(leagueCode)) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF10291F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '此聯賽未接入馬會賽程',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              '目前只抓取馬會公開的英超及西甲賽程與角球大細盤，請切換至英超或西甲。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }
    final current = snapshot;
    final fixtures = current?.forLeague(leagueCode) ?? const [];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14382A), Color(0xFF0A1D15)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _purple.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.sports_soccer,
                  size: 18,
                  color: _purple,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '馬會賽程 · 角球大細',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      current == null
                          ? '正在讀取馬會賽程…'
                          : '馬會公開足球頁 · ${fixtures.length} 場 · '
                                '讀取於 ${_time(current.capturedAt)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '重新讀取馬會賠率',
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          if ((current?.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 13, color: _amber),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    current!.note,
                    style: const TextStyle(fontSize: 11, color: _amber),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (current == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (fixtures.isEmpty)
            Text(
              '馬會暫未開出此聯賽賽程',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          for (final fixture in fixtures) ...[
            _FixtureTile(
              fixture: fixture,
              assessment: HkjcCornerModel(
                calibration: calibration,
                prior: combineCornerPriors(
                  strengths?.priorFor(
                    homeTeam: _homeName(fixture),
                    awayTeam: _awayName(fixture),
                    kickOff: fixture.kickOffTime,
                  ),
                  shotCorners?.priorFor(
                    homeTeam: _homeName(fixture),
                    awayTeam: _awayName(fixture),
                    kickOff: fixture.kickOffTime,
                  ),
                ),
                weather: weather[fixture.matchId],
                online: online,
                anchor: anchor,
                joint: joint,
                homeNews: teamNews[fixture.homeTeam],
                awayNews: teamNews[fixture.awayTeam],
              ).assess(fixture),
            ),
            const SizedBox(height: 11),
          ],
          const SizedBox(height: 2),
          Text(
            calibration == null
                ? '校準狀態：未有已結算樣本，機率為原始模型分數。'
                : '校準狀態：${calibration!.report.verdict}',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: (calibration?.report.beatsBaseline ?? false)
                  ? _accent
                  : _amber,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '真實賠率＝除去馬會抽水後的同盤賠率；模型賠率＝以全部盤口聯合擬合的'
            '負二項（NB2）角球期望值重算，並按不確定度與時變隊伍角球評分混合。'
            '信心分數綜合期望值大小、各盤與模型的一致度、盤口數目、馬會抽水'
            '及隊伍評分方向，並非中獎機率。全部數字皆為研究參考，'
            '不構成任何投注建議。',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.42),
            ),
          ),
        ],
      ),
    );
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _FixtureTile extends StatelessWidget {
  const _FixtureTile({required this.fixture, required this.assessment});

  final HkjcFootballFixture fixture;
  final HkjcCornerAssessment? assessment;

  @override
  Widget build(BuildContext context) {
    final current = assessment;
    final odds = fixture.matchOdds;
    final local = fixture.kickOffTime.toLocal();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E241B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  children: [
                    Text(
                      '${local.month}/${local.day}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    Text(
                      '${local.hour.toString().padLeft(2, '0')}:'
                      '${local.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fixture.homeTeam,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      fixture.awayTeam,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (odds != null && odds.complete) ...[
            const SizedBox(height: 11),
            Row(
              children: [
                _OddsBox(label: '主', value: odds.home!),
                const SizedBox(width: 7),
                _OddsBox(label: '和', value: odds.draw!),
                const SizedBox(width: 7),
                _OddsBox(label: '客', value: odds.away!),
              ],
            ),
          ],
          const SizedBox(height: 11),
          if (current == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '角球大細盤未開出（馬會多在臨場前才開放此盤）',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            )
          else ...[
            Wrap(
              spacing: 7,
              runSpacing: 6,
              children: [
                _Chip(
                  label: '模型期望角球 ${current.expectedCorners.toStringAsFixed(2)}',
                  color: _accent,
                ),
                _Chip(
                  label:
                      '盤口一致度 '
                      '${_plainPercent((1 - current.lineDispersion * 20).clamp(0.0, 1.0))}',
                  color: _blue,
                ),
                _Chip(
                  label: '馬會抽水 ${_plainPercent(current.averageOverround)}',
                  color: _grey,
                ),
                if (current.priorExpectedCorners != null)
                  _Chip(
                    label:
                        '隊伍評分 '
                        '${current.priorExpectedCorners!.toStringAsFixed(2)}'
                        ' · 佔 ${_plainPercent(current.priorWeight)}',
                    color: _purple,
                  ),
                if (current.modelTrust < 1)
                  _Chip(
                    label:
                        '模型信任 ${_plainPercent(current.modelTrust)}'
                        '${current.drifting ? ' · 已偵測漂移' : ''}',
                    color: current.drifting ? _amber : _purple,
                  ),
                if (current.weatherNote != null)
                  _Chip(label: current.weatherNote!, color: _blue),
                if (current.newsNote != null)
                  _Chip(label: current.newsNote!, color: _amber),
                if (current.jointCorrelation != null)
                  _Chip(
                    label:
                        '主客角球 ρ '
                        '${current.jointCorrelation!.toStringAsFixed(2)}',
                    color: _blue,
                  ),
                if (current.dispersion > 0)
                  _Chip(
                    label:
                        '過度分散 α '
                        '${current.dispersion.toStringAsFixed(3)}',
                    color: _amber,
                  ),
              ],
            ),
            const SizedBox(height: 9),
            _RecommendationBox(
              recommendation: current.recommendation,
              observation: current.observation,
            ),
            const SizedBox(height: 10),
            const _LineHeader(),
            for (final line in current.lines) _LineRow(assessment: line),
          ],
        ],
      ),
    );
  }

  static String _plainPercent(double value) =>
      '${(value * 100).toStringAsFixed(1)}%';
}

class _OddsBox extends StatelessWidget {
  const _OddsBox({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            Text(
              value.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                color: _accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Model pick plus its confidence, or the declined side's own numbers.
///
/// A fixture the model will not back still shows the probability, confidence
/// and expected value of its least-bad side: a blank card reads as a fault.
class _RecommendationBox extends StatelessWidget {
  const _RecommendationBox({
    required this.recommendation,
    required this.observation,
  });

  final HkjcCornerRecommendation? recommendation;
  final HkjcCornerRecommendation? observation;

  @override
  Widget build(BuildContext context) {
    final pick = recommendation;
    final shown = pick ?? observation;
    final color = pick == null
        ? _grey
        : switch (pick.confidenceLabel) {
            '高' => _accent,
            '中' => _amber,
            _ => _purple,
          };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pick == null ? Icons.visibility_outlined : Icons.trending_up,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pick == null
                      ? '模型推介：不建議 · 各盤與模型一致'
                      : '模型推介：${pick.directionLabel} '
                            '${pick.line.line.condition}'
                            ' @ ${pick.odds.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          if (pick == null)
            Text(
              shown == null
                  ? '未有一邊的期望值高於門檻，此場只作觀察。'
                  : '未有一邊的期望值高於門檻，以下是模型最接近的一邊'
                        '（${shown.directionLabel} '
                        '${shown.line.line.condition}'
                        ' @ ${shown.odds.toStringAsFixed(2)}），只作觀察。',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          if (shown != null) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                Text(
                  '信心 ${shown.confidenceLabel}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: shown.confidence.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(shown.confidence * 100).toStringAsFixed(0)}/100',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '模型機率 ${(shown.winProbability * 100).toStringAsFixed(1)}%'
              ' · 市場真實機率 ${(_marketProbability(shown) * 100).toStringAsFixed(1)}%'
              ' · 期望值 ${_signed(shown.edge)}'
              '${pick == null ? '' : ' · 1/4 Kelly 注碼 '
                        '${(shown.stakeFraction * 100).toStringAsFixed(2)}%'}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _signed(double value) =>
      '${value >= 0 ? '+' : ''}${(value * 100).toStringAsFixed(1)}%';

  /// Vig-free market probability of the same side, for a like-for-like read.
  static double _marketProbability(HkjcCornerRecommendation pick) =>
      pick.direction == 'high'
      ? pick.line.marketHighProbability
      : pick.line.marketLowProbability;
}

class _LineHeader extends StatelessWidget {
  const _LineHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: Colors.white.withValues(alpha: 0.4),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(width: 74, child: Text('盤口', style: style)),
          Expanded(child: Text('馬會 大／細', style: style)),
          Expanded(child: Text('真實', style: style)),
          Expanded(child: Text('模型', style: style)),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.assessment});

  final HkjcCornerLineAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final line = assessment.line;
    final suspended = line.status != 'AVAILABLE';
    final style = TextStyle(
      fontSize: 11.5,
      color: Colors.white.withValues(alpha: suspended ? 0.35 : 0.78),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: line.main
            ? _accent.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(
              '${line.condition}${line.main ? ' ★' : ''}',
              style: style.copyWith(
                fontWeight: FontWeight.w800,
                color: line.main ? _accent : style.color,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '大${line.highOdds!.toStringAsFixed(2)}'
              ' / 細${line.lowOdds!.toStringAsFixed(2)}',
              style: style,
            ),
          ),
          Expanded(
            child: Text(
              '${assessment.fairHighOdds.toStringAsFixed(2)}'
              ' / ${assessment.fairLowOdds.toStringAsFixed(2)}',
              style: style,
            ),
          ),
          Expanded(
            child: Text(
              '${assessment.modelHighOdds.toStringAsFixed(2)}'
              ' / ${assessment.modelLowOdds.toStringAsFixed(2)}',
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
