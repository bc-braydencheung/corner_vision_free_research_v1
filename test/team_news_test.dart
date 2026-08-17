import 'package:edgewise/models/team_news.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:edgewise/services/team_news_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shape of the real HKJC preview payload: escaped markup inside a script push.
const _page =
    r'''<script>self.__next_f.push([1,"軍情\u003cbr /\u003e\n'''
    r'''泰國於首仗大勝老撾。\u003cbr /\u003e\n\u003cbr /\u003e\n'''
    r'''泰國\u003cbr /\u003e\n停賽：／\u003cbr /\u003e\n'''
    r'''上陣成疑：猶恩（腿筋）\u003cbr /\u003e\n'''
    r'''受傷／缺陣：古斯達維臣（不詳）\u003cbr /\u003e\n\u003cbr /\u003e\n'''
    r'''馬來西亞\u003cbr /\u003e\n停賽：沙迪、卡列\u003cbr /\u003e\n'''
    r'''上陣成疑：安迪歷（撞傷）\u003cbr /\u003e\n'''
    r'''受傷／缺陣：／\u003cbr /\u003e\n"])</script>''';

void main() {
  test('parses the labelled availability block of each team', () {
    final notes = TeamNewsService.parse(
      _page,
      capturedAt: DateTime(2026, 8, 15),
    );
    final byTeam = {for (final note in notes) note.teamName: note};

    expect(byTeam.keys, containsAll(['泰國', '馬來西亞']));
    final thailand = byTeam['泰國']!;
    expect(thailand.suspended, isEmpty);
    expect(thailand.doubtful, ['猶恩（腿筋）']);
    expect(thailand.absent, ['古斯達維臣（不詳）']);
    expect(thailand.shortfall, 1.5);
    expect(thailand.source, hkjcTeamNewsEndpoint);
    // The HKJC prints this content with a no-verification notice.
    expect(thailand.verified, isFalse);

    final malaysia = byTeam['馬來西亞']!;
    expect(malaysia.suspended, ['沙迪', '卡列']);
    expect(malaysia.absent, isEmpty);
    expect(malaysia.shortfall, 2.5);
  });

  test('returns nothing when no block was published', () {
    expect(
      TeamNewsService.parse(
        '<html><body>未有賽前預測</body></html>',
        capturedAt: DateTime(2026, 8, 15),
      ),
      isEmpty,
    );
  });

  test('the note widens the distribution and never moves the mean', () {
    final note = TeamNewsSnapshot(
      teamName: '阿仙奴',
      capturedAt: DateTime(2026, 8, 15),
      source: hkjcTeamNewsEndpoint,
      suspended: const ['A'],
      doubtful: const ['B', 'C'],
      absent: const ['D', 'E'],
    );
    const plain = HkjcCornerModel();
    final withNews = HkjcCornerModel(homeNews: note);

    expect(plain.newsDispersion, 0);
    expect(withNews.newsDispersion, greaterThan(0));
    expect(withNews.dispersionAt(10), greaterThan(plain.dispersionAt(10)));
    expect(withNews.newsNote, contains('第三方未核實'));
  });

  test('an empty note leaves the model untouched', () {
    final note = TeamNewsSnapshot(
      teamName: '車路士',
      capturedAt: DateTime(2026, 8, 15),
      source: hkjcTeamNewsEndpoint,
      suspended: const [],
      doubtful: const [],
      absent: const [],
    );
    final model = HkjcCornerModel(homeNews: note, awayNews: note);

    expect(model.newsDispersion, 0);
    expect(model.newsNote, isNull);
    expect(model.dispersionAt(10), 0);
  });
}
