/// Learns how far the model is allowed to disagree with the HKJC price.
///
/// The blend used to be a hard-coded constant, which is a claim nobody had
/// measured. Here the same Hedge machinery that weighs the model against its
/// fallback weighs a small grid of anchor weights against each other on settled
/// matches, so the blend converges to whatever the settled record supports and
/// keeps a documented conservative value until the record is long enough.
library;

import 'dart:math';

import 'online_learning.dart';

/// Candidate shares of the model's own view, the rest coming from the market.
const marketAnchorCandidates = <double>[0.25, 0.55, 0.85, 1.0];

/// Share used until there are enough settled matches to measure one.
const defaultMarketAnchor = 0.55;

/// Share used while the anchor's own loss stream is drifting.
const driftingMarketAnchor = 0.35;

/// Minimum settled matches before a learned anchor replaces the default.
const minimumAnchorSamples = 30;

/// One settled match, seen from the market's side.
class MarketAnchorObservation {
  const MarketAnchorObservation({
    required this.settledAt,
    required this.outcome,
    required this.modelProbability,
    required this.marketProbability,
  });

  final DateTime settledAt;
  final bool outcome;

  /// Model probability of the same event, before anchoring.
  final double modelProbability;

  /// Vig-free market probability of the event at capture time.
  final double marketProbability;

  bool get usable =>
      modelProbability.isFinite &&
      marketProbability.isFinite &&
      modelProbability >= 0 &&
      modelProbability <= 1 &&
      marketProbability > 0 &&
      marketProbability < 1;

  /// Probability implied by keeping [share] of the model's disagreement.
  double probabilityAt(double share) =>
      (marketProbability + share * (modelProbability - marketProbability))
          .clamp(0.0, 1.0);
}

/// Learned anchor plus everything needed to audit it.
class MarketAnchorState {
  const MarketAnchorState({
    required this.ensemble,
    required this.pageHinkley,
    required this.samples,
    required this.brier,
    required this.marketBrier,
    required this.note,
    this.updatedAt,
  });

  static final initial = MarketAnchorState(
    ensemble: HedgeEnsemble.uniform(_members),
    pageHinkley: const PageHinkleyDetector(),
    samples: 0,
    brier: 0,
    marketBrier: 0,
    note: '尚未有足夠已結算樣本，市場錨定權重維持保守預設值。',
  );

  factory MarketAnchorState.fromJson(Map<String, Object?> json) =>
      MarketAnchorState(
        ensemble: HedgeEnsemble.fromJson(
          (json['ensemble'] as Map).cast<String, Object?>(),
        ),
        pageHinkley: PageHinkleyDetector.fromJson(
          (json['pageHinkley'] as Map).cast<String, Object?>(),
        ),
        samples: (json['samples'] as num).toInt(),
        brier: (json['brier'] as num).toDouble(),
        marketBrier: (json['marketBrier'] as num).toDouble(),
        note: json['note'] as String? ?? '',
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
      );

  static List<String> get _members =>
      marketAnchorCandidates.map(_member).toList();

  static String _member(double share) => share.toStringAsFixed(2);

  final HedgeEnsemble ensemble;
  final PageHinkleyDetector pageHinkley;
  final int samples;

  /// Brier score of the Hedge-weighted anchor and of the raw market price, on
  /// the same settled matches.
  final double brier;
  final double marketBrier;
  final String note;
  final DateTime? updatedAt;

  bool get drifting => pageHinkley.alarm;

  /// Whether the learned share is used instead of the conservative default.
  bool get learned => samples >= minimumAnchorSamples && !drifting;

  /// Hedge-weighted share of the model's own view that survives.
  double get share {
    if (drifting) {
      return driftingMarketAnchor;
    }
    if (samples < minimumAnchorSamples) {
      return defaultMarketAnchor;
    }
    var total = 0.0;
    var mass = 0.0;
    for (final candidate in marketAnchorCandidates) {
      final weight = ensemble.weightOf(_member(candidate));
      total += weight * candidate;
      mass += weight;
    }
    return mass <= 0 ? defaultMarketAnchor : total / mass;
  }

  /// Whether the anchor is beating the raw market price it is anchored to.
  bool get beatsMarket =>
      samples >= minimumAnchorSamples && brier < marketBrier;

  Map<String, Object?> toJson() => {
    'ensemble': ensemble.toJson(),
    'pageHinkley': pageHinkley.toJson(),
    'samples': samples,
    'brier': brier,
    'marketBrier': marketBrier,
    'note': note,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };
}

/// Replays settled matches into a [MarketAnchorState].
class MarketAnchorLearner {
  const MarketAnchorLearner();

  MarketAnchorState replay(List<MarketAnchorObservation> observations) {
    final ordered =
        observations.where((observation) => observation.usable).toList()
          ..sort((left, right) => left.settledAt.compareTo(right.settledAt));
    if (ordered.isEmpty) {
      return MarketAnchorState.initial;
    }
    var ensemble = HedgeEnsemble.uniform(MarketAnchorState._members);
    var pageHinkley = const PageHinkleyDetector();
    var blendLoss = 0.0;
    var marketLoss = 0.0;
    var used = 0;
    for (final observation in ordered) {
      final predictions = {
        for (final candidate in marketAnchorCandidates)
          MarketAnchorState._member(candidate): observation.probabilityAt(
            candidate,
          ),
      };
      final losses = {
        for (final entry in predictions.entries)
          entry.key: brierLoss(entry.value, observation.outcome),
      };
      final blend = ensemble.blend(predictions);
      final loss = brierLoss(blend, observation.outcome);
      ensemble = ensemble.update(losses);
      pageHinkley = pageHinkley.observe(loss);
      blendLoss += loss;
      marketLoss += brierLoss(
        observation.marketProbability,
        observation.outcome,
      );
      used += 1;
      if (pageHinkley.alarm) {
        // A drifting anchor is answered by forgetting what it learned, not by
        // chasing the loss with an ever more extreme weight.
        ensemble = HedgeEnsemble.uniform(MarketAnchorState._members);
        pageHinkley = pageHinkley.reset();
      }
    }
    final share = used < minimumAnchorSamples
        ? defaultMarketAnchor
        : marketAnchorCandidates.fold<double>(
                0,
                (total, candidate) =>
                    total +
                    ensemble.weightOf(MarketAnchorState._member(candidate)) *
                        candidate,
              ) /
              max(
                marketAnchorCandidates.fold<double>(
                  0,
                  (total, candidate) =>
                      total +
                      ensemble.weightOf(MarketAnchorState._member(candidate)),
                ),
                1e-9,
              );
    return MarketAnchorState(
      ensemble: ensemble,
      pageHinkley: pageHinkley,
      samples: used,
      brier: blendLoss / used,
      marketBrier: marketLoss / used,
      note: used < minimumAnchorSamples
          ? '只有 $used 筆帶市場價的已結算樣本（需 $minimumAnchorSamples '
                '筆），仍用保守預設 ${defaultMarketAnchor.toStringAsFixed(2)}。'
          : '已由 $used 筆已結算樣本學得模型觀點保留 '
                '${share.toStringAsFixed(2)}，其餘錨定於市場價。',
      updatedAt: ordered.last.settledAt,
    );
  }
}
