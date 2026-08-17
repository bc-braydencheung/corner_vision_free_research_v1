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
import 'source_contract.dart';

class ForecastLoadResult {
  const ForecastLoadResult({
    required this.data,
    required this.isRemote,
    required this.message,
    this.footballStatus,
    this.racingStatus,
    this.shadowHealth = ShadowHealth.empty,
    this.sourceErrors = const {},
    this.mirrorHealth = const [],
  });

  final ForecastData data;
  final bool isRemote;
  final String message;
  final FootballSyncStatus? footballStatus;
  final RacingSyncStatus? racingStatus;
  final ShadowHealth shadowHealth;
  final Map<String, String> sourceErrors;

  /// Per-mirror outcome of the last full-model fetch.
  final List<SourceHealth> mirrorHealth;
}

class DataService {
  const DataService({
    this.checkDirectResults = true,
    this.checkRacingUpdates = true,
  });

  static const _assetPath = 'assets/data/latest.json';
  static const _remoteUrl = String.fromEnvironment(
    'FORECAST_DATA_URL',
    defaultValue:
        'https://bc-braydencheung.github.io/'
        'corner_vision_free_research_v1/latest.json',
  );
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
    var mirrorHealth = const <SourceHealth>[];

    if (_remoteUrl.isNotEmpty) {
      final fetched = await _loadRemote();
      mirrorHealth = fetched.health;
      final remote = fetched.payload;
      if (remote != null) {
        isRemote = true;
        final isNewer =
            remote.dataVersion != bundled.dataVersion ||
            remote.generatedAt.isAfter(bundled.generatedAt);
        selected = isNewer ? remote : bundled;
        final healthy = fetched.healthyCount;
        final tried = fetched.health.length;
        final quorum = tried > 1 ? ' · 鏡像 $healthy/$tried' : '';
        message = isNewer ? '已下載最新完整模型$quorum' : '已連線檢查 · 完整模型是最新版本$quorum';
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
      mirrorHealth: mirrorHealth,
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
              .map(
                (l) => FootballLeagueConfig(
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
                ),
              )
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
        mirrorHealth: current.mirrorHealth,
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
      mirrorHealth: current.mirrorHealth,
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
      mirrorHealth: current.mirrorHealth,
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
        mirrorHealth: current.mirrorHealth,
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
      mirrorHealth: current.mirrorHealth,
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
      mirrorHealth: current.mirrorHealth,
    );
  }

  Future<ShadowHealth> _updateShadow(ForecastData data) async {
    try {
      return (await ShadowService().update(data)).health;
    } on Object {
      return ShadowHealth.empty;
    }
  }

  /// Fetches the full model from every free mirror and keeps the freshest
  /// payload that satisfies the schema contract.
  Future<MirrorFetchResult<ForecastData>> _loadRemote() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      return await fetchFromMirrors<ForecastData>(
        urls: mirrorCandidates(_remoteUrl),
        fetch: (url) async {
          final parsed = Uri.parse(url);
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
          final body = await utf8.decoder.bind(response).join();
          return (status: response.statusCode, body: body);
        },
        contract: forecastContractViolations,
        parse: ForecastData.fromJson,
      );
    } on Object catch (error) {
      return MirrorFetchResult<ForecastData>(
        health: [
          SourceHealth(
            url: _remoteUrl,
            ok: false,
            latencyMs: 0,
            error: '$error',
          ),
        ],
      );
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
