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
      text: '期數-${DateTime.now().toIso8601String().substring(0, 10)}',
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
              '本頁不作任何預測。它從你的裝置採集真實物理熵，用密碼學方式先行承諾，'
              '再把結果推離大眾偏好的組合。中獎概率不變，也無法改變：'
              '1／13,983,816。',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '第一步 — 觀測者塌縮',
          subtitle:
              '在下面的區域拖動。種子取自指針幾何，以及事件到達時間的微秒抖動——'
              '該抖動源自振盪器熱噪聲。熵讀數只計時間通道，並以 Miller-Madow '
              '修正的 Shannon 估計計算。',
          trailing: Text(
            '${_entropyBits.toStringAsFixed(0)} 位元',
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
                _ready ? '熵已足夠：256 位元種子已飽和。' : '繼續拖動，直到收集夠 256 位元。',
                style: const TextStyle(fontSize: 12, color: kMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '第二步 — 事前承諾',
          subtitle:
              '生成之前先公佈 commitment = SHA256(serverSeed)。事後公開種子，'
              '任何人都可以自行重算號碼，所以本 App 無法事後篡改注單。'
              '市面上的選號工具都沒有這一步。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SeedRow(
                label: '承諾值 commitment',
                value: ProvablyFair.commit(_serverSeed),
              ),
              const SizedBox(height: 8),
              _SeedRow(label: '你的種子 client seed', value: _pool.seedHex()),
              const SizedBox(height: 12),
              TextField(
                controller: _publicContext,
                decoration: const InputDecoration(
                  labelText: '公開背景資料（第三方可查證）',
                  helperText: '太空天氣、月相、潮汐、氣壓——任何陌生人都可以自行查到的數據。',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _drawLabel,
                decoration: const InputDecoration(labelText: '期數標籤'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '第三步 — 反人群過濾',
          subtitle:
              '以人群模型 q(c) 做拒絕抽樣。這是唯一有真實數學回報的部分：'
              '它不會提高你中獎的機會，只會提高你中獎時實際拿到的金額。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LabeledSlider(
                label: '最低冷門百分位',
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
                      label: const Text('鑄造號碼'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('重新開始'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_ticket != null) ...<Widget>[
          const SizedBox(height: 16),
          SectionCard(
            title: '結果',
            subtitle:
                '可由上方配方完整重現，包括被拒絕的 '
                '${_ticket!.rerollCount} 個候選組合。',
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
                      label: '冷門百分位',
                      value: '${(_ticketRarity * 100).toStringAsFixed(1)}%',
                      hint: '比這個比例的組合更少人選',
                      emphasis: true,
                    ),
                    StatTile(
                      label: '人群密度比 q/q̄',
                      value: _ticketCrowdRatio.toStringAsFixed(3),
                      hint: '小於 1 表示分帳人數較少',
                    ),
                    StatTile(
                      label: '頭獎概率',
                      value: '1 / ${kTotalCombinations.toString()}',
                      hint: '每個組合都完全相同',
                    ),
                    StatTile(
                      label: '預期同時中獎人數',
                      value: outcome.expectedCoWinners.toStringAsFixed(3),
                      hint:
                          '平均選號為 '
                          '${(_units / kTotalCombinations).toStringAsFixed(3)}',
                    ),
                    StatTile(
                      label: '頭獎期望值提升',
                      value:
                          '${((outcome.improvementRatio - 1) * 100).toStringAsFixed(1)}%',
                      hint: '來自少人分帳，不是中得更多',
                      color: outcome.improvementRatio >= 1 ? kAccent : kDanger,
                    ),
                    StatTile(
                      label: '整體期望回報',
                      value:
                          '${(outcome.expectedValueRatio * 100).toStringAsFixed(1)}%',
                      hint: '依然遠低於本金，永遠如此。',
                      color: kDanger,
                      emphasis: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LabeledSlider(
                  label: '假設頭獎基金（港元）',
                  value: _pool1,
                  min: 8.0e6,
                  max: 5.0e8,
                  display: '${(_pool1 / 1e6).toStringAsFixed(0)}M',
                  onChanged: (v) => setState(() => _pool1 = v),
                ),
                LabeledSlider(
                  label: '假設總投注注數',
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
                                  const SnackBar(content: Text('注單已連完整配方存檔。')),
                                );
                              },
                        icon: const Icon(Icons.archive_outlined),
                        label: Text(state.inCooldown ? '冷靜期中' : '存檔注單'),
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
                      label: const Text('複製配方'),
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
                '已收集 $samples 個樣本',
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
            tooltip: '複製',
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
          ? '承諾值正確。重算號碼：${numbers.join('、')}'
          : '承諾值不符：SHA256(serverSeed) 與公佈的 commitment 不一致。'
                '仍然重算結果：${numbers.join('、')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '獨立驗證器',
      subtitle: '貼上任何存檔配方（你的或別人的）自行重算。可驗證才是功能，不需要信任。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _serverSeed,
            decoration: const InputDecoration(labelText: '伺服器種子（hex）'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commitment,
            decoration: const InputDecoration(labelText: '已公佈的承諾值'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _clientSeed,
            decoration: const InputDecoration(labelText: '客戶端種子（hex）'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _context,
            decoration: const InputDecoration(labelText: '公開背景資料'),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _label,
                  decoration: const InputDecoration(labelText: '期數標籤'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _rerolls,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '重抽次數'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _verify,
            icon: const Icon(Icons.verified_outlined),
            label: const Text('驗證'),
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
      title: '存檔',
      subtitle: tickets.isEmpty ? '尚未有存檔。' : '${tickets.length} 張注單，每張都可完整重現。',
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
                                  '${t.drawLabel} · 冷門度 '
                                  '${(t.rarityPercentile * 100).toStringAsFixed(1)}% · '
                                  '承諾 ${t.commitment.substring(0, 12)}…',
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
