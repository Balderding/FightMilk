import 'package:flutter/material.dart';

import '../domain/exercise.dart';
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

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final pr = s.profile!;
    var list = s.lib.search(q).where((e) => !widget.exclude.contains(e.id)).toList();
    if (fitOnly) list = list.where((e) => s.lib.usable(e, pr.have, pr.avoid)).toList();
    list = [...list]..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: TextField(autofocus: false, decoration: const InputDecoration(hintText: 'Search: name, muscle or equipment', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => q = v)),
        ),
        SwitchListTile(value: fitOnly, onChanged: (v) => setState(() => fitOnly = v), title: const Text('Only what my gym has and my joints like'), dense: true),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerLeft, child: Dim('${list.length} exercises · tap ⓘ for how to do it', size: 12))),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (c, i) {
              final e = list[i];
              return ListTile(
                leading: ExIcon(s.iconFor(e), size: 40),
                title: Text(e.name),
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

/// Swap sheet: same muscles with what the gym has. Returns (exercise, forever).
Future<(Exercise, bool)?> swapSheet(BuildContext context, AppState s, Exercise from, {Set<String> exclude = const {}}) async {
  final pr = s.profile!;
  final alts = s.lib.swapsFor(from, pr.have, pr.avoid).where((e) => !exclude.contains(e.id)).toList();
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
