import 'dart:io';

import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/models/racing_mobile.dart';
import 'package:edgewise/services/hkjc_mobile_service.dart';
import 'package:edgewise/services/racing_store.dart';
import 'package:edgewise/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merges English and Chinese racecard horse names by permanent ID', () {
    final service = HKJCMobileService();
    final english = _racecard(
      metadata:
          'Race 1 - TEST HANDICAP Wednesday, July 15, 2026, '
          'Happy Valley, 19:10 Class 4 - 1200M, TURF, "C" Course, GOOD',
      horseName: 'EMERGING STAR',
      href: '/en-us/local/information/horse?horseid=HK_2024_K390',
      jockey: 'R Kingscote',
      trainer: 'C W Chang',
    );
    final chinese = _racecard(
      metadata: '測試賽事',
      horseName: '摘星聲升',
      href: '/zh-hk/local/information/horse?horseid=HK_2024_K390',
      jockey: '金誠剛',
      trainer: '鄭俊偉',
    );

    final race = service.parseRaceCardDocuments(english, chinese)!;
    final runner = ((race['runners'] as List).first as Map);

    expect(race['raceId'], 'HK:2026-07-15:HV:1');
    expect(runner['horseId'], '2024_K390');
    expect(runner['horseNameEnglish'], 'EMERGING STAR');
    expect(runner['horseNameChinese'], '摘星聲升');
  });

  test('waits for streamed HKJC responses before closing the client', () async {
    final directory = await Directory.systemTemp.createTemp('hkjc-stream-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    final english = _racecard(
      metadata:
          'Race 1 - TEST HANDICAPWednesday, July 15, 2026, '
          'Happy Valley, 19:10 Turf, "C" Course, 1200M, Good Class 4',
      horseName: 'EMERGING STAR',
      href: '/en/horse?horseid=HK_2024_K390',
      jockey: 'R Kingscote',
      trainer: 'C W Chang',
    );
    final chinese = _racecard(
      metadata: '測試賽事',
      horseName: '摘星聲升',
      href: '/zh/horse?horseid=HK_2024_K390',
      jockey: '金誠剛',
      trainer: '鄭俊偉',
    );
    server.listen((request) async {
      final body = request.uri.path.endsWith('/racecard')
          ? request.uri.path.startsWith('/zh')
                ? chinese
                : english
          : '<select><option>12/07/2026</option></select>';
      final midpoint = body.length ~/ 2;
      request.response.write(body.substring(0, midpoint));
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      request.response.write(body.substring(midpoint));
      await request.response.close();
    });

    final store = RacingStore(directory: directory);
    await store.saveDataset(
      MobileRacingDataset(
        schemaVersion: 1,
        datasetVersion: 'test-v1',
        trainedThrough: '2026-07-12',
        featureNames: List.generate(17, (index) => 'feature_$index'),
        rows: [
          RacingTrainingRow(
            raceId: 'HK:2026-07-12:ST:1',
            date: '2026-07-12',
            fieldSize: 2,
            won: 1,
            placed: 1,
            features: List.filled(17, 0),
          ),
        ],
        horses: {},
        jockeys: {},
        trainers: {},
      ),
    );
    final origin = 'http://${server.address.host}:${server.port}';
    final synced =
        await HKJCMobileService(
          store: store,
          minimumInterval: Duration.zero,
          baseUrl: '$origin/en',
          chineseBaseUrl: '$origin/zh',
          weather: WeatherService(fetch: (url) async => '{}'),
        ).sync(
          const RacingSummary(
            available: false,
            status: '測試',
            sourceNotice: '測試',
            model: RacingModelSummary(trainedThrough: '2026-07-12'),
          ),
          force: true,
        );

    expect(synced.status.message, '排位已更新 · 賽果是最新版本 · 天文台觀測暫時不可用');
    expect(synced.racing.races, hasLength(1));
    expect(synced.racing.races.single.runners.first.horseNameChinese, '摘星聲升');
  });
}

String _racecard({
  required String metadata,
  required String horseName,
  required String href,
  required String jockey,
  required String trainer,
}) {
  final cells = List<String>.filled(27, '<td></td>');
  cells[0] = '<td>1</td>';
  cells[1] = '<td>3/2/1</td>';
  cells[3] = '<td><a href="$href">$horseName</a></td>';
  cells[5] = '<td>126</td>';
  cells[6] = '<td>$jockey</td>';
  cells[8] = '<td>3</td>';
  cells[9] = '<td>$trainer</td>';
  cells[11] = '<td>55</td>';
  cells[13] = '<td>1100</td>';
  return '''
    <html>
      <div class="f_fs13">$metadata</div>
      <table class="starter">
        <tr><th>header</th></tr>
        <tr>${cells.join()}</tr>
        <tr>${cells.join().replaceFirst('>1<', '>2<').replaceFirst(horseName, '$horseName TWO').replaceFirst('K390', 'K391')}</tr>
      </table>
    </html>
  ''';
}
