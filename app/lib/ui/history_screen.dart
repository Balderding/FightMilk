import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../domain/exercise.dart';
import '../domain/units.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

String fmtDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${w[d.weekday - 1]} ${m[d.month - 1]} ${d.day}';
}

/// Weight moved: dumbbell/kettlebell weights count twice (one in each hand).
double volumeOf(SetLog s, Exercise? e) => s.kg * s.reps * ((e?.equipment == Equipment.dumbbell || e?.equipment == Equipment.kettlebell) ? 2 : 1);

class HistoryScreen extends StatefulWidget {
  final AppState s;
  const HistoryScreen({super.key, required this.s});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return SafeArea(
      child: FutureBuilder<List<(Session, List<SetLog>)>>(
        future: () async {
          final h = await s.repo.history();
          return [for (final x in h) (x, await s.repo.setsFor(x.id))];
        }(),
        builder: (c, snap) {
          final l = snap.data;
          if (l == null) return const Center(child: CircularProgressIndicator());
          if (l.isEmpty) return const Center(child: Dim('No workouts yet. Finished workouts show up here.', size: 15));
          return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
            const Text('History', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            for (final (ses, sets) in l)
              Card(
                child: ListTile(
                  title: Text('${fmtDate(ses.started)} · ${ses.day.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Dim('${sets.length} sets · ${fmtNum(toUnit(sets.fold<double>(0, (a, x) => a + volumeOf(x, s.lib.byId(x.exerciseId))), s.unit))} ${unitLabel(s.unit)} lifted'
                      '${ses.finished != null ? ' · ${ses.finished!.difference(ses.started).inMinutes} min' : ''}'),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => SessionDetail(s: s, session: ses)));
                    setState(() {});
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class SessionDetail extends StatefulWidget {
  final AppState s;
  final Session session;
  const SessionDetail({super.key, required this.s, required this.session});
  @override
  State<SessionDetail> createState() => _SessionDetailState();
}

class _SessionDetailState extends State<SessionDetail> {
  AppState get s => widget.s;

  Future<void> _edit(SetLog x) async {
    final e = s.lib.byId(x.exerciseId);
    final step = e == null ? 2.5 : stepKg(e.step, s.unit);
    var k = x.kg, r = x.reps;
    final res = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(e?.name ?? x.exerciseId, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              BigStepper(value: fmtWeight(k, s.unit), unit: unitLabel(s.unit), onMinus: () => set(() => k = (k - step).clamp(0, 2000)), onPlus: () => set(() => k += step)),
              const SizedBox(height: 8),
              BigStepper(value: '$r', unit: 'reps', onMinus: () => set(() => r = (r - 1).clamp(0, 500)), onPlus: () => set(() => r++)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Delete set'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save'))),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (res == 'save') await s.repo.updateSet(x.id, k, r);
    if (res == 'delete') await s.repo.deleteSet(x.id);
    if (res != null) await s.historyChanged([x.exerciseId]);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ses = widget.session;
    return Scaffold(
      appBar: AppBar(
        title: Text('${fmtDate(ses.started)} · ${ses.day.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete workout',
            onPressed: () async {
              if (await confirm(context, 'Delete this workout?', 'Its sets are removed from history and progress.', yes: 'Delete')) {
                final ids = (await s.repo.setsFor(ses.id)).map((x) => x.exerciseId).toList();
                await s.repo.deleteSession(ses.id);
                await s.historyChanged(ids);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<SetLog>>(
        future: s.repo.setsFor(ses.id),
        builder: (c, snap) {
          final sets = snap.data ?? const [];
          final groups = <String, List<SetLog>>{};
          for (final x in sets) {
            (groups[x.exerciseId] ??= []).add(x);
          }
          return ListView(padding: const EdgeInsets.all(14), children: [
            if (ses.note.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(ses.note))),
            for (final g in groups.entries)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.lib.byId(g.key)?.name ?? g.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final x in g.value) ActionChip(label: Text('${fmtWeight(x.kg, s.unit)} × ${x.reps}'), onPressed: () => _edit(x)),
                    ]),
                  ]),
                ),
              ),
            const Dim('Tap a set to change or delete it.'),
          ]);
        },
      ),
    );
  }
}
