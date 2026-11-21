import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/superset.dart';
import '../domain/units.dart';
import 'app_state.dart';
import 'pickers.dart';
import 'setup_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class PlanScreen extends StatelessWidget {
  final AppState s;
  const PlanScreen({super.key, required this.s});

  Future<String?> _ask(BuildContext context, String title, String initial) async {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.card,
        title: Text(title),
        content: TextField(enableIMEPersonalizedLearning: false, controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('OK'))],
      ),
    );
  }

  Plan _mine(Plan p) => Plan(id: p.id, name: p.name, source: p.source == 'built-in' ? 'mine' : p.source, days: p.days, userEdited: true, created: p.created);

  @override
  Widget build(BuildContext context) {
    final plan = s.plan;
    return SafeArea(
      child: plan == null
          ? Center(child: FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupScreen(s: s))), child: const Text('Make a plan')))
          : ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final n = await _ask(context, 'Plan name', plan.name);
                      if (n != null && n.isNotEmpty) await s.savePlanEdits(_mine(plan.renamed(n)));
                    },
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(plan.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      Dim('${plan.days.length} days in rotation · tap a day to edit${plan.userEdited ? ' · edited by you' : ''}'),
                    ]),
                  ),
                ),
                Tag(switch (plan.source) { 'ai' => 'AI', 'mine' => 'Mine', _ => 'Built-in' }, ai: plan.source == 'ai'),
              ]),
              const SizedBox(height: 10),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: (a, b) => s.savePlanEdits(_mine(plan.moveDay(a, b))),
                children: [
                  for (var i = 0; i < plan.days.length; i++)
                    Card(
                      key: ValueKey('day$i${plan.days[i].name}'),
                      child: ListTile(
                        leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle, color: C.dim)),
                        title: Text(plan.days[i].name, style: TextStyle(fontWeight: FontWeight.w600, color: i == s.todayIndex ? C.teal : C.text)),
                        subtitle: Dim(plan.days[i].items.map((it) => s.lib.byId(it.exerciseId)?.name ?? it.exerciseId).join(' · '), size: 12),
                        trailing: i == s.todayIndex ? const Tag('Next') : null,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DayEditor(s: s, dayIndex: i))),
                      ),
                    ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final n = await _ask(context, 'New day', 'Day ${plan.days.length + 1}');
                  if (n != null && n.isNotEmpty) await s.savePlanEdits(_mine(plan.addDay(n)));
                },
                icon: const Icon(Icons.add),
                label: const Text('Add a day'),
              ),
              const SizedBox(height: 20),
              const Text('New plan', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              FilledButton.tonal(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupScreen(s: s))),
                child: Text(s.settings.aiOn ? 'Make a new plan (built-in or AI)' : 'Make a new plan'),
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: () async {
                  final ok = await confirm(context, 'Start an empty plan?', 'You build it day by day. Your current plan is kept under Old plans.', yes: 'Start empty');
                  if (ok) await s.usePlan(Plan(name: 'My plan', source: 'mine', userEdited: true, days: const [PlanDay(name: 'Day 1', items: [])]));
                },
                child: const Text('Build my own from scratch'),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExercisePicker(s: s, title: 'All exercises', browse: true))),
                icon: const Icon(Icons.menu_book_outlined),
                label: Text('Browse all ${s.lib.all.length} exercises'),
              ),
              const SizedBox(height: 20),
              _OldPlans(s: s),
            ]),
    );
  }
}

class _OldPlans extends StatelessWidget {
  final AppState s;
  const _OldPlans({required this.s});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Plan>>(
        future: s.repo.oldPlans(),
        builder: (c, snap) {
          final l = snap.data ?? const [];
          if (l.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Old plans', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final p in l)
              Card(
                child: ListTile(
                  title: Text(p.name),
                  subtitle: Dim('${p.days.map((d) => d.name).join(' → ')} · ${p.created.year}-${p.created.month}-${p.created.day}', size: 12),
                  trailing: TextButton(
                    onPressed: () async {
                      if (await confirm(context, 'Go back to "${p.name}"?', 'Your current plan is kept here as an old plan. Progress per lift carries over.', yes: 'Use it')) {
                        await s.restorePlan(p.id);
                      }
                    },
                    child: const Text('Use'),
                  ),
                ),
              ),
          ]);
        },
      );
}

class DayEditor extends StatefulWidget {
  final AppState s;
  final int dayIndex;
  const DayEditor({super.key, required this.s, required this.dayIndex});
  @override
  State<DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<DayEditor> {
  AppState get s => widget.s;
  int get di => widget.dayIndex;

  Plan _mine(Plan p) => Plan(id: p.id, name: p.name, source: p.source == 'built-in' ? 'mine' : p.source, days: p.days, userEdited: true, created: p.created);

  Future<void> _save(Plan p) async {
    await s.savePlanEdits(_mine(p));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final plan = s.plan!;
    if (di >= plan.days.length) return const Scaffold();
    final day = plan.days[di];
    return Scaffold(
      appBar: AppBar(
        title: Text(day.name),
        actions: [
          IconButton(
            tooltip: 'Rename day',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final c = TextEditingController(text: day.name);
              final n = await showDialog<String>(
                context: context,
                builder: (d) => AlertDialog(
                  backgroundColor: C.card,
                  title: const Text('Day name'),
                  content: TextField(enableIMEPersonalizedLearning: false, controller: c, autofocus: true),
                  actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('OK'))],
                ),
              );
              if (n != null && n.isNotEmpty) await _save(plan.renameDay(di, n));
            },
          ),
          IconButton(
            tooltip: 'Delete day',
            icon: const Icon(Icons.delete_outline),
            onPressed: plan.days.length <= 1
                ? null
                : () async {
                    if (await confirm(context, 'Delete ${day.name}?', 'It is removed from the rotation.', yes: 'Delete')) {
                      await s.savePlanEdits(_mine(plan.removeDay(di)));
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ReorderableListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              buildDefaultDragHandles: false,
              onReorderItem: (a, b) => _save(plan.moveItem(di, a, b)),
              children: [
                for (var i = 0; i < day.items.length; i++) _tile(plan, day.items[i], i),
              ],
            ),
          ),
          if (day.items.length >= 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _save(_withItems(plan, day.items.any((x) => x.group != null) ? [for (final x in day.items) x.copyWith(clearGroup: true)] : autoSupersets(day.items, s.lib))),
                  icon: const Icon(Icons.link),
                  label: Text(day.items.any((x) => x.group != null) ? 'Remove all supersets' : 'Make supersets to save time'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final e = await Navigator.push<Exercise>(context, MaterialPageRoute(builder: (_) => ExercisePicker(s: s, exclude: {for (final it in day.items) it.exerciseId})));
                  if (e != null) {
                    await _save(plan.addItem(di, PlanItem(exerciseId: e.id, sets: 3, repLow: e.repLow, repHigh: e.repHigh, restSec: e.compound ? 120 : 75)));
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add exercise'),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Plan _withItems(Plan plan, List<PlanItem> items) {
    final days = [...plan.days]..[di] = plan.days[di].copyWith(items: items);
    return Plan(id: plan.id, name: plan.name, source: plan.source, days: days, userEdited: true, created: plan.created);
  }

  Widget _tile(Plan plan, PlanItem it, int i) {
    final e = s.lib.byId(it.exerciseId);
    return Card(
      key: ValueKey('it$i${it.exerciseId}'),
      child: ListTile(
        leading: ReorderableDragStartListener(index: i, child: e == null ? const Icon(Icons.help_outline) : ExIcon(s.iconFor(e), size: 40)),
        title: Text(e?.name ?? it.exerciseId),
        subtitle: Dim('${groupLabel(plan.days[di].items, i).isEmpty ? '' : 'Superset ${groupLabel(plan.days[di].items, i)} · '}${it.sets} × ${it.repLow}-${it.repHigh} · rest ${it.restSec}s${it.style.isEmpty ? '' : ' · last set ${lastSetStyles[it.style]!.toLowerCase()}'}'),
        onTap: () async {
          final v = await itemEditor(context, e?.name ?? it.exerciseId, it.sets, it.repLow, it.repHigh, it.restSec);
          if (v != null) await _save(plan.updateItem(di, i, it.copyWith(sets: v.$1, repLow: v.$2, repHigh: v.$3, restSec: v.$4)));
        },
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'remove') {
              await _save(plan.removeItem(di, i));
              return;
            }
            if (v == 'super' || v == 'unsuper') {
              final items = v == 'super' ? supersetWithNext(plan.days[di].items, i) : ungroup(plan.days[di].items, i);
              await _save(_withItems(plan, items));
              return;
            }
            if (v == 'linear' || v == 'double') {
              await s.setScheme(it.exerciseId, v);
              setState(() {});
              return;
            }
            if (v == 'step' && e != null) {
              final u = s.unit;
              final opts = u == Unit.lb ? const [1.25, 2.5, 5.0, 10.0] : const [0.5, 1.0, 1.25, 2.5, 5.0];
              if (!mounted) return;
              final pick = await showModalBottomSheet<double>(
                context: context,
                backgroundColor: C.card,
                builder: (c) => SafeArea(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    const ListTile(title: Text('Weight step for this lift')),
                    for (final o in opts) Padding(padding: const EdgeInsets.all(6), child: ActionChip(label: Text('${fmtNum(o)} ${unitLabel(u)}'), onPressed: () => Navigator.pop(c, fromUnit(o, u)))),
                    Padding(padding: const EdgeInsets.all(6), child: ActionChip(label: const Text('The usual'), onPressed: () => Navigator.pop(c, -1))),
                  ]),
                ),
              );
              if (pick != null) await s.setExStep(it.exerciseId, pick < 0 ? null : pick);
              setState(() {});
              return;
            }
            if (v.startsWith('style:')) {
              await _save(plan.updateItem(di, i, it.copyWith(style: v.substring(6))));
              return;
            }
            if (v == 'info' && e != null) {
              await exerciseInfo(context, s, e);
              return;
            }
            if (v == 'swap' && e != null) {
              if (!mounted) return;
              final r = await swapSheet(context, s, e, exclude: {for (final x in plan.days[di].items) x.exerciseId});
              if (r != null) await _save(plan.updateItem(di, i, it.copyWith(exerciseId: r.$1.id)));
            }
          },
          itemBuilder: (c) => [
            const PopupMenuItem(value: 'info', child: Text('How to do it')),
            const PopupMenuItem(value: 'swap', child: Text('Swap')),
            if (i + 1 < plan.days[di].items.length) const PopupMenuItem(value: 'super', child: Text('Superset with the next exercise')),
            if (it.group != null) const PopupMenuItem(value: 'unsuper', child: Text('Take out of the superset')),
            for (final st in lastSetStyles.entries)
              if (st.key != it.style) PopupMenuItem(value: 'style:${st.key}', child: Text('Last set: ${st.value.toLowerCase()}')),
            PopupMenuItem(value: s.exScheme[it.exerciseId] == 'linear' ? 'double' : 'linear', child: Text(s.exScheme[it.exerciseId] == 'linear' ? 'Progression: reps first, then weight' : 'Progression: add weight every session')),
            const PopupMenuItem(value: 'step', child: Text('Weight step for this lift')),
            const PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
      ),
    );
  }
}
