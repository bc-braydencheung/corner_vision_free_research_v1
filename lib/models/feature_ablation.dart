/// Purged-fold feature attribution.
///
/// Twenty-two flat features on a few thousand matches per league is exactly the
/// regime where a model looks better in training than it is, so every feature
/// has to earn its place: each one is dropped in turn and the whole purged
/// walk-forward is re-run. A feature only helps if dropping it makes the folds
/// worse, and that is the number recorded here.
library;

/// What dropping one feature did to the purged folds.
class FeatureAblationEntry {
  const FeatureAblationEntry({
    required this.index,
    required this.name,
    required this.maeDelta,
    required this.brierDelta,
    required this.folds,
  });

  factory FeatureAblationEntry.fromJson(Map<String, Object?> json) =>
      FeatureAblationEntry(
        index: (json['index'] as num).toInt(),
        name: json['name'] as String? ?? '',
        maeDelta: (json['maeDelta'] as num).toDouble(),
        brierDelta: (json['brierDelta'] as num).toDouble(),
        folds: (json['folds'] as num?)?.toInt() ?? 0,
      );

  final int index;
  final String name;

  /// Test MAE without the feature minus test MAE with it.
  ///
  /// Positive means the folds got worse without it, i.e. the feature carried
  /// signal; negative means the model was better off without it.
  final double maeDelta;
  final double brierDelta;
  final int folds;

  /// Whether the feature paid for itself on both metrics.
  bool get carriesSignal => maeDelta > 0.005 && brierDelta >= 0;

  /// Whether dropping it clearly improved the folds.
  bool get hurts => maeDelta < -0.005;

  Map<String, Object?> toJson() => {
    'index': index,
    'name': name,
    'maeDelta': maeDelta,
    'brierDelta': brierDelta,
    'folds': folds,
  };
}

/// One league's attribution run.
class FeatureAblationLeague {
  const FeatureAblationLeague({
    required this.code,
    required this.name,
    required this.baseMae,
    required this.baseBrier,
    required this.folds,
    required this.samples,
    required this.entries,
  });

  factory FeatureAblationLeague.fromJson(Map<String, Object?> json) =>
      FeatureAblationLeague(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        baseMae: (json['baseMae'] as num?)?.toDouble() ?? 0,
        baseBrier: (json['baseBrier'] as num?)?.toDouble() ?? 0,
        folds: (json['folds'] as num?)?.toInt() ?? 0,
        samples: (json['samples'] as num?)?.toInt() ?? 0,
        entries: (json['entries'] as List<Object?>? ?? const [])
            .map(
              (entry) => FeatureAblationEntry.fromJson(
                (entry as Map).cast<String, Object?>(),
              ),
            )
            .toList(growable: false),
      );

  final String code;
  final String name;
  final double baseMae;
  final double baseBrier;
  final int folds;
  final int samples;
  final List<FeatureAblationEntry> entries;

  /// Features that carried signal, best first.
  List<FeatureAblationEntry> get useful =>
      (entries.where((entry) => entry.carriesSignal).toList()
            ..sort((left, right) => right.maeDelta.compareTo(left.maeDelta)))
          .toList(growable: false);

  /// Features the folds were better off without, worst first.
  List<FeatureAblationEntry> get harmful =>
      (entries.where((entry) => entry.hurts).toList()
            ..sort((left, right) => left.maeDelta.compareTo(right.maeDelta)))
          .toList(growable: false);

  Map<String, Object?> toJson() => {
    'code': code,
    'name': name,
    'baseMae': baseMae,
    'baseBrier': baseBrier,
    'folds': folds,
    'samples': samples,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };
}

/// Which features a league's model is allowed to read, and why.
///
/// Selection is decided by the purged folds alone: the surviving set has to
/// score at least as well out of sample as the full feature set, otherwise
/// nothing is dropped and the reason is recorded instead.
class FeatureSelection {
  const FeatureSelection({
    required this.kept,
    required this.baseMae,
    required this.keptMae,
    required this.adopted,
    required this.folds,
    this.note = '',
  });

  /// Selection that reads every feature, used when the folds cannot decide.
  const FeatureSelection.all({required this.note, this.folds = 0})
    : kept = const [],
      baseMae = 0,
      keptMae = 0,
      adopted = false;

  /// Kept feature indices, best first; empty means every feature is kept.
  final List<int> kept;

  /// Purged-fold MAE with every feature.
  final double baseMae;

  /// Purged-fold MAE with only [kept]; equals [baseMae] when nothing was cut.
  final double keptMae;

  /// Whether the reduced set was actually adopted.
  final bool adopted;
  final int folds;

  /// Why the reduced set was rejected, when it was.
  final String note;

  /// Features the model must not read, given [featureCount] columns in total.
  Set<int> droppedOf(int featureCount) => adopted
      ? {
          for (var index = 0; index < featureCount; index++)
            if (!kept.contains(index)) index,
        }
      : const {};
}

/// The stored attribution report, one entry per league.
class FeatureAblationReport {
  const FeatureAblationReport({
    required this.computedAt,
    required this.datasetVersion,
    required this.leagues,
    this.note = '',
  });

  static final empty = FeatureAblationReport(
    computedAt: DateTime.fromMillisecondsSinceEpoch(0),
    datasetVersion: '',
    leagues: const [],
  );

  factory FeatureAblationReport.fromJson(Map<String, Object?> json) =>
      FeatureAblationReport(
        computedAt:
            DateTime.tryParse(json['computedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        datasetVersion: json['datasetVersion'] as String? ?? '',
        note: json['note'] as String? ?? '',
        leagues: (json['leagues'] as List<Object?>? ?? const [])
            .map(
              (league) => FeatureAblationLeague.fromJson(
                (league as Map).cast<String, Object?>(),
              ),
            )
            .toList(growable: false),
      );

  final DateTime computedAt;
  final String datasetVersion;
  final List<FeatureAblationLeague> leagues;
  final String note;

  bool get isEmpty => leagues.isEmpty;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'computedAt': computedAt.toIso8601String(),
    'datasetVersion': datasetVersion,
    'note': note,
    'leagues': leagues.map((league) => league.toJson()).toList(),
  };
}
