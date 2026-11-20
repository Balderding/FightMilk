import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/plan_maker.dart';
import '../domain/units.dart';
import 'ai_sheet.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// First-time setup (also reached from Settings to change answers). One screen, no account.
class SetupScreen extends StatefulWidget {
  final AppState s;
  final bool firstRun;
  const SetupScreen({super.key, required this.s, this.firstRun = false});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late Profile p;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    p = widget.s.profile ??
        const Profile(
          goal: Goal.both,
          days: 4,
          minutes: 60,
          have: {Equipment.barbell, Equipment.dumbbell, Equipment.machine, Equipment.cable},
          avoid: {},
          unit: Unit.lb,
        );
  }

  Set<T> _toggle<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};

  Future<void> _make({required bool ai}) async {
    final s = widget.s;
    if (s.plan != null && s.plan!.userEdited) {
      final ok = await confirm(context, 'Replace your edited plan?', 'You changed this plan by hand. The new plan replaces it; the old one is kept under Plan → Old plans.', yes: 'Replace');
      if (!ok) return;
    }
    setState(() => busy = true);
    await s.saveProfile(p);
    if (!mounted) return;
    if (ai) {
      final done = await runAi(context, s, () => s.aiPlanRequest(p));
      if (!mounted) return;
      if (!done) {
        setState(() => busy = false);
        return;
      }
    } else {
      await s.makeBuiltInPlan();
    }
    if (!mounted) return;
    setState(() => busy = false);
    if (!widget.firstRun) Navigator.pop(context);
  }

  Future<void> _saveOnly() async {
    await widget.s.saveProfile(p);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: Text(widget.firstRun ? "Let's set you up" : 'Your setup'), automaticallyImplyLeading: !widget.firstRun),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          const Q('Goal'),
          Pills(values: Goal.values, label: (g) => goalLabel[g]!, selected: {p.goal}, onTap: (g) => setState(() => p = p.copyWith(goal: g))),
          const Q('Days per week'),
          Pills(values: const [2, 3, 4, 5, 6], label: (d) => '$d', selected: {p.days}, onTap: (d) => setState(() => p = p.copyWith(days: d))),
          const Q('Time per session'),
          Pills(values: const [45, 60, 90], label: (m) => '$m min', selected: {p.minutes}, onTap: (m) => setState(() => p = p.copyWith(minutes: m))),
          const Q('Your gym has'),
          Pills(
              values: Equipment.values.where((e) => e != Equipment.bodyweight).toList(),
              label: (e) => equipmentLabel[e]!,
              selected: p.have,
              onTap: (e) => setState(() => p = p.copyWith(have: _toggle(p.have, e)))),
          const Q('Go easy on'),
          Pills(values: Joint.values, label: (j) => jointLabel[j]!, selected: p.avoid, onTap: (j) => setState(() => p = p.copyWith(avoid: _toggle(p.avoid, j)))),
          const Q('How to split the week'),
          Pills<String?>(
            values: const [null, 'full_body', 'upper_lower', 'ppl', 'bro'],
            label: (v) => v == null ? 'Let the app choose' : splitLabel[v]!,
            selected: {p.split},
            onTap: (v) => setState(() => p = v == null ? p.copyWith(clearSplit: true) : p.copyWith(split: v)),
          ),
          Padding(padding: const EdgeInsets.only(top: 6), child: Dim('Days: ${dayNames(p.days, p.split).join(' → ')}')),
          const Q('Weights in'),
          Pills(values: Unit.values, label: unitLabel, selected: {p.unit}, onTap: (u) => setState(() => p = p.copyWith(unit: u))),
          const SizedBox(height: 22),
          if (busy) const Center(child: CircularProgressIndicator()) else ...[
            FilledButton(onPressed: p.have.isEmpty ? null : () => _make(ai: false), child: const Text('Make my plan')),
            if (s.settings.aiOn) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: p.have.isEmpty ? null : () => _make(ai: true), icon: const Icon(Icons.auto_awesome, color: C.gold), label: const Text('Make my plan with AI')),
            ],
            if (!widget.firstRun) ...[
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _saveOnly, child: const Text('Save, keep my current plan')),
            ],
          ],
          if (p.have.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Problem(['Pick at least one kind of equipment.'])),
          const SizedBox(height: 10),
          const Dim('No account, no email. This stays on your phone.'),
        ]),
      ),
    );
  }
}
