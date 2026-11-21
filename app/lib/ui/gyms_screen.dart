import 'package:flutter/material.dart';

import '../domain/gym.dart';
import '../domain/plates.dart';
import '../domain/units.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Your gyms: which one you are at, add one from a template, edit what each has.
class GymsScreen extends StatefulWidget {
  final AppState s;
  const GymsScreen({super.key, required this.s});
  @override
  State<GymsScreen> createState() => _GymsScreenState();
}

class _GymsScreenState extends State<GymsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: const Text('Your gyms')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await addGym(context, s);
          if (mounted) setState(() {});
        },
        icon: const Icon(Icons.add),
        label: const Text('Add a gym'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [
        const Dim('Each gym lists the machines and equipment it really has. Plans, swaps and the AI only use what is in the gym you are at.'),
        const SizedBox(height: 10),
        if (s.gyms.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No gyms yet. Tap "Add a gym" and start from Planet Fitness, a big gym, a home gym, a hotel gym or nothing.'))),
        for (final g in s.gyms)
          Card(
            child: ListTile(
              leading: Icon(g.id == s.gymId ? Icons.radio_button_checked : Icons.radio_button_off, color: g.id == s.gymId ? C.teal : C.dim),
              title: Text(g.name),
              subtitle: Dim('${g.items.length} items${g.id == s.gymId ? ' · you are here' : ''}', size: 12),
              onTap: () async {
                await s.useGym(g.id);
                if (mounted) setState(() {});
              },
              trailing: IconButton(
                tooltip: 'Edit what this gym has',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => GymEditScreen(s: s, gym: g)));
                  if (mounted) setState(() {});
                },
              ),
            ),
          ),
        if (s.gyms.isNotEmpty)
          TextButton(
            onPressed: () async {
              await s.useGym(null);
              if (mounted) setState(() {});
            },
            child: Text(s.gymId == null ? 'No gym picked: your setup\'s equipment is used' : 'Use no gym (go back to the setup\'s equipment)'),
          ),
      ]),
    );
  }
}

/// Pick a template, name it, then walk through and tick what is there.
Future<void> addGym(BuildContext context, AppState s) async {
  final t = await showModalBottomSheet<GymTemplate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      maxChildSize: .95,
      builder: (c2, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
        const Text('What kind of gym?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const Dim('Pick the closest; next you tick what yours really has.'),
        const SizedBox(height: 8),
        for (final t in gymTemplates)
          Card(
            color: C.card2,
            child: ListTile(title: Text(t.label), subtitle: Dim(t.note, size: 12), onTap: () => Navigator.pop(c, t)),
          ),
      ]),
    ),
  );
  if (t == null || !context.mounted) return;
  final g = Gym.create(t.id == 'empty' || t.id == 'bodyweight' ? (t.id == 'empty' ? 'My gym' : 'Bodyweight') : t.label, {...t.items}, maxDumbbellKg: t.maxDumbbellKg);
  await Navigator.push(context, MaterialPageRoute(builder: (_) => GymEditScreen(s: s, gym: g, isNew: true)));
}

/// The walk-through: every area, every item, tick what you see.
class GymEditScreen extends StatefulWidget {
  final AppState s;
  final Gym gym;
  final bool isNew;
  const GymEditScreen({super.key, required this.s, required this.gym, this.isNew = false});
  @override
  State<GymEditScreen> createState() => _GymEditScreenState();
}

class _GymEditScreenState extends State<GymEditScreen> {
  late final name = TextEditingController(text: widget.gym.name);
  late Set<String> items = {...widget.gym.items};
  late double? maxDb = widget.gym.maxDumbbellKg;
  late double? bar = widget.gym.barKg;
  late double smith = widget.gym.smithKg;
  late List<double>? plates = widget.gym.plates;

  Future<void> _save() async {
    final g = Gym(
      id: widget.gym.id,
      name: name.text.trim().isEmpty ? 'My gym' : name.text.trim(),
      items: items,
      maxDumbbellKg: maxDb,
      barKg: bar,
      smithKg: smith,
      plates: plates,
      platesUnit: widget.s.unit == Unit.kg ? 'kg' : 'lb',
    );
    await widget.s.saveGym(g, use: widget.isNew);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final u = s.unit;
    return Scaffold(
      appBar: AppBar(title: Text(widget.isNew ? 'New gym' : 'Edit gym'), actions: [
        if (!widget.isNew)
          IconButton(
            tooltip: 'Delete this gym',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(context, 'Delete ${widget.gym.name}?', 'Only the gym list goes; your workouts stay.', yes: 'Delete')) {
                await s.deleteGym(widget.gym.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: FilledButton(onPressed: _save, child: Text(widget.isNew ? 'Save and use this gym' : 'Save'))),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        TextField(enableIMEPersonalizedLearning: false, controller: name, decoration: const InputDecoration(labelText: 'Name'), textCapitalization: TextCapitalization.words),
        const SizedBox(height: 8),
        const Dim('Walk round and tick what you see. Exercises that need something you leave unticked are not used here.', size: 12),
        for (final area in gymAreas.entries) ...[
          Q(area.value),
          for (final it in gymItems.where((i) => i.area == area.key))
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: items.contains(it.id),
              title: Text(it.label),
              onChanged: (v) => setState(() => v == true ? items.add(it.id) : items.remove(it.id)),
            ),
          if (area.key == 'racks' && (items.contains('barbell') || items.contains('smith'))) ...[
            const SizedBox(height: 6),
            const Text('Bar and plates (for "per side")', style: TextStyle(fontWeight: FontWeight.w600)),
            if (items.contains('barbell')) ...[
              const Dim('The barbell weighs', size: 12),
              Pills<double>(
                values: u == Unit.lb ? [lbToKg(45), lbToKg(35), lbToKg(25), lbToKg(15)] : const [20, 15, 10],
                label: (v) => '${fmtWeight(v, u)} ${unitLabel(u)}',
                selected: {bar ?? defaultBarKg(u)},
                onTap: (v) => setState(() => bar = v),
              ),
            ],
            if (items.contains('smith')) ...[
              const Dim('The Smith bar counts as (many are counterbalanced: 0)', size: 12),
              Pills<double>(
                values: u == Unit.lb ? [0, lbToKg(15), lbToKg(25), lbToKg(35)] : const [0, 7, 10, 15],
                label: (v) => v == 0 ? '0' : '${fmtWeight(v, u)} ${unitLabel(u)}',
                selected: {smith},
                onTap: (v) => setState(() => smith = v),
              ),
            ],
            const Dim('Plate sizes there (each side)', size: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final pl in (u == Unit.lb ? const [55.0, 45.0, 35.0, 25.0, 10.0, 5.0, 2.5, 1.25] : const [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25, 0.5]))
                FilterChip(
                  label: Text('${fmtNum(pl)} ${unitLabel(u)}'),
                  selected: (plates ?? (u == Unit.lb ? defaultPlatesLb : defaultPlatesKg)).contains(pl),
                  onSelected: (on) => setState(() {
                    final cur = [...(plates ?? (u == Unit.lb ? defaultPlatesLb : defaultPlatesKg))];
                    on ? cur.add(pl) : cur.remove(pl);
                    cur.sort((a, b) => b.compareTo(a));
                    plates = cur;
                  }),
                ),
            ]),
          ],
          if (area.key == 'free' && items.contains('dumbbells')) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Expanded(child: Text('Heaviest dumbbell')),
              IconButton(onPressed: () => setState(() => maxDb = ((maxDb ?? 30) - fromUnit(u == Unit.kg ? 2 : 5, u)).clamp(2, 100)), icon: const Icon(Icons.remove)),
              Text(maxDb == null ? 'not set' : '${fmtWeight(maxDb!, u)} ${unitLabel(u)}'),
              IconButton(onPressed: () => setState(() => maxDb = ((maxDb ?? 30) + fromUnit(u == Unit.kg ? 2 : 5, u)).clamp(2, 100)), icon: const Icon(Icons.add)),
            ]),
          ],
        ],
        const SizedBox(height: 12),
        Dim('${s.lib.all.where((e) => gymAllows(e, items)).length} of ${s.lib.all.length} exercises can be done here.', size: 12),
      ]),
    );
  }
}

/// The gym chip's sheet on Today: switch gym, manage gyms, see what is taken today.
Future<void> gymSheet(BuildContext context, AppState s) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.card,
    builder: (c) => SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
        const Text('Which gym today?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final g in s.gyms)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(g.id == s.gymId ? Icons.radio_button_checked : Icons.radio_button_off, color: g.id == s.gymId ? C.teal : C.dim),
            title: Text(g.name),
            onTap: () async {
              await s.useGym(g.id);
              if (c.mounted) Navigator.pop(c);
            },
          ),
        if (s.takenToday.isNotEmpty) ...[
          const Q('Taken or broken today'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final i in s.takenToday)
              InputChip(
                label: Text(gymItemById[i]?.label ?? i),
                onDeleted: () async {
                  await s.setTaken(i, false);
                  if (c.mounted) Navigator.pop(c);
                },
              ),
          ]),
          const Dim('They come back by themselves tomorrow.', size: 12),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(c);
            Navigator.push(context, MaterialPageRoute(builder: (_) => GymsScreen(s: s)));
          },
          icon: const Icon(Icons.fitness_center),
          label: const Text('Manage gyms'),
        ),
      ]),
    ),
  );
}
