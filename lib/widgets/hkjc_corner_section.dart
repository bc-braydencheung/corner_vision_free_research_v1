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
import '../services/market_residual.dart';
import '../services/odds_movement.dart';
import '../services/online_learning.dart';
import '../services/staked_selections.dart';
import '../services/two_stage_corner_model.dart';
import '../theme/app_theme.dart';
import 'motion.dart';
import 'scroll_focus.dart';

const _accent = AppPalette.mint;
const _purple = AppPalette.violet;
const _blue = AppPalette.cyan;
const _amber = AppPalette.amber;
const _grey = AppPalette.slate;

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
    this.residual,
    this.joint,
    this.teamNews = const {},
    this.focusMatchId,
    this.focusRequest = 0,
    this.suspended = false,
    this.onAddSimulation,
    this.staked = StakedSelections.empty,
    this.oddsHistory = const [],
    this.asOf,
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

  /// Learned deviation from the quoted price, when it has been measured.
  final MarketResidualState? residual;

  /// Measured home/away corner covariance of this league, when fitted.
  final BivariateCornerFit? joint;

  /// Free HKJC availability notes, keyed by the Chinese club name.
  final Map<String, TeamNewsSnapshot> teamNews;

  /// Fixture a tapped pick pointed at; it is scrolled to and outlined.
  final String? focusMatchId;

  /// Bumped by every pick tap, so repeating the same pick navigates again.
  final int focusRequest;

  /// Whether the forward-looking error audit has stopped new picks.
  final bool suspended;

  /// Records the fixture's cleared pick in the simulated account, when offered.
  final void Function(HkjcFootballFixture, HkjcCornerRecommendation)?
  onAddSimulation;

  /// Picks the simulated account already holds, so a card can say so instead of
  /// letting the same bet be recorded twice.
  final StakedSelections staked;

  /// Append-only HKJC corner quote history, used to read how the market moved
  /// at 24h, 6h and 1h before kick-off.
  final List<FootballOddsSnapshot> oddsHistory;

  /// Moment the pre-match cut-off is measured against; defaults to now.
  final DateTime? asOf;

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
      return GradientCard(
        accent: _amber,
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 17, color: _amber),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                '此聯賽未接入馬會賽程',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }
    final current = snapshot;
    final asOf = this.asOf ?? DateTime.now();
    final all = current?.forLeague(leagueCode) ?? const <HkjcFootballFixture>[];
    final fixtures =
        current?.upcomingForLeague(leagueCode, asOf: asOf) ??
        const <HkjcFootballFixture>[];
    final started = all.length - fixtures.length;
    final movements = oddsHistory.isEmpty
        ? const <String, FixtureOddsMovement>{}
        : cornerMovements(
            snapshots: oddsHistory,
            kickOffs: {
              for (final fixture in all) fixture.matchId: fixture.kickOffTime,
            },
          );
    return GradientCard(
      accent: _purple,
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
                          ? '讀取中…'
                          : '${fixtures.length} 場 · '
                                '${_time(current.capturedAt)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '計算方法及研究聲明',
                onPressed: () => _showMethodSheet(context),
                icon: const Icon(Icons.info_outline, size: 18),
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
              started > 0 ? '此聯賽的馬會賽事已全部開賽' : '馬會暫未開出此聯賽賽程',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          if (started > 0) ...[
            GlowPill(
              label: '已開賽 $started 場（不作賽前分析）',
              color: _grey,
              dense: true,
            ),
            const SizedBox(height: 8),
          ],
          for (final (index, fixture) in fixtures.indexed) ...[
            ScrollFocusTarget(
              key: ValueKey('focus-${fixture.matchId}'),
              focused: fixture.matchId == focusMatchId,
              request: focusRequest,
              child: StaggerIn(
                index: index,
                child: _FixtureTile(
                  fixture: fixture,
                  focused: fixture.matchId == focusMatchId,
                  focusRequest: focusRequest,
                  onAddSimulation: onAddSimulation,
                  staked: staked,
                  movement: movements[fixture.matchId],
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
                    residual: residual,
                    joint: joint,
                    homeNews: teamNews[fixture.homeTeam],
                    awayNews: teamNews[fixture.awayTeam],
                    suspended: suspended,
                  ).assess(fixture),
                ),
              ),
            ),
            const SizedBox(height: 11),
          ],
          if (calibration != null)
            GlowPill(
              label: '校準 ${calibration!.report.badge}',
              color: calibration!.report.beatsBaseline ? _accent : _amber,
              dense: true,
            ),
        ],
      ),
    );
  }

  /// Shows how the card's numbers are derived, plus the research-only notice.
  ///
  /// The wording is kept verbatim and only moved off the card: it is read once,
  /// while the fixtures under it are read daily.
  void _showMethodSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppPalette.surfaceHigh,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '計算方法',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 10),
            Text(
              calibration == null
                  ? '校準狀態：未有已結算樣本，機率為原始模型分數。'
                  : '校準狀態：${calibration!.report.verdict}',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: (calibration?.report.beatsBaseline ?? false)
                    ? _accent
                    : _amber,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '真實賠率＝除去馬會抽水後的同盤賠率；模型賠率＝以全部盤口聯合擬合的'
              '負二項（NB2）角球期望值重算，並按不確定度與時變隊伍角球評分混合。'
              '信心分數綜合期望值大小、各盤與模型的一致度、盤口數目、馬會抽水'
              '及隊伍評分方向，並非中獎機率。全部數字皆為研究參考，'
              '不構成任何投注建議。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
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

/// One fixture, collapsed to its verdict until it is opened.
///
/// A league round is a dozen fixtures deep in odds tables, so the closed card
/// keeps only what decides whether to read further — kick-off, the two teams and
/// the pick (or 不建議) — and the fixture a tapped pick pointed at opens itself.
class _FixtureTile extends StatefulWidget {
  const _FixtureTile({
    required this.fixture,
    required this.assessment,
    this.focused = false,
    this.focusRequest = 0,
    this.onAddSimulation,
    this.staked = StakedSelections.empty,
    this.movement,
  });

  final HkjcFootballFixture fixture;
  final HkjcCornerAssessment? assessment;

  /// How this fixture's stored quotes moved towards kick-off, when the history
  /// covers more than one timepoint.
  final FixtureOddsMovement? movement;

  /// Outlines the tile so the fixture a pick pointed at is unmistakable.
  final bool focused;

  /// Bumped by every pick tap, so a repeated tap reopens this tile.
  final int focusRequest;

  /// Records this fixture's cleared pick in the simulated account.
  final void Function(HkjcFootballFixture, HkjcCornerRecommendation)?
  onAddSimulation;

  /// Picks the simulated account already holds.
  final StakedSelections staked;

  @override
  State<_FixtureTile> createState() => _FixtureTileState();
}

class _FixtureTileState extends State<_FixtureTile> {
  late bool _expanded = widget.focused;

  @override
  void didUpdateWidget(_FixtureTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (shouldReopenForFocus(
      focused: widget.focused,
      wasFocused: oldWidget.focused,
      request: widget.focusRequest,
      previousRequest: oldWidget.focusRequest,
    )) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fixture = widget.fixture;
    final focused = widget.focused;
    final current = widget.assessment;
    final odds = fixture.matchOdds;
    final local = fixture.kickOffTime.toLocal();
    final accent = current?.recommendation == null
        ? _grey
        : AppPalette.confidence(current!.recommendation!.confidenceLabel);
    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: focused ? 0.2 : 0.09),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(AppShape.tileRadius),
        border: Border.all(
          color: focused ? accent : accent.withValues(alpha: 0.2),
          width: focused ? 1.7 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Row(
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
                      if (!_expanded) ...[
                        const SizedBox(height: 5),
                        _VerdictLine(assessment: current),
                      ],
                      if (widget.staked.holdsMatch(fixture.matchId)) ...[
                        const SizedBox(height: 5),
                        const _StakedTag(),
                      ],
                    ],
                  ),
                ),
                if (!_expanded && current?.recommendation != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ConfidenceRing(
                      value: current!.recommendation!.confidence,
                      color: accent,
                      caption: current.recommendation!.confidenceLabel,
                      size: 44,
                    ),
                  ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: AppMotion.normal,
                  curve: Curves.easeOut,
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          if (_expanded && odds != null && odds.complete) ...[
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
          if (_expanded) const SizedBox(height: 11),
          if (_expanded && current == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '角球大細盤未開',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            )
          else if (_expanded && current != null) ...[
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
            _MovementRow(movement: widget.movement),
            const SizedBox(height: 9),
            _RecommendationBox(
              recommendation: current.recommendation,
              observation: current.observation,
              signalGap: current.signalGap,
              suspended: current.suspended,
              alreadyStaked:
                  current.recommendation != null &&
                  widget.staked.holdsCornerPick(
                    matchId: fixture.matchId,
                    pick: current.recommendation!,
                  ),
              onAddSimulation: widget.onAddSimulation == null
                  ? null
                  : (pick) => widget.onAddSimulation!(widget.fixture, pick),
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

/// How the stored quotes of this fixture moved towards kick-off.
///
/// The reading is the margin-free over probability of the deepest stored line at
/// 24h, 6h and 1h before kick-off plus the last pre-match quote, so the row says
/// which way the money went rather than only where the price stands now. It is
/// evidence, not an input: the released model carries no movement column,
/// because the free settled history holds one closing price per match.
class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement});

  final FixtureOddsMovement? movement;

  @override
  Widget build(BuildContext context) {
    final primary = movement?.primary;
    if (primary == null || !primary.hasMovement) {
      return _Chip(label: '盤口移動 快照未足兩個時點', color: _grey);
    }
    final total = primary.total!;
    final rising = total > 0;
    final color = total.abs() < cornerMovementNoise
        ? _grey
        : rising
        ? _accent
        : _blue;
    return Wrap(
      spacing: 7,
      runSpacing: 6,
      children: [
        _Chip(
          label:
              '盤口移動 ${primary.line.toStringAsFixed(1)} · '
              '${_movementLabel(total)}',
          color: color,
        ),
        for (var index = 1; index < primary.points.length; index++)
          _Chip(
            label:
                '${primary.points[index - 1].label}→'
                '${primary.points[index].label} '
                '${_movementLabel(primary.points[index].fairOverProbability - primary.points[index - 1].fairOverProbability)}',
            color: _grey,
          ),
        if (primary.steaming)
          _Chip(label: rising ? '單向走向大盤' : '單向走向細盤', color: _amber),
      ],
    );
  }

  /// Signed change in the over probability, in percentage points.
  static String _movementLabel(double move) {
    if (move.abs() < cornerMovementNoise) {
      return '未動';
    }
    final points = (move * 100).abs().toStringAsFixed(1);
    return move > 0 ? '大 +$points pt' : '細 +$points pt';
  }
}

/// The single line a closed card shows: the pick, 不建議, or no market at all.
class _VerdictLine extends StatelessWidget {
  const _VerdictLine({required this.assessment});

  final HkjcCornerAssessment? assessment;

  @override
  Widget build(BuildContext context) {
    final current = assessment;
    if (current == null) {
      return Text(
        '角球大細盤未開',
        style: TextStyle(
          fontSize: 11.5,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      );
    }
    final pick = current.recommendation;
    if (pick == null) {
      return const GlowPill(label: '不建議', color: _grey, dense: true);
    }
    final color = AppPalette.confidence(pick.confidenceLabel);
    return Wrap(
      spacing: 5,
      runSpacing: 4,
      children: [
        GlowPill(
          label: '${pick.directionLabel} ${pick.line.line.condition}',
          color: color,
          icon: Icons.trending_up,
          dense: true,
        ),
        GlowPill(
          label: pick.odds.toStringAsFixed(2),
          color: _blue,
          dense: true,
        ),
      ],
    );
  }
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
    required this.signalGap,
    this.suspended = false,
    this.alreadyStaked = false,
    this.onAddSimulation,
  });

  final HkjcCornerRecommendation? recommendation;
  final HkjcCornerRecommendation? observation;
  final HkjcSignalGap? signalGap;

  /// Whether the forward-looking error audit has stopped new picks.
  final bool suspended;

  /// Whether this exact side, line and market is already in the simulated
  /// account; the card then states it and stops offering the same bet again.
  final bool alreadyStaked;

  /// Records the cleared pick in the simulated account, when one is offered.
  ///
  /// Only a cleared [recommendation] can be recorded: an observation is a side
  /// the model refused to back, so offering it as a bet would misread the card.
  final ValueChanged<HkjcCornerRecommendation>? onAddSimulation;

  @override
  Widget build(BuildContext context) {
    final pick = recommendation;
    final shown = pick ?? observation;
    final color = pick == null
        ? _grey
        : AppPalette.confidence(pick.confidenceLabel);
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
                      ? '模型不建議'
                      : '${pick.directionLabel} '
                            '${pick.line.line.condition}'
                            ' @ ${pick.odds.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
              if (shown != null)
                ConfidenceRing(
                  value: shown.confidence,
                  color: color,
                  caption: shown.confidenceLabel,
                  size: 46,
                ),
            ],
          ),
          if (suspended) ...[
            const SizedBox(height: 7),
            const GlowPill(
              label: '審核暫停推介',
              color: _amber,
              icon: Icons.pause_circle_outline,
              dense: true,
            ),
          ],
          if (shown != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                GlowPill(
                  label:
                      '模型 '
                      '${(shown.winProbability * 100).toStringAsFixed(1)}%',
                  color: color,
                  dense: true,
                ),
                GlowPill(
                  label:
                      '市場 '
                      '${(_marketProbability(shown) * 100).toStringAsFixed(1)}%',
                  color: _blue,
                  dense: true,
                ),
                GlowPill(
                  label: '期望值 ${_signed(shown.edge)}',
                  color: shown.edge >= 0 ? _accent : _grey,
                  dense: true,
                ),
                if (pick != null)
                  GlowPill(
                    label:
                        '注碼 '
                        '${(shown.stakeFraction * 100).toStringAsFixed(2)}%',
                    color: _purple,
                    dense: true,
                  ),
                if (pick == null && signalGap != null)
                  GlowPill(
                    label:
                        '尚差 '
                        '${(signalGap!.probabilityShortfall * 100).toStringAsFixed(1)}'
                        ' 個百分點',
                    color: _amber,
                    dense: true,
                  ),
              ],
            ),
          ],
          if (pick != null && onAddSimulation != null) ...[
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: alreadyStaked ? null : () => onAddSimulation!(pick),
                style: FilledButton.styleFrom(
                  backgroundColor: (alreadyStaked ? _grey : color).withValues(
                    alpha: 0.22,
                  ),
                  foregroundColor: alreadyStaked ? _grey : color,
                  disabledBackgroundColor: _grey.withValues(alpha: 0.18),
                  disabledForegroundColor: _grey,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                icon: Icon(
                  alreadyStaked ? Icons.check_circle_outline : Icons.add_chart,
                  size: 17,
                ),
                label: Text(alreadyStaked ? '已加入模擬戶口' : '加入模擬戶口'),
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

/// States that the simulated account already carries a bet on this fixture.
///
/// The point is only to stop the same pick being recorded twice: it says a bet
/// exists, never that the bet is a good one or that it is still open.
class _StakedTag extends StatelessWidget {
  const _StakedTag();

  @override
  Widget build(BuildContext context) {
    return const GlowPill(
      label: '已入模擬戶口',
      color: AppPalette.staked,
      icon: Icons.check_circle_outline,
      dense: true,
    );
  }
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
          Expanded(child: Text('真實 大／細', style: style)),
          Expanded(child: Text('模型 大／細', style: style)),
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
              '${line.highOdds!.toStringAsFixed(2)}'
              ' / ${line.lowOdds!.toStringAsFixed(2)}',
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
