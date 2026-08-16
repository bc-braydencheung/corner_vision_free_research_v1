/// Provenance ledger: an append-only, hash-chained record of where every
/// displayed number came from.
///
/// Each entry names its stage (dataset, feature, model, prediction,
/// settlement), the free source it came from, its inputs and a digest of its
/// own content, and carries the digest of the entry before it. Any silent edit
/// to an earlier entry breaks the chain, so a research claim can be checked
/// rather than trusted.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Stage of the pipeline an entry describes.
enum ProvenanceStage {
  dataset,
  feature,
  model,
  calibration,
  prediction,
  settlement,
}

extension ProvenanceStageLabel on ProvenanceStage {
  String get label => switch (this) {
    ProvenanceStage.dataset => '資料集',
    ProvenanceStage.feature => '特徵',
    ProvenanceStage.model => '模型',
    ProvenanceStage.calibration => '校準',
    ProvenanceStage.prediction => '預測',
    ProvenanceStage.settlement => '結算',
  };
}

/// One immutable step in the lineage.
class ProvenanceEntry {
  const ProvenanceEntry({
    required this.id,
    required this.stage,
    required this.source,
    required this.recordedAt,
    required this.contentHash,
    required this.previousHash,
    this.inputs = const [],
    this.notes = '',
  });

  factory ProvenanceEntry.fromJson(Map<String, Object?> json) =>
      ProvenanceEntry(
        id: json['id'] as String,
        stage: ProvenanceStage.values.firstWhere(
          (stage) => stage.name == json['stage'],
          orElse: () => ProvenanceStage.dataset,
        ),
        source: json['source'] as String,
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        contentHash: json['contentHash'] as String,
        previousHash: json['previousHash'] as String,
        inputs: (json['inputs'] as List<Object?>? ?? const [])
            .map((value) => value as String)
            .toList(),
        notes: json['notes'] as String? ?? '',
      );

  final String id;
  final ProvenanceStage stage;

  /// Free source or component that produced the artefact.
  final String source;
  final DateTime recordedAt;

  /// Digest of the artefact itself.
  final String contentHash;

  /// Digest of the previous entry, `''` for the first one.
  final String previousHash;
  final List<String> inputs;
  final String notes;

  /// Digest of this entry, which the next entry links to.
  String get chainHash => digestOf({
    'id': id,
    'stage': stage.name,
    'source': source,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'contentHash': contentHash,
    'previousHash': previousHash,
    'inputs': inputs,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'stage': stage.name,
    'source': source,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'contentHash': contentHash,
    'previousHash': previousHash,
    'inputs': inputs,
    'notes': notes,
  };
}

/// Stable digest of any JSON-encodable artefact.
///
/// Maps are encoded with sorted keys so the same artefact always hashes the
/// same way regardless of insertion order.
String digestOf(Object? content) => sha256
    .convert(utf8.encode(_canonical(content)))
    .toString()
    .substring(0, 32);

String _canonical(Object? content) {
  if (content is Map) {
    final keys = content.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonical(content[key])}').join(',')}}';
  }
  if (content is Iterable) {
    return '[${content.map(_canonical).join(',')}]';
  }
  if (content is double && content == content.roundToDouble()) {
    // 3 and 3.0 describe the same artefact.
    return jsonEncode(content.toInt());
  }
  return jsonEncode(content);
}

/// Append-only chain of [ProvenanceEntry].
class ProvenanceLedger {
  const ProvenanceLedger({this.entries = const [], this.limit = 400});

  factory ProvenanceLedger.fromJson(
    Map<String, Object?> json,
  ) => ProvenanceLedger(
    entries: (json['entries'] as List<Object?>? ?? const [])
        .map(
          (value) =>
              ProvenanceEntry.fromJson((value as Map).cast<String, Object?>()),
        )
        .toList(),
    limit: (json['limit'] as num?)?.toInt() ?? 400,
  );

  final List<ProvenanceEntry> entries;

  /// Oldest entries are dropped past this count; the chain stays verifiable
  /// from the retained head onwards.
  final int limit;

  String get headHash => entries.isEmpty ? '' : entries.last.chainHash;

  /// Ledger with one more entry, whose digests are computed here so a caller
  /// cannot forge them.
  ProvenanceLedger append({
    required String id,
    required ProvenanceStage stage,
    required String source,
    required Object? content,
    required DateTime recordedAt,
    List<String> inputs = const [],
    String notes = '',
  }) {
    final entry = ProvenanceEntry(
      id: id,
      stage: stage,
      source: source,
      recordedAt: recordedAt,
      contentHash: digestOf(content),
      previousHash: headHash,
      inputs: inputs,
      notes: notes,
    );
    final appended = [...entries, entry];
    return ProvenanceLedger(
      entries: appended.length > limit
          ? appended.sublist(appended.length - limit)
          : appended,
      limit: limit,
    );
  }

  /// Whether every retained entry still links to the one before it.
  bool get intact {
    for (var index = 1; index < entries.length; index++) {
      if (entries[index].previousHash != entries[index - 1].chainHash) {
        return false;
      }
    }
    return true;
  }

  /// Entries of one stage, oldest first.
  List<ProvenanceEntry> ofStage(ProvenanceStage stage) =>
      entries.where((entry) => entry.stage == stage).toList();

  /// Every entry that fed [id], transitively, oldest first.
  List<ProvenanceEntry> lineageOf(String id) {
    final byId = {for (final entry in entries) entry.id: entry};
    final collected = <String>{};
    final queue = <String>[id];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      final entry = byId[current];
      if (entry == null || !collected.add(current)) {
        continue;
      }
      queue.addAll(entry.inputs);
    }
    return entries.where((entry) => collected.contains(entry.id)).toList();
  }

  Map<String, Object?> toJson() => {
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'limit': limit,
  };
}
