import 'package:flutter/material.dart';

import '../models/forecast_data.dart';
import 'team_name_cn.dart';

class PredictionCard extends StatelessWidget {
  const PredictionCard({
    required this.prediction,
    required this.onSimulate,
    super.key,
  });

  final MatchPrediction prediction;
  final VoidCallback? onSimulate;

  @override
  Widget build(BuildContext context) {
    final market = prediction.primaryMarket;
    final overPercent = (market.overProbability * 100).round();
    final isBacktest = prediction.mode == 'backtest';
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF0E241B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Badge(
                label: prediction.leagueName,
                color: const Color(0xFFB491FF),
              ),
              const SizedBox(width: 8),
              Text(
                _dateLabel(prediction.date),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.52),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (isBacktest)
                _Badge(
                  label: '實際 ${prediction.actualTotalCorners}',
                  color: const Color(0xFF7FD1FF),
                )
              else
                _Badge(
                  label: _confidenceLabel(prediction.confidence),
                  color: _confidenceColor(prediction.confidence),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Team(
                  name: prediction.homeTeam,
                  cnName: prediction.homeTeamCn,
                  expected: prediction.expectedHomeCorners,
                  alignment: CrossAxisAlignment.start,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              Expanded(
                child: _Team(
                  name: prediction.awayTeam,
                  cnName: prediction.awayTeamCn,
                  expected: prediction.expectedAwayCorners,
                  alignment: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prediction.expectedTotalCorners.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 33,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '預期總角球 · 80% ${prediction.interval80[0]}—${prediction.interval80[1]}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$overPercent%',
                    style: const TextStyle(
                      color: Color(0xFF42E695),
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                    ),
                  ),
                  Text(
                    '大 9.5 · 公平賠率 ${market.fairOverOdds.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: market.overProbability,
              color: const Color(0xFF42E695),
              backgroundColor: const Color(0xFF233B31),
            ),
          ),
          if (!isBacktest) ...[
            const SizedBox(height: 9),
            Text(
              '${prediction.forecastStage} · '
              '信心 ${(prediction.confidenceScore * 100).round()}% · '
              '資料 ${(prediction.dataQuality * 100).round()}% · '
              '穩定 ${(prediction.modelStability * 100).round()}%',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.46),
                fontSize: 10,
              ),
            ),
          ],
          if (prediction.recommendation == 'no-prediction') ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8FA3).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF8FA3).withValues(alpha: 0.28),
                ),
              ),
              child: const Text(
                '資料或機率優勢不足：只顯示統計分布，不作方向判斷。',
                style: TextStyle(
                  color: Color(0xFFFFB2BF),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (!isBacktest && !prediction.tradeEligible) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC857).withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFFC857).withValues(alpha: 0.24),
                ),
              ),
              child: Text(
                prediction.tradeReason,
                style: const TextStyle(
                  color: Color(0xFFFFD784),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (!isBacktest && prediction.marketAvailable) ...[
            const SizedBox(height: 8),
            Text(
              '${prediction.marketSource} · '
              '${prediction.researchDirection == 'under' ? '小' : '大'}'
              '${prediction.marketLine?.toStringAsFixed(1) ?? '-'} · '
              '研究限價 '
              '${prediction.minimumAcceptableOdds?.toStringAsFixed(2) ?? '-'}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
              ),
            ),
          ],
          if (prediction.factors.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final factor in prediction.factors)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.bolt, size: 14, color: Color(0xFFFFC857)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        factor,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (!isBacktest) ...[
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSimulate,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text(
                  prediction.tradeEligible
                      ? '輸入盤口及賠率 · 虛擬模擬'
                      : 'No bet · 市場資料或驗證閘門未通過',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _dateLabel(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static String _confidenceLabel(String confidence) {
    return switch (confidence) {
      'high' => '高信心',
      'medium' => '中信心',
      'avoid' => '不預測',
      _ => '低信心',
    };
  }

  static Color _confidenceColor(String confidence) {
    return switch (confidence) {
      'high' => const Color(0xFF42E695),
      'medium' => const Color(0xFFFFC857),
      'avoid' => const Color(0xFFFF8FA3),
      _ => const Color(0xFFB491FF),
    };
  }
}

class _Team extends StatelessWidget {
  const _Team({
    required this.name,
    this.cnName = '',
    required this.expected,
    required this.alignment,
  });

  final String name;
  final String cnName;
  final double expected;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final cn = cnName.isNotEmpty ? cnName : teamNameToCn(name);
    final displayName = cn.isNotEmpty ? cn : name;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        if (cn.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
        const SizedBox(height: 3),
        Text(
          '預期 ${expected.toStringAsFixed(1)}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}
