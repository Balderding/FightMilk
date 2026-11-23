import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/plan_maker.dart';
import '../domain/program.dart';
import '../domain/superset.dart';
import '../domain/units.dart';
import 'app_state.dart';
import 'coaching_screen.dart';
import 'muscles_screen.dart';
import 'pickers.dart';
import 'programs_screen.dart';
import 'setup_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'plan_share.dart';

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

  Plan _mine(Plan p) => p.copyWith(source: p.source == 'built-in' ? 'mine' : p.source, userEdited: true);

  @override
  Widget build(BuildContext context) {
    final plan = s.plan;
    return SafeArea(
      child: plan == null
          ? Center(child: FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupScreen(s: s))), child: const Text('Make my plan')))
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
                      Dim(plan.weeksPerCycle > 1
                          ? 'Week ${s.programWeek.$1} of ${plan.weeksPerCycle} · cycle ${s.programWeek.$2} · ${plan.daysPerWeek} days a week'
                          : '${plan.days.length} days in rotation · tap a day to edit${plan.userEdited ? ' · edited by you' : ''}'),
                      if (plan.folder.isNotEmpty) Dim('Folder: ${plan.folder}', size: 12),
                    ]),
                  ),
                ),
                Tag(switch (plan.source) { 'ai' => 'AI', 'mine' => 'Mine', 'program' => 'Program', _ => 'Built-in' }, ai: plan.source == 'ai'),
                IconButton(tooltip: 'Switch plan', icon: const Icon(Icons.swap_vert), onPressed: () => plansSheet(context, s)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                ActionChip(avatar: const Icon(Icons.library_books_outlined, size: 18), label: const Text('Programs'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProgramsScreen(s: s)))),
                ActionChip(avatar: const Icon(Icons.history_toggle_off, size: 18), label: const Text('Changes'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChangesScreen(s: s)))),
                if (!s.settings.simple || plan.program != null)
                  ActionChip(avatar: const Icon(Icons.trending_up, size: 18), label: const Text('Lift rules'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiftRulesScreen(s: s)))),
                if (!s.settings.simple) ActionChip(avatar: const Icon(Icons.shuffle, size: 18), label: Text(plan.rotateWeeks == 0 ? 'Variety: off' : 'Variety: ${plan.rotateWeeks} weeks'), onPressed: () => _variety(context, plan)),
                if (!s.settings.simple) ActionChip(avatar: const Icon(Icons.adjust, size: 18), label: const Text('Weak point'), onPressed: () => _weakPoint(context, plan)),
                ActionChip(avatar: const Icon(Icons.share, size: 18), label: const Text('Share plan'), onPressed: () => planShareSheet(context, s, plan)),
                ActionChip(
                    avatar: const Icon(Icons.copy_all_outlined, size: 18),
                    label: const Text('Copy plan'),
                    onPressed: () async {
                      await s.duplicatePlan();
                      if (context.mounted) toast(context, 'Copy saved under Saved plans');
                    }),
              ]),
              for (final w in planWarnings(plan, s.lib)) Padding(padding: const EdgeInsets.only(top: 6), child: Text(w, style: const TextStyle(color: C.gold, fontSize: 12.5))),
              const SizedBox(height: 6),
              PlanWeekCard(
                  s: s,
                  plan: plan,
                  folded: true,
                  onFit: () async {
                    final n = await s.fitPlanVolume();
                    if (context.mounted) toast(context, n == 0 ? 'Nothing to change within your session time' : 'Changed $n set${n == 1 ? '' : 's'}');
                  }),
              const SizedBox(height: 10),
              if (plan.weeksPerCycle > 1)
                for (var w = 0; w < plan.weeksPerCycle; w++)
                  ExpansionTile(
                    key: ValueKey('week$w'),
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: s.todayIndex ~/ plan.daysPerWeek == w,
                    title: Text('Week ${w + 1}', style: TextStyle(fontWeight: FontWeight.w700, color: s.todayIndex ~/ plan.daysPerWeek == w ? C.teal : C.text)),
                    children: [
                      for (var i = w * plan.daysPerWeek; i < (w + 1) * plan.daysPerWeek && i < plan.days.length; i++)
                        Card(
                          child: ListTile(
                            title: Text(plan.days[i].name, style: TextStyle(fontWeight: FontWeight.w600, color: i == s.todayIndex ? C.teal : C.text)),
                            subtitle: Dim(plan.days[i].items.map((it) => s.lib.byId(it.exerciseId)?.name ?? it.exerciseId).join(' · '), size: 12),
                            trailing: i == s.todayIndex ? const Tag('Next') : null,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DayEditor(s: s, dayIndex: i))),
                          ),
                        ),
                    ],
                  )
              else
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
                child: const Text('Make my plan'),
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

  Future<void> _variety(BuildContext context, Plan plan) async {
    final v = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Change the accessories every…', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Dim('Main lifts stay; the smaller exercises change to another of the same kind your gym has, so the plan stays fresh.', size: 12)),
          for (final n in const [0, 4, 6, 8]) ListTile(title: Text(n == 0 ? 'Never (keep them)' : '$n weeks'), trailing: plan.rotateWeeks == n ? const Icon(Icons.check, color: C.teal) : null, onTap: () => Navigator.pop(c, n)),
        ]),
      ),
    );
    if (v != null) await s.setRotation(v);
  }

  Future<void> _weakPoint(BuildContext context, Plan plan) async {
    final lifts = [for (final k in weakPoints.keys) if (plan.days.any((d) => d.items.any((it) => it.exerciseId == k))) k];
    if (lifts.isEmpty) {
      toast(context, 'Weak points are for bench, squat, deadlift and overhead press, and this plan has none of them.');
      return;
    }
    final r = await showModalBottomSheet<(String, String)>(
      context: context,
      backgroundColor: C.card,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
          const Text('Where does the lift get hard?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Dim('An exercise for that part goes in after the lift on every day that has it.', size: 12),
          for (final l in lifts) ...[
            Q(s.lib.byId(l)?.name ?? l),
            Wrap(spacing: 6, runSpacing: 4, children: [for (final pt in weakPoints[l]!.keys) ActionChip(label: Text(pt), onPressed: () => Navigator.pop(c, (l, pt)))]),
          ],
        ]),
      ),
    );
    if (r == null) return;
    final n = await s.addWeakPoint(r.$1, r.$2);
    if (context.mounted) toast(context, n == null ? 'None of the exercises for that fit your gym, or it is already in.' : '$n added after ${s.lib.byId(r.$1)?.name}');
  }
}

/// Saved plans (F206, F207): switch, copy, folders and search, one tap from the top of Plan.
Future<void> plansSheet(BuildContext context, AppState s) async {
  var q = '';
  final all = await s.savedPlans();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.card,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final l = [for (final p in all) if (q.isEmpty || '${p.name} ${p.folder}'.toLowerCase().contains(q.toLowerCase())) p];
      final folders = {for (final p in l) p.folder}.toList()..sort();
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        builder: (c2, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
          const Text('Saved plans', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          Dim('Now: ${s.plan?.name ?? 'none'}. Progress per lift carries over when you switch.', size: 12),
          const SizedBox(height: 8),
          TextField(enableIMEPersonalizedLearning: false, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search plans', isDense: true), onChanged: (v) => set(() => q = v.trim())),
          if (l.isEmpty) const Padding(padding: EdgeInsets.only(top: 16), child: Dim('No saved plans yet. "Copy plan" or starting a new one keeps the old one here.')),
          for (final f in folders) ...[
            Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(f.isEmpty ? 'No folder' : f, style: const TextStyle(fontWeight: FontWeight.w700, color: C.sky))),
            for (final p in l.where((p) => p.folder == f))
              Card(
                child: ListTile(
                  title: Text(p.name),
                  subtitle: Dim('${p.days.length} days · ${p.created.year}-${p.created.month}-${p.created.day}', size: 12),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'use') {
                        await s.restorePlan(p.id);
                        if (c.mounted) Navigator.pop(c);
                      } else if (v == 'copy') {
                        await s.duplicatePlan(id: p.id);
                        all
                          ..clear()
                          ..addAll(await s.savedPlans());
                        set(() {});
                      } else if (v == 'folder') {
                        final ctl = TextEditingController(text: p.folder);
                        final n = await showDialog<String>(
                          context: c,
                          builder: (d) => AlertDialog(
                            backgroundColor: C.card,
                            title: const Text('Folder'),
                            content: TextField(enableIMEPersonalizedLearning: false, controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Home, Travel (empty = none)')),
                            actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('OK'))],
                          ),
                        );
                        if (n == null) return;
                        await s.setPlanFolder(p.id, n);
                        all
                          ..clear()
                          ..addAll(await s.savedPlans());
                        set(() {});
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'use', child: Text('Use this plan')),
                      PopupMenuItem(value: 'copy', child: Text('Make a copy')),
                      PopupMenuItem(value: 'folder', child: Text('Put in a folder')),
                    ],
                  ),
                  onTap: () async {
                    await s.restorePlan(p.id);
                    if (c.mounted) Navigator.pop(c);
                  },
                ),
              ),
          ],
          if (s.plan != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_outlined),
              label: Text(s.plan!.folder.isEmpty ? 'Put the current plan in a folder' : 'Current plan folder: ${s.plan!.folder}'),
              onPressed: () async {
                final ctl = TextEditingController(text: s.plan!.folder);
                final n = await showDialog<String>(
                  context: c,
                  builder: (d) => AlertDialog(
                    backgroundColor: C.card,
                    title: const Text('Folder'),
                    content: TextField(enableIMEPersonalizedLearning: false, controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Gym, Home (empty = none)')),
                    actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('OK'))],
                  ),
                );
                if (n != null) await s.setPlanFolder(s.plan!.id, n);
                set(() {});
              },
            ),
          ],
        ]),
      );
    }),
  );
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
            Row(children: [
              const Expanded(child: Text('Saved plans', style: TextStyle(fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => plansSheet(context, s), child: const Text('Search and folders')),
            ]),
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

  Plan _mine(Plan p) => p.copyWith(source: p.source == 'built-in' ? 'mine' : p.source, userEdited: true);

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
            tooltip: 'Duplicate day',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              await _save(plan.duplicateDay(di));
              if (context.mounted) toast(context, 'Copy added after this day');
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
    return plan.copyWith(days: days, userEdited: true);
  }

  Widget _tile(Plan plan, PlanItem it, int i) {
    final e = s.lib.byId(it.exerciseId);
    return Card(
      key: ValueKey('it$i${it.exerciseId}'),
      child: ListTile(
        leading: ReorderableDragStartListener(index: i, child: e == null ? const Icon(Icons.help_outline) : ExIcon(s.iconFor(e), size: 40)),
        title: Text(e?.name ?? it.exerciseId),
        subtitle: Dim('${groupLabel(plan.days[di].items, i).isEmpty ? '' : 'Superset ${groupLabel(plan.days[di].items, i)} · '}${it.sets} × ${it.repLow}-${it.repHigh} · rest ${it.restSec}s${it.style.isEmpty ? '' : ' · last set ${lastSetStyles[it.style]!.toLowerCase()}'}'),
        trailing: const Icon(Icons.edit_outlined, color: C.dim),
        onTap: () => _itemSheet(plan, it, i),
      ),
    );
  }

  /// Everything about one exercise in the plan on one sheet, with the current choice shown.
  Future<void> _itemSheet(Plan plan, PlanItem it, int i) async {
    final e = s.lib.byId(it.exerciseId);
    final simple = s.settings.simple;
    final u = s.unit;
    final stepOpts = u == Unit.lb ? const [1.25, 2.5, 5.0, 10.0] : const [0.5, 1.0, 1.25, 2.5, 5.0];
    var sets = it.sets, lo = it.repLow, hi = it.repHigh, rest = it.restSec;
    var style = it.style;
    var scheme = s.exScheme[it.exerciseId] ?? 'double';
    final setsCtl = TextEditingController(text: setsText(it.specs));
    String? setsErr;
    double? step = s.exStep[it.exerciseId];
    final items = plan.days[di].items;
    final res = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        Widget row(String label, int val, void Function(int) f, int by, int min, int max, {String unit = ''}) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 84, child: Text(label)),
                Expanded(child: BigStepper(value: '$val', unit: unit, onMinus: () => set(() => f((val - by).clamp(min, max))), onPlus: () => set(() => f((val + by).clamp(min, max))))),
              ]),
            );
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .85,
          maxChildSize: .95,
          builder: (c2, sc) => SafeArea(
            child: ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
              Text(e?.name ?? it.exerciseId, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (it.perSet == null) ...[
                row('Sets', sets, (x) => sets = x, 1, 1, 10),
                row('Reps from', lo, (x) {
                  lo = x;
                  if (hi < x) hi = x;
                }, 1, 1, 120),
                row('Reps to', hi, (x) {
                  hi = x;
                  if (lo > x) lo = x;
                }, 1, 1, 120),
              ] else
                const Dim('This lift has its own target for each set (written below).', size: 12),
              row('Rest', rest, (x) => rest = x, 15, 30, 600, unit: 'seconds'),
              if (!simple) ...[
                const Q('Last set'),
                Pills<String>(values: lastSetStyles.keys.toList(), label: (k) => lastSetStyles[k]!, selected: {style}, onTap: (k) => set(() => style = k)),
                const Q('How the weight goes up'),
                Pills<String>(
                  values: const ['double', 'linear'],
                  label: (k) => k == 'linear' ? 'Every session' : 'Reps first, then weight',
                  selected: {scheme},
                  onTap: (k) => set(() => scheme = k),
                ),
                Dim(scheme == 'linear' ? 'Adds weight each time you hit the reps (good for big barbell lifts).' : 'Work up to the top of the rep range, then add weight and start at the bottom again (double progression).', size: 12),
                const Q('Every set, written out'),
                TextField(
                  enableIMEPersonalizedLearning: false,
                  controller: setsCtl,
                  decoration: InputDecoration(isDense: true, errorText: setsErr, helperText: '3x8-12 · 5x5 · 2x5 1x5+ (last set as many as you can) · 1x5@85 (85% of the training max)', helperMaxLines: 2),
                  onChanged: (_) => set(() => setsErr = null),
                ),
                const Q('Weight step for this lift'),
                Pills<double?>(
                  values: [null, ...stepOpts.map((o) => fromUnit(o, u))],
                  label: (v) => v == null ? 'The usual' : '${fmtNum(toUnit(v, u))} ${unitLabel(u)}',
                  selected: {step},
                  onTap: (v) => set(() => step = v),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                  height: 52,
                  child: FilledButton(
                      onPressed: () {
                        if (setsCtl.text.trim() != setsText(it.specs)) {
                          try {
                            parseSets(setsCtl.text);
                          } on FormatException catch (fe) {
                            set(() => setsErr = fe.message);
                            return;
                          }
                        }
                        Navigator.pop(c, 'save');
                      },
                      child: const Text('Save'))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (e != null) OutlinedButton.icon(onPressed: () => Navigator.pop(c, 'info'), icon: const Icon(Icons.info_outline), label: const Text('How to do it')),
                if (!simple) OutlinedButton.icon(onPressed: () => Navigator.pop(c, 'rule'), icon: const Icon(Icons.trending_up), label: const Text('Lift rule')),
                if (e != null) OutlinedButton.icon(onPressed: () => Navigator.pop(c, 'swap'), icon: const Icon(Icons.swap_horiz), label: const Text('Swap in the plan')),
                if (it.group == null && i + 1 < items.length) OutlinedButton.icon(onPressed: () => Navigator.pop(c, 'super'), icon: const Icon(Icons.link), label: const Text('Superset with the next')),
                if (it.group != null) OutlinedButton.icon(onPressed: () => Navigator.pop(c, 'unsuper'), icon: const Icon(Icons.link_off), label: const Text('Out of the superset')),
                OutlinedButton.icon(onPressed: () => Navigator.pop(c, 'remove'), icon: const Icon(Icons.delete_outline, color: C.gold), label: const Text('Remove', style: TextStyle(color: C.gold))),
              ]),
            ]),
          ),
        );
      }),
    );
    if (res == null || !mounted) return;
    switch (res) {
      case 'rule':
        final k = liftKey(it);
        await ruleSheet(context, s, k, s.plan?.program?.rules[k] ?? ruleFor(s.plan?.program, it) ?? LiftRule(kind: scheme == 'linear' ? 'linear' : 'double'));
      case 'save':
        final written = setsCtl.text.trim();
        if (written != setsText(it.specs)) {
          final n = PlanItem.of(it.exerciseId, parseSets(written), rest: rest, tier: it.tier, tmOf: it.tmOf, bump: it.bump, group: it.group);
          await _save(plan.updateItem(di, i, n));
        } else {
          await _save(plan.updateItem(di, i, it.copyWith(sets: sets, repLow: lo, repHigh: hi, restSec: rest, style: style)));
        }
        if (scheme != (s.exScheme[it.exerciseId] ?? 'double')) await s.setScheme(it.exerciseId, scheme);
        if (step != s.exStep[it.exerciseId]) await s.setExStep(it.exerciseId, step);
        if (mounted) setState(() {});
      case 'remove':
        await _save(plan.removeItem(di, i));
      case 'super':
        await _save(_withItems(plan, supersetWithNext(items, i)));
      case 'unsuper':
        await _save(_withItems(plan, ungroup(items, i)));
      case 'info':
        if (e != null) await exerciseInfo(context, s, e);
      case 'swap':
        if (e == null) return;
        final r = await swapSheet(context, s, e, exclude: {for (final x in items) x.exerciseId});
        if (r != null) await _save(plan.updateItem(di, i, it.copyWith(exerciseId: r.$1.id)));
    }
  }
}
