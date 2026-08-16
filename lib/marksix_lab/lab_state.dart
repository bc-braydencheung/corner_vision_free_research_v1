import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/combinatorics.dart';
import 'core/drbg.dart';
import 'core/provably_fair.dart';
import 'crowd/crowd_model.dart';
import 'data/draw.dart';
import 'data/synthetic_history.dart';

class SavedTicket {
  const SavedTicket({
    required this.numbers,
    required this.createdAt,
    required this.commitment,
    required this.serverSeedHex,
    required this.clientSeedHex,
    required this.publicContext,
    required this.drawLabel,
    required this.rarityPercentile,
    required this.rerollCount,
    this.stake = 10,
  });

  final List<int> numbers;
  final DateTime createdAt;
  final String commitment;
  final String serverSeedHex;
  final String clientSeedHex;
  final String publicContext;
  final String drawLabel;
  final double rarityPercentile;
  final int rerollCount;
  final double stake;

  DrawRecipe get recipe => DrawRecipe(
    serverSeedHex: serverSeedHex,
    clientSeedHex: clientSeedHex,
    publicContext: publicContext,
    drawLabel: drawLabel,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'numbers': numbers,
    'createdAt': createdAt.toIso8601String(),
    'commitment': commitment,
    'serverSeedHex': serverSeedHex,
    'clientSeedHex': clientSeedHex,
    'publicContext': publicContext,
    'drawLabel': drawLabel,
    'rarityPercentile': rarityPercentile,
    'rerollCount': rerollCount,
    'stake': stake,
  };

  static SavedTicket fromJson(Map<String, dynamic> json) => SavedTicket(
    numbers: (json['numbers'] as List<dynamic>).map((e) => e as int).toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    commitment: json['commitment'] as String,
    serverSeedHex: json['serverSeedHex'] as String,
    clientSeedHex: json['clientSeedHex'] as String,
    publicContext: json['publicContext'] as String,
    drawLabel: json['drawLabel'] as String,
    rarityPercentile: (json['rarityPercentile'] as num).toDouble(),
    rerollCount: json['rerollCount'] as int,
    stake: (json['stake'] as num?)?.toDouble() ?? 10,
  );
}

enum HistorySource { synthetic, imported }

class LabState extends ChangeNotifier {
  LabState();

  static const String _prefsKey = 'marksix_physics_lab_state_v1';

  bool _initialised = false;
  bool get initialised => _initialised;

  bool _ageConfirmed = false;
  bool get ageConfirmed => _ageConfirmed;

  double _monthlyBudget = 100;
  double get monthlyBudget => _monthlyBudget;

  double _spentThisMonth = 0;
  double get spentThisMonth => _spentThisMonth;

  DateTime? _cooldownUntil;
  DateTime? get cooldownUntil => _cooldownUntil;
  bool get inCooldown =>
      _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);

  double get budgetRemaining =>
      (_monthlyBudget - _spentThisMonth).clamp(0, double.infinity);

  final List<SavedTicket> _tickets = <SavedTicket>[];
  List<SavedTicket> get tickets => List<SavedTicket>.unmodifiable(_tickets);

  List<Draw> _history = <Draw>[];
  List<Draw> get history => List<Draw>.unmodifiable(_history);

  HistorySource _historySource = HistorySource.synthetic;
  HistorySource get historySource => _historySource;

  String _historyNote = '';
  String get historyNote => _historyNote;

  int _syntheticDraws = 1200;
  int get syntheticDraws => _syntheticDraws;

  int? _injectedBiasBall;
  int? get injectedBiasBall => _injectedBiasBall;

  double _injectedBias = 0.0;
  double get injectedBias => _injectedBias;

  /// Explicit seed of the current synthetic dataset, so resampling is a new
  /// experiment while any single dataset stays reproducible.
  int _syntheticSeed = 0xC0FFEE;
  int get syntheticSeed => _syntheticSeed;

  CrowdModel _crowdModel = CrowdModel();
  CrowdModel get crowdModel => _crowdModel;

  RarityScale? _rarityScale;
  RarityScale get rarityScale =>
      _rarityScale ??= buildRarityScale(_crowdModel, samples: 12000);

  Future<void> initialise() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _ageConfirmed = json['ageConfirmed'] as bool? ?? false;
        _monthlyBudget = (json['monthlyBudget'] as num?)?.toDouble() ?? 100;
        _spentThisMonth = (json['spentThisMonth'] as num?)?.toDouble() ?? 0;
        final cooldown = json['cooldownUntil'] as String?;
        _cooldownUntil = cooldown == null ? null : DateTime.parse(cooldown);
        _tickets
          ..clear()
          ..addAll(
            (json['tickets'] as List<dynamic>? ?? <dynamic>[]).map(
              (e) => SavedTicket.fromJson(e as Map<String, dynamic>),
            ),
          );
      } catch (_) {
        // Corrupt preferences are not worth crashing over; start clean.
      }
    }
    regenerateSynthetic();
    _initialised = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(<String, dynamic>{
        'ageConfirmed': _ageConfirmed,
        'monthlyBudget': _monthlyBudget,
        'spentThisMonth': _spentThisMonth,
        'cooldownUntil': _cooldownUntil?.toIso8601String(),
        'tickets': _tickets.map((t) => t.toJson()).toList(),
      }),
    );
  }

  void confirmAge() {
    _ageConfirmed = true;
    _persist();
    notifyListeners();
  }

  void setMonthlyBudget(double value) {
    _monthlyBudget = value;
    _persist();
    notifyListeners();
  }

  void recordSpend(double amount) {
    _spentThisMonth += amount;
    _persist();
    notifyListeners();
  }

  void resetSpend() {
    _spentThisMonth = 0;
    _persist();
    notifyListeners();
  }

  void startCooldown(Duration duration) {
    _cooldownUntil = DateTime.now().add(duration);
    _persist();
    notifyListeners();
  }

  void endCooldown() {
    _cooldownUntil = null;
    _persist();
    notifyListeners();
  }

  void saveTicket(SavedTicket ticket) {
    _tickets.insert(0, ticket);
    _persist();
    notifyListeners();
  }

  void removeTicket(SavedTicket ticket) {
    _tickets.remove(ticket);
    _persist();
    notifyListeners();
  }

  void configureSynthetic({
    int? draws,
    int? biasedBall,
    double? relativeBias,
    bool clearBias = false,
  }) {
    if (draws != null) _syntheticDraws = draws;
    if (clearBias) {
      _injectedBiasBall = null;
      _injectedBias = 0;
    } else {
      if (biasedBall != null) _injectedBiasBall = biasedBall;
      if (relativeBias != null) _injectedBias = relativeBias;
    }
    regenerateSynthetic();
  }

  /// [newSeed] draws a different dataset; omit it to rebuild the same one.
  void regenerateSynthetic({bool newSeed = false}) {
    if (newSeed) {
      _syntheticSeed =
          (_syntheticSeed * 1103515245 +
              DateTime.now().microsecondsSinceEpoch) &
          0x7fffffff;
    }
    _history = SyntheticHistory.generate(
      draws: _syntheticDraws,
      biasedBall: _injectedBiasBall,
      relativeBias: _injectedBias,
      seed: _syntheticSeed,
    );
    _historySource = HistorySource.synthetic;
    _historyNote = _injectedBiasBall == null
        ? '合成的公平機器，$_syntheticDraws 期。非官方資料。'
        : '合成機器，已在球號 $_injectedBiasBall 上注入 '
              '${(_injectedBias * 100).toStringAsFixed(1)}% 偏差，'
              '$_syntheticDraws 期。非官方資料。';
    _historyNote = '$_historyNote 種子 0x${_syntheticSeed.toRadixString(16)}。';
    notifyListeners();
  }

  void setImportedHistory(List<Draw> draws, String note) {
    _history = draws;
    _historySource = HistorySource.imported;
    _historyNote = note;
    notifyListeners();
  }

  void setCrowdWeights(
    Map<CrowdFeature, double> weights, {
    double intercept = 0,
  }) {
    _crowdModel = CrowdModel(weights: weights, intercept: intercept);
    _rarityScale = null;
    notifyListeners();
  }

  void resetCrowdWeights() {
    _crowdModel = CrowdModel();
    _rarityScale = null;
    notifyListeners();
  }

  /// Fresh 32-byte server seed for the next commitment.
  String freshServerSeed() {
    final rng = Drbg(<int>[
      ...utf8.encode(DateTime.now().microsecondsSinceEpoch.toString()),
      ...utf8.encode(identityHashCode(this).toString()),
    ]);
    return toHex(rng.nextBytes(32));
  }

  int get totalCombinations => kTotalCombinations;
}
