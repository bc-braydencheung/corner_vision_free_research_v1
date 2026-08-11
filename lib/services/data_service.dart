import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/football_mobile.dart';
import '../models/forecast_data.dart';
import '../models/shadow_forecast.dart';
import 'football_mobile_service.dart';
import 'hkjc_mobile_service.dart';
import 'shadow_service.dart';

class ForecastLoadResult {
  const ForecastLoadResult({
    required this.data,
    required this.isRemote,
    required this.message,
    this.footballStatus,
    this.racingStatus,
    this.shadowHealth = ShadowHealth.empty,
    this.sourceErrors = const {},
  });

  final ForecastData data;
  final bool isRemote;
  final String message;
  final FootballSyncStatus? footballStatus;
  final RacingSyncStatus? racingStatus;
  final ShadowHealth shadowHealth;
  final Map<String, String> sourceErrors;
}

class DataService {
  const DataService({
    this.checkDirectResults = true,
    this.checkRacingUpdates = true,
  });

  static const _assetPath = 'assets/data/latest.json';
  static const _remoteUrl = String.fromEnvironment('FORECAST_DATA_URL');
  final bool checkDirectResults;
  final bool checkRacingUpdates;

  Future<ForecastLoadResult> load() async {
    final bundled = ForecastData.fromJson(
      (jsonDecode(await rootBundle.loadString(_assetPath)) as Map)
          .cast<String, Object?>(),
    );
    var selected = bundled;
    var isRemote = false;
    var message = '已檢查內置模型';

    if (_remoteUrl.isNotEmpty) {
      final remote = await _loadRemote();
      if (remote != null) {
        isRemote = true;
        final isNewer =
            remote.dataVersion != bundled.dataVersion ||
            remote.generatedAt.isAfter(bundled.generatedAt);
        selected = isNewer ? remote : bundled;
        message = isNewer ? '已下載最新完整模型' : '已連線檢查 · 完整模型是最新版本';
      } else {
        message = '完整模型更新暫時不可用 · 已使用內置模型';
      }
    }

    FootballSyncStatus? footballStatus;
    final sourceErrors = <String, String>{};
    if (checkDirectResults) {
      try {
        final cached = await FootballMobileService().loadCached(
          selected.leagues,
        );
        final merged = {
          for (final result in selected.settlementResults)
            result.matchId: result,
          for (final result in cached.settlementResults) result.matchId: result,
        };
        selected = selected.withFootball(
          value: cached.leagues,
          results: merged.values.toList(),
        );
        footballStatus = cached.status;
      } on Object catch (error) {
        sourceErrors['Football-Data'] = '$error';
      }
    }

    RacingSyncStatus? racingStatus;
    if (checkRacingUpdates) {
      try {
        final cached = await HKJCMobileService().loadCached(selected.racing);
        selected = selected.withRacing(cached.racing);
        racingStatus = cached.status;
      } on Object catch (error) {
        sourceErrors['HKJC'] = '$error';
      }
    }

    final shadowHealth = await _updateShadow(selected);
    return ForecastLoadResult(
      data: selected,
      isRemote: isRemote,
      message: message,
      footballStatus: footballStatus,
      racingStatus: racingStatus,
      shadowHealth: shadowHealth,
      sourceErrors: sourceErrors,
    );
  }

  Future<ForecastLoadResult> refreshFootball(
    ForecastLoadResult current, {
    void Function(double progress, String status)? onBootstrapProgress,
  }) async {
    if (!checkDirectResults) {
      return current;
    }
    FootballMobileLoad refreshed;
    try {
      final service = FootballMobileService();
      // Check if we have any data - if not, bootstrap from scratch
      final dataset = await service.store.loadDataset();
      if (dataset.rows.isEmpty && onBootstrapProgress != null) {
        onBootstrapProgress(0, '正在從 football-data.co.uk 下載全部歷史數據...');
        final bootstrapped = await service.bootstrap(
          leagues: current.data.leagues
              .map((l) => FootballLeagueConfig(
                    code: l.code,
                    name: l.name,
                    supportCode: l.supportName == '英冠'
                        ? 'E1'
                        : l.supportName == '西乙'
                            ? 'SP2'
                            : l.supportName == '德乙'
                                ? 'D2'
                                : l.supportName == '意乙'
                                    ? 'I2'
                                    : l.supportName == '法乙'
                                        ? 'F2'
                                        : '',
                    supportName: l.supportName,
                  ))
              .toList(),
          onProgress: onBootstrapProgress,
        );
        if (bootstrapped == null) {
          throw const HttpException('無法從 football-data.co.uk 下載數據');
        }
        onBootstrapProgress(1.0, '歷史數據下載完成，正在同步最新賽果...');
      }
      refreshed = await service.sync(current.data.leagues);
    } on Object catch (error) {
      return ForecastLoadResult(
        data: current.data,
        isRemote: current.isRemote,
        message: current.message,
        footballStatus: current.footballStatus,
        racingStatus: current.racingStatus,
        shadowHealth: current.shadowHealth,
        sourceErrors: {...current.sourceErrors, 'Football-Data': '$error'},
      );
    }
    final merged = {
      for (final result in current.data.settlementResults)
        result.matchId: result,
      for (final result in refreshed.settlementResults) result.matchId: result,
    };
    return ForecastLoadResult(
      data: current.data.withFootball(
        value: refreshed.leagues,
        results: merged.values.toList(),
      ),
      isRemote: current.isRemote,
      message: current.message,
      footballStatus: refreshed.status,
      racingStatus: current.racingStatus,
      shadowHealth: await _updateShadow(
        current.data.withFootball(
          value: refreshed.leagues,
          results: merged.values.toList(),
        ),
      ),
      sourceErrors: {...current.sourceErrors}..remove('Football-Data'),
    );
  }

  Future<ForecastLoadResult> reloadFootballCache(
    ForecastLoadResult current,
  ) async {
    if (!checkDirectResults) {
      return current;
    }
    final cached = await FootballMobileService().loadCached(
      current.data.leagues,
    );
    final merged = {
      for (final result in current.data.settlementResults)
        result.matchId: result,
      for (final result in cached.settlementResults) result.matchId: result,
    };
    return ForecastLoadResult(
      data: current.data.withFootball(
        value: cached.leagues,
        results: merged.values.toList(),
      ),
      isRemote: current.isRemote,
      message: current.message,
      footballStatus: cached.status,
      racingStatus: current.racingStatus,
      shadowHealth: await _updateShadow(
        current.data.withFootball(
          value: cached.leagues,
          results: merged.values.toList(),
        ),
      ),
      sourceErrors: current.sourceErrors,
    );
  }

  Future<ForecastLoadResult> refreshRacing(
    ForecastLoadResult current, {
    bool force = false,
  }) async {
    if (!checkRacingUpdates) {
      return current;
    }
    RacingMobileLoad refreshed;
    try {
      refreshed = await HKJCMobileService().sync(
        current.data.racing,
        force: force,
      );
    } on Object catch (error) {
      return ForecastLoadResult(
        data: current.data,
        isRemote: current.isRemote,
        message: current.message,
        footballStatus: current.footballStatus,
        racingStatus: current.racingStatus,
        shadowHealth: current.shadowHealth,
        sourceErrors: {...current.sourceErrors, 'HKJC': '$error'},
      );
    }
    return ForecastLoadResult(
      data: current.data.withRacing(refreshed.racing),
      isRemote: current.isRemote,
      message: current.message,
      footballStatus: current.footballStatus,
      racingStatus: refreshed.status,
      shadowHealth: await _updateShadow(
        current.data.withRacing(refreshed.racing),
      ),
      sourceErrors: {...current.sourceErrors}..remove('HKJC'),
    );
  }

  Future<ForecastLoadResult> reloadRacingCache(
    ForecastLoadResult current,
  ) async {
    if (!checkRacingUpdates) {
      return current;
    }
    final cached = await HKJCMobileService().loadCached(current.data.racing);
    return ForecastLoadResult(
      data: current.data.withRacing(cached.racing),
      isRemote: current.isRemote,
      message: current.message,
      footballStatus: current.footballStatus,
      racingStatus: cached.status,
      shadowHealth: await _updateShadow(current.data.withRacing(cached.racing)),
      sourceErrors: current.sourceErrors,
    );
  }

  Future<ShadowHealth> _updateShadow(ForecastData data) async {
    try {
      return (await ShadowService().update(data)).health;
    } on Object {
      return ShadowHealth.empty;
    }
  }

  Future<ForecastData?> _loadRemote() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final parsed = Uri.parse(_remoteUrl);
      final uri = parsed.replace(
        queryParameters: {
          ...parsed.queryParameters,
          'check': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      final body = await utf8.decoder.bind(response).join();
      return ForecastData.fromJson(
        (jsonDecode(body) as Map).cast<String, Object?>(),
      );
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

List<MatchResult> parseFootballDataResults(String division, String csvBody) {
  return parseFootballDataMatches(csvBody, division: division)
      .where((row) => row.isComplete)
      .map(
        (row) => MatchResult(
          matchId: row.matchId,
          actualTotalCorners: row.homeCorners! + row.awayCorners!,
        ),
      )
      .toList(growable: false);
}
