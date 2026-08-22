import 'dart:math';

import '../models/simulated_trade.dart';

/// Money view of the simulated ledger, in the account's own currency units.
///
/// Everything here is a sum of what the rows already hold: an unsettled row
/// contributes exposure only, never profit, so an open position can never read
/// as a gain.
class SimulationLedger {
  const SimulationLedger({
    required this.bankroll,
    required this.staked,
    required this.settledStake,
    required this.profit,
    required this.balance,
    required this.available,
    required this.openStake,
    required this.openCount,
    required this.settledCount,
    required this.wins,
    required this.losses,
    required this.pushes,
    required this.maximumDrawdown,
  });

  /// Starting balance the user set for the account.
  final double bankroll;

  /// Every stake ever recorded, settled or not.
  final double staked;
  final double settledStake;
  final double profit;

  /// Bankroll plus settled profit; open stakes are not deducted from it.
  final double balance;

  /// Balance minus the stakes still riding on unsettled events.
  final double available;
  final double openStake;
  final int openCount;
  final int settledCount;
  final int wins;
  final int losses;

  /// Settled rows that returned the stake exactly, i.e. a pushed line.
  final int pushes;

  /// Deepest fall from an equity peak, as a fraction of that peak.
  final double maximumDrawdown;

  bool get hasSettled => settledCount > 0;

  /// Profit per unit staked on settled rows; unmeasurable before one settles.
  double get roi => settledStake == 0 ? 0 : profit / settledStake;

  /// Share of decided rows that won; pushes are not decisions.
  double get hitRate => wins + losses == 0 ? 0 : wins / (wins + losses);
}

/// Sums the simulated rows into the account view the page and cards show.
SimulationLedger buildSimulationLedger({
  required List<SimulatedTrade> trades,
  required double bankroll,
}) {
  final settled = trades.where((trade) => trade.status == 'settled').toList()
    ..sort((left, right) {
      final byEvent = left.matchDate.compareTo(right.matchDate);
      return byEvent != 0 ? byEvent : left.createdAt.compareTo(right.createdAt);
    });
  final open = trades.where((trade) => trade.status != 'settled').toList();
  var equity = bankroll;
  var peak = equity;
  var drawdown = 0.0;
  var profit = 0.0;
  var wins = 0;
  var losses = 0;
  var pushes = 0;
  for (final trade in settled) {
    final outcome = trade.profit ?? 0;
    profit += outcome;
    equity += outcome;
    peak = max(peak, equity);
    drawdown = max(drawdown, peak <= 0 ? 0 : (peak - equity) / peak);
    switch (trade.won) {
      case true:
        wins++;
      case false:
        losses++;
      case null:
        pushes++;
    }
  }
  final openStake = open.fold<double>(0, (sum, trade) => sum + trade.stake);
  return SimulationLedger(
    bankroll: bankroll,
    staked: trades.fold<double>(0, (sum, trade) => sum + trade.stake),
    settledStake: settled.fold<double>(0, (sum, trade) => sum + trade.stake),
    profit: profit,
    balance: bankroll + profit,
    available: bankroll + profit - openStake,
    openStake: openStake,
    openCount: open.length,
    settledCount: settled.length,
    wins: wins,
    losses: losses,
    pushes: pushes,
    maximumDrawdown: drawdown,
  );
}

/// Ledger rows newest first, unsettled ones ahead of settled ones.
///
/// A pending position is what the user is waiting on, so it stays at the top
/// however old the account is.
List<SimulatedTrade> sortSimulationTrades(List<SimulatedTrade> trades) {
  return trades.toList()..sort((left, right) {
    final leftOpen = left.status != 'settled';
    final rightOpen = right.status != 'settled';
    if (leftOpen != rightOpen) {
      return leftOpen ? -1 : 1;
    }
    final byEvent = right.matchDate.compareTo(left.matchDate);
    return byEvent != 0 ? byEvent : right.createdAt.compareTo(left.createdAt);
  });
}
