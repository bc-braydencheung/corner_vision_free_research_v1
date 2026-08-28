import 'package:flutter/material.dart';

import '../services/research_alerts.dart';
import '../services/simulation_entry.dart';
import '../services/staked_selections.dart';

/// Top-of-page banner of every pick the models currently stand behind.
///
/// Its whole purpose is that no fixture or race has to be opened to learn there
/// is nothing to look at: an empty list is stated outright rather than hidden,
/// and the card never relaxes a threshold to have something to show.
class AlertSummaryCard extends StatelessWidget {
  const AlertSummaryCard({
    required this.alerts,
    required this.loading,
    required this.onShare,
    this.onSelect,
    this.sharing = false,
    this.staked = StakedSelections.empty,
    super.key,
  });

  final List<ResearchAlert> alerts;

  /// `true` while the quotes the picks are derived from are still loading.
  final bool loading;

  /// Renders the picks as an image and hands them to the system share sheet.
  final VoidCallback onShare;
  final ValueChanged<ResearchAlert>? onSelect;
  final bool sharing;

  /// Picks the simulated account already holds, so a row can say so rather than
  /// leaving the user to remember whether it was recorded.
  final StakedSelections staked;

  static const _green = Color(0xFF42E695);
  static const _amber = Color(0xFFFFC857);
  static const _blue = Color(0xFF6FA8FF);

  /// Whether this row's own selection is already in the simulated account.
  ///
  /// The draft is derived exactly as the recording sheet would, so the badge
  /// cannot claim a different line or side from the one that was staked.
  static bool isStaked(StakedSelections staked, ResearchAlert alert) {
    final draft = simulationDraftFromAlert(alert);
    return draft != null && staked.holdsDraft(draft);
  }

  @override
  Widget build(BuildContext context) {
    final has = alerts.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: has
            ? _green.withValues(alpha: 0.09)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (has ? _green : Colors.white).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                has ? Icons.campaign : Icons.do_not_disturb_on_outlined,
                size: 18,
                color: has ? _green : _amber,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loading && !has
                      ? '正在計算今日推介…'
                      : has
                      ? '今日有推介 · ${alerts.length} 項'
                      : '今日無推介',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
              ),
              IconButton(
                tooltip: '分享（WhatsApp 等）',
                onPressed: sharing ? null : onShare,
                icon: sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share, size: 18),
              ),
            ],
          ),
          if (!has)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                loading ? '讀取馬會賠率後即時更新，毋須逐場查看。' : '沒有場次通過模型門檻，寧可不出訊號。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          for (final alert in alerts) ...[
            const SizedBox(height: 8),
            _AlertRow(
              alert: alert,
              staked: isStaked(staked, alert),
              onTap: onSelect == null ? null : () => onSelect!(alert),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, this.staked = false, this.onTap});

  final ResearchAlert alert;

  /// Whether this pick is already recorded in the simulated account.
  final bool staked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${alert.context} · ${alert.subject}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${alert.market} @${alert.odds.toStringAsFixed(2)} · '
                    '信心 ${alert.confidenceLabel}',
                    style: const TextStyle(
                      color: AlertSummaryCard._green,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (staked) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AlertSummaryCard._blue.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: AlertSummaryCard._blue.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        '已入模擬戶口',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AlertSummaryCard._blue,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Colors.white.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }
}
