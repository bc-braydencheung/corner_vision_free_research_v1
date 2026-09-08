import 'package:flutter/material.dart';

import '../services/research_alerts.dart';
import '../services/simulation_entry.dart';
import '../services/staked_selections.dart';
import '../theme/app_theme.dart';
import 'motion.dart';

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
    final accent = has ? AppPalette.mint : AppPalette.slate;
    return GradientCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pulse(
                enabled: has,
                child: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.9),
                        accent.withValues(alpha: 0.45),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: has
                      ? AnimatedNumber(
                          value: alerts.length.toDouble(),
                          format: (value) => value.round().toString(),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0B0A1F),
                          ),
                        )
                      : const Icon(
                          Icons.do_not_disturb_on_outlined,
                          size: 21,
                          color: Color(0xFF0B0A1F),
                        ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  loading && !has
                      ? '計算中'
                      : has
                      ? '今日有推介'
                      : '今日無推介',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
              IconButton(
                tooltip: '分享',
                onPressed: sharing ? null : onShare,
                icon: sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share, size: 19),
              ),
            ],
          ),
          for (final (index, alert) in alerts.indexed) ...[
            const SizedBox(height: 9),
            StaggerIn(
              index: index,
              child: _AlertRow(
                alert: alert,
                accent: AppPalette.confidence(alert.confidenceLabel),
                staked: isStaked(staked, alert),
                onTap: onSelect == null ? null : () => onSelect!(alert),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.alert,
    required this.accent,
    this.staked = false,
    this.onTap,
  });

  final ResearchAlert alert;
  final Color accent;

  /// Whether this pick is already recorded in the simulated account.
  final bool staked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppShape.tileRadius),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            ConfidenceRing(
              value: alert.confidence,
              color: accent,
              caption: alert.confidenceLabel,
              size: 46,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      GlowPill(label: alert.market, color: accent, dense: true),
                      GlowPill(
                        label: alert.odds.toStringAsFixed(2),
                        color: AppPalette.cyan,
                        dense: true,
                      ),
                      if (staked)
                        const GlowPill(
                          label: '已入模擬戶口',
                          color: AppPalette.staked,
                          dense: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Colors.white.withValues(alpha: 0.45),
              ),
          ],
        ),
      ),
    );
  }
}
