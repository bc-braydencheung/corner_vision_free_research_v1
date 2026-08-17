import 'package:flutter/material.dart';

import 'lab_state.dart';
import 'ui/audit_page.dart';
import 'ui/crowd_page.dart';
import 'ui/ensemble_page.dart';
import 'ui/predictability_page.dart';
import 'ui/responsible_page.dart';
import 'ui/ritual_page.dart';
import 'ui/theme.dart';

/// Entry point of the Mark Six "disruptive mode": the physics laboratory.
///
/// Statistical mode answers "which numbers came up more often". This mode
/// answers a different question - how much information about the outcome can
/// physically survive the mixing, whether the machine is uniform at all, and
/// how much of a prize you would have to share - and refuses to predict.
class MarkSixLabView extends StatefulWidget {
  const MarkSixLabView({super.key});

  @override
  State<MarkSixLabView> createState() => _MarkSixLabViewState();
}

class _LabDestination {
  const _LabDestination(this.label, this.icon, this.builder);

  final String label;
  final IconData icon;
  final Widget Function(LabState state) builder;
}

final List<_LabDestination> _destinations = <_LabDestination>[
  _LabDestination(
    '鑄造',
    Icons.auto_awesome,
    (state) => RitualPage(state: state),
  ),
  _LabDestination(
    '可預測上界',
    Icons.functions,
    (state) => const PredictabilityPage(),
  ),
  _LabDestination('混沌攪珠', Icons.scatter_plot, (state) => const EnsemblePage()),
  _LabDestination(
    '機器審計',
    Icons.query_stats,
    (state) => AuditPage(state: state),
  ),
  _LabDestination(
    '反人群',
    Icons.groups_outlined,
    (state) => CrowdPage(state: state),
  ),
  _LabDestination(
    '誠實面板',
    Icons.shield_outlined,
    (state) => ResponsiblePage(state: state),
  ),
];

class _MarkSixLabViewState extends State<MarkSixLabView> {
  final LabState _state = LabState();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _state.initialise();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildLabTheme(),
      child: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          if (!_state.initialised) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!_state.ageConfirmed) {
            return AgeGate(onConfirm: _state.confirmAge);
          }
          return Column(
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: <Widget>[
                    for (var i = 0; i < _destinations.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(_destinations[i].icon, size: 16),
                          label: Text(_destinations[i].label),
                          selected: _index == i,
                          onSelected: (_) => setState(() => _index = i),
                        ),
                      ),
                    if (_state.inCooldown)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text(
                          '冷靜期中',
                          style: TextStyle(fontSize: 11, color: kDanger),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(child: _destinations[_index].builder(_state)),
            ],
          );
        },
      ),
    );
  }
}
