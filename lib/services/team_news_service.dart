import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/team_news.dart';

/// Free HKJC football preview page carrying the availability blocks.
const hkjcTeamNewsEndpoint = 'https://football.hkjc.com/zh-hk/home';

/// How many availability captures the on-device archive keeps.
const archiveLimit = 4000;

/// Reads the free HKJC pre-match availability notes.
///
/// The page is a server rendered React app, so the preview text arrives inside
/// escaped script payloads rather than as markup. Only the labelled block is
/// parsed; free prose is never mined for injuries, because a sentence such as
/// "上仗有球員復出" cannot be turned into a count without guessing.
///
/// Every capture is appended instead of overwriting the previous one. Free
/// sources publish only the current note, so a note that is not archived at
/// capture time can never be checked against a later result: without that
/// archive the absence count can only ever widen the distribution, never point
/// it in a direction.
class TeamNewsService {
  TeamNewsService({
    this.endpoint = hkjcTeamNewsEndpoint,
    this.refreshInterval = const Duration(hours: 6),
    Directory? directory,
    HttpClient? client,
  }) : _directoryOverride = directory,
       _clientOverride = client;

  final String endpoint;
  final Duration refreshInterval;
  final Directory? _directoryOverride;
  final HttpClient? _clientOverride;

  DateTime? _lastFetch;
  List<TeamNewsSnapshot> _cache = const [];

  /// Latest note per team name, refreshed at most once per [refreshInterval].
  Future<Map<String, TeamNewsSnapshot>> latest({bool force = false}) async {
    final last = _lastFetch;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < refreshInterval &&
        _cache.isNotEmpty) {
      return _byTeam(_cache);
    }
    final stored = await _load();
    try {
      final fetched = await _fetch();
      if (fetched.isNotEmpty) {
        final history = archive(stored, fetched);
        _cache = history;
        _lastFetch = DateTime.now();
        await _save(history);
        return _byTeam(history);
      }
    } on Object {
      // The note is an uncertainty input only; a failed read keeps the cache.
    }
    _cache = stored;
    return _byTeam(stored);
  }

  Future<List<TeamNewsSnapshot>> _fetch() async {
    final client = _clientOverride ?? HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(endpoint));
      request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (response.statusCode != 200) {
        return const [];
      }
      final body = await response.transform(utf8.decoder).join();
      return parse(body, capturedAt: DateTime.now());
    } finally {
      if (_clientOverride == null) {
        client.close(force: true);
      }
    }
  }

  /// Extracts every labelled availability block from a raw HKJC page.
  static List<TeamNewsSnapshot> parse(
    String body, {
    required DateTime capturedAt,
  }) {
    final text = plainText(body);
    final pattern = RegExp(
      r'([^\n：:]{1,24})\n'
      r'(?:停賽[：:]([^\n]*)\n)?'
      r'(?:上陣成疑[：:]([^\n]*)\n)?'
      r'受傷／缺陣[：:]([^\n]*)',
    );
    final results = <String, TeamNewsSnapshot>{};
    for (final match in pattern.allMatches(text)) {
      final team = match.group(1)!.trim();
      if (team.isEmpty || team.contains('軍情') || team.length > 24) {
        continue;
      }
      final snapshot = TeamNewsSnapshot(
        teamName: team,
        capturedAt: capturedAt,
        source: hkjcTeamNewsEndpoint,
        suspended: _players(match.group(2)),
        doubtful: _players(match.group(3)),
        absent: _players(match.group(4)),
      );
      results[team] = snapshot;
    }
    return results.values.toList();
  }

  /// Unescapes the server payload and drops markup, keeping line breaks.
  static String plainText(String body) {
    final unescaped = body
        .replaceAll(r'\u003c', '<')
        .replaceAll(r'\u003e', '>')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\"', '"');
    return unescaped
        .replaceAll(RegExp('<br */*>', caseSensitive: false), '\n')
        .replaceAll(RegExp('<[^>]*>'), '\n')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&ndash;', '-')
        .replaceAll('&rdquo;', '"')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{2,}'), '\n');
  }

  static List<String> _players(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || value == '／' || value == '/' || value == '-') {
      return const [];
    }
    return value
        .split(RegExp('[、,，]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != '／' && part != '/')
        .toList();
  }

  /// Latest capture of every team, so the archive order cannot change a read.
  static Map<String, TeamNewsSnapshot> _byTeam(List<TeamNewsSnapshot> items) {
    final output = <String, TeamNewsSnapshot>{};
    for (final item in items) {
      final kept = output[item.teamName];
      if (kept == null || item.capturedAt.isAfter(kept.capturedAt)) {
        output[item.teamName] = item;
      }
    }
    return output;
  }

  /// Appends the new captures, keeping every earlier one exactly as read.
  ///
  /// A capture that repeats a stored one verbatim is not appended twice, so an
  /// unchanged page does not inflate the archive. Once [archiveLimit] captures
  /// are held the oldest ones are dropped, so an on-device archive cannot grow
  /// without bound.
  static List<TeamNewsSnapshot> archive(
    List<TeamNewsSnapshot> stored,
    List<TeamNewsSnapshot> fetched,
  ) {
    final identities = stored.map(_identity).toSet();
    final output = List<TeamNewsSnapshot>.from(stored);
    for (final snapshot in fetched) {
      if (identities.add(_identity(snapshot))) {
        output.add(snapshot);
      }
    }
    // Insertion order is already capture order; sorting would only risk
    // reordering the captures that share one page read.
    if (output.length <= archiveLimit) {
      return output;
    }
    return output.sublist(output.length - archiveLimit);
  }

  /// What makes two captures the same note rather than two observations.
  static String _identity(TeamNewsSnapshot snapshot) =>
      '${snapshot.teamName}|${snapshot.suspended.join(',')}|'
      '${snapshot.doubtful.join(',')}|${snapshot.absent.join(',')}';

  /// Every archived capture, oldest first, for later validation work.
  Future<List<TeamNewsSnapshot>> history() async => _load();

  Future<File> _file() async {
    final override = _directoryOverride;
    final directory =
        override ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/edgewise_team_news',
        );
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/hkjc_team_news_v1.json');
  }

  Future<void> _save(List<TeamNewsSnapshot> items) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<TeamNewsSnapshot>> _load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) {
        return const [];
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map<String, Object?>>()
          .map(TeamNewsSnapshot.fromJson)
          .toList();
    } on Object {
      return const [];
    }
  }
}
