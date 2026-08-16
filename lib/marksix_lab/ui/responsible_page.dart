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
              'This app cannot improve your chance of winning, and neither can '
              'anything else. It generates numbers, audits randomness, and '
              'reduces how often you would split a prize. It does not place bets, '
              'take payments, or forward anything to an operator.',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'The arithmetic, stated plainly',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StatWrap(
                children: <Widget>[
                  StatTile(
                    label: 'jackpot odds',
                    value: '1 : ${kTotalCombinations.toString()}',
                    emphasis: true,
                  ),
                  const StatTile(
                    label: 'typical return',
                    value: 'negative',
                    hint: 'a fixed share of every dollar staked is retained',
                    color: kDanger,
                  ),
                  const StatTile(
                    label: 'effect of past results',
                    value: 'none',
                    hint: 'draws are independent',
                  ),
                  const StatTile(
                    label: 'effect of any strategy on odds',
                    value: 'none',
                    hint: 'only the split changes',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Playing more often does not make a win more likely per dollar; '
                'it only increases how much you spend. If choosing numbers has '
                'stopped feeling like a game, the tools below are the only ones '
                'on this screen that can actually change an outcome.',
                style: TextStyle(fontSize: 12.5, height: 1.5, color: kMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Budget',
          subtitle: 'Tracked locally, never transmitted.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LabeledSlider(
                label: 'monthly limit (HKD)',
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
                'Recorded this month: HKD ${state.spentThisMonth.toStringAsFixed(0)} '
                'of ${state.monthlyBudget.toStringAsFixed(0)} · remaining '
                'HKD ${state.budgetRemaining.toStringAsFixed(0)}',
                style: kMonoStyle.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  OutlinedButton(
                    onPressed: () => state.recordSpend(10),
                    child: const Text('+10 spent'),
                  ),
                  OutlinedButton(
                    onPressed: () => state.recordSpend(50),
                    child: const Text('+50 spent'),
                  ),
                  OutlinedButton(
                    onPressed: state.resetSpend,
                    child: const Text('Reset month'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Cooling-off',
          subtitle: cooldown == null
              ? 'No cooling-off period active.'
              : 'Ticket generation is locked until '
                    '${cooldown.toLocal().toString().substring(0, 16)}.',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => state.startCooldown(const Duration(days: 7)),
                child: const Text('Lock for 7 days'),
              ),
              OutlinedButton(
                onPressed: () => state.startCooldown(const Duration(days: 30)),
                child: const Text('Lock for 30 days'),
              ),
              if (cooldown != null)
                TextButton(
                  onPressed: state.endCooldown,
                  child: const Text('End cooling-off'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionCard(
          title: 'If gambling has stopped being a game',
          subtitle: 'Support is free and confidential.',
          child: Text(
            'Hong Kong: the Ping Wo Fund funds free counselling services for '
            'people affected by gambling, and the Tung Wah Group of Hospitals '
            'and Caritas both operate dedicated gambling counselling centres. '
            'Elsewhere, national gambling helplines offer the same service. '
            'Talking to one of them changes an outcome; picking different '
            'numbers does not.',
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
                  'Mark Six Physics Lab',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'A randomness laboratory, not a prediction service.',
                  style: TextStyle(fontSize: 14, color: kAccent),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Three things this app will never do: claim to predict a draw, '
                  'place a bet, or take a payment.\n\n'
                  'It computes the physical upper bound on how predictable a ball '
                  'machine is, audits published results for non-uniformity, and '
                  'minimises how many people you would share a prize with. The '
                  'first two are physics and statistics. The third is the only '
                  'one that changes money.',
                  style: TextStyle(fontSize: 13, height: 1.6, color: kMuted),
                ),
                const SizedBox(height: 26),
                FilledButton(
                  onPressed: onConfirm,
                  child: const Text('I am 18 or older, and I understand'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
