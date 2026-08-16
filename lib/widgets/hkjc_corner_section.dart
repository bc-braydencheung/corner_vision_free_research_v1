import 'package:flutter/material.dart';

import '../models/hkjc_football.dart';
import '../services/hkjc_corner_model.dart';
import '../services/hkjc_football_service.dart';

/// Shows the HKJC fixtures, corner hi/lo odds, vig-free odds and the model
/// reading for the league currently selected in the football view.
class HkjcCornerSection extends StatelessWidget {
  const HkjcCornerSection({
    required this.snapshot,
    required this.leagueCode,
    required this.loading,
    required this.onRefresh,
    super.key,
  });

  final HkjcFootballSnapshot? snapshot;
  final String leagueCode;
  final bool loading;
  final Future<void> Function() onRefresh;

  static const _model = HkjcCornerModel();

  @override
  Widget build(BuildContext context) {
    if (!hkjcFootballProfiles.containsKey(leagueCode)) {
      return const SizedBox.shrink();
    }
    final current = snapshot;
    final fixtures = current?.forLeague(leagueCode) ?? const [];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sports_soccer,
                size: 18,
                color: Color(0xFFB491FF),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '馬會賽程 · 角球大細',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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
          Text(
            current == null
                ? '正在讀取馬會賽程…'
                : '賠率來源：馬會公開足球頁 · 讀取於 ${_time(current.capturedAt)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          if ((current?.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              current!.note,
              style: const TextStyle(fontSize: 11, color: Color(0xFFFFC857)),
            ),
          ],
          const SizedBox(height: 12),
          if (current != null && fixtures.isEmpty)
            Text(
              '馬會暫未開出此聯賽賽程',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          for (final fixture in fixtures) ...[
            _FixtureTile(fixture: fixture, assessment: _model.assess(fixture)),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 2),
          Text(
            '真實賠率＝除去馬會抽水後的同盤賠率；模型賠率＝以全部盤口聯合擬合的'
            '泊松角球期望值重算。信心分數綜合期望值大小、各盤與模型的一致度、'
            '盤口數目及馬會抽水，並非中獎機率。全部數字皆為研究參考，'
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
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0E241B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${fixture.homeTeam} vs ${fixture.awayTeam}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                _kickOff(fixture.kickOffTime),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          if (odds != null && odds.complete) ...[
            const SizedBox(height: 4),
            Text(
              '馬會主客和：主 ${odds.home!.toStringAsFixed(2)} · '
              '和 ${odds.draw!.toStringAsFixed(2)} · '
              '客 ${odds.away!.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (current == null)
            Text(
              '角球大細盤未開出（馬會多在臨場前才開放此盤）',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(
                  label: '模型期望角球 ${current.expectedCorners.toStringAsFixed(2)}',
                  color: const Color(0xFF42E695),
                ),
                _Chip(
                  label:
                      '盤口一致度 '
                      '${_plainPercent((1 - current.lineDispersion * 20).clamp(0.0, 1.0))}',
                  color: const Color(0xFF6FA8FF),
                ),
                _Chip(
                  label: '馬會抽水 ${_plainPercent(current.averageOverround)}',
                  color: const Color(0xFF7F8C8D),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _RecommendationBox(recommendation: current.recommendation),
            const SizedBox(height: 8),
            for (final line in current.lines) _LineRow(assessment: line),
          ],
        ],
      ),
    );
  }

  static String _plainPercent(double value) =>
      '${(value * 100).toStringAsFixed(1)}%';

  static String _kickOff(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Model pick plus its confidence, or an explicit "no pick" state.
class _RecommendationBox extends StatelessWidget {
  const _RecommendationBox({required this.recommendation});

  final HkjcCornerRecommendation? recommendation;

  @override
  Widget build(BuildContext context) {
    final pick = recommendation;
    final color = pick == null
        ? const Color(0xFF7F8C8D)
        : switch (pick.confidenceLabel) {
            '高' => const Color(0xFF42E695),
            '中' => const Color(0xFFFFC857),
            _ => const Color(0xFFB491FF),
          };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pick == null
                ? '模型推介：不建議 · 各盤與模型一致'
                : '模型推介：${pick.directionLabel} ${pick.line.line.condition}'
                      ' @ ${pick.odds.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          if (pick == null)
            Text(
              '未有一邊的期望值高於門檻，此場只作觀察。',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            )
          else ...[
            Row(
              children: [
                Text(
                  '信心 ${pick.confidenceLabel}',
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
                      value: pick.confidence.clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(pick.confidence * 100).toStringAsFixed(0)}/100',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '模型勝率 ${(pick.winProbability * 100).toStringAsFixed(1)}%'
              ' · 期望值 ${_signed(pick.edge)}'
              ' · 1/4 Kelly 注碼 ${(pick.stakeFraction * 100).toStringAsFixed(2)}%',
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              '${line.condition}${line.main ? ' ★' : ''}',
              style: style.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              '馬會 大${line.highOdds!.toStringAsFixed(2)}'
              ' / 細${line.lowOdds!.toStringAsFixed(2)}',
              style: style,
            ),
          ),
          Expanded(
            child: Text(
              '真實 ${assessment.fairHighOdds.toStringAsFixed(2)}'
              ' / ${assessment.fairLowOdds.toStringAsFixed(2)}',
              style: style,
            ),
          ),
          Expanded(
            child: Text(
              '模型 ${assessment.modelHighOdds.toStringAsFixed(2)}'
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
