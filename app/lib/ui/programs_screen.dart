import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/program.dart';
import '../domain/programs.dart';
import '../domain/progression.dart';
import '../domain/units.dart';
import '../domain/explain.dart';
import 'app_state.dart';
import 'coaching_screen.dart';
import 'muscles_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Plan → Programs (F211): the program library, grouped, each with who it is for and a Start.
class ProgramsScreen extends StatefulWidget {
  final AppState s;
  const ProgramsScreen({super.key, required this.s});
  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final q = _q.toLowerCase();
    final best = q.length >= 3 ? matchProgram(q) : null;
    final shown = [for (final t in programTemplates) if (t != best && (q.isEmpty || '${t.name} ${t.about} ${t.who} ${t.group}'.toLowerCase().contains(q))) t];
    return Scaffold(
      appBar: AppBar(title: const Text('Programs')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: [
          const Dim('Ready-made programs with their own rules for how the weights go up. Starting one keeps your current plan under Saved plans, and every lift keeps its history.', size: 13),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProgramPicker(s: s))),
            icon: const Icon(Icons.help_outline),
            label: const Text('Which is right for me?'),
          ),
          const SizedBox(height: 10),
          TextField(
            enableIMEPersonalizedLearning: false,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search or describe ("531 bbb 4 days")', isDense: true),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
          if (best != null) ...[
            const Padding(padding: EdgeInsets.only(top: 14, bottom: 6), child: Text('Closest match', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            ProgramCard(s: s, t: best),
          ],
          for (final g in programGroups)
            if (shown.any((t) => t.group == g)) ...[
              Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Text(g, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              for (final t in shown.where((t) => t.group == g)) ProgramCard(s: s, t: t),
            ],
          if (shown.isEmpty && best == null) const Padding(padding: EdgeInsets.only(top: 20), child: Center(child: Dim('No program matches.'))),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: () => importPlanSheet(context, s), icon: const Icon(Icons.file_open_outlined), label: const Text('Import a plan from text or a file')),
        ]),
      ),
    );
  }
}

class ProgramCard extends StatelessWidget {
  final AppState s;
  final ProgramTemplate t;
  const ProgramCard({super.key, required this.s, required this.t});

  @override
  Widget build(BuildContext context) {
    final p = s.profile;
    final swaps = p == null ? const <String>[] : programSwaps(t, p, s.lib);
    final running = s.plan?.program?.id == t.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(t.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            if (running) const Tag('Running'),
          ]),
          Dim('${t.days} days a week · ${t.length} · ${levelLabel[t.level]}', size: 12),
          const SizedBox(height: 6),
          Text(t.about, style: const TextStyle(fontSize: 13.5)),
          const SizedBox(height: 4),
          Text('For: ${t.who}', style: const TextStyle(fontSize: 13, color: C.sky)),
          if (swaps.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Dim('At your gym: ${swaps.take(4).join(', ')}${swaps.length > 4 ? ' …' : ''}', size: 12)),
          if (t.credit.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Dim(t.credit, size: 12)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: p == null ? null : () => startProgramSheet(context, s, t), child: Text(running ? 'Start again' : 'Start')),
          ),
        ]),
      ),
    );
  }
}

/// Start sheet: what changes at this gym, the training maxes (from history when there is one).
Future<void> startProgramSheet(BuildContext context, AppState s, ProgramTemplate t) async {
  final plan = buildProgram(t, s.profile!, s.lib);
  final keys = programMaxes(plan);
  final guess = {for (final k in keys.keys) k: await s.guessMax(k, basis: t.tmBasis)};
  final ctl = {for (final k in keys.keys) k: TextEditingController(text: guess[k] == null ? '' : fmtWeight(guess[k]!, s.unit))};
  if (!context.mounted) return;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Start ${t.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Dim('${plan.days.length} days in the rotation${plan.weeksPerCycle > 1 ? ' (${plan.weeksPerCycle} weeks of ${plan.daysPerWeek})' : ''}.', size: 13),
          if (programSwaps(t, s.profile!, s.lib).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Dim('Swapped for your gym: ${programSwaps(t, s.profile!, s.lib).join(', ')}', size: 12)),
          const SizedBox(height: 6),
          PlanWeekCard(s: s, plan: plan, folded: true),
          if (keys.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(t.tmBasis == '5rm' ? 'Your best sets of 5' : (t.tmBasis == '1rm' ? 'Your 1-rep maxes' : 'Training maxes'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Dim('${tmBasisText[t.tmBasis]} Or type a recent set (100 x 5) and the app works it out. Leave a box empty and you pick only the first weight on the day; the rest follow from it.', size: 12),
            for (final k in keys.keys)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: StatefulBuilder(
                  builder: (c2, set) => TextField(
                    enableIMEPersonalizedLearning: false,
                    controller: ctl[k],
                    keyboardType: TextInputType.text, // "100 x 5" needs the x
                    onChanged: (_) => set(() {}),
                    decoration: InputDecoration(
                        labelText: '${s.lib.byId(keys[k]!)?.name ?? keys[k]}${k.contains('#') ? ' (${k.split('#')[1]})' : ''}',
                        hintText: 'or a recent set: 100 x 5',
                        // a box it cannot read says so instead of counting as empty (P3-N4)
                        errorText: ctl[k]!.text.trim().isNotEmpty && parseMaxInput(ctl[k]!.text, s.unit, t.tmBasis) == null ? 'Not understood: type 100 or 100 x 5' : null,
                        suffixText: unitLabel(s.unit),
                        isDense: true),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 14),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Start this program')),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
        ]),
      ),
    ),
  );
  if (ok != true) return;
  final maxes = <String, double?>{
    for (final k in keys.keys)
      k: () {
        final v = parseMaxInput(ctl[k]!.text, s.unit, t.tmBasis);
        final e = s.lib.byId(keys[k]!);
        return v == null || e == null ? v : roundToStep(v, e.step, s.unit);
      }()
  };
  await s.startProgram(plan, maxes);
  if (context.mounted) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    toast(context, '${t.name} started. Your old plan is under Saved plans.');
  }
}

/// "Which is right for me?" (F211): three answers, the best matches first.
class ProgramPicker extends StatefulWidget {
  final AppState s;
  const ProgramPicker({super.key, required this.s});
  @override
  State<ProgramPicker> createState() => _ProgramPickerState();
}

class _ProgramPickerState extends State<ProgramPicker> {
  late int level = switch (widget.s.profile?.experience) { 'new' => 0, 'years' => 2, _ => 1 };
  late int days = (widget.s.profile?.days ?? 3).clamp(2, 6);
  late String goal = switch (widget.s.profile?.goal) {
    Goal.strength || Goal.sport => 'strength',
    Goal.size => 'size',
    Goal.fitness || Goal.fatLoss => 'fitness',
    Goal.powerlifting => 'powerlifting',
    _ => 'both',
  };

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final have = s.profile?.have ?? Equipment.values.toSet();
    final best = suggestPrograms(level: level, days: days, goal: goal, have: have).take(3).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Which is right for me?')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: [
          const Q('How long have you been lifting?'),
          Pills<int>(values: const [0, 1, 2], label: (l) => const ['Under 6 months', '6 months to 2 years', 'Longer'][l], selected: {level}, onTap: (l) => setState(() => level = l)),
          const Q('Days a week'),
          Pills<int>(values: const [2, 3, 4, 5, 6], label: (d) => '$d', selected: {days}, onTap: (d) => setState(() => days = d)),
          const Q('Most of all you want'),
          Pills<String>(
            values: const ['strength', 'size', 'both', 'fitness', 'powerlifting'],
            label: (g) => const {'strength': 'Strength', 'size': 'Size', 'both': 'Both', 'fitness': 'General fitness', 'powerlifting': 'Powerlifting'}[g]!,
            selected: {goal},
            onTap: (g) => setState(() => goal = g),
          ),
          const SizedBox(height: 16),
          const Text('Best matches', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          for (final t in best) ProgramCard(s: s, t: t),
        ]),
      ),
    );
  }
}

/// Plan → Lift rules (F221, F222): every lift's rule, training max and stage, all editable.
class LiftRulesScreen extends StatelessWidget {
  final AppState s;
  const LiftRulesScreen({super.key, required this.s});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final pl = s.plan;
          final rules = pl?.program?.rules ?? const <String, LiftRule>{};
          final maxes = pl == null ? const <String, String>{} : programMaxes(pl);
          final keys = {...rules.keys, ...maxes.keys}.toList();
          final others = <String>{
            for (final d in pl?.days ?? const <PlanDay>[])
              for (final it in d.items)
                if (!keys.contains(liftKey(it)) && !(it.perSet?.any((x) => x.pct != null) ?? false)) liftKey(it)
          }.toList();
          return Scaffold(
            appBar: AppBar(title: const Text('Lift rules')),
            body: SafeArea(
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: [
                const Dim('How each lift moves on. Lifts with no rule here use the usual progression (Settings → Workout → Progression).', size: 13),
                for (final k in keys) _RuleTile(s: s, keyName: k, rule: rules[k]),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Give another lift its own rule', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final k in others)
                      ActionChip(
                        label: Text(_name(s, k)),
                        onPressed: () => ruleSheet(context, s, k, const LiftRule(kind: 'linear')),
                      ),
                  ]),
                ],
              ]),
            ),
          );
        },
      );
}

String _name(AppState s, String key) {
  final p = key.split('#');
  final n = s.lib.byId(p.first)?.name ?? p.first;
  return p.length > 1 ? '$n (${p[1]})' : n;
}

class _RuleTile extends StatelessWidget {
  final AppState s;
  final String keyName;
  final LiftRule? rule;
  const _RuleTile({required this.s, required this.keyName, required this.rule});

  @override
  Widget build(BuildContext context) {
    final e = s.lib.byId(keyName.split('#').first);
    return FutureBuilder<LiftState?>(
      future: s.repo.lift(keyName),
      builder: (c, snap) {
        final st = snap.data;
        final r = rule ?? const LiftRule(kind: 'tm');
        return Card(
          child: ListTile(
            title: Text(_name(s, keyName)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Dim(e == null ? r.kind : r.describe(s.unit, e.step), size: 12),
              if (r.kind == 'tm' || st?.tm != null) Text('Training max: ${st?.tm == null ? 'not set yet' : '${fmtWeight(st!.tm!, s.unit)} ${unitLabel(s.unit)}'}', style: const TextStyle(color: C.sky, fontSize: 12.5)),
              if (r.kind == 'stage' && r.stages.isNotEmpty) Text('Now on: ${r.stages[(st?.stage ?? 0).clamp(0, r.stages.length - 1)]}', style: const TextStyle(color: C.sky, fontSize: 12.5)),
            ]),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => ruleSheet(context, s, keyName, r, tm: st?.tm, stage: st?.stage ?? 0),
          ),
        );
      },
    );
  }
}

const _scriptHelp = '''One rule per line; the first that fits is used.
if top: add 1        every set at the top of the range: one step more
if hit: add 1        every set got its planned reps
if amrap >= 10: add 2   the + set got 10 or more
if reps >= 12: add 1
if miss 3: times 0.9   3rd workout in a row with a short set: 90%
if miss: same
else: reps +1
Actions: add N (steps), add 5kg / add 5lb, times 0.9, same, reps +1''';

/// The editor for one lift's rule: kind, steps, misses, reset, + goal, stages, script, training max.
Future<void> ruleSheet(BuildContext context, AppState s, String key, LiftRule start, {double? tm, int stage = 0}) async {
  var r = start;
  var st = stage;
  final tmCtl = TextEditingController(text: tm == null ? '' : fmtWeight(tm, s.unit));
  final stagesCtl = TextEditingController(text: r.stages.join(', '));
  final scriptCtl = TextEditingController(text: r.script.isEmpty ? 'if top: add 1\nif miss 3: times 0.9\nelse: same' : r.script);
  String? err;
  final e = s.lib.byId(key.split('#').first);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(_name(s, key), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const Q('How it moves on'),
            Pills<String>(
              values: [for (final k in ruleKinds.keys) if (k != 'ladder' || r.ladder.isNotEmpty) k],
              label: (k) => const {'double': 'Reps first', 'linear': 'Every session', 'tm': 'Training max', 'stage': 'Stages', 'ladder': 'Ladder', 'script': 'My own rule'}[k]!,
              selected: {r.kind},
              onTap: (k) => set(() => r = r.copyWith(kind: k)),
            ),
            Padding(padding: const EdgeInsets.only(top: 4), child: Dim(ruleKinds[r.kind]!, size: 12)),
            if (r.kind != 'script' && r.kind != 'ladder') ...[
              const Q('Weight step on a success'),
              Pills<double>(values: const [0.5, 1, 2, 3], label: (v) => '${fmtNum(v)}× (${e == null ? '' : '${fmtNum(stepIn(e.step, s.unit) * v)} ${unitLabel(s.unit)}'})', selected: {r.inc}, onTap: (v) => set(() => r = r.copyWith(inc: v))),
            ],
            if (r.kind == 'linear' || r.kind == 'ladder' || r.kind == 'tm') ...[
              const Q('Misses in a row before it changes'),
              Pills<int>(values: const [1, 2, 3, 4], label: (v) => '$v', selected: {r.misses}, onTap: (v) => set(() => r = r.copyWith(misses: v))),
            ],
            if (r.kind == 'linear' || r.kind == 'stage' || r.kind == 'tm') ...[
              const Q('Then the weight goes to'),
              Pills<double>(values: const [0.8, 0.85, 0.9, 0.95, 1.0], label: (v) => '${(v * 100).round()}%', selected: {r.reset}, onTap: (v) => set(() => r = r.copyWith(reset: v))),
            ],
            if (r.kind == 'linear' || r.kind == 'stage') ...[
              Q(r.kind == 'linear' ? 'Double jump when the + set gets' : 'Only add weight when the + set gets'),
              Pills<int>(values: const [0, 8, 10, 15, 25], label: (v) => v == 0 ? 'off' : '$v reps', selected: {r.amrapGoal}, onTap: (v) => set(() => r = r.copyWith(amrapGoal: v))),
            ],
            if (r.kind == 'stage') ...[
              const Q('Stages, in order'),
              TextField(enableIMEPersonalizedLearning: false, controller: stagesCtl, decoration: const InputDecoration(hintText: '5x3+, 6x2+, 10x1+', isDense: true)),
              if (r.stages.isNotEmpty) ...[
                const Q('Now on'),
                Pills<int>(values: [for (var i = 0; i < r.stages.length; i++) i], label: (i) => r.stages[i], selected: {st}, onTap: (i) => set(() => st = i)),
              ],
            ],
            if (r.kind == 'script') ...[
              const Q('My rule'),
              TextField(enableIMEPersonalizedLearning: false, controller: scriptCtl, maxLines: 6, minLines: 3, style: const TextStyle(fontFamily: 'monospace', fontSize: 13), decoration: const InputDecoration(isDense: true)),
              const Padding(padding: EdgeInsets.only(top: 4), child: Dim(_scriptHelp, size: 12)),
            ],
            if (r.kind == 'tm') ...[
              const Q('Training max'),
              TextField(
                enableIMEPersonalizedLearning: false,
                controller: tmCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(suffixText: unitLabel(s.unit), hintText: 'empty = set from the next workout', isDense: true),
              ),
            ],
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Problem([err!])),
            const SizedBox(height: 14),
            Row(children: [
              TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Cancel')),
              const Spacer(),
              if (start.kind.isNotEmpty) TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Usual progression')),
              FilledButton(
                onPressed: () {
                  if (r.kind == 'stage') {
                    final l = stagesCtl.text.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
                    for (final x in l) {
                      try {
                        parseSets(x);
                      } on FormatException catch (fe) {
                        set(() => err = fe.message);
                        return;
                      }
                    }
                    if (l.isEmpty) {
                      set(() => err = 'Write at least one stage, like 5x3+.');
                      return;
                    }
                    r = r.copyWith(stages: l);
                  }
                  if (r.kind == 'script') {
                    final bad = checkScript(scriptCtl.text);
                    if (bad != null) {
                      set(() => err = bad);
                      return;
                    }
                    r = r.copyWith(script: scriptCtl.text.trim());
                  }
                  Navigator.pop(c, true);
                },
                child: const Text('Save'),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (saved == null) return;
  if (saved == false) {
    await s.setRule(key, null);
    return;
  }
  await s.setRule(key, r);
  if (r.kind == 'tm') {
    final v = double.tryParse(tmCtl.text.replaceAll(',', '.'));
    await s.setTm(key, v == null || v <= 0 ? null : fromUnit(v, s.unit));
  }
  if (r.kind == 'stage' && st != stage) await s.setStage(key, st);
}
