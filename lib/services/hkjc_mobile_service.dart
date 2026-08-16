import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/forecast_data.dart';
import '../models/racing_mobile.dart';
import 'racing_mobile_engine.dart';
import 'racing_store.dart';
import 'weather_service.dart';

class RacingSyncStatus {
  const RacingSyncStatus({
    required this.message,
    required this.hasNewResults,
    required this.newRunnerRows,
    required this.upcomingChanged,
    required this.datasetVersion,
    required this.latestResultDate,
    this.oddsSnapshotCount = 0,
    this.latestOddsCapturedAt,
    this.job,
  });

  final String message;
  final bool hasNewResults;
  final int newRunnerRows;
  final bool upcomingChanged;
  final String datasetVersion;
  final String latestResultDate;
  final int oddsSnapshotCount;
  final DateTime? latestOddsCapturedAt;
  final RacingTrainingJob? job;
}

class RacingMobileLoad {
  const RacingMobileLoad({required this.racing, required this.status});

  final RacingSummary racing;
  final RacingSyncStatus status;
}

class HKJCMobileService {
  HKJCMobileService({
    RacingStore? store,
    RacingMobileEngine? engine,
    WeatherService? weather,
    this.minimumInterval = const Duration(milliseconds: 1200),
    this.baseUrl = 'https://racing.hkjc.com/en-us/local/information',
    this.chineseBaseUrl = 'https://racing.hkjc.com/zh-hk/local/information',
  }) : store = store ?? RacingStore(),
       engine = engine ?? const RacingMobileEngine(),
       weather = weather ?? WeatherService();

  static const _userAgent =
      'EdgeWise personal research mobile/1.0 '
      '(low-frequency cached access)';

  final RacingStore store;
  final RacingMobileEngine engine;
  final WeatherService weather;
  final Duration minimumInterval;
  final String baseUrl;
  final String chineseBaseUrl;
  DateTime? _lastRequest;

  Future<RacingMobileLoad> loadCached(RacingSummary bundled) async {
    await store.initialize();
    final dataset = await store.loadDataset();
    final cached = await store.loadUpcoming();
    final model = await store.loadModel();
    final job = await store.loadJob();
    final oddsSnapshots = await store.loadOddsSnapshots();
    final pendingTraining = model == null
        ? dataset.trainedThrough.compareTo(bundled.model.trainedThrough) > 0
        : model.datasetVersion != dataset.datasetVersion;
    if (cached == null && model == null) {
      return RacingMobileLoad(
        racing: bundled,
        status: RacingSyncStatus(
          message: '已載入內置排位，正在等待低頻更新檢查',
          hasNewResults: pendingTraining,
          newRunnerRows: 0,
          upcomingChanged: false,
          datasetVersion: dataset.datasetVersion,
          latestResultDate: dataset.trainedThrough,
          job: job,
        ),
      );
    }
    final upcoming = cached == null
        ? bundled.races.map(_raceToMap).toList()
        : (cached['races'] as List<Object?>)
              .map((value) => (value as Map).cast<String, Object?>())
              .toList();
    final predicted = engine.predictRaces(
      races: upcoming,
      dataset: dataset,
      model: model,
      poolOdds: _latestPoolOdds(oddsSnapshots),
      weather: _latestWeather(await store.loadWeatherSnapshots()),
    );
    return RacingMobileLoad(
      racing: _summary(
        bundled: bundled,
        dataset: dataset,
        model: model,
        predicted: predicted,
        hasNewResults: pendingTraining,
        usingMobileBaseline: model == null,
      ),
      status: RacingSyncStatus(
        message: cached == null ? '已載入內置排位' : '已載入手機快取排位',
        hasNewResults: pendingTraining,
        newRunnerRows: 0,
        upcomingChanged: false,
        datasetVersion: dataset.datasetVersion,
        latestResultDate: dataset.trainedThrough,
        oddsSnapshotCount: oddsSnapshots.length,
        latestOddsCapturedAt: _latestOddsTimestamp(oddsSnapshots),
        job: job,
      ),
    );
  }

  Future<RacingMobileLoad> sync(
    RacingSummary bundled, {
    bool force = false,
  }) async {
    await store.initialize();
    final dataset = await store.loadDataset();
    var upcomingChanged = false;
    var newRows = 0;
    var messageParts = <String>[];
    List<Map<String, Object?>> upcoming = [];
    final cached = await store.loadUpcoming();
    if (cached != null) {
      upcoming = (cached['races'] as List<Object?>)
          .map((value) => (value as Map).cast<String, Object?>())
          .toList();
    }

    final lastUpcomingCheck = DateTime.tryParse(
      cached?['checkedAt'] as String? ?? '',
    );
    final upcomingCacheIsFresh =
        !force &&
        lastUpcomingCheck != null &&
        DateTime.now().difference(lastUpcomingCheck) < const Duration(hours: 6);
    if (upcomingCacheIsFresh) {
      messageParts.add('排位使用六小時條件快取');
    } else {
      try {
        final downloaded = await _downloadUpcoming();
        if (downloaded.isNotEmpty) {
          final oldHash = cached?['contentHash'] as String? ?? '';
          final newHash = _contentHash(downloaded);
          upcomingChanged = oldHash != newHash;
          upcoming = downloaded;
          await store.saveUpcoming({
            'contentHash': newHash,
            'checkedAt': DateTime.now().toIso8601String(),
            'races': downloaded,
          });
          var namesChanged = false;
          for (final race in downloaded) {
            for (final raw in race['runners'] as List<Object?>) {
              final runner = (raw as Map).cast<String, Object?>();
              final names = [
                runner['horseNameEnglish'] as String? ?? '',
                runner['horseNameChinese'] as String? ?? '',
              ];
              final existing = dataset.horseNames[runner['horseId']];
              if (existing == null ||
                  existing.length < 2 ||
                  existing[0] != names[0] ||
                  existing[1] != names[1]) {
                dataset.horseNames[runner['horseId'] as String] = names;
                namesChanged = true;
              }
            }
          }
          if (namesChanged) {
            await store.saveDataset(dataset);
          }
          messageParts.add(upcomingChanged ? '排位已更新' : '排位沒有變更');
        }
      } on Object catch (error) {
        final label = _errorLabel(error);
        messageParts.add(
          upcoming.isEmpty ? '排位更新暫時不可用（$label）' : '使用已快取排位（$label）',
        );
      }
    }

    try {
      final resultRaces = await _downloadNewResults(dataset.trainedThrough);
      if (resultRaces.isNotEmpty) {
        newRows = engine.appendResults(dataset, resultRaces);
        if (newRows > 0) {
          await store.saveDataset(dataset);
        }
      }
      messageParts.add(newRows > 0 ? '新增 $newRows 筆賽果' : '賽果是最新版本');
    } on Object catch (error) {
      messageParts.add('賽果更新暫時不可用（${_errorLabel(error)}）');
    }

    final model = await store.loadModel();
    if (upcoming.isEmpty) {
      upcoming = bundled.races.map(_raceToMap).toList();
    }
    final storedOdds = await store.loadOddsSnapshots();
    messageParts.add(await _collectWeather(upcoming));
    final predicted = engine.predictRaces(
      races: upcoming,
      dataset: dataset,
      model: model,
      poolOdds: _latestPoolOdds(storedOdds),
      weather: _latestWeather(await store.loadWeatherSnapshots()),
    );
    final pendingTraining = model == null
        ? dataset.trainedThrough.compareTo(bundled.model.trainedThrough) > 0
        : model.datasetVersion != dataset.datasetVersion;
    final summary = _summary(
      bundled: bundled,
      dataset: dataset,
      model: model,
      predicted: predicted,
      hasNewResults: pendingTraining,
      usingMobileBaseline: model == null,
    );
    final job = await store.loadJob();
    final oddsSnapshots = await store.loadOddsSnapshots();
    return RacingMobileLoad(
      racing: summary,
      status: RacingSyncStatus(
        message: messageParts.join(' · '),
        hasNewResults: pendingTraining,
        newRunnerRows: newRows,
        upcomingChanged: upcomingChanged,
        datasetVersion: dataset.datasetVersion,
        latestResultDate: dataset.trainedThrough,
        oddsSnapshotCount: oddsSnapshots.length,
        latestOddsCapturedAt: _latestOddsTimestamp(oddsSnapshots),
        job: job,
      ),
    );
  }

  /// Appends the free Hong Kong Observatory reading of every upcoming meeting.
  Future<String> _collectWeather(List<Map<String, Object?>> upcoming) async {
    final venues = <String, String>{
      for (final race in upcoming)
        if ((race['raceId'] as String?)?.isNotEmpty ?? false)
          race['raceId'] as String: race['venueCode'] as String? ?? '',
    };
    if (venues.isEmpty) {
      return '未有排位，因此沒有收集天氣';
    }
    try {
      final snapshots = await weather.racingObservations(venues);
      for (final snapshot in snapshots) {
        await store.saveWeatherSnapshot(snapshot);
      }
      return snapshots.isEmpty
          ? '天文台觀測暫時不可用'
          : '已記錄 ${snapshots.length} 筆天文台觀測';
    } on Object catch (error) {
      return '天氣更新暫時不可用（${_errorLabel(error)}）';
    }
  }

  /// The most recent stored reading of every race.
  static Map<String, RacingWeatherSnapshot> _latestWeather(
    List<RacingWeatherSnapshot> snapshots,
  ) {
    final latest = <String, RacingWeatherSnapshot>{};
    for (final snapshot in snapshots) {
      final previous = latest[snapshot.raceId];
      if (previous == null ||
          snapshot.capturedAt.isAfter(previous.capturedAt)) {
        latest[snapshot.raceId] = snapshot;
      }
    }
    return latest;
  }

  /// The most recent stored win quote of every race, used as a pool prior.
  static Map<String, Map<String, double>> _latestPoolOdds(
    List<RacingOddsSnapshot> snapshots,
  ) {
    final latest = <String, RacingOddsSnapshot>{};
    for (final snapshot in snapshots) {
      final previous = latest[snapshot.raceId];
      if (previous == null ||
          snapshot.capturedAt.isAfter(previous.capturedAt)) {
        latest[snapshot.raceId] = snapshot;
      }
    }
    return {
      for (final entry in latest.entries)
        if (entry.value.oddsByHorse.length >= 3)
          entry.key: entry.value.oddsByHorse,
    };
  }

  static DateTime? _latestOddsTimestamp(List<RacingOddsSnapshot> snapshots) {
    if (snapshots.isEmpty) {
      return null;
    }
    return snapshots
        .map((snapshot) => snapshot.capturedAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);
  }

  Future<List<Map<String, Object?>>> _downloadUpcoming() async {
    final english = await _get('$baseUrl/racecard');
    final chinese = await _getOptional('$chineseBaseUrl/racecard');
    final first = parseRaceCardDocuments(english, chinese);
    if (first == null) {
      return [];
    }
    final document = html_parser.parse(english);
    final raceNumbers = <int>{
      (first['raceNumber'] as num).toInt(),
      for (final link in document.querySelectorAll('a[href]'))
        if (RegExp(
              r'RaceNo=(\d+)',
              caseSensitive: false,
            ).firstMatch(link.attributes['href'] ?? '')
            case final match?)
          int.parse(match.group(1)!),
    };
    final date = first['date'] as String;
    final venue = first['venueCode'] as String;
    final races = <Map<String, Object?>>[first];
    for (final raceNumber in raceNumbers.toList()..sort()) {
      if (raceNumber == first['raceNumber']) {
        continue;
      }
      final query =
          '?RaceDate=${date.replaceAll('-', '/')}'
          '&Racecourse=$venue&RaceNo=$raceNumber';
      final englishRace = await _get('$baseUrl/racecard$query');
      final chineseRace = await _getOptional('$chineseBaseUrl/racecard$query');
      final race = parseRaceCardDocuments(englishRace, chineseRace);
      if (race != null) {
        races.add(race);
      }
    }
    races.sort(
      (left, right) =>
          (left['raceNumber'] as int).compareTo(right['raceNumber'] as int),
    );
    return races;
  }

  Future<List<Map<String, Object?>>> _downloadNewResults(
    String latestDate,
  ) async {
    final index = html_parser.parse(await _get('$baseUrl/localresults'));
    final latest = DateTime.parse(latestDate);
    final today = DateTime.now();
    final dates = <DateTime>[];
    for (final option in index.querySelectorAll('option')) {
      final parts = option.text.trim().split('/');
      if (parts.length != 3) {
        continue;
      }
      final parsed = DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
      if (parsed != null && parsed.isAfter(latest) && !parsed.isAfter(today)) {
        dates.add(parsed);
      }
    }
    dates.sort();
    final races = <Map<String, Object?>>[];
    for (final date in dates.take(3)) {
      final formatted = _isoDate(date);
      final all = html_parser.parse(
        await _get(
          '$baseUrl/resultsall?RaceDate=${formatted.replaceAll('-', '/')}',
        ),
      );
      final numbers = <int>{};
      for (final label in all.querySelectorAll(
        'div.race_result div.f_fs13.margin_top15 div.bg_blue',
      )) {
        final match = RegExp(r'\d+').firstMatch(label.text);
        if (match != null) {
          numbers.add(int.parse(match.group(0)!));
        }
      }
      for (final number in numbers.toList()..sort()) {
        final document = await _get(
          '$baseUrl/localresults?RaceDate=${formatted.replaceAll('-', '/')}'
          '&RaceNo=$number',
        );
        final race = _parseResultRace(document, date);
        if (race != null) {
          races.add(race);
        }
      }
    }
    return races;
  }

  Map<String, Object?>? parseRaceCardDocuments(String english, String chinese) {
    final document = html_parser.parse(english);
    final chineseDocument = html_parser.parse(chinese);
    final table = document.querySelector('table.starter');
    final chineseTable = chineseDocument.querySelector('table.starter');
    final metadataNode = document
        .querySelectorAll('div.f_fs13')
        .where((node) => node.text.trim().startsWith('Race '))
        .firstOrNull;
    if (table == null || metadataNode == null) {
      return null;
    }
    final text = metadataNode.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final raceMatch = RegExp(
      r'Race\s+(\d+)\s*-\s*(.*?)\s*(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),',
    ).firstMatch(text);
    final dateMatch = RegExp(
      r'(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}',
    ).firstMatch(text);
    final venueMatch = RegExp(
      r',\s*(Sha Tin|Happy Valley),\s*(\d{1,2}:\d{2})',
    ).firstMatch(text);
    if (raceMatch == null || dateMatch == null || venueMatch == null) {
      return null;
    }
    final date = _parseEnglishDate(dateMatch.group(0)!);
    final venue = venueMatch.group(1)!;
    final venueCode = venue == 'Happy Valley' ? 'HV' : 'ST';
    final raceNumber = int.parse(raceMatch.group(1)!);
    final englishRows = table.querySelectorAll('tr').skip(1).toList();
    final chineseRows =
        chineseTable?.querySelectorAll('tr').skip(1).toList() ?? [];
    final chineseNames = <String, String>{};
    for (final row in chineseRows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 5) {
        continue;
      }
      chineseNames[_horseId(cells[3])] = cells[3].text.trim();
    }
    final runners = <Map<String, Object?>>[];
    for (final row in englishRows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 27 || cells[3].text.trim().isEmpty) {
        continue;
      }
      final horseId = _horseId(cells[3]);
      runners.add({
        'horseId': horseId,
        'horseName': cells[3].text.trim(),
        'horseNameEnglish': cells[3].text.trim(),
        'horseNameChinese': chineseNames[horseId] ?? '',
        'number': _integer(cells[0].text),
        'lastSix': cells[1].text.trim(),
        'weight': _number(cells[5].text),
        'jockey': cells[6].text.trim(),
        'draw': _integer(cells[8].text),
        'trainer': cells[9].text.trim(),
        'rating': _number(cells[11].text),
        'horseWeight': _number(cells[13].text),
      });
    }
    if (runners.length < 2) {
      return null;
    }
    final distance =
        int.tryParse(
          RegExp(
                r'(\d{3,4})M',
                caseSensitive: false,
              ).firstMatch(text)?.group(1) ??
              '',
        ) ??
        0;
    final raceClass =
        RegExp(
          r'\bClass\s+([A-Za-z0-9]+)',
          caseSensitive: false,
        ).firstMatch(text)?.group(1) ??
        'Open';
    final going =
        RegExp(
          r'\b(GOOD TO FIRM|GOOD TO YIELDING|WET SLOW|WET FAST|YIELDING|GOOD|SOFT|FAST|SLOW)\b',
          caseSensitive: false,
        ).firstMatch(text)?.group(1)?.toUpperCase() ??
        '';
    final surface = text.toUpperCase().contains('ALL WEATHER') ? 'AWT' : 'TURF';
    final course =
        RegExp(
          r'(?:TURF|ALL WEATHER TRACK)\s*(?:-|,)\s*("[A-Z+0-9]+"\s+Course|[^-\n]+?Course)',
          caseSensitive: false,
        ).firstMatch(text)?.group(1)?.trim() ??
        '';
    return {
      'raceId': 'HK:${_isoDate(date)}:$venueCode:$raceNumber',
      'date': _isoDate(date),
      'startTime': '${_isoDate(date)}T${venueMatch.group(2)}:00+08:00',
      'venue': venue,
      'venueCode': venueCode,
      'raceNumber': raceNumber,
      'raceName': raceMatch.group(2)!.trim(),
      'distanceMetres': distance,
      'surface': surface,
      'course': course,
      'going': going,
      'raceClass': raceClass,
      'runners': runners,
    };
  }

  Map<String, Object?>? _parseResultRace(String html, DateTime date) {
    final document = html_parser.parse(html);
    final venueTable = document.querySelector('table.js_racecard');
    final venue = venueTable?.text.split(':').first.trim() ?? '';
    final metadataTable = document.querySelectorAll('table').where((table) {
      final text = table.text;
      return RegExp(r'RACE\s+\d+').hasMatch(text) && text.contains('Going');
    }).firstOrNull;
    final resultTable = document.querySelectorAll('table').where((table) {
      final text = table.text;
      return text.contains('Horse No.') && text.contains('Finish Time');
    }).firstOrNull;
    if (venue.isEmpty || metadataTable == null || resultTable == null) {
      return null;
    }
    final metadata = metadataTable.text.replaceAll(RegExp(r'\s+'), ' ');
    final raceNumber = int.tryParse(
      RegExp(r'RACE\s+(\d+)').firstMatch(metadata)?.group(1) ?? '',
    );
    if (raceNumber == null) {
      return null;
    }
    final venueCode = venue.toUpperCase().contains('VALLEY') ? 'HV' : 'ST';
    final distance =
        int.tryParse(
          RegExp(r'(\d{3,4})M').firstMatch(metadata)?.group(1) ?? '',
        ) ??
        0;
    final raceClass =
        RegExp(
          r'\bClass\s+([A-Za-z0-9]+)',
          caseSensitive: false,
        ).firstMatch(metadata)?.group(1) ??
        'Open';
    final rows = <Map<String, Object?>>[];
    for (final row in resultTable.querySelectorAll('tr').skip(1)) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 12) {
        continue;
      }
      final finish = int.tryParse(
        RegExp(r'\d+').firstMatch(cells[0].text.trim())?.group(0) ?? '',
      );
      if (finish == null) {
        continue;
      }
      final horseId = _horseId(cells[2]);
      final horseText = cells[2].text.trim();
      rows.add({
        'horseId': horseId,
        'horseName': horseText.replaceFirst(
          RegExp(r'\s*\([A-Z]\d{3}\)\s*$'),
          '',
        ),
        'horseNameEnglish': horseText.replaceFirst(
          RegExp(r'\s*\([A-Z]\d{3}\)\s*$'),
          '',
        ),
        'horseNameChinese': '',
        'jockey': cells[3].text.trim(),
        'trainer': cells[4].text.trim(),
        'weight': _number(cells[5].text),
        'draw': _integer(cells[7].text),
        'finishPosition': finish,
      });
    }
    if (rows.length < 2) {
      return null;
    }
    return {
      'raceId': 'HK:${_isoDate(date)}:$venueCode:$raceNumber',
      'date': _isoDate(date),
      'startTime': '${_isoDate(date)}T00:00:00+08:00',
      'venue': venue,
      'venueCode': venueCode,
      'raceNumber': raceNumber,
      'raceName': '',
      'distanceMetres': distance,
      'surface': metadata.toUpperCase().contains('ALL WEATHER')
          ? 'AWT'
          : 'TURF',
      'course': '',
      'going': '',
      'raceClass': raceClass,
      'runners': rows,
    };
  }

  Future<String> _get(String url) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _getOnce(url);
      } on Object catch (error) {
        lastError = error;
        if (attempt == 2 ||
            (error is! SocketException &&
                error is! TimeoutException &&
                error is! HttpException)) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
    throw lastError!;
  }

  Future<String> _getOptional(String url) async {
    try {
      return await _get(url);
    } on Object {
      return '';
    }
  }

  Future<String> _getOnce(String url) async {
    final previous = _lastRequest;
    if (previous != null) {
      final wait = minimumInterval - DateTime.now().difference(previous);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }
    _lastRequest = DateTime.now();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'HKJC returned ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      return await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
  }

  static String _horseId(Element cell) {
    final href = cell.querySelector('a[href]')?.attributes['href'] ?? '';
    final match = RegExp(
      r'horseid=([^&]+)',
      caseSensitive: false,
    ).firstMatch(href);
    if (match != null) {
      return Uri.decodeComponent(match.group(1)!).replaceFirst('HK_', '');
    }
    final mark = RegExp(r'\(([A-Z]\d{3})\)').firstMatch(cell.text);
    return mark?.group(1) ??
        cell.text.trim().toUpperCase().replaceAll(' ', '_');
  }

  static double? _number(String value) =>
      double.tryParse(value.replaceAll(',', '').replaceAll('+', '').trim());

  static int _integer(String value) => _number(value)?.toInt() ?? 0;

  static String _errorLabel(Object error) {
    if (error is SocketException) {
      return '網絡連線失敗';
    }
    if (error is TimeoutException) {
      return '連線逾時';
    }
    if (error is HttpException) {
      if (error.message.contains('Connection closed')) {
        return '下載連線中斷';
      }
      return '伺服器回應錯誤（${error.message}）';
    }
    if (error is FormatException) {
      return '頁面格式或本機資料不相容';
    }
    return error.runtimeType.toString();
  }

  static DateTime _parseEnglishDate(String value) {
    const months = {
      'January': 1,
      'February': 2,
      'March': 3,
      'April': 4,
      'May': 5,
      'June': 6,
      'July': 7,
      'August': 8,
      'September': 9,
      'October': 10,
      'November': 11,
      'December': 12,
    };
    final match = RegExp(r'(\w+)\s+(\d{1,2}),\s+(\d{4})').firstMatch(value)!;
    return DateTime(
      int.parse(match.group(3)!),
      months[match.group(1)]!,
      int.parse(match.group(2)!),
    );
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _contentHash(List<Map<String, Object?>> races) {
    var hash = 2166136261;
    final stable = jsonEncode(
      races
          .map(
            (race) => {
              'raceId': race['raceId'],
              'startTime': race['startTime'],
              'going': race['going'],
              'runners': (race['runners'] as List<Object?>).map((runner) {
                final value = (runner as Map).cast<String, Object?>();
                return [
                  value['horseId'],
                  value['number'],
                  value['draw'],
                  value['jockey'],
                  value['trainer'],
                ];
              }).toList(),
            },
          )
          .toList(),
    );
    for (final unit in stable.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Map<String, Object?> _raceToMap(RacingRace race) => {
    'raceId': race.raceId,
    'date': _isoDate(race.date),
    'startTime': race.startTime.toIso8601String(),
    'venue': race.venue,
    'venueCode': race.venue.toLowerCase().contains('valley') ? 'HV' : 'ST',
    'raceNumber': race.raceNumber,
    'raceName': race.raceName,
    'distanceMetres': race.distanceMetres,
    'surface': race.surface,
    'course': race.course,
    'going': race.going,
    'raceClass': race.raceClass,
    'runners': race.runners
        .map(
          (runner) => {
            'horseId': runner.horseId,
            'horseName': runner.horseName,
            'horseNameEnglish': runner.horseNameEnglish,
            'horseNameChinese': runner.horseNameChinese,
            'number': runner.number,
            'lastSix': '',
            'weight': 126,
            'jockey': runner.jockey,
            'draw': runner.draw,
            'trainer': runner.trainer,
          },
        )
        .toList(),
  };

  static RacingModelSummary _modelSummary(
    MobileRacingModel model,
    MobileRacingDataset dataset,
  ) {
    final skill = model.baselineWinLogLoss == 0
        ? 0.0
        : 100 *
              (model.baselineWinLogLoss - model.winLogLoss) /
              model.baselineWinLogLoss;
    return RacingModelSummary(
      selectedCandidate: model.useWinModel
          ? 'mobile_logistic'
          : 'mobile_dynamic',
      trainingRaces: model.trainingRaces,
      holdoutRaces: model.holdoutRaces,
      winLogLoss: model.winLogLoss,
      baselineWinLogLoss: model.baselineWinLogLoss,
      winLogLossSkillPercent: skill,
      winBrier: model.winBrier,
      placeBrier: model.placeBrier,
      trainedThrough: model.trainedThrough,
      firstSeason: _firstRacingSeason(dataset),
      lastSeason: _seasonLabel(dataset.trainedThrough),
      trainingSeasons: _trainingSeasonCount(dataset),
    );
  }

  static RacingSummary _summary({
    required RacingSummary bundled,
    required MobileRacingDataset dataset,
    required MobileRacingModel? model,
    required List<Map<String, Object?>> predicted,
    required bool hasNewResults,
    required bool usingMobileBaseline,
  }) {
    final summary = model != null
        ? _modelSummary(model, dataset)
        : usingMobileBaseline
        ? _dynamicModelSummary(bundled.model, dataset)
        : bundled.model;
    final results = <String, RacingResult>{
      for (final result in bundled.results)
        '${result.raceId}:${result.horseId}': result,
      for (final value in dataset.results)
        '${value['raceId']}:${value['horseId']}': RacingResult.fromJson(value),
    };
    return RacingSummary(
      available: predicted.isNotEmpty || bundled.available,
      status: hasNewResults
          ? '已下載新賽果，可重新訓練手機模型'
          : model == null
          ? bundled.status
          : '手機模型已訓練至 ${model.trainedThrough}',
      sourceNotice:
          'HKJC 低頻率條件檢查及本機快取，只供個人非商業研究；'
          '背景工作可被系統暫停，checkpoint 會保留。',
      modelVersion:
          model?.version ?? 'mobile-dynamic-${dataset.datasetVersion}',
      model: summary,
      races: predicted.map(RacingRace.fromJson).toList(),
      results: results.values.toList(),
    );
  }

  static RacingModelSummary _dynamicModelSummary(
    RacingModelSummary bundled,
    MobileRacingDataset dataset,
  ) {
    return RacingModelSummary(
      selectedCandidate: 'mobile_dynamic',
      trainingRaces: dataset.rows.map((row) => row.raceId).toSet().length,
      holdoutRaces: bundled.holdoutRaces,
      winLogLoss: bundled.baselineWinLogLoss,
      baselineWinLogLoss: bundled.baselineWinLogLoss,
      winLogLossSkillPercent: 0,
      winBrier: bundled.winBrier,
      placeBrier: bundled.placeBrier,
      trainedThrough: dataset.trainedThrough,
      firstSeason: _firstRacingSeason(dataset),
      lastSeason: _seasonLabel(dataset.trainedThrough),
      trainingSeasons: _trainingSeasonCount(dataset),
    );
  }

  static String _firstRacingSeason(MobileRacingDataset dataset) {
    if (dataset.rows.isEmpty) {
      return '';
    }
    final earliest = dataset.rows
        .map((row) => row.date)
        .reduce((left, right) => left.compareTo(right) <= 0 ? left : right);
    return _seasonLabel(earliest);
  }

  static int _trainingSeasonCount(MobileRacingDataset dataset) {
    return dataset.rows.map((row) => _seasonLabel(row.date)).toSet().length;
  }

  static String _seasonLabel(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return '';
    }
    final start = parsed.month >= 8 ? parsed.year : parsed.year - 1;
    return '$start/${((start + 1) % 100).toString().padLeft(2, '0')}';
  }
}
