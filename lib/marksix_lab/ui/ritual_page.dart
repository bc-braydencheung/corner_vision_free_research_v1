import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lab_state.dart';
import '../core/combinatorics.dart';
import '../core/entropy_pool.dart';
import '../core/provably_fair.dart';
import '../crowd/parimutuel.dart';
import 'theme.dart';
import 'widgets/panels.dart';

class RitualPage extends StatefulWidget {
  const RitualPage({super.key, required this.state});

  final LabState state;

  @override
  State<RitualPage> createState() => _RitualPageState();
}

class _RitualPageState extends State<RitualPage> {
  static const double _requiredBits = 256;

  final EntropyPool _pool = EntropyPool();
  late String _serverSeed;
  late TextEditingController _publicContext;
  late TextEditingController _drawLabel;

  double _rarityFloor = 0.90;
  GeneratedTicket? _ticket;
  double _ticketRarity = 0;
  double _ticketCrowdRatio = 1;
  double _pool1 = 8.0e7;
  double _units = 3.0e7;

  @override
  void initState() {
    super.initState();
    _serverSeed = widget.state.freshServerSeed();
    _publicContext = TextEditingController(
      text: 'Kp=2.3; moon=waxing gibbous; tide=1.8m; HKO 1006.4hPa',
    );
    _drawLabel = TextEditingController(
      text: 'draw-${DateTime.now().toIso8601String().substring(0, 10)}',
    );
  }

  @override
  void dispose() {
    _publicContext.dispose();
    _drawLabel.dispose();
    super.dispose();
  }

  double get _entropyBits => _pool.estimatedEntropyBits();
  bool get _ready => _entropyBits >= _requiredBits;

  void _capture(Offset position, {double pressure = 0}) {
    _pool.addSample(
      micros: DateTime.now().microsecondsSinceEpoch,
      x: position.dx,
      y: position.dy,
      pressure: pressure,
    );
    setState(() {});
  }

  void _generate() {
    final model = widget.state.crowdModel;
    final scale = widget.state.rarityScale;
    final recipe = DrawRecipe(
      serverSeedHex: _serverSeed,
      clientSeedHex: _pool.seedHex(),
      publicContext: _publicContext.text,
      drawLabel: _drawLabel.text,
    );
    final ticket = ProvablyFair.generate(
      recipe,
      reject: (candidate) =>
          scale.percentileForScore(model.logPopularity(candidate)) <
          _rarityFloor,
    );
    final score = model.logPopularity(ticket.numbers);
    setState(() {
      _ticket = ticket;
      _ticketRarity = scale.percentileForScore(score);
      _ticketCrowdRatio = scale.crowdRatio(score);
    });
  }

  void _reset() {
    setState(() {
      _pool.clear();
      _ticket = null;
      _serverSeed = widget.state.freshServerSeed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final outcome = evaluateParimutuel(
      pool: _pool1,
      unitsSold: _units,
      crowdRatio: _ticket == null ? 1 : _ticketCrowdRatio,
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const InfoBanner(
          icon: Icons.science_outlined,
          text:
              'This screen does not predict anything. It harvests real physical '
              'entropy from your device, commits to it cryptographically, and '
              'steers the result away from combinations the crowd over-picks. '
              'Winning probability is unchanged and unchangeable: 1 in 13,983,816.',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Step 1 - Observer collapse',
          subtitle:
              'Drag inside the field. The seed comes from pointer geometry and '
              'from microsecond arrival jitter of the events, which is driven by '
              'oscillator thermal noise. The entropy readout is a Miller-Madow '
              'corrected Shannon estimate of the timing channel only.',
          trailing: Text(
            '${_entropyBits.toStringAsFixed(0)} bits',
            style: kMonoStyle.copyWith(
              color: _ready ? kAccent : kAccentWarm,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _EntropyField(
                onSample: _capture,
                progress: (_entropyBits / _requiredBits).clamp(0.0, 1.0),
                samples: _pool.sampleCount,
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (_entropyBits / _requiredBits).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: kSurfaceAlt,
                color: _ready ? kAccent : kAccentWarm,
              ),
              const SizedBox(height: 8),
              Text(
                _ready
                    ? 'Entropy sufficient: the 256-bit seed is saturated.'
                    : 'Keep going until 256 bits are collected.',
                style: const TextStyle(fontSize: 12, color: kMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Step 2 - Commitment',
          subtitle:
              'commitment = SHA256(serverSeed) is published before generation. '
              'Reveal the seed afterwards and anyone can recompute the numbers, '
              'so the app cannot retro-fit a ticket. No lottery number generator '
              'on the market offers this.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SeedRow(
                label: 'commitment',
                value: ProvablyFair.commit(_serverSeed),
              ),
              const SizedBox(height: 8),
              _SeedRow(label: 'client seed (yours)', value: _pool.seedHex()),
              const SizedBox(height: 12),
              TextField(
                controller: _publicContext,
                decoration: const InputDecoration(
                  labelText: 'public context (third-party verifiable)',
                  helperText:
                      'Space weather, moon phase, tide, pressure - anything a '
                      'stranger can look up independently.',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _drawLabel,
                decoration: const InputDecoration(labelText: 'draw label'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Step 3 - Anti-crowd filter',
          subtitle:
              'Rejection sampling against the crowd model q(c). This is the only '
              'component with a real mathematical payoff: it does not raise your '
              'chance of winning, it raises what you collect if you do.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LabeledSlider(
                label: 'minimum rarity percentile',
                value: _rarityFloor,
                min: 0.0,
                max: 0.99,
                display: '${(_rarityFloor * 100).toStringAsFixed(0)}%',
                onChanged: (v) => setState(() => _rarityFloor = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _ready ? _generate : null,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Forge numbers'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('New ritual'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_ticket != null) ...<Widget>[
          const SizedBox(height: 16),
          SectionCard(
            title: 'Result',
            subtitle:
                'Reproducible from the recipe above, including the '
                '${_ticket!.rerollCount} rejected candidate(s).',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _ticket!.numbers
                      .map((n) => BallChip(number: n, highlight: true))
                      .toList(growable: false),
                ),
                const SizedBox(height: 18),
                StatWrap(
                  children: <Widget>[
                    StatTile(
                      label: 'rarity percentile',
                      value: '${(_ticketRarity * 100).toStringAsFixed(1)}%',
                      hint: 'less popular than this share of combinations',
                      emphasis: true,
                    ),
                    StatTile(
                      label: 'crowd ratio q/q̄',
                      value: _ticketCrowdRatio.toStringAsFixed(3),
                      hint: 'below 1 means fewer co-winners',
                    ),
                    StatTile(
                      label: 'jackpot probability',
                      value: '1 / ${kTotalCombinations.toString()}',
                      hint: 'identical for every combination',
                    ),
                    StatTile(
                      label: 'expected co-winners',
                      value: outcome.expectedCoWinners.toStringAsFixed(3),
                      hint:
                          'vs ${(_units / kTotalCombinations).toStringAsFixed(3)} '
                          'for an average pick',
                    ),
                    StatTile(
                      label: 'division-1 EV gain',
                      value:
                          '${((outcome.improvementRatio - 1) * 100).toStringAsFixed(1)}%',
                      hint: 'from splitting less, not winning more',
                      color: outcome.improvementRatio >= 1 ? kAccent : kDanger,
                    ),
                    StatTile(
                      label: 'overall expected return',
                      value:
                          '${(outcome.expectedValueRatio * 100).toStringAsFixed(1)}%',
                      hint: 'still deeply negative. It always is.',
                      color: kDanger,
                      emphasis: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LabeledSlider(
                  label: 'assumed division-1 pool (HKD)',
                  value: _pool1,
                  min: 8.0e6,
                  max: 5.0e8,
                  display: '${(_pool1 / 1e6).toStringAsFixed(0)}M',
                  onChanged: (v) => setState(() => _pool1 = v),
                ),
                LabeledSlider(
                  label: 'assumed units sold',
                  value: _units,
                  min: 5.0e6,
                  max: 1.5e8,
                  display: '${(_units / 1e6).toStringAsFixed(0)}M',
                  onChanged: (v) => setState(() => _units = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: state.inCooldown
                            ? null
                            : () {
                                state.saveTicket(
                                  SavedTicket(
                                    numbers: _ticket!.numbers,
                                    createdAt: DateTime.now(),
                                    commitment: _ticket!.commitment,
                                    serverSeedHex: _serverSeed,
                                    clientSeedHex:
                                        _ticket!.recipe.clientSeedHex,
                                    publicContext:
                                        _ticket!.recipe.publicContext,
                                    drawLabel: _ticket!.recipe.drawLabel,
                                    rarityPercentile: _ticketRarity,
                                    rerollCount: _ticket!.rerollCount,
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Ticket archived with '
                                      'its full recipe.',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.archive_outlined),
                        label: Text(
                          state.inCooldown
                              ? 'Cooldown active'
                              : 'Archive ticket',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text:
                                '${_ticket!.numbers.join(', ')}\n'
                                'commitment: ${_ticket!.commitment}\n'
                                'serverSeed: $_serverSeed\n'
                                'clientSeed: ${_ticket!.recipe.clientSeedHex}\n'
                                'context: ${_ticket!.recipe.publicContext}\n'
                                'label: ${_ticket!.recipe.drawLabel}\n'
                                'rerolls: ${_ticket!.rerollCount}',
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copy recipe'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _VerifierCard(state: widget.state),
        const SizedBox(height: 16),
        _ArchiveCard(state: widget.state),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _EntropyField extends StatelessWidget {
  const _EntropyField({
    required this.onSample,
    required this.progress,
    required this.samples,
  });

  final void Function(Offset position, {double pressure}) onSample;
  final double progress;
  final int samples;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: (e) => onSample(e.localPosition, pressure: e.pressure),
      onPointerDown: (e) => onSample(e.localPosition, pressure: e.pressure),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: RadialGradient(
            colors: <Color>[
              kAccent.withValues(alpha: 0.10 + 0.22 * progress),
              kVoid,
            ],
          ),
          border: Border.all(color: kAccent.withValues(alpha: 0.30)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Transform.rotate(
                angle: progress * 6 * math.pi,
                child: Icon(
                  Icons.blur_on,
                  size: 46 + 18 * progress,
                  color: kAccent.withValues(alpha: 0.35 + 0.5 * progress),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$samples samples collected',
                style: const TextStyle(fontSize: 12, color: kMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeedRow extends StatelessWidget {
  const _SeedRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: kMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: kMonoStyle.copyWith(fontSize: 11),
            ),
          ),
          IconButton(
            tooltip: 'copy',
            iconSize: 16,
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            icon: const Icon(Icons.copy, size: 16),
          ),
        ],
      ),
    );
  }
}

class _VerifierCard extends StatefulWidget {
  const _VerifierCard({required this.state});

  final LabState state;

  @override
  State<_VerifierCard> createState() => _VerifierCardState();
}

class _VerifierCardState extends State<_VerifierCard> {
  final TextEditingController _serverSeed = TextEditingController();
  final TextEditingController _commitment = TextEditingController();
  final TextEditingController _clientSeed = TextEditingController();
  final TextEditingController _context = TextEditingController();
  final TextEditingController _label = TextEditingController();
  final TextEditingController _rerolls = TextEditingController(text: '0');
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _serverSeed,
      _commitment,
      _clientSeed,
      _context,
      _label,
      _rerolls,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _verify() {
    final commitmentOk = ProvablyFair.verifyCommitment(
      _serverSeed.text.trim(),
      _commitment.text.trim(),
    );
    final recipe = DrawRecipe(
      serverSeedHex: _serverSeed.text.trim(),
      clientSeedHex: _clientSeed.text.trim(),
      publicContext: _context.text,
      drawLabel: _label.text,
    );
    final rerolls = int.tryParse(_rerolls.text.trim()) ?? 0;
    final rng = ProvablyFair.drbg(recipe);
    var numbers = rng.chooseSubset(kBallCount, kPickCount);
    for (var i = 0; i < rerolls; i++) {
      numbers = rng.chooseSubset(kBallCount, kPickCount);
    }
    setState(() {
      _ok = commitmentOk;
      _result = commitmentOk
          ? 'Commitment valid. Recomputed numbers: ${numbers.join(', ')}'
          : 'Commitment MISMATCH: SHA256(serverSeed) does not equal the '
                'published commitment. Recomputed anyway: ${numbers.join(', ')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Independent verifier',
      subtitle:
          'Paste any archived recipe - yours or a stranger\'s - and '
          'recompute it. Verification is the feature; trust is not required.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _serverSeed,
            decoration: const InputDecoration(labelText: 'server seed (hex)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commitment,
            decoration: const InputDecoration(
              labelText: 'published commitment',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _clientSeed,
            decoration: const InputDecoration(labelText: 'client seed (hex)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _context,
            decoration: const InputDecoration(labelText: 'public context'),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _label,
                  decoration: const InputDecoration(labelText: 'draw label'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _rerolls,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'rerolls'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _verify,
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Verify'),
          ),
          if (_result != null) ...<Widget>[
            const SizedBox(height: 12),
            InfoBanner(
              text: _result!,
              icon: _ok ? Icons.check_circle_outline : Icons.error_outline,
              color: _ok ? kAccent : kDanger,
            ),
          ],
        ],
      ),
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({required this.state});

  final LabState state;

  @override
  Widget build(BuildContext context) {
    final tickets = state.tickets;
    return SectionCard(
      title: 'Archive',
      subtitle: tickets.isEmpty
          ? 'Nothing archived yet.'
          : '${tickets.length} ticket(s), each fully reproducible.',
      child: tickets.isEmpty
          ? const SizedBox.shrink()
          : Column(
              children: tickets
                  .take(12)
                  .map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  t.numbers.join(' · '),
                                  style: kMonoStyle.copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${t.drawLabel} · rarity '
                                  '${(t.rarityPercentile * 100).toStringAsFixed(1)}% · '
                                  'commit ${t.commitment.substring(0, 12)}…',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: kMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            iconSize: 18,
                            onPressed: () => state.removeTicket(t),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}
