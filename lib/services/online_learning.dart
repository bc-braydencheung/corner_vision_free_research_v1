/// Online learning primitives: an exponentially weighted ensemble, two drift
/// detectors and the checkpoint bookkeeping needed to roll a bad update back.
///
/// Everything here is replayed strictly in settlement order, one settled
/// outcome at a time, so no update can ever see a result that had not happened
/// yet. Weights move multiplicatively and are floored, which is what keeps a
/// single strange match from rewriting the model.
library;

import 'dart:math';

/// Squared error of a probabilistic forecast of a binary outcome.
double brierLoss(double probability, bool outcome) =>
    squaredLoss(probability, outcome ? 1.0 : 0.0);

/// Squared error against a probability target.
///
/// A binary result is the special case `target == 0` or `target == 1`; a
/// closing-line probability is a target strictly inside the interval, which is
/// why the same loss can score both kinds of label on one scale.
double squaredLoss(double probability, double target) {
  final clamped = probability.clamp(0.0, 1.0);
  final bounded = target.clamp(0.0, 1.0);
  return (clamped - bounded) * (clamped - bounded);
}

/// What the app thinks caused an unusual observation.
///
/// Separating these matters because only one of them is a reason to change the
/// model: a broken feed or a void match must never be learned from, and a
/// market that has moved is new information rather than a model failure.
enum LearningEventKind { healthy, dataError, voidEvent, marketMove, modelDrift }

extension LearningEventLabel on LearningEventKind {
  String get label => switch (this) {
    LearningEventKind.healthy => '正常',
    LearningEventKind.dataError => '資料異常（不學習）',
    LearningEventKind.voidEvent => '賽事取消／作廢（不學習）',
    LearningEventKind.marketMove => '市場已移動（只記錄）',
    LearningEventKind.modelDrift => '模型漂移（已回滾）',
  };

  /// Whether an observation of this kind is allowed to move the weights.
  bool get learnable =>
      this == LearningEventKind.healthy || this == LearningEventKind.marketMove;
}

/// Classifies one settled observation before it is allowed to teach anything.
LearningEventKind classifyEvent({
  required bool missingData,
  required bool voided,
  required double marketShift,
  required bool driftAlarm,
  double marketShiftThreshold = 0.18,
}) {
  if (voided) {
    return LearningEventKind.voidEvent;
  }
  if (missingData) {
    return LearningEventKind.dataError;
  }
  if (driftAlarm) {
    return LearningEventKind.modelDrift;
  }
  if (marketShift.abs() >= marketShiftThreshold) {
    return LearningEventKind.marketMove;
  }
  return LearningEventKind.healthy;
}

/// Multiplicative (Hedge) weights over competing forecasters.
///
/// The regret of Hedge against the best single member grows like
/// `sqrt(T log n)`, so the blend cannot end up much worse than whichever member
/// turns out to be right, which is the property that makes it safe to run
/// unattended.
class HedgeEnsemble {
  const HedgeEnsemble({
    required this.weights,
    this.eta = 0.6,
    this.floor = 0.03,
  });

  factory HedgeEnsemble.uniform(List<String> members, {double eta = 0.6}) {
    if (members.isEmpty) {
      throw ArgumentError.value(members, 'members', 'Must not be empty.');
    }
    return HedgeEnsemble(
      weights: {for (final member in members) member: 1 / members.length},
      eta: eta,
    );
  }

  factory HedgeEnsemble.fromJson(Map<String, Object?> json) => HedgeEnsemble(
    weights: (json['weights'] as Map).map(
      (key, value) => MapEntry(key as String, (value as num).toDouble()),
    ),
    eta: (json['eta'] as num?)?.toDouble() ?? 0.6,
  );

  final Map<String, double> weights;

  /// Learning rate; larger reacts faster and forgets faster.
  final double eta;

  /// Smallest weight any member keeps, so a member can always come back.
  final double floor;

  /// New weights after one round of losses, keyed the same way as [weights].
  HedgeEnsemble update(Map<String, double> losses) {
    final updated = <String, double>{};
    for (final entry in weights.entries) {
      final loss = losses[entry.key];
      updated[entry.key] = loss == null
          ? entry.value
          : entry.value * exp(-eta * loss);
    }
    return HedgeEnsemble(weights: _normalise(updated), eta: eta, floor: floor);
  }

  /// Weighted average of the members' forecasts.
  double blend(Map<String, double> predictions) {
    var total = 0.0;
    var mass = 0.0;
    for (final entry in weights.entries) {
      final prediction = predictions[entry.key];
      if (prediction == null) {
        continue;
      }
      total += entry.value * prediction;
      mass += entry.value;
    }
    return mass == 0 ? 0 : total / mass;
  }

  double weightOf(String member) => weights[member] ?? 0;

  Map<String, Object?> toJson() => {'weights': weights, 'eta': eta};

  Map<String, double> _normalise(Map<String, double> raw) {
    final sum = raw.values.fold<double>(0, (total, value) => total + value);
    if (sum <= 0 || !sum.isFinite) {
      return {for (final key in raw.keys) key: 1 / raw.length};
    }
    final scaled = {
      for (final entry in raw.entries) entry.key: entry.value / sum,
    };
    // The floor is honoured exactly: members already at the floor keep it and
    // only the free mass above it is rescaled, so no member can be squeezed
    // below the floor by the renormalisation itself.
    final pinned = scaled.keys.where((key) => scaled[key]! <= floor).toSet();
    if (pinned.isEmpty) {
      return scaled;
    }
    final freeMass = 1 - floor * pinned.length;
    if (freeMass <= 0) {
      return {for (final key in scaled.keys) key: 1 / scaled.length};
    }
    final freeSum = scaled.entries
        .where((entry) => !pinned.contains(entry.key))
        .fold<double>(0, (total, entry) => total + entry.value);
    return {
      for (final entry in scaled.entries)
        entry.key: pinned.contains(entry.key)
            ? floor
            : freeSum <= 0
            ? freeMass / (scaled.length - pinned.length)
            : entry.value / freeSum * freeMass,
    };
  }
}

/// Page–Hinkley test on a loss stream.
///
/// It accumulates how far the loss runs above its own running mean plus a
/// tolerance and alarms when that excursion passes a threshold, which detects a
/// sustained deterioration far sooner than a rolling average does.
class PageHinkleyDetector {
  const PageHinkleyDetector({
    this.delta = 0.005,
    this.threshold = 0.35,
    this.mean = 0,
    this.samples = 0,
    this.cumulative = 0,
    this.minimum = 0,
  });

  factory PageHinkleyDetector.fromJson(Map<String, Object?> json) =>
      PageHinkleyDetector(
        delta: (json['delta'] as num?)?.toDouble() ?? 0.005,
        threshold: (json['threshold'] as num?)?.toDouble() ?? 0.35,
        mean: (json['mean'] as num?)?.toDouble() ?? 0,
        samples: (json['samples'] as num?)?.toInt() ?? 0,
        cumulative: (json['cumulative'] as num?)?.toDouble() ?? 0,
        minimum: (json['minimum'] as num?)?.toDouble() ?? 0,
      );

  final double delta;
  final double threshold;
  final double mean;
  final int samples;
  final double cumulative;
  final double minimum;

  /// Size of the current excursion above the running mean.
  double get statistic => cumulative - minimum;
  bool get alarm => samples >= 20 && statistic > threshold;

  PageHinkleyDetector observe(double loss) {
    final count = samples + 1;
    final updatedMean = mean + (loss - mean) / count;
    final updatedCumulative = cumulative + loss - updatedMean - delta;
    return PageHinkleyDetector(
      delta: delta,
      threshold: threshold,
      mean: updatedMean,
      samples: count,
      cumulative: updatedCumulative,
      minimum: min(minimum, updatedCumulative),
    );
  }

  /// Fresh detector that keeps the configuration but forgets the excursion.
  PageHinkleyDetector reset() =>
      PageHinkleyDetector(delta: delta, threshold: threshold);

  Map<String, Object?> toJson() => {
    'delta': delta,
    'threshold': threshold,
    'mean': mean,
    'samples': samples,
    'cumulative': cumulative,
    'minimum': minimum,
  };
}

/// Two-sided CUSUM on the difference between two competing loss streams.
///
/// Positive drift means the challenger is losing to the champion; negative
/// drift means it is beating it well enough to be promoted.
class CusumDetector {
  const CusumDetector({
    this.slack = 0.004,
    this.threshold = 0.25,
    this.positive = 0,
    this.negative = 0,
    this.samples = 0,
  });

  factory CusumDetector.fromJson(Map<String, Object?> json) => CusumDetector(
    slack: (json['slack'] as num?)?.toDouble() ?? 0.004,
    threshold: (json['threshold'] as num?)?.toDouble() ?? 0.25,
    positive: (json['positive'] as num?)?.toDouble() ?? 0,
    negative: (json['negative'] as num?)?.toDouble() ?? 0,
    samples: (json['samples'] as num?)?.toInt() ?? 0,
  );

  final double slack;
  final double threshold;
  final double positive;
  final double negative;
  final int samples;

  bool get degraded => samples >= 20 && positive > threshold;
  bool get improved => samples >= 20 && negative < -threshold;

  CusumDetector observe(double difference) => CusumDetector(
    slack: slack,
    threshold: threshold,
    positive: max(0, positive + difference - slack),
    negative: min(0, negative + difference + slack),
    samples: samples + 1,
  );

  CusumDetector reset() => CusumDetector(slack: slack, threshold: threshold);

  Map<String, Object?> toJson() => {
    'slack': slack,
    'threshold': threshold,
    'positive': positive,
    'negative': negative,
    'samples': samples,
  };
}

/// A set of weights that was good enough to return to.
class OnlineCheckpoint {
  const OnlineCheckpoint({
    required this.version,
    required this.weights,
    required this.brier,
    required this.samples,
    required this.createdAt,
  });

  factory OnlineCheckpoint.fromJson(Map<String, Object?> json) =>
      OnlineCheckpoint(
        version: json['version'] as int,
        weights: HedgeEnsemble.fromJson(
          (json['weights'] as Map).cast<String, Object?>(),
        ),
        brier: (json['brier'] as num).toDouble(),
        samples: (json['samples'] as num).toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final int version;
  final HedgeEnsemble weights;
  final double brier;
  final int samples;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'version': version,
    'weights': weights.toJson(),
    'brier': brier,
    'samples': samples,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

/// Everything the online learner carries between runs.
class OnlineLearningState {
  const OnlineLearningState({
    required this.ensemble,
    required this.pageHinkley,
    required this.cusum,
    required this.version,
    required this.settledSamples,
    required this.blendBrier,
    required this.championBrier,
    required this.rollbacks,
    required this.event,
    required this.note,
    this.closingLineSamples = 0,
    this.resultSamples = 0,
    this.checkpoints = const [],
    this.skipped = const {},
    this.updatedAt,
  });

  static OnlineLearningState initial(List<String> members) =>
      OnlineLearningState(
        ensemble: HedgeEnsemble.uniform(members),
        pageHinkley: const PageHinkleyDetector(),
        cusum: const CusumDetector(),
        version: 1,
        settledSamples: 0,
        blendBrier: 0,
        championBrier: 0,
        rollbacks: 0,
        event: LearningEventKind.healthy,
        note: '尚未有已結算樣本，權重維持平均。',
      );

  factory OnlineLearningState.fromJson(
    Map<String, Object?> json,
  ) => OnlineLearningState(
    ensemble: HedgeEnsemble.fromJson(
      (json['ensemble'] as Map).cast<String, Object?>(),
    ),
    pageHinkley: PageHinkleyDetector.fromJson(
      (json['pageHinkley'] as Map).cast<String, Object?>(),
    ),
    cusum: CusumDetector.fromJson(
      (json['cusum'] as Map).cast<String, Object?>(),
    ),
    version: (json['version'] as num).toInt(),
    settledSamples: (json['settledSamples'] as num).toInt(),
    blendBrier: (json['blendBrier'] as num).toDouble(),
    championBrier: (json['championBrier'] as num).toDouble(),
    rollbacks: (json['rollbacks'] as num).toInt(),
    event: LearningEventKind.values.firstWhere(
      (kind) => kind.name == json['event'],
      orElse: () => LearningEventKind.healthy,
    ),
    note: json['note'] as String? ?? '',
    closingLineSamples: (json['closingLineSamples'] as num?)?.toInt() ?? 0,
    resultSamples:
        (json['resultSamples'] as num?)?.toInt() ??
        (json['settledSamples'] as num).toInt(),
    checkpoints: (json['checkpoints'] as List<Object?>? ?? const [])
        .map(
          (value) =>
              OnlineCheckpoint.fromJson((value as Map).cast<String, Object?>()),
        )
        .toList(),
    skipped: (json['skipped'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key as String, (value as num).toInt()),
    ),
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.parse(json['updatedAt'] as String),
  );

  final HedgeEnsemble ensemble;
  final PageHinkleyDetector pageHinkley;
  final CusumDetector cusum;

  /// Bumped on every rollback so a displayed probability can be traced back.
  final int version;
  final int settledSamples;

  /// Brier score of the blend and of the best single member, on the same
  /// settled outcomes.
  final double blendBrier;
  final double championBrier;
  final int rollbacks;
  final LearningEventKind event;
  final String note;

  /// Observations learned from a closing line rather than from a result.
  final int closingLineSamples;

  /// Observations learned from a settled result.
  final int resultSamples;
  final List<OnlineCheckpoint> checkpoints;

  /// Count of observations that were refused, by [LearningEventKind] name.
  final Map<String, int> skipped;
  final DateTime? updatedAt;

  bool get drifting => pageHinkley.alarm || cusum.degraded;

  /// Weight currently placed on the fitted model rather than on the fallback.
  double get modelWeight => ensemble.weightOf('model');

  Map<String, Object?> toJson() => {
    'ensemble': ensemble.toJson(),
    'pageHinkley': pageHinkley.toJson(),
    'cusum': cusum.toJson(),
    'version': version,
    'settledSamples': settledSamples,
    'blendBrier': blendBrier,
    'championBrier': championBrier,
    'rollbacks': rollbacks,
    'event': event.name,
    'note': note,
    'closingLineSamples': closingLineSamples,
    'resultSamples': resultSamples,
    'checkpoints': checkpoints.map((value) => value.toJson()).toList(),
    'skipped': skipped,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };
}

/// One graded observation offered to the learner.
///
/// Two kinds of label are accepted. A result label is the binary outcome of the
/// event and only exists once the match is over. A closing-line label is the
/// margin-free probability the market itself closed at, which is available at
/// kick-off, carries less variance than a coin-flip-like result and can be
/// graded for every recorded line rather than only for settled matches.
class OnlineObservation {
  const OnlineObservation({
    required this.settledAt,
    required bool outcome,
    required this.predictions,
    this.missingData = false,
    this.voided = false,
    this.marketShift = 0,
  }) : target = outcome ? 1.0 : 0.0,
       fromClosingLine = false;

  /// Observation whose label is the closing (pre-kick-off) market probability.
  const OnlineObservation.closingLine({
    required this.settledAt,
    required this.target,
    required this.predictions,
    this.missingData = false,
    this.voided = false,
    this.marketShift = 0,
  }) : fromClosingLine = true;

  final DateTime settledAt;

  /// Label on the probability scale: `0`/`1` for a result, the closing market
  /// probability for a closing-line observation.
  final double target;

  /// Whether the label leans to the event happening.
  bool get outcome => target >= 0.5;

  /// Whether this label came from the closing line instead of a result.
  final bool fromClosingLine;

  /// Forecast of every ensemble member, keyed by member name.
  final Map<String, double> predictions;
  final bool missingData;
  final bool voided;

  /// How far the market moved between capture and grading.
  final double marketShift;
}

/// Replays settled observations into an [OnlineLearningState].
///
/// The learner is deliberately conservative: refused observations never move a
/// weight, a Page–Hinkley alarm rolls the weights back to the last checkpoint
/// instead of continuing to chase the loss, and a checkpoint is only taken when
/// the blend is genuinely ahead of its own history.
class OnlineLearner {
  const OnlineLearner({
    this.members = const ['model', 'fallback'],
    this.checkpointEvery = 25,
  });

  final List<String> members;
  final int checkpointEvery;

  OnlineLearningState replay(List<OnlineObservation> observations) {
    final ordered = [...observations]
      ..sort((left, right) => left.settledAt.compareTo(right.settledAt));
    var ensemble = HedgeEnsemble.uniform(members);
    var pageHinkley = const PageHinkleyDetector();
    var cusum = const CusumDetector();
    final checkpoints = <OnlineCheckpoint>[];
    final skipped = <String, int>{};
    var version = 1;
    var rollbacks = 0;
    var used = 0;
    var closingLineSamples = 0;
    var resultSamples = 0;
    var blendLoss = 0.0;
    final memberLoss = {for (final member in members) member: 0.0};
    var event = LearningEventKind.healthy;
    var note = '尚未有已結算樣本，權重維持平均。';

    for (final observation in ordered) {
      final classified = classifyEvent(
        missingData:
            observation.missingData ||
            members.any(
              (member) => !(observation.predictions[member]?.isFinite ?? false),
            ),
        voided: observation.voided,
        marketShift: observation.marketShift,
        driftAlarm: false,
      );
      if (!classified.learnable) {
        skipped[classified.name] = (skipped[classified.name] ?? 0) + 1;
        event = classified;
        note = '最近一筆觀測被拒絕：${classified.label}';
        continue;
      }
      final losses = {
        for (final member in members)
          member: squaredLoss(
            observation.predictions[member]!,
            observation.target,
          ),
      };
      final blend = ensemble.blend(observation.predictions);
      final currentBlendLoss = squaredLoss(blend, observation.target);
      final championLoss = losses.values.reduce(min);

      used += 1;
      if (observation.fromClosingLine) {
        closingLineSamples += 1;
      } else {
        resultSamples += 1;
      }
      blendLoss += currentBlendLoss;
      for (final member in members) {
        memberLoss[member] = memberLoss[member]! + losses[member]!;
      }
      ensemble = ensemble.update(losses);
      pageHinkley = pageHinkley.observe(currentBlendLoss);
      cusum = cusum.observe(currentBlendLoss - championLoss);
      event = classified;
      note = classified == LearningEventKind.marketMove
          ? '市場在開賽前大幅移動，已記錄但不視為模型失效。'
          : '權重按已結算樣本更新中。';

      if (pageHinkley.alarm || cusum.degraded) {
        // A sustained deterioration is answered by returning to the last set of
        // weights that was known to be good, not by learning harder.
        if (checkpoints.isNotEmpty) {
          ensemble = checkpoints.last.weights;
        } else {
          ensemble = HedgeEnsemble.uniform(members);
        }
        pageHinkley = pageHinkley.reset();
        cusum = cusum.reset();
        rollbacks += 1;
        version += 1;
        event = LearningEventKind.modelDrift;
        note = '偵測到持續變差，已回滾至第 $version 版權重。';
        continue;
      }

      final averageBlend = blendLoss / used;
      if (used % checkpointEvery == 0 &&
          (checkpoints.isEmpty || averageBlend < checkpoints.last.brier)) {
        checkpoints.add(
          OnlineCheckpoint(
            version: version,
            weights: ensemble,
            brier: averageBlend,
            samples: used,
            createdAt: observation.settledAt,
          ),
        );
        if (checkpoints.length > 20) {
          checkpoints.removeAt(0);
        }
      }
    }

    final championBrier = used == 0
        ? 0.0
        : memberLoss.values.map((loss) => loss / used).reduce(min);
    return OnlineLearningState(
      ensemble: ensemble,
      pageHinkley: pageHinkley,
      cusum: cusum,
      version: version,
      settledSamples: used,
      blendBrier: used == 0 ? 0 : blendLoss / used,
      championBrier: championBrier,
      rollbacks: rollbacks,
      event: event,
      note: note,
      closingLineSamples: closingLineSamples,
      resultSamples: resultSamples,
      checkpoints: checkpoints,
      skipped: skipped,
      updatedAt: ordered.isEmpty ? null : ordered.last.settledAt,
    );
  }
}
