import 'dart:math';

import 'package:flutter/material.dart';

import '../models/simulated_trade.dart';
import '../services/simulation_service.dart';

class SimulationAccount extends StatelessWidget {
  const SimulationAccount({required this.trades, super.key});

  final List<SimulatedTrade> trades;

  @override
  Widget build(BuildContext context) {
    final settled = trades.where((trade) => trade.status == 'settled').toList()
      ..sort((a, b) => a.matchDate.compareTo(b.matchDate));
    final open = trades.where((trade) => trade.status == 'open').toList();
    final profit = settled.fold(0.0, (sum, trade) => sum + (trade.profit ?? 0));
    final settledStake = settled.fold(0.0, (sum, trade) => sum + trade.stake);
    final openStake = open.fold(0.0, (sum, trade) => sum + trade.stake);
    final balance = SimulationService.initialBalance + profit;
    final available = balance - openStake;
    final roi = settledStake == 0 ? 0.0 : profit / settledStake;
    final drawdown = _maximumDrawdown(settled);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const Text(
          '模擬戶口',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          '只有發布後、開賽前建立的不可修改虛擬記錄',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF10291F),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _Metric(label: '戶口價值', value: balance.toStringAsFixed(1)),
                  _Metric(label: '可用餘額', value: available.toStringAsFixed(1)),
                  _Metric(label: '未結算', value: open.length.toString()),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  _Metric(label: '累計盈虧', value: _signed(profit)),
                  _Metric(label: 'ROI', value: _percent(roi)),
                  _Metric(label: '最大回撤', value: _percent(drawdown)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: drawdown >= 0.15
                ? const Color(0xFF4A1F2B)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            drawdown >= 0.15
                ? '最大回撤已達15%，系統停止新增模擬交易。'
                : '低風險模式：固定0.25%或十分一Kelly；單項最多0.5%，'
                      '每個賽事日最多2%。注碼只能控制風險，不能令負EV變成正EV。',
            style: const TextStyle(fontSize: 11, height: 1.45),
          ),
        ),
        if (settled.isNotEmpty) ...[
          const SizedBox(height: 10),
          _StrategyComparison(trades: settled),
        ],
        const SizedBox(height: 20),
        if (trades.isEmpty)
          const _EmptyAccount()
        else
          for (final trade in trades.reversed) ...[
            _TradeCard(trade: trade),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  static double _maximumDrawdown(List<SimulatedTrade> settled) {
    var equity = SimulationService.initialBalance;
    var peak = equity;
    var maximum = 0.0;
    for (final trade in settled) {
      equity += trade.profit ?? 0;
      peak = max(peak, equity);
      maximum = max(maximum, peak == 0 ? 0 : (peak - equity) / peak);
    }
    return maximum;
  }

  static String _signed(double value) {
    final sign = value >= 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)}';
  }

  static String _percent(double value) {
    final sign = value >= 0 ? '+' : '';
    return '$sign${(value * 100).toStringAsFixed(1)}%';
  }
}

class _StrategyComparison extends StatelessWidget {
  const _StrategyComparison({required this.trades});

  final List<SimulatedTrade> trades;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<SimulatedTrade>>{};
    for (final trade in trades) {
      groups.putIfAbsent(trade.stakeStrategy, () => []).add(trade);
    }
    String label(String value) => switch (value) {
      'fixed' => '固定0.25%',
      'kelly' => '十分一Kelly',
      _ => '舊版策略',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('策略對照組', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          for (final entry in groups.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(label(entry.key))),
                  Text(
                    '${entry.value.length}注 · ${_strategyRoi(entry.value)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _strategyRoi(List<SimulatedTrade> trades) {
    final stake = trades.fold<double>(0, (sum, trade) => sum + trade.stake);
    final profit = trades.fold<double>(
      0,
      (sum, trade) => sum + (trade.profit ?? 0),
    );
    if (stake == 0) {
      return 'ROI 0.0%';
    }
    final value = profit / stake * 100;
    return 'ROI ${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}%';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _TradeCard extends StatelessWidget {
  const _TradeCard({required this.trade});

  final SimulatedTrade trade;

  @override
  Widget build(BuildContext context) {
    final profit = trade.profit;
    final color = profit == null
        ? const Color(0xFFFFC857)
        : profit >= 0
        ? const Color(0xFF42E695)
        : const Color(0xFFFF8FA3);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF0E241B),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                trade.leagueName,
                style: const TextStyle(
                  color: Color(0xFFB491FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                trade.status == 'open'
                    ? '未結算'
                    : '盈虧 ${profit! >= 0 ? '+' : ''}${profit.toStringAsFixed(1)}',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            trade.sport == 'racing'
                ? '${trade.homeTeam} · ${trade.awayTeam}'
                : '${trade.homeTeam} 對 ${trade.awayTeam}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            '${trade.sport == 'racing'
                ? trade.marketType == 'place'
                      ? '位置'
                      : '獨贏'
                : trade.direction == 'over'
                ? '大 ${trade.line.toStringAsFixed(2)}'
                : '小 ${trade.line.toStringAsFixed(2)}'} '
            '@ ${trade.odds.toStringAsFixed(2)} · '
            '${trade.stake.toStringAsFixed(1)} units · '
            'EV ${(trade.expectedValue * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
            ),
          ),
          if (trade.marketSource.isNotEmpty)
            Text(
              '${trade.marketSource} · '
              '${trade.marketCapturedAt?.toUtc().toIso8601String() ?? '無時間戳'} · '
              '限價 ${trade.minimumAcceptableOdds?.toStringAsFixed(2) ?? '—'}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.42),
                fontSize: 9,
              ),
            ),
          if (trade.actualTotalCorners != null)
            Text(
              '實際角球 ${trade.actualTotalCorners}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10,
              ),
            ),
          if (trade.finishPosition != null)
            Text(
              '實際名次 ${trade.finishPosition}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyAccount extends StatelessWidget {
  const _EmptyAccount();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 42),
          SizedBox(height: 10),
          Text('尚未建立模擬買入', style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 5),
          Text('在未來賽事卡片使用帶時間戳價格；只有通過安全邊際才可加入。', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
