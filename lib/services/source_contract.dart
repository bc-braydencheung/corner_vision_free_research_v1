import 'dart:convert';

/// Outcome of one attempt against one free mirror.
class SourceHealth {
  const SourceHealth({
    required this.url,
    required this.ok,
    required this.latencyMs,
    this.statusCode,
    this.error,
    this.generatedAt,
    this.violations = const [],
  });

  final String url;

  /// True only when the payload parsed *and* satisfied the schema contract.
  final bool ok;
  final int latencyMs;
  final int? statusCode;
  final String? error;

  /// `generatedAt` reported by the payload, when it had one.
  final DateTime? generatedAt;

  /// Contract violations found in the payload; empty when [ok].
  final List<String> violations;

  String get label {
    if (ok) {
      return '正常 · ${latencyMs}ms';
    }
    if (violations.isNotEmpty) {
      return '格式不符 · ${violations.first}';
    }
    return error ?? 'HTTP ${statusCode ?? 0}';
  }

  Map<String, Object?> toJson() => {
    'url': url,
    'ok': ok,
    'latencyMs': latencyMs,
    if (statusCode != null) 'statusCode': statusCode,
    if (error != null) 'error': error,
    if (generatedAt != null) 'generatedAt': generatedAt!.toIso8601String(),
    if (violations.isNotEmpty) 'violations': violations,
  };
}

/// One payload accepted from a mirror, with the health of every mirror tried.
class MirrorFetchResult<T> {
  const MirrorFetchResult({required this.health, this.payload, this.url});

  final List<SourceHealth> health;

  /// Freshest payload that satisfied the contract, or `null` when none did.
  final T? payload;

  /// Mirror [payload] came from.
  final String? url;

  bool get ok => payload != null;
  int get healthyCount => health.where((entry) => entry.ok).length;
}

/// Schema contract of the free forecast payload.
///
/// The mirrors are static files on free hosting: a half written deploy, a 404
/// page served with status 200 or a truncated JSON body are all realistic, so a
/// payload is only accepted after the fields the app actually reads are present
/// and of the right type. Failing the contract is reported as source health
/// rather than crashing the load.
List<String> forecastContractViolations(Object? decoded) {
  if (decoded is! Map) {
    return ['payload 不是 JSON 物件'];
  }
  final json = decoded.cast<String, Object?>();
  final violations = <String>[];
  void requireField(String key, bool Function(Object? value) predicate) {
    if (!json.containsKey(key)) {
      violations.add('缺少 $key');
      return;
    }
    if (!predicate(json[key])) {
      violations.add('$key 類型不符');
    }
  }

  requireField('dataVersion', (value) => value is String && value.isNotEmpty);
  requireField(
    'generatedAt',
    (value) => value is String && DateTime.tryParse(value) != null,
  );
  requireField('leagues', (value) => value is List);
  final leagues = json['leagues'];
  if (leagues is List) {
    if (leagues.isEmpty) {
      violations.add('leagues 為空');
    }
    for (final league in leagues) {
      if (league is! Map || league['code'] is! String) {
        violations.add('leagues 內有無效項目');
        break;
      }
    }
  }
  return violations;
}

/// Schema contract of the compact football history seed.
List<String> footballSeedContractViolations(Object? decoded) {
  if (decoded is! Map) {
    return ['payload 不是 JSON 物件'];
  }
  final json = decoded.cast<String, Object?>();
  final violations = <String>[];
  if (json['schemaVersion'] is! int) {
    violations.add('缺少 schemaVersion');
  }
  final rows = json['rows'];
  if (rows is! List) {
    violations.add('缺少 rows');
    return violations;
  }
  if (rows.isEmpty) {
    violations.add('rows 為空');
    return violations;
  }
  for (final row in rows.take(50)) {
    if (row is! List || row.length < 6) {
      violations.add('rows 內有過短的紀錄');
      break;
    }
    if (row[0] is! String || row[1] is! String) {
      violations.add('rows 內 division/date 類型不符');
      break;
    }
  }
  return violations;
}

/// Free read-only mirrors of the same GitHub Pages payload.
///
/// GitHub Pages, raw.githubusercontent, jsDelivr and Statically all serve the
/// identical committed file for free, and they fail independently (a Pages
/// deploy can be mid-flight while jsDelivr still holds the previous good
/// build). Trying all of them turns a single point of failure into a quorum,
/// and the freshest contract-satisfying payload wins.
List<String> mirrorCandidates(String primary) {
  final candidates = <String>[primary];
  final uri = Uri.tryParse(primary);
  if (uri == null || !uri.host.endsWith('github.io')) {
    return candidates;
  }
  final owner = uri.host.split('.').first;
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (segments.length < 2) {
    return candidates;
  }
  final repository = segments.first;
  final path = segments.skip(1).join('/');
  candidates.addAll([
    'https://raw.githubusercontent.com/$owner/$repository/gh-pages/$path',
    'https://cdn.jsdelivr.net/gh/$owner/$repository@gh-pages/$path',
    'https://cdn.statically.io/gh/$owner/$repository/gh-pages/$path',
  ]);
  return candidates;
}

/// Fetches every mirror, keeps the freshest payload that passes [contract].
///
/// [fetch] returns the raw body of one mirror or throws; [parse] turns an
/// accepted decoded payload into the model type. Mirrors are always all tried,
/// because the health of a mirror that is currently not needed is exactly what
/// tells the research page a source is degrading.
///
/// The mirrors are fetched concurrently — they are independent hosts, so paying
/// for their latencies one after another only delays the first paint — while
/// health is still reported in [urls] order and only the winning payload is
/// parsed.
///
/// A mirror that has not answered within [timeout] is reported as a failed
/// source rather than holding the whole quorum: cdn.statically.io has been
/// observed answering a 722 KB model file after 580 seconds.
Future<MirrorFetchResult<T>> fetchFromMirrors<T>({
  required List<String> urls,
  required Future<({int status, String body})> Function(String url) fetch,
  required List<String> Function(Object? decoded) contract,
  required T Function(Map<String, Object?> json) parse,
  DateTime? Function(Map<String, Object?> json)? generatedAt,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final fetched = await Future.wait([
    for (final url in urls)
      Future(() async {
        final started = DateTime.now();
        try {
          final response = await fetch(url).timeout(timeout);
          return (
            latency: DateTime.now().difference(started).inMilliseconds,
            response: response,
            error: null,
          );
        } on Object catch (error) {
          return (
            latency: DateTime.now().difference(started).inMilliseconds,
            response: null,
            error: '$error',
          );
        }
      }),
  ]);
  final health = <SourceHealth>[];
  final accepted =
      <({int index, String url, Map<String, Object?> json, DateTime? stamp})>[];
  for (var index = 0; index < urls.length; index++) {
    final url = urls[index];
    final attempt = fetched[index];
    final latency = attempt.latency;
    final response = attempt.response;
    if (response == null) {
      health.add(
        SourceHealth(
          url: url,
          ok: false,
          latencyMs: latency,
          error: attempt.error,
        ),
      );
      continue;
    }
    try {
      if (response.status != 200) {
        health.add(
          SourceHealth(
            url: url,
            ok: false,
            latencyMs: latency,
            statusCode: response.status,
          ),
        );
        continue;
      }
      final decoded = jsonDecode(response.body);
      final violations = contract(decoded);
      if (violations.isNotEmpty) {
        health.add(
          SourceHealth(
            url: url,
            ok: false,
            latencyMs: latency,
            statusCode: response.status,
            violations: violations,
          ),
        );
        continue;
      }
      final json = (decoded as Map).cast<String, Object?>();
      final stamp = generatedAt == null
          ? DateTime.tryParse('${json['generatedAt']}')
          : generatedAt(json);
      health.add(
        SourceHealth(
          url: url,
          ok: true,
          latencyMs: latency,
          statusCode: response.status,
          generatedAt: stamp,
        ),
      );
      accepted.add((index: index, url: url, json: json, stamp: stamp));
    } on Object catch (error) {
      health.add(
        SourceHealth(url: url, ok: false, latencyMs: latency, error: '$error'),
      );
    }
  }
  // Freshest payload first, so only one candidate is normally parsed; a
  // candidate whose parse throws is demoted to a failed mirror and the next
  // freshest one is tried, exactly as when every mirror was parsed in turn.
  accepted.sort((left, right) {
    if (left.stamp == right.stamp) {
      return left.index.compareTo(right.index);
    }
    if (left.stamp == null) {
      return 1;
    }
    if (right.stamp == null) {
      return -1;
    }
    return right.stamp!.compareTo(left.stamp!);
  });
  for (final candidate in accepted) {
    try {
      return MirrorFetchResult<T>(
        health: health,
        payload: parse(candidate.json),
        url: candidate.url,
      );
    } on Object catch (error) {
      final failed = health[candidate.index];
      health[candidate.index] = SourceHealth(
        url: failed.url,
        ok: false,
        latencyMs: failed.latencyMs,
        statusCode: failed.statusCode,
        error: '$error',
      );
    }
  }
  return MirrorFetchResult<T>(health: health);
}
