import 'package:flutter/material.dart';

import '../lab_state.dart';
import '../core/combinatorics.dart';
import 'theme.dart';
import 'widgets/panels.dart';

class ResponsiblePage extends StatelessWidget {
  const ResponsiblePage({super.key, required this.state});

  final LabState state;

  @override
  Widget build(BuildContext context) {
    final cooldown = state.cooldownUntil;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const InfoBanner(
          icon: Icons.report_gmailerrorred_outlined,
          color: kDanger,
          text:
              '這個 App 不能提高你中獎的機會，任何東西都不能。它只做三件事：'
              '生成號碼、審計隨機性、減少你中獎時要分帳的人數。'
              '它不下注、不收款，也不會把任何資料送給彩票運營商。',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '把數字直白說清',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StatWrap(
                children: <Widget>[
                  StatTile(
                    label: '頭獎機率',
                    value: '1 : ${kTotalCombinations.toString()}',
                    emphasis: true,
                  ),
                  const StatTile(
                    label: '一般回報',
                    value: '負數',
                    hint: '每一元投注都有固定比例被抽去',
                    color: kDanger,
                  ),
                  const StatTile(
                    label: '過往賽果的影響',
                    value: '沒有',
                    hint: '各期開獎互相獨立',
                  ),
                  const StatTile(
                    label: '任何策略對機率的影響',
                    value: '沒有',
                    hint: '只有分帳人數會變',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                '買得越多，每一元的中獎機率並不會提高，只會令你花得更多。'
                '如果選號已經不再像一個遊戲，下面這些工具是本頁唯一真的能改變結果的東西。',
                style: TextStyle(fontSize: 12.5, height: 1.5, color: kMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '預算',
          subtitle: '只存在本機，不會上傳。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LabeledSlider(
                label: '每月上限（港元）',
                value: state.monthlyBudget,
                min: 0,
                max: 2000,
                divisions: 40,
                display: state.monthlyBudget.toStringAsFixed(0),
                onChanged: state.setMonthlyBudget,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: state.monthlyBudget == 0
                    ? 0
                    : (state.spentThisMonth / state.monthlyBudget).clamp(
                        0.0,
                        1.0,
                      ),
                minHeight: 8,
                backgroundColor: kSurfaceAlt,
                color: state.spentThisMonth >= state.monthlyBudget
                    ? kDanger
                    : kAccent,
              ),
              const SizedBox(height: 8),
              Text(
                '本月已記錄：港幣 ${state.spentThisMonth.toStringAsFixed(0)} / '
                '${state.monthlyBudget.toStringAsFixed(0)} · 餘額港幣 '
                '${state.budgetRemaining.toStringAsFixed(0)}',
                style: kMonoStyle.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  OutlinedButton(
                    onPressed: () => state.recordSpend(10),
                    child: const Text('記 +10'),
                  ),
                  OutlinedButton(
                    onPressed: () => state.recordSpend(50),
                    child: const Text('記 +50'),
                  ),
                  OutlinedButton(
                    onPressed: state.resetSpend,
                    child: const Text('重設本月'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '冷靜期',
          subtitle: cooldown == null
              ? '目前沒有冷靜期。'
              : '鑄造號碼已鎖存至 '
                    '${cooldown.toLocal().toString().substring(0, 16)}。',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => state.startCooldown(const Duration(days: 7)),
                child: const Text('鎖 7 天'),
              ),
              OutlinedButton(
                onPressed: () => state.startCooldown(const Duration(days: 30)),
                child: const Text('鎖 30 天'),
              ),
              if (cooldown != null)
                TextButton(
                  onPressed: state.endCooldown,
                  child: const Text('結束冷靜期'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionCard(
          title: '如果賭博已經不再是遊戲',
          subtitle: '輔導服務免費且保密。',
          child: Text(
            '香港：平和基金資助免費輔導服務，東華三院與明愛就集體都設有'
            '專門的戒賭輔導中心；其他地區也有全國性的戒賭熱線。'
            '跟他們傾談真的會改變結果，換別的號碼不會。',
            style: TextStyle(fontSize: 12.5, height: 1.55, color: kMuted),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class AgeGate extends StatelessWidget {
  const AgeGate({super.key, required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '六合彩物理實驗室',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '這是隨機性實驗室，不是預測服務。',
                  style: TextStyle(fontSize: 14, color: kAccent),
                ),
                const SizedBox(height: 22),
                const Text(
                  '這個 App 永遠不會做三件事：聲稱可以預測開獎、下注、收錢。\n\n'
                  '它計算攪珠機可預測性的物理上界，審計公佈賽果是否均勻，'
                  '並將你中獎時要分帳的人數降到最低。前兩項是物理與統計，'
                  '第三項才是唯一真的影響金錢的。',
                  style: TextStyle(fontSize: 13, height: 1.6, color: kMuted),
                ),
                const SizedBox(height: 26),
                FilledButton(
                  onPressed: onConfirm,
                  child: const Text('我已滿 18 歲，並且明白以上內容'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
