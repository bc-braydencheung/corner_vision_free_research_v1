import 'dart:convert';

import 'package:edgewise/services/model_cards.dart';
import 'package:edgewise/services/source_contract.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _forecast({
  String dataVersion = 'v1',
  String generatedAt = '2026-08-01T00:00:00Z',
}) => {
  'dataVersion': dataVersion,
  'generatedAt': generatedAt,
  'leagues': [
    {'code': 'E0', 'name': 'Premier League'},
  ],
};

void main() {
  group('forecastContractViolations', () {
    test('accepts a well formed payload', () {
      expect(forecastContractViolations(_forecast()), isEmpty);
    });

    test('rejects a non object payload', () {
      expect(forecastContractViolations('<html>404</html>'), isNotEmpty);
      expect(forecastContractViolations([1, 2, 3]), isNotEmpty);
    });

    test('reports every missing field', () {
      final violations = forecastContractViolations(<String, Object?>{});
      expect(violations.length, 3);
    });

    test('rejects a wrong type and an unparsable timestamp', () {
      final violations = forecastContractViolations({
        'dataVersion': 7,
        'generatedAt': 'yesterday',
        'leagues': [
          {'code': 'E0'},
        ],
      });
      expect(violations, contains('dataVersion 類型不符'));
      expect(violations, contains('generatedAt 類型不符'));
    });

    test('rejects empty and malformed leagues', () {
      expect(
        forecastContractViolations({..._forecast(), 'leagues': <Object?>[]}),
        contains('leagues 為空'),
      );
      expect(
        forecastContractViolations({
          ..._forecast(),
          'leagues': [
            {'name': 'no code'},
          ],
        }),
        contains('leagues 內有無效項目'),
      );
    });
  });

  group('footballSeedContractViolations', () {
    test('accepts a compact seed', () {
      expect(
        footballSeedContractViolations({
          'schemaVersion': 1,
          'rows': [
            ['E0', '2024-01-01', 'A', 'B', 5, 4],
          ],
        }),
        isEmpty,
      );
    });

    test('rejects missing schema version, rows and short rows', () {
      expect(
        footballSeedContractViolations({
          'rows': [
            ['E0', '2024-01-01', 'A', 'B', 5, 4],
          ],
        }),
        contains('缺少 schemaVersion'),
      );
      expect(
        footballSeedContractViolations({'schemaVersion': 1}),
        contains('缺少 rows'),
      );
      expect(
        footballSeedContractViolations({
          'schemaVersion': 1,
          'rows': <Object?>[],
        }),
        contains('rows 為空'),
      );
      expect(
        footballSeedContractViolations({
          'schemaVersion': 1,
          'rows': [
            ['E0', '2024-01-01'],
          ],
        }),
        contains('rows 內有過短的紀錄'),
      );
      expect(
        footballSeedContractViolations({
          'schemaVersion': 1,
          'rows': [
            [1, 2, 'A', 'B', 5, 4],
          ],
        }),
        contains('rows 內 division/date 類型不符'),
      );
    });
  });

  group('mirrorCandidates', () {
    test('expands a GitHub Pages url into free mirrors', () {
      final candidates = mirrorCandidates(
        'https://owner.github.io/repo/latest.json',
      );
      expect(candidates.length, 4);
      expect(candidates.first, 'https://owner.github.io/repo/latest.json');
      expect(
        candidates,
        contains(
          'https://raw.githubusercontent.com/owner/repo/gh-pages/latest.json',
        ),
      );
      expect(
        candidates,
        contains('https://cdn.jsdelivr.net/gh/owner/repo@gh-pages/latest.json'),
      );
    });

    test('leaves a custom host alone', () {
      expect(mirrorCandidates('https://example.com/data.json'), [
        'https://example.com/data.json',
      ]);
      expect(mirrorCandidates('https://owner.github.io/repo'), [
        'https://owner.github.io/repo',
      ]);
    });
  });

  group('fetchFromMirrors', () {
    Future<MirrorFetchResult<String>> run(
      Map<String, ({int status, String body})> responses, {
      Set<String> throwing = const {},
    }) => fetchFromMirrors<String>(
      urls: responses.keys.toList(),
      fetch: (url) async {
        if (throwing.contains(url)) {
          throw StateError('socket closed');
        }
        return responses[url]!;
      },
      contract: forecastContractViolations,
      parse: (json) => json['dataVersion'] as String,
    );

    test('keeps the freshest healthy mirror', () async {
      final result = await run({
        'https://a/latest.json': (
          status: 200,
          body: jsonEncode(
            _forecast(dataVersion: 'old', generatedAt: '2026-01-01T00:00:00Z'),
          ),
        ),
        'https://b/latest.json': (
          status: 200,
          body: jsonEncode(
            _forecast(dataVersion: 'new', generatedAt: '2026-06-01T00:00:00Z'),
          ),
        ),
      });
      expect(result.ok, isTrue);
      expect(result.payload, 'new');
      expect(result.url, 'https://b/latest.json');
      expect(result.healthyCount, 2);
    });

    test('does not downgrade to an older healthy mirror', () async {
      final result = await run({
        'https://a/latest.json': (
          status: 200,
          body: jsonEncode(
            _forecast(dataVersion: 'new', generatedAt: '2026-06-01T00:00:00Z'),
          ),
        ),
        'https://b/latest.json': (
          status: 200,
          body: jsonEncode(
            _forecast(dataVersion: 'old', generatedAt: '2026-01-01T00:00:00Z'),
          ),
        ),
      });
      expect(result.payload, 'new');
    });

    test('a 200 served payload off contract fails only that mirror', () async {
      final result = await run({
        'https://a/latest.json': (
          status: 200,
          body: jsonEncode({'dataVersion': 'half-deployed'}),
        ),
        'https://b/latest.json': (
          status: 200,
          body: jsonEncode(_forecast(dataVersion: 'good')),
        ),
      });
      expect(result.payload, 'good');
      expect(result.health.first.ok, isFalse);
      expect(result.health.first.violations, isNotEmpty);
      expect(result.health.first.label, contains('格式不符'));
    });

    test('a 200 served html error page is recorded as a failure', () async {
      final result = await run({
        'https://a/latest.json': (status: 200, body: '<html>404</html>'),
      });
      expect(result.ok, isFalse);
      expect(result.health.single.ok, isFalse);
      expect(result.health.single.error, isNotNull);
    });

    test('records http status and transport failures per mirror', () async {
      final result = await run(
        {
          'https://a/latest.json': (status: 503, body: ''),
          'https://b/latest.json': (status: 200, body: ''),
        },
        throwing: {'https://b/latest.json'},
      );
      expect(result.ok, isFalse);
      expect(result.healthyCount, 0);
      expect(result.health.first.statusCode, 503);
      expect(result.health.first.label, contains('503'));
      expect(result.health.last.error, contains('socket closed'));
    });

    test('always tries every mirror so health stays observable', () async {
      final tried = <String>[];
      final result = await fetchFromMirrors<String>(
        urls: const ['https://a', 'https://b', 'https://c'],
        fetch: (url) async {
          tried.add(url);
          return (status: 200, body: jsonEncode(_forecast()));
        },
        contract: forecastContractViolations,
        parse: (json) => json['dataVersion'] as String,
      );
      expect(tried, ['https://a', 'https://b', 'https://c']);
      expect(result.health.length, 3);
      expect(result.health.every((entry) => entry.ok), isTrue);
      expect(result.health.first.toJson()['ok'], isTrue);
    });

    test(
      'mirrors are fetched at the same time, not one after another',
      () async {
        var inFlight = 0;
        var peakInFlight = 0;
        final result = await fetchFromMirrors<String>(
          urls: const ['https://a', 'https://b', 'https://c', 'https://d'],
          fetch: (url) async {
            inFlight++;
            peakInFlight = peakInFlight < inFlight ? inFlight : peakInFlight;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            inFlight--;
            return (status: 200, body: jsonEncode(_forecast()));
          },
          contract: forecastContractViolations,
          parse: (json) => json['dataVersion'] as String,
        );
        expect(peakInFlight, 4);
        expect(result.healthyCount, 4);
      },
    );

    test('a mirror that stalls fails instead of holding the quorum', () async {
      final result = await fetchFromMirrors<String>(
        urls: const ['https://slow', 'https://fast'],
        fetch: (url) async {
          if (url == 'https://slow') {
            await Future<void>.delayed(const Duration(seconds: 30));
          }
          return (status: 200, body: jsonEncode(_forecast()));
        },
        contract: forecastContractViolations,
        parse: (json) => json['dataVersion'] as String,
        timeout: const Duration(milliseconds: 20),
      );
      expect(result.payload, 'v1');
      expect(result.url, 'https://fast');
      expect(result.health.first.ok, isFalse);
      expect(result.health.first.error, contains('TimeoutException'));
    });

    test('parses the winning payload only', () async {
      var parsed = 0;
      final result = await fetchFromMirrors<String>(
        urls: const ['https://a', 'https://b'],
        fetch: (url) async => (status: 200, body: jsonEncode(_forecast())),
        contract: forecastContractViolations,
        parse: (json) {
          parsed++;
          return json['dataVersion'] as String;
        },
      );
      expect(result.payload, 'v1');
      expect(parsed, 1);
    });

    test(
      'a payload that fails to parse falls back to the next mirror',
      () async {
        final result = await fetchFromMirrors<String>(
          urls: const ['https://a', 'https://b'],
          fetch: (url) async => (
            status: 200,
            body: jsonEncode(
              _forecast(
                dataVersion: url == 'https://a' ? 'poison' : 'good',
                generatedAt: url == 'https://a'
                    ? '2026-06-01T00:00:00Z'
                    : '2026-01-01T00:00:00Z',
              ),
            ),
          ),
          contract: forecastContractViolations,
          parse: (json) {
            final version = json['dataVersion'] as String;
            if (version == 'poison') {
              throw const FormatException('unsupported schema');
            }
            return version;
          },
        );
        expect(result.payload, 'good');
        expect(result.url, 'https://b');
        expect(result.health.first.ok, isFalse);
        expect(result.health.first.error, contains('unsupported schema'));
      },
    );
  });

  group('model cards', () {
    test('every card states data, gate and limits', () {
      expect(modelCards.length, greaterThanOrEqualTo(6));
      for (final card in modelCards) {
        expect(card.name, isNotEmpty);
        expect(card.purpose, isNotEmpty);
        expect(card.data, isNotEmpty);
        expect(card.method, isNotEmpty);
        expect(card.gate, isNotEmpty);
        expect(card.limits, isNotEmpty);
      }
    });

    test('card names are unique', () {
      expect(
        modelCards.map((card) => card.name).toSet().length,
        modelCards.length,
      );
    });
  });
}
