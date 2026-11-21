import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/gym.dart';
import 'anim/exercise_anim.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Searchable list of the whole library. Exercises that fit the gym and joints come first.
/// What an exercise works and how to do it.
Future<void> exerciseInfo(BuildContext context, AppState s, Exercise e) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: ExerciseAnim(e: e, size: 170)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Dim('${equipmentLabel[e.equipment]} · ${e.compound ? 'compound' : 'isolation'}${e.timed ? ' · timed' : ''}'),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Text('Works: ${e.muscles}', style: const TextStyle(color: C.teal, fontWeight: FontWeight.w600)),
            if (e.joints.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Dim('Can be hard on: ${e.joints.map((j) => jointLabel[j]!.toLowerCase()).join(', ')}')),
            const SizedBox(height: 10),
            Text(e.about.isEmpty ? 'No description yet.' : e.about, style: const TextStyle(fontSize: 15, height: 1.4)),
            const SizedBox(height: 10),
            Dim('Usual range: ${e.repLow}-${e.repHigh} ${e.timed ? 'seconds' : 'reps'}'),
            const SizedBox(height: 10),
            StatefulBuilder(
              builder: (c2, set) => Wrap(spacing: 6, runSpacing: 6, children: [
                FilterChip(
                  avatar: Icon(s.lib.favs.contains(e.id) ? Icons.star : Icons.star_border, size: 18, color: C.gold),
                  label: const Text('Favourite'),
                  selected: s.lib.favs.contains(e.id),
                  onSelected: (v) async {
                    await s.setFavourite(e.id, v);
                    set(() {});
                  },
                ),
                FilterChip(
                  avatar: const Icon(Icons.visibility_off_outlined, size: 18),
                  label: const Text('Never use'),
                  selected: s.lib.hidden.contains(e.id),
                  onSelected: (v) async {
                    await s.setHidden(e.id, v);
                    set(() {});
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Rename'),
                  onPressed: () async {
                    final ctl = TextEditingController(text: s.renames[e.id] ?? e.name);
                    final v = await showDialog<String>(
                      context: c2,
                      builder: (d) => AlertDialog(
                        backgroundColor: C.card,
                        title: const Text('Your name for it'),
                        content: TextField(enableIMEPersonalizedLearning: false, controller: ctl, autofocus: true),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, ''), child: const Text('Use the usual name')),
                          FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: const Text('Save')),
                        ],
                      ),
                    );
                    if (v != null) await s.renameExercise(e.id, v);
                    if (c2.mounted) Navigator.pop(c2);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Make my own version'),
                  onPressed: () {
                    Navigator.pop(c2);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomExerciseScreen(s: s, base: e)));
                  },
                ),
              ]),
            ),
          ]),
        ),
      ),
    );

class ExercisePicker extends StatefulWidget {
  final AppState s;
  final String title;
  final bool browse; // just looking: tap shows the explanation
  final Set<String> exclude; // already in the day
  const ExercisePicker({super.key, required this.s, this.title = 'Add exercise', this.browse = false, this.exclude = const {}});
  @override
  State<ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<ExercisePicker> {
  String q = '';
  bool fitOnly = true;
  String? muscle;
  Equipment? kind;
  List<String> recent = [];

  static const _muscles = ['chest', 'back', 'lats', 'shoulders', 'rear_delts', 'biceps', 'triceps', 'quads', 'hamstrings', 'glutes', 'calves', 'core', 'traps', 'forearms', 'adductors'];

  @override
  void initState() {
    super.initState();
    widget.s.repo.loggedExercises().then((l) {
      if (mounted) setState(() => recent = l.take(12).toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final pr = s.profile!;
    var list = s.lib.search(q).where((e) => !widget.exclude.contains(e.id)).toList();
    if (fitOnly) list = list.where((e) => s.lib.usable(e, pr.have, pr.avoid, items: pr.items)).toList();
    if (muscle != null) list = list.where((e) => e.primary.contains(muscle) || e.secondary.contains(muscle)).toList();
    if (kind != null) list = list.where((e) => e.equipment == kind).toList();
    int rank(Exercise e) => s.lib.favs.contains(e.id) ? 0 : (recent.contains(e.id) && q.isEmpty ? 1 : 2);
    list = [...list]..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        if (rank(a) == 1) return recent.indexOf(a.id).compareTo(recent.indexOf(b.id));
        return a.name.compareTo(b.name);
      });
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'mine',
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomExerciseScreen(s: s)));
          if (mounted) setState(() {});
        },
        icon: const Icon(Icons.add),
        label: const Text('My own exercise'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: TextField(enableIMEPersonalizedLearning: false, autofocus: false, decoration: const InputDecoration(hintText: 'Search: name, muscle or equipment', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => q = v)),
        ),
        SwitchListTile(value: fitOnly, onChanged: (v) => setState(() => fitOnly = v), title: const Text('Only what my gym has and my joints like'), dense: true),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final m in _muscles)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(m.replaceAll('_', ' ')), selected: muscle == m, showCheckmark: false, onSelected: (v) => setState(() => muscle = v ? m : null)),
              ),
          ]),
        ),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final k in Equipment.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(equipmentLabel[k]!), selected: kind == k, showCheckmark: false, onSelected: (v) => setState(() => kind = v ? k : null)),
              ),
          ]),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerLeft, child: Dim('${list.length} exercises · tap ⓘ for how to do it', size: 12))),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (c, i) {
              final e = list[i];
              return ListTile(
                leading: ExIcon(s.iconFor(e), size: 40),
                title: Row(children: [
                  if (s.lib.favs.contains(e.id)) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star, size: 16, color: C.gold)),
                  Flexible(child: Text(e.name)),
                  if (s.lib.hidden.contains(e.id)) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.visibility_off_outlined, size: 14, color: C.dim)),
                ]),
                subtitle: Dim('${equipmentLabel[e.equipment]} · ${e.primary.join(', ').replaceAll('_', ' ')}'),
                trailing: IconButton(icon: const Icon(Icons.info_outline, color: C.dim), onPressed: () => exerciseInfo(context, s, e)),
                onTap: () => widget.browse ? exerciseInfo(context, s, e) : Navigator.pop(context, e),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// The gym items [e] is done on here (for "taken today").
List<String> _usedItems(Exercise e, Set<String> items) {
  final opt = needsOf(e).where((o) => items.containsAll(o)).firstOrNull;
  return opt == null ? const [] : [for (final i in opt) if (gymItemById[i]?.area != 'benches') i];
}

final _retry = Exercise.fromJson(const {'id': '__retry__', 'name': '', 'equipment': 'bodyweight', 'primary': ['core'], 'secondary': [], 'pattern': '', 'swap': '', 'joints': [], 'repLow': 1, 'repHigh': 1, 'step': 'bodyweight', 'bodyweight': true, 'compound': false, 'timed': false, 'icon': '', 'about': ''});

/// Swap sheet: same muscles with what the gym has. Returns (exercise, forever).
Future<(Exercise, bool)?> swapSheet(BuildContext context, AppState s, Exercise from, {Set<String> exclude = const {}}) async {
  final pr = s.profile!;
  final alts = s.lib.swapsFor(from, pr.have, pr.avoid, items: pr.items).where((e) => !exclude.contains(e.id)).toList();
  final pick = await showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      maxChildSize: .9,
      builder: (c2, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
        Text('Swap ${from.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const Dim('Same muscles, with what your gym has'),
        if (pr.items != null)
          for (final it in _usedItems(from, pr.items!))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await s.setTaken(it, true);
                  if (c.mounted) Navigator.pop(c, _retry);
                },
                icon: const Icon(Icons.block, size: 18, color: C.gold),
                label: Text('${gymItemById[it]?.label ?? it} is taken or broken today'),
              ),
            ),
        const SizedBox(height: 10),
        if (alts.isEmpty) const Problem(['No other exercise for these muscles fits your gym. Search all exercises below.']),
        for (final e in alts)
          Card(
            color: C.card2,
            child: ListTile(
              leading: ExIcon(s.iconFor(e), size: 40),
              title: Text(e.name),
              subtitle: Dim(equipmentLabel[e.equipment]!),
              trailing: IconButton(icon: const Icon(Icons.info_outline, color: C.dim), onPressed: () => exerciseInfo(c, s, e)),
              onTap: () => Navigator.pop(c, e),
            ),
          ),
        TextButton.icon(
          onPressed: () async {
            final e = await Navigator.push<Exercise>(c, MaterialPageRoute(builder: (_) => ExercisePicker(s: s, title: 'Swap for…', exclude: {...exclude, from.id})));
            if (e != null && c.mounted) Navigator.pop(c, e);
          },
          icon: const Icon(Icons.search),
          label: const Text('Search all exercises'),
        ),
      ]),
    ),
  );
  if (pick == null || !context.mounted) return null;
  if (identical(pick, _retry)) return swapSheet(context, s, from, exclude: exclude); // the list without the taken item
  final forever = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: C.card,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${pick.name} instead of ${from.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Just today')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(c, true), child: const Text('From now on (change my plan)')),
        ]),
      ),
    ),
  );
  if (forever == null) return null;
  return (pick, forever);
}

/// Sets / reps / rest editor for one plan item. Returns the new values or null.
Future<(int, int, int, int)?> itemEditor(BuildContext context, String name, int sets, int lo, int hi, int rest) {
  return showModalBottomSheet<(int, int, int, int)>(
    context: context,
    backgroundColor: C.card,
    isScrollControlled: true,
    builder: (c) {
      var v = (sets, lo, hi, rest);
      return StatefulBuilder(builder: (c, set) {
        Widget row(String label, int val, void Function(int) f, int step, int min, int max) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 90, child: Text(label)),
                Expanded(child: BigStepper(value: '$val', unit: label == 'Rest' ? 'seconds' : '', onMinus: () => set(() => f((val - step).clamp(min, max))), onPlus: () => set(() => f((val + step).clamp(min, max))))),
              ]),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              row('Sets', v.$1, (x) => v = (x, v.$2, v.$3, v.$4), 1, 1, 10),
              row('Reps from', v.$2, (x) => v = (v.$1, x, x > v.$3 ? x : v.$3, v.$4), 1, 1, 120),
              row('Reps to', v.$3, (x) => v = (v.$1, x < v.$2 ? x : v.$2, x, v.$4), 1, 1, 120),
              row('Rest', v.$4, (x) => v = (v.$1, v.$2, v.$3, x), 15, 30, 600),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => Navigator.pop(c, v), child: const Text('Save')),
            ]),
          ),
        );
      });
    },
  );
}

/// Your own exercise, started from a similar one (it keeps that one's picture, muscles and swaps).
class CustomExerciseScreen extends StatefulWidget {
  final AppState s;
  final Exercise? base;
  final Exercise? editing;
  const CustomExerciseScreen({super.key, required this.s, this.base, this.editing});
  @override
  State<CustomExerciseScreen> createState() => _CustomExerciseScreenState();
}

class _CustomExerciseScreenState extends State<CustomExerciseScreen> {
  late Exercise? base = widget.editing ?? widget.base;
  late final name = TextEditingController(text: widget.editing?.name ?? (widget.base == null ? '' : 'My ${widget.base!.name.toLowerCase()}'));
  late final about = TextEditingController(text: widget.editing?.about ?? '');
  late int lo = (widget.editing ?? widget.base)?.repLow ?? 8, hi = (widget.editing ?? widget.base)?.repHigh ?? 12;
  late Set<String> needs = {...?(widget.editing == null ? null : customNeeds[widget.editing!.id]?.firstOrNull)};

  Future<void> _save() async {
    final b = base;
    if (b == null || name.text.trim().isEmpty) return;
    final id = widget.editing?.id ?? 'my_${DateTime.now().millisecondsSinceEpoch}';
    final e = b.copyWith(id: id, name: name.text.trim(), repLow: lo, repHigh: hi, about: about.text.trim().isEmpty ? b.about : about.text.trim());
    await widget.s.saveCustomExercise(e, needs.isEmpty ? needsOf(b) : [needs]);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: Text(widget.editing == null ? 'My own exercise' : 'Edit my exercise'), actions: [
        if (widget.editing != null)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(context, 'Delete ${widget.editing!.name}?', 'Workouts already logged with it stay in your history.', yes: 'Delete')) {
                await s.deleteCustomExercise(widget.editing!.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
      ]),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: FilledButton(onPressed: base == null ? null : _save, child: const Text('Save')))),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Dim('Start from the closest exercise in the library: yours gets its muscles, picture and swaps, and your own name and machine.', size: 12),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: base == null ? const Icon(Icons.search) : ExIcon(s.iconFor(base!), size: 40),
            title: Text(base == null ? 'Pick the closest exercise' : 'Like: ${base!.name}'),
            subtitle: base == null ? null : Dim(base!.muscles, size: 12),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final e = await Navigator.push<Exercise>(context, MaterialPageRoute(builder: (_) => ExercisePicker(s: s, title: 'Closest to mine')));
              if (e != null) setState(() => base = e);
            },
          ),
        ),
        TextField(enableIMEPersonalizedLearning: false, controller: name, decoration: const InputDecoration(labelText: 'Name'), textCapitalization: TextCapitalization.sentences),
        const SizedBox(height: 10),
        Row(children: [
          const Expanded(child: Text('Usual reps')),
          IconButton(onPressed: () => setState(() => lo = (lo - 1).clamp(1, hi)), icon: const Icon(Icons.remove)),
          Text('$lo-$hi'),
          IconButton(onPressed: () => setState(() => hi = (hi + 1).clamp(lo, 120)), icon: const Icon(Icons.add)),
        ]),
        const Q('What it needs in the gym'),
        const Dim('Leave all off to use what the exercise you started from needs.', size: 12),
        for (final area in gymAreas.entries) ...[
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(area.value, style: const TextStyle(color: C.teal))),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final it in gymItems.where((i) => i.area == area.key))
              FilterChip(label: Text(it.label), selected: needs.contains(it.id), onSelected: (v) => setState(() => v ? needs.add(it.id) : needs.remove(it.id))),
          ]),
        ],
        const SizedBox(height: 10),
        TextField(enableIMEPersonalizedLearning: false, controller: about, maxLines: 3, decoration: const InputDecoration(labelText: 'How to do it (optional)')),
      ]),
    );
  }
}
