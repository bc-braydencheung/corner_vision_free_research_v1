import 'package:flutter/material.dart';

import '../services/track_record.dart';

/// Public record of every recommendation the app has shown so far.
///
/// The page exists to be checkable: each row carries the capture time, the
/// quote that was on screen, the closing quote and the settled result, so the
/// summary above it can be recomputed by hand. Prediction quality and price
/// quality are shown as two separate blocks on purpose.
class TrackRecordView extends StatelessWidget {
  const TrackRecordView({
    required this.report,
    required this.onShare,
    this.sharing = false,
    super.key,
  });

  final TrackRecordReport? report;

  /// Renders the record as an image and hands it to the system share sheet.
  final VoidCallback onShare;
  final bool sharing;

  @override
  Widget build(BuildContext context) {
    final record = report;
    if (record == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            '正在整理紀錄…',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        _SummaryCard(report: record, onShare: onShare, sharing: sharing),
        const SizedBox(height: 14),
        if (record.entries.isEmpty)
          const _EmptyCard()
        else
          ...record.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EntryCard(entry: entry),
            ),
          ),
        if (record.skipped.isNotEmpty) ...[
          const SizedBox(height: 4),
          _SkippedCard(skipped: record.skipped),
        ],
        const SizedBox(height: 14),
        const _DisclosureCard(),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.report,
    required this.onShare,
    required this.sharing,
  });

  final TrackRecordReport report;
  final VoidCallback onShare;
  final bool sharing;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: '至今紀錄',
      icon: Icons.receipt_long_outlined,
      trailing: '${report.recommended} 個推介',
      action: IconButton(
        tooltip: '分享紀錄（WhatsApp 等）',
        onPressed: sharing ? null : onShare,
        icon: sharing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.share, size: 18),
      ),
      children: [
        Text(
          report.verdict,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        const _Label('預測表現（機率準唔準）'),
        _Row(label: '已結算推介', value: '${report.settled} 個'),
        _Row(
          label: '命中率',
          value: report.hasSettled
              ? '${(report.hitRate * 100).toStringAsFixed(1)}%'
              : '未有已結算賽果',
        ),
        _Row(
          label: 'Brier（模型）',
          value: report.brierSamples == 0
              ? '樣本不足'
              : report.brier.toStringAsFixed(4),
        ),
        _Row(
          label: 'Brier（同場盤口）',
          value: report.brierSamples == 0
              ? '樣本不足'
              : report.marketBrier.toStringAsFixed(4),
        ),
        _Row(
          label: '是否勝過盤口',
          value: report.brierSamples < 20
              ? '樣本不足 20，未足以評估'
              : report.beatsMarketBrier
              ? '是'
              : '否',
        ),
        const SizedBox(height: 10),
        const _Label('價格表現（收盤價 CLV）'),
        _Row(label: '有收盤價樣本', value: '${report.clvSamples} 個'),
        _Row(
          label: '平均 CLV',
          value: report.clvSamples == 0
              ? '樣本不足'
              : '${(report.meanClosingLineValue * 100).toStringAsFixed(2)}%',
        ),
        _Row(
          label: '打敗收盤價比率',
          value: report.clvSamples == 0
              ? '樣本不足'
              : '${(report.beatClosingRate * 100).toStringAsFixed(1)}%',
        ),
        const SizedBox(height: 10),
        const _Label('研究單位（非金錢，不代表任何投注）'),
        _Row(
          label: '累計單位',
          value: report.hasSettled
              ? report.netUnits.toStringAsFixed(2)
              : '未有已結算賽果',
        ),
        _Row(
          label: '最大回撤',
          value: report.hasSettled
              ? report.maximumDrawdownUnits.toStringAsFixed(2)
              : '未有已結算賽果',
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final TrackRecordEntry entry;

  @override
  Widget build(BuildContext context) {
    final clv = entry.closingLineValue;
    final result = entry.won;
    return _Card(
      title: '${entry.homeTeam} 對 ${entry.awayTeam}',
      icon: entry.recommended ? Icons.flag_outlined : Icons.visibility_outlined,
      trailing: entry.recommended ? '推介${entry.directionLabel}' : '只作觀察',
      children: [
        _Row(label: '聯賽／盤口', value: '${entry.leagueName} · ${entry.line}'),
        _Row(label: '賽事時間', value: _time(entry.matchDate)),
        _Row(label: '預測捕取時間', value: _time(entry.capturedAt)),
        _Row(
          label: '下注時賠率',
          value:
              '${entry.takenOdds.toStringAsFixed(2)}'
              '（${_time(entry.takenAt)}）',
        ),
        _Row(
          label: '模型／盤口機率',
          value:
              '${(entry.modelProbability * 100).toStringAsFixed(1)}%'
              ' / ${(entry.marketProbability * 100).toStringAsFixed(1)}%',
        ),
        _Row(label: '期望值', value: '${(entry.edge * 100).toStringAsFixed(2)}%'),
        _Row(
          label: '收盤賠率',
          value: entry.closingOdds == null
              ? '未有收盤價'
              : entry.closingOdds!.toStringAsFixed(2),
        ),
        _Row(
          label: 'CLV',
          value: clv == null ? '未有收盤價' : '${(clv * 100).toStringAsFixed(2)}%',
        ),
        _Row(
          label: '實際結果',
          value: entry.actualTotalCorners == null
              ? '未結算'
              : '${entry.actualTotalCorners} 個角球'
                    '（${result == true ? '中' : '不中'}）',
        ),
      ],
    );
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}

class _SkippedCard extends StatelessWidget {
  const _SkippedCard({required this.skipped});

  final Map<TrackRecordSkip, int> skipped;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: '未能入帳的預測',
      icon: Icons.filter_alt_outlined,
      children: [
        Text(
          '有紀錄但缺少當時盤口的預測不會入帳，以免用事後價格充當當時價格。',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.52),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in skipped.entries)
          _Row(label: _reason(entry.key), value: '${entry.value} 筆'),
      ],
    );
  }

  static String _reason(TrackRecordSkip skip) => switch (skip) {
    TrackRecordSkip.noTimeline => '無該場該盤的賠率紀錄',
    TrackRecordSkip.noTakenQuote => '預測時未有已保存的賠率',
    TrackRecordSkip.unusableOdds => '賠率無法換算機率',
  };
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: '尚未有可公開的紀錄',
      icon: Icons.hourglass_bottom,
      children: [
        Text(
          '紀錄由第一個有保存賠率的預測開始累積。'
          '模型在無正期望值時會顯示「不建議」，該類場次只會以「只作觀察」入帳，'
          '不會計入命中率。',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _DisclosureCard extends StatelessWidget {
  const _DisclosureCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: '披露',
      icon: Icons.info_outline,
      children: [
        Text(
          '本頁只作研究記錄：App 不提供投注、付款、轉帳或模擬戶口，'
          '「研究單位」只是每次一注的假設計數，不代表任何金額或收益。\n'
          '「下注時賠率」是捕取預測當刻已保存的馬會賠率，'
          '收盤賠率是開賽前最後一個非即場報價；兩者都不會用事後價格改寫。\n'
          '命中率與 Brier 只計已結算的推介；樣本不足時直接顯示樣本不足，'
          '不會以少量樣本聲稱有優勢。',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.52),
            fontSize: 11,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
    this.action,
  });

  final String title;
  final IconData icon;
  final String? trailing;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
              Icon(icon, color: const Color(0xFF8BE9A6), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ?action,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF8BE9A6),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
