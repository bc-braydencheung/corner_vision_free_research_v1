import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/signal_change.dart';

/// Local store of the signal log; nothing leaves the device.
class SignalLogService {
  static const _storageKey = 'edgewise_signal_log_v1';

  /// Hard cap on stored readings, so a long-running install stays bounded.
  static const _limit = 4000;

  Future<List<SignalChange>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      return [];
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      return [];
    }
    final payload = decoded.cast<String, Object?>();
    final records = payload['records'] as List<Object?>? ?? const [];
    final changes = <SignalChange>[];
    for (final value in records) {
      if (value is! Map) {
        continue;
      }
      // A row written by an older or partial build is dropped rather than
      // guessed at: an invented reading would read as a real signal.
      try {
        changes.add(SignalChange.fromJson(value.cast<String, Object?>()));
      } on Object {
        continue;
      }
    }
    changes.sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
    return changes;
  }

  Future<void> save(List<SignalChange> changes) async {
    final preferences = await SharedPreferences.getInstance();
    final sorted = changes.toList()
      ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
    final retained = sorted.length <= _limit
        ? sorted
        : sorted.sublist(sorted.length - _limit);
    await preferences.setString(
      _storageKey,
      jsonEncode({
        'schemaVersion': 1,
        'records': retained.map((change) => change.toJson()).toList(),
      }),
    );
  }
}
