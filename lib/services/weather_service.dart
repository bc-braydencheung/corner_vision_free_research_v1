import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/football_mobile.dart';
import '../models/hkjc_football.dart';
import '../models/racing_mobile.dart';

/// Free weather sources.
///
/// * Open-Meteo publishes an hourly forecast for any coordinate without a key
///   or a quota, which covers the European football venues.
/// * The Hong Kong Observatory publishes the current district readings as open
///   data, which covers Sha Tin and Happy Valley.
///
/// Both are recorded as append-only snapshots with the time they were captured
/// and the time they are valid for, so a stale forecast can never be mistaken
/// for the observation of a settled event.
const openMeteoEndpoint = 'https://api.open-meteo.com/v1/forecast';
const hkoCurrentEndpoint =
    'https://data.weather.gov.hk/weatherAPI/opendata/weather.php'
    '?dataType=rhrread&lang=en';

/// A coarse, city level venue coordinate.
///
/// Only the free hourly weather grid is read with these, and that grid is far
/// coarser than a stadium, so a city centre coordinate is the honest precision
/// to claim here.
class VenueLocation {
  const VenueLocation(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// City coordinates of the clubs quoted by the HKJC in the two tracked
/// tournaments, keyed by the normalised English club name.
const venueLocations = <String, VenueLocation>{
  // Premier League
  'arsenal': VenueLocation(51.555, -0.108),
  'aston villa': VenueLocation(52.509, -1.885),
  'bournemouth': VenueLocation(50.735, -1.838),
  'brentford': VenueLocation(51.491, -0.289),
  'brighton': VenueLocation(50.862, -0.084),
  'burnley': VenueLocation(53.789, -2.230),
  'chelsea': VenueLocation(51.482, -0.191),
  'crystal palace': VenueLocation(51.398, -0.086),
  'everton': VenueLocation(53.439, -2.966),
  'fulham': VenueLocation(51.475, -0.222),
  'leeds': VenueLocation(53.778, -1.572),
  'liverpool': VenueLocation(53.431, -2.961),
  'man city': VenueLocation(53.483, -2.200),
  'man united': VenueLocation(53.463, -2.291),
  'newcastle': VenueLocation(54.976, -1.622),
  'nottingham forest': VenueLocation(52.940, -1.133),
  'sunderland': VenueLocation(54.914, -1.388),
  'tottenham': VenueLocation(51.604, -0.066),
  'west ham': VenueLocation(51.539, -0.017),
  'wolves': VenueLocation(52.590, -2.130),
  // La Liga
  'alaves': VenueLocation(42.847, -2.688),
  'ath bilbao': VenueLocation(43.264, -2.949),
  'athletic club': VenueLocation(43.264, -2.949),
  'atletico madrid': VenueLocation(40.436, -3.599),
  'barcelona': VenueLocation(41.381, 2.123),
  'betis': VenueLocation(37.356, -5.982),
  'celta': VenueLocation(42.212, -8.740),
  'elche': VenueLocation(38.267, -0.712),
  'espanol': VenueLocation(41.348, 2.076),
  'espanyol': VenueLocation(41.348, 2.076),
  'getafe': VenueLocation(40.325, -3.715),
  'girona': VenueLocation(41.961, 2.828),
  'levante': VenueLocation(39.475, -0.364),
  'mallorca': VenueLocation(39.590, 2.630),
  'osasuna': VenueLocation(42.796, -1.637),
  'oviedo': VenueLocation(43.360, -5.865),
  'rayo vallecano': VenueLocation(40.392, -3.659),
  'real madrid': VenueLocation(40.453, -3.688),
  'real sociedad': VenueLocation(43.301, -1.974),
  'sevilla': VenueLocation(37.384, -5.971),
  'valencia': VenueLocation(39.475, -0.358),
  'villarreal': VenueLocation(39.944, -0.104),
};

/// HKO district whose readings stand in for a HKJC racecourse.
const hkjcWeatherDistricts = <String, String>{
  'ST': 'Sha Tin',
  'HV': 'Happy Valley',
};

/// One hour of the Open-Meteo forecast.
class HourlyWeather {
  const HourlyWeather({
    required this.validAt,
    required this.temperatureC,
    required this.precipitationProbability,
    required this.windSpeedKmh,
  });

  final DateTime validAt;
  final double temperatureC;
  final double precipitationProbability;
  final double windSpeedKmh;
}

/// Parses the Open-Meteo hourly block into typed rows.
List<HourlyWeather> parseOpenMeteoHourly(Map<String, Object?> payload) {
  final hourly = payload['hourly'];
  if (hourly is! Map) {
    return const [];
  }
  final times = (hourly['time'] as List<Object?>? ?? const []).cast<Object?>();
  double? number(String key, int index) {
    final values = hourly[key] as List<Object?>?;
    if (values == null || values.length <= index) {
      return null;
    }
    return (values[index] as num?)?.toDouble();
  }

  final rows = <HourlyWeather>[];
  for (var index = 0; index < times.length; index++) {
    final validAt = DateTime.tryParse('${times[index]}Z');
    final temperature = number('temperature_2m', index);
    if (validAt == null || temperature == null) {
      continue;
    }
    rows.add(
      HourlyWeather(
        validAt: validAt,
        temperatureC: temperature,
        precipitationProbability:
            (number('precipitation_probability', index) ?? 0) / 100,
        windSpeedKmh: number('wind_speed_10m', index) ?? 0,
      ),
    );
  }
  return rows;
}

/// The forecast hour closest to [target], or `null` when nothing is close.
HourlyWeather? nearestHour(
  List<HourlyWeather> hours,
  DateTime target, {
  Duration tolerance = const Duration(hours: 2),
}) {
  HourlyWeather? best;
  var bestGap = tolerance;
  for (final hour in hours) {
    final gap = hour.validAt.difference(target).abs();
    if (gap <= bestGap) {
      best = hour;
      bestGap = gap;
    }
  }
  return best;
}

/// Parses one HKO district reading out of the open data payload.
RacingWeatherSnapshot? parseHkoReading(
  Map<String, Object?> payload, {
  required String district,
  required String raceId,
  required DateTime capturedAt,
}) {
  double? readingFor(String block) {
    final section = payload[block];
    if (section is! Map) {
      return null;
    }
    for (final entry in (section['data'] as List<Object?>? ?? const [])) {
      final row = entry is Map ? entry.cast<String, Object?>() : null;
      if (row == null || row['place'] != district) {
        continue;
      }
      final value = row['value'] ?? row['max'];
      if (value is num) {
        return value.toDouble();
      }
    }
    return null;
  }

  final temperature = readingFor('temperature');
  if (temperature == null) {
    return null;
  }
  final humidity = payload['humidity'] is Map
      ? ((payload['humidity'] as Map)['data'] as List<Object?>? ?? const [])
                .whereType<Map>()
                .map((row) => (row['value'] as num?)?.toDouble())
                .firstWhere((value) => value != null, orElse: () => null) ??
            0.0
      : 0.0;
  final validAt =
      DateTime.tryParse(payload['updateTime'] as String? ?? '')?.toUtc() ??
      capturedAt;
  return RacingWeatherSnapshot(
    raceId: raceId,
    capturedAt: capturedAt,
    source: 'hko-rhrread',
    district: district,
    validAt: validAt,
    temperatureC: temperature,
    humidity: humidity / 100,
    rainfallMm: readingFor('rainfall') ?? 0,
  );
}

/// Collects the free weather feeds and appends them to the local stores.
class WeatherService {
  WeatherService({Future<String> Function(String url)? fetch})
    : _fetch = fetch ?? _httpGet;

  final Future<String> Function(String url) _fetch;

  /// Forecast for one fixture, or `null` when the venue is unknown to the free
  /// coordinate table or the feed is unavailable.
  Future<FootballWeatherSnapshot?> footballForecast(
    HkjcFootballFixture fixture, {
    DateTime? now,
  }) async {
    final key = _venueKey(fixture);
    final location = venueLocations[key];
    if (location == null) {
      return null;
    }
    final capturedAt = (now ?? DateTime.now()).toUtc();
    final url =
        '$openMeteoEndpoint'
        '?latitude=${location.latitude}&longitude=${location.longitude}'
        '&hourly=temperature_2m,precipitation_probability,wind_speed_10m'
        '&forecast_days=3&timezone=UTC';
    final Map<String, Object?> payload;
    try {
      payload = (jsonDecode(await _fetch(url)) as Map).cast<String, Object?>();
    } on Object {
      return null;
    }
    final hour = nearestHour(
      parseOpenMeteoHourly(payload),
      fixture.kickOffTime.toUtc(),
    );
    if (hour == null) {
      return null;
    }
    return FootballWeatherSnapshot(
      matchId: fixture.matchId,
      capturedAt: capturedAt,
      validAt: hour.validAt,
      source: 'open-meteo',
      latitude: location.latitude,
      longitude: location.longitude,
      temperatureC: hour.temperatureC,
      precipitationProbability: hour.precipitationProbability,
      windSpeedKmh: hour.windSpeedKmh,
    );
  }

  /// Current racecourse readings for the given races.
  Future<List<RacingWeatherSnapshot>> racingObservations(
    Map<String, String> raceIdToVenueCode, {
    DateTime? now,
  }) async {
    if (raceIdToVenueCode.isEmpty) {
      return const [];
    }
    final capturedAt = (now ?? DateTime.now()).toUtc();
    final Map<String, Object?> payload;
    try {
      payload = (jsonDecode(await _fetch(hkoCurrentEndpoint)) as Map)
          .cast<String, Object?>();
    } on Object {
      return const [];
    }
    final snapshots = <RacingWeatherSnapshot>[];
    for (final entry in raceIdToVenueCode.entries) {
      final district = hkjcWeatherDistricts[entry.value.toUpperCase()];
      if (district == null) {
        continue;
      }
      final snapshot = parseHkoReading(
        payload,
        district: district,
        raceId: entry.key,
        capturedAt: capturedAt,
      );
      if (snapshot != null) {
        snapshots.add(snapshot);
      }
    }
    return snapshots;
  }

  static String _venueKey(HkjcFootballFixture fixture) {
    final english = fixture.homeTeamEnglish.trim();
    return (english.isEmpty ? fixture.homeTeam : english).toLowerCase();
  }

  static Future<String> _httpGet(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} for $url');
      }
      return response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}
