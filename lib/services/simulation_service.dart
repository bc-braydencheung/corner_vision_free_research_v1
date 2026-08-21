import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/forecast_data.dart';
import '../models/simulated_trade.dart';

class SimulationService {
  static const initialBalance = 1000.0;

  /// Starting balance of the user-run account, in the same units as the stakes.
  static const defaultBankroll = 10000.0;
  static const _storageKey = 'edgewise_simulated_trades_v1';
  static const _bankrollKey = 'edgewise_simulated_bankroll_v1';

  Future<List<SimulatedTrade>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      return [];
    }
    final values = jsonDecode(encoded) as List<Object?>;
    return values
        .map(
          (value) =>
              SimulatedTrade.fromJson((value as Map).cast<String, Object?>()),
        )
        .toList();
  }

  Future<void> save(List<SimulatedTrade> trades) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(trades.map((trade) => trade.toJson()).toList()),
    );
  }

  /// Starting balance the user chose, or [defaultBankroll] before they choose.
  Future<double> loadBankroll() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getDouble(_bankrollKey);
    return stored != null && stored > 0 ? stored : defaultBankroll;
  }

  Future<void> saveBankroll(double bankroll) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_bankrollKey, bankroll);
  }

  /// Drops every simulated row, leaving the rest of the research data alone.
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }

  SimulationRiskSummary riskSummary(
    List<SimulatedTrade> trades, {
    DateTime? eventDate,
  }) {
    final settled = trades.where((trade) => trade.status == 'settled').toList()
      ..sort((left, right) {
        final eventOrder = left.matchDate.compareTo(right.matchDate);
        return eventOrder != 0
            ? eventOrder
            : left.createdAt.compareTo(right.createdAt);
      });
    final open = trades.where((trade) => trade.status == 'open').toList();
    var equity = initialBalance;
    var peak = equity;
    var maximumDrawdown = 0.0;
    for (final trade in settled) {
      equity += trade.profit ?? 0;
      peak = max(peak, equity);
      maximumDrawdown = max(
        maximumDrawdown,
        peak <= 0 ? 0 : (peak - equity) / peak,
      );
    }
    final openStake = open.fold<double>(0, (sum, trade) => sum + trade.stake);
    final target = (eventDate ?? DateTime.now()).toUtc();
    final dayExposure = trades
        .where(
          (trade) =>
              trade.matchDate.toUtc().year == target.year &&
              trade.matchDate.toUtc().month == target.month &&
              trade.matchDate.toUtc().day == target.day,
        )
        .fold<double>(0, (sum, trade) => sum + trade.stake);
    final available = max(equity - openStake, 0.0);
    final remainingDayExposure = max(equity * 0.02 - dayExposure, 0.0);
    return SimulationRiskSummary(
      balance: equity,
      available: available,
      openStake: openStake,
      maximumDrawdown: maximumDrawdown,
      dayExposure: dayExposure,
      maximumNewStake: min(available * 0.005, remainingDayExposure),
      stopped: maximumDrawdown >= 0.15 || remainingDayExposure <= 0,
      reason: maximumDrawdown >= 0.15
          ? '最大回撤已達15%，新增模擬交易暫停。'
          : remainingDayExposure <= 0
          ? '今日總曝險已達戶口2%，新增模擬交易暫停。'
          : '單項最多0.5%，每日總曝險最多2%。',
    );
  }

  Future<List<SimulatedTrade>> settle(
    List<SimulatedTrade> trades,
    List<MatchResult> results, {
    List<RacingResult> racingResults = const [],
    Map<String, int> hkjcCornerTotals = const {},
  }) async {
    final resultByMatch = {
      for (final result in results) result.matchId: result.actualTotalCorners,
      // HKJC-keyed rows can only be settled by the HKJC feed's own corner
      // count, so it takes precedence over the free dataset's bridged key.
      ...hkjcCornerTotals,
    };
    final racingBySelection = {
      for (final result in racingResults)
        '${result.raceId}:${result.horseId}': result,
    };
    var changed = false;
    final settled = trades.map((trade) {
      if (trade.sport == 'racing' &&
          trade.status == 'open' &&
          trade.selectionId != null) {
        final result =
            racingBySelection['${trade.matchId}:${trade.selectionId}'];
        if (result != null) {
          changed = true;
          return trade.settleRacing(position: result.finishPosition);
        }
      }
      // A racing row can only be settled by a finishing position; a corner
      // count keyed to the same id would be a different event entirely.
      final actual = trade.sport == 'racing'
          ? null
          : resultByMatch[trade.matchId];
      if (trade.status == 'open' && actual != null) {
        changed = true;
        return trade.settle(totalCorners: actual);
      }
      return trade;
    }).toList();
    if (changed) {
      await save(settled);
    }
    return settled;
  }
}

class SimulationRiskSummary {
  const SimulationRiskSummary({
    required this.balance,
    required this.available,
    required this.openStake,
    required this.maximumDrawdown,
    required this.dayExposure,
    required this.maximumNewStake,
    required this.stopped,
    required this.reason,
  });

  final double balance;
  final double available;
  final double openStake;
  final double maximumDrawdown;
  final double dayExposure;
  final double maximumNewStake;
  final bool stopped;
  final String reason;
}
