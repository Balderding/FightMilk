import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/gym.dart';
import '../domain/plan.dart';
import '../domain/plan_maker.dart';
import '../domain/body.dart';
import '../domain/units.dart';
import '../domain/volume.dart';
import 'ai_sheet.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';
import 'import_screen.dart';

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
        Profile(
          goal: Goal.both,
          days: 4,
          minutes: 60,
          have: const {Equipment.barbell, Equipment.dumbbell, Equipment.machine, Equipment.cable},
          avoid: const {},
          unit: _localUnit(),
        );
  }

  /// Pounds where the phone's region uses them (read on the phone, nothing is sent).
  static Unit _localUnit() {
    final c = WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? '';
    return const {'US', 'LR', 'MM'}.contains(c.toUpperCase()) ? Unit.lb : Unit.kg;
  }

  GymTemplate? _tpl; // where you train (first setup): becomes your first gym
  late final _bw = TextEditingController(text: widget.s.profile?.bodyKg == null ? '' : fmtWeight(widget.s.profile!.bodyKg!, widget.s.profile!.unit));
  late final _age = TextEditingController(text: widget.s.profile?.age?.toString() ?? '');
  late final _height = TextEditingController(
      text: widget.s.profile?.heightCm == null ? '' : (widget.s.profile!.unit == Unit.kg ? '${widget.s.profile!.heightCm!.round()}' : fmtHeight(widget.s.profile!.heightCm!, Unit.lb).replaceAll(' ft ', "'").replaceAll(' in', ''))); // F300

  /// The optional body answers typed in (F199); empty boxes clear them.
  Profile _withBody(Profile x) {
    final w = double.tryParse(_bw.text.replaceAll(',', '.'));
    final a = int.tryParse(_age.text);
    final h = parseHeight(_height.text);
    final base = Profile.fromJson({...x.toJson()..remove('bodyKg')..remove('age')..remove('height')});
    return base.copyWith(
        bodyKg: w != null && validBodyKg(fromUnit(w, x.unit)) ? fromUnit(w, x.unit) : null, age: a != null && a >= 12 && a <= 100 ? a : null, heightCm: h, items: x.items);
  }

  static String _muscle(String m) => '${m[0].toUpperCase()}${m.substring(1)}';

  Set<T> _toggle<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};

  Future<void> _make({required bool ai}) async {
    final s = widget.s;
    if (s.plan != null && s.plan!.userEdited) {
      final ok = await confirm(context, 'Replace your edited plan?', 'You changed this plan by hand. The new plan replaces it; the old one is kept under Plan → Old plans.', yes: 'Replace');
      if (!ok) return;
    }
    setState(() => busy = true);
    p = _withBody(p);
    final t = _tpl;
    if (t != null && s.gyms.isEmpty) {
      p = p.copyWith(have: kindsOf(t.items));
      await s.saveGym(Gym.create(t.id == 'bodyweight' ? 'Bodyweight' : t.label, {...t.items}, maxDumbbellKg: t.maxDumbbellKg), use: true);
    }
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
    // the rest-timer buzz needs this; asked here once, not in the middle of the first workout
    if (widget.firstRun) {
      s.notifier.askOnce().ignore();
      s.showTour = true;
    }
    if (!widget.firstRun) Navigator.pop(context);
  }

  Future<void> _saveOnly() async {
    await widget.s.saveProfile(_withBody(p));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: Text(widget.firstRun ? "Let's set you up" : 'Your setup'), automaticallyImplyLeading: !widget.firstRun),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          if (widget.firstRun) const Padding(padding: EdgeInsets.only(top: 8), child: Dim('Three quick answers. Everything else has a sensible start and can be changed any time.', size: 13)),
          const Q('Days per week'),
          Pills(values: const [1, 2, 3, 4, 5, 6, 7], label: (d) => '$d', selected: {p.days}, onTap: (d) => setState(() => p = p.copyWith(days: d, weekdays: p.weekdays.length == d ? null : const []))),
          if (s.gyms.isEmpty) ...[
            const Q('Where do you train?'),
            Pills<GymTemplate?>(
              values: [for (final t in gymTemplates) if (t.id != 'empty') t, null],
              label: (t) => t == null ? "I'll pick the equipment" : t.label,
              selected: {_tpl},
              onTap: (t) => setState(() => _tpl = t),
            ),
            if (_tpl != null) Padding(padding: const EdgeInsets.only(top: 4), child: Dim('${_tpl!.note} You can tick the exact machines later in Settings → Gyms & equipment.', size: 12)),
          ],
          const Q('Weights in'),
          Pills(values: Unit.values, label: unitLabel, selected: {p.unit}, onTap: (u) => setState(() => p = p.copyWith(unit: u))),
          if (s.gyms.isEmpty && _tpl == null) ...[
            const Q('Your gym has'),
            Pills(
                values: Equipment.values.where((e) => e != Equipment.bodyweight).toList(),
                label: (e) => equipmentLabel[e]!,
                selected: p.have,
                onTap: (e) => setState(() => p = p.copyWith(have: _toggle(p.have, e)))),
          ] else if (s.activeGym != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Dim('Equipment: from your gym, ${s.activeGym!.name} (Settings → Gyms & equipment).', size: 12)),
          // first run: in sight, not inside "More choices" (review 6 P3-N42)
          if (widget.firstRun)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImportScreen(s: widget.s))),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Coming from another app? Import your history'),
              ),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: !widget.firstRun,
            title: const Text('More choices'),
            subtitle: Dim(
                '${goalLabel[p.goal]} · ${experienceLabel[p.experience]} · ${p.minutes} min${p.weekdays.isEmpty ? '' : ' · ${p.weekdays.map((d) => weekdayShort[d - 1]).join('/')}'}${p.avoid.isEmpty ? '' : ' · go easy on ${p.avoid.length}'} · ${p.split == null ? 'split chosen for you' : splitLabel[p.split]}',
                size: 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Q('Goal'),
              Pills(values: Goal.values, label: (g) => goalLabel[g]!, selected: {p.goal}, onTap: (g) => setState(() => p = p.copyWith(goal: g))),
              Padding(padding: const EdgeInsets.only(top: 4), child: Dim(goalHelp[p.goal]!, size: 12)),
              const Q('How long have you been lifting?'),
              Pills<String>(values: experienceLabel.keys.toList(), label: (x) => experienceLabel[x]!, selected: {p.experience}, onTap: (x) => setState(() => p = p.copyWith(experience: x))),
              const Padding(padding: EdgeInsets.only(top: 4), child: Dim('New: fewer sets to start and machines first for the extras. Years: a set more on the extras.', size: 12)),
              const Q('Time per session'),
              Pills(values: sessionLengths, label: (m) => '$m min', selected: {p.minutes}, onTap: (m) => setState(() => p = p.copyWith(minutes: m))),
              const Q('Train on set weekdays?'),
              Pills<int>(
                values: const [1, 2, 3, 4, 5, 6, 7],
                label: (d) => weekdayShort[d - 1],
                selected: p.weekdays.toSet(),
                onTap: (d) => setState(() {
                  final l = p.weekdays.contains(d) ? ([...p.weekdays]..remove(d)) : ([...p.weekdays, d]..sort());
                  p = p.copyWith(weekdays: l, days: l.isEmpty ? null : l.length);
                }),
              ),
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Dim(p.weekdays.isEmpty ? 'None picked: the plan runs in a loop, train any day.' : 'Each plan day belongs to one of these days; on other days Today says it is a rest day.', size: 12)),
              const Q('Go easy on'),
              Pills(values: Joint.values, label: (j) => jointLabel[j]!, selected: p.avoid, onTap: (j) => setState(() => p = p.copyWith(avoid: _toggle(p.avoid, j)))),
              const Q('How to split the week'),
              Pills<String?>(
                values: [null, ...splitLabel.keys],
                label: (v) => v == null ? 'Let the app choose' : splitLabel[v]!,
                selected: {p.split},
                onTap: (v) => setState(() => p = v == null ? p.copyWith(clearSplit: true) : p.copyWith(split: v)),
              ),
              if (p.split != null) Padding(padding: const EdgeInsets.only(top: 4), child: Dim(splitHelp[p.split]!, size: 12)),
              const Q('More work for (priority)'),
              Pills<String>(
                values: priorityMuscles,
                label: _muscle,
                selected: p.priority,
                onTap: (m) => setState(() => p = p.copyWith(priority: _toggle(p.priority, m), low: {...p.low}..remove(m))),
              ),
              const Q('Less work for'),
              Pills<String>(
                values: priorityMuscles,
                label: _muscle,
                selected: p.low,
                onTap: (m) => setState(() => p = p.copyWith(low: _toggle(p.low, m), priority: {...p.priority}..remove(m))),
              ),
              const Q('A focus block for one muscle'),
              Pills<String?>(
                values: [null, ...priorityMuscles],
                label: (m) => m == null ? 'None' : _muscle(m),
                selected: {p.special},
                onTap: (m) => setState(() => p = m == null ? p.copyWith(clearSpecial: true) : p.copyWith(special: m)),
              ),
              const Padding(padding: EdgeInsets.only(top: 4), child: Dim('Extra sets and one more exercise for it; the rest is held, not grown. Run it 4-6 weeks, then make a normal plan.', size: 12)),
              const Q('Sport or long runs on'),
              Pills<int>(
                values: const [1, 2, 3, 4, 5, 6, 7],
                label: (d) => weekdayShort[d - 1],
                selected: p.sportDays,
                onTap: (d) => setState(() => p = p.copyWith(sportDays: _toggle(p.sportDays, d))),
              ),
              const Padding(padding: EdgeInsets.only(top: 4), child: Dim('On those days and the day before, leg exercises get one set fewer.', size: 12)),
              const Q('About you (optional)'),
              const Dim('Used for a first guess at your starting weights and for the body numbers. Stays on your phone.', size: 12),
              Row(children: [
                Expanded(
                    child: TextField(
                        enableIMEPersonalizedLearning: false,
                        controller: _bw,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'Body weight', suffixText: unitLabel(p.unit), isDense: true))),
                const SizedBox(width: 10),
                Expanded(child: TextField(enableIMEPersonalizedLearning: false, controller: _age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Age', isDense: true))),
                const SizedBox(width: 10),
                Expanded(child: TextField(enableIMEPersonalizedLearning: false, controller: _height, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height', suffixText: 'cm', isDense: true))),
              ]),
              const SizedBox(height: 6),
              Pills<String?>(
                values: const [null, 'f', 'm'],
                label: (x) => switch (x) { 'f' => 'Female', 'm' => 'Male', _ => 'Rather not say' },
                selected: {p.sex},
                onTap: (x) => setState(() => p = x == null ? Profile.fromJson({...p.toJson()..remove('sex')}).copyWith(items: p.items) : p.copyWith(sex: x)),
              ),
              if (p.sex != 'm') ...[
                const Q('Pregnant, or had a baby in the last year?'),
                Pills<String?>(
                  values: const [null, 'pregnant', 'postpartum'],
                  label: (x) => x == null ? 'No' : pregnancyLabel[x]!,
                  selected: {p.pregnancy},
                  onTap: (x) => setState(() => p = x == null ? p.copyWith(clearPregnancy: true) : p.copyWith(pregnancy: x)),
                ),
                if (p.pregnancy != null) const Padding(padding: EdgeInsets.only(top: 4), child: Dim(pregnancyHelp, size: 12)),
              ],
            ],
          ),
          Padding(padding: const EdgeInsets.only(top: 6), child: Dim('Days: ${dayNames(p.days, p.split).join(' · ')}')),
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
