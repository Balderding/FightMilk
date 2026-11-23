import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/units.dart';
import '../domain/volume.dart';
import 'app_state.dart';
import 'body_screen.dart';
import 'calculators_screen.dart';
import 'coaching_screen.dart';
import 'history_screen.dart';
import 'lift_chart.dart';
import 'reports_screen.dart';
import 'muscles_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Per-lift progress and weekly totals, all worked out on the phone.
class ProgressScreen extends StatefulWidget {
  final AppState s;
  const ProgressScreen({super.key, required this.s});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  String? pick;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return SafeArea(
      child: FutureBuilder<List<String>>(
        future: s.repo.loggedExercises(),
        builder: (c, snap) {
          final ids = (snap.data ?? const []).where((id) => s.lib.byId(id) != null).toList();
          if (snap.data == null) return const Center(child: CircularProgressIndicator());
          if (ids.isEmpty) {
            return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
              Row(children: [const Expanded(child: Text('Progress', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))), TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CalculatorsScreen(s: s))), icon: const Icon(Icons.calculate_outlined), label: const Text('Calculators'))]),
              const SizedBox(height: 30),
              const Center(child: Dim('Finish a workout and your lifts show up here.', size: 15)),
              const SizedBox(height: 12),
              Center(child: OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MusclesScreen(s: s))), icon: const Icon(Icons.accessibility_new), label: const Text('Muscles and recovery'))),
              const SizedBox(height: 18),
              BodyCard(s: s),
            ]);
          }
          final cur = ids.contains(pick) ? pick! : ids.first;
          return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
            Row(children: [
              const Expanded(child: Text('Progress', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
              if (!s.settings.simple) IconButton(tooltip: 'Goals', icon: const Icon(Icons.flag_outlined, color: C.teal), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GoalsScreen(s: s)))),
              IconButton(tooltip: 'Records', icon: const Icon(Icons.emoji_events_outlined, color: C.gold), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordsScreen(s: s)))),
              TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CalculatorsScreen(s: s))), icon: const Icon(Icons.calculate_outlined), label: const Text('Calculators')),
            ]),
            if (!s.settings.simple) DashboardCard(s: s),
            const SizedBox(height: 4),
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final id in ids)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s.lib.byId(id)!.name, style: TextStyle(color: id == cur ? C.onTeal : C.text)),
                      selected: id == cur,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => pick = id),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            _Lift(key: ValueKey('lift$cur'), s: s, e: s.lib.byId(cur)!),
            StallCard(key: ValueKey('stall$cur'), s: s, e: s.lib.byId(cur)!),
            _Week(s: s),
            if (!s.settings.simple) WeeklyReviewCard(s: s, shown: cur),
            BodyCard(s: s),
          ]);
        },
      ),
    );
  }
}

class _Lift extends StatelessWidget {
  final AppState s;
  final Exercise e;
  const _Lift({super.key, required this.s, required this.e});

  @override
  Widget build(BuildContext context) => Column(children: [
        LiftChart(key: ValueKey('chart${e.id}'), s: s, e: e),
        CachedFuture<List<SetLog>>(
          cacheKey: '${s.historyVersion}|${e.id}',
          load: () => s.repo.setsOf(e.id),
          builder: (c, snap) {
            final sets = snap.data ?? const <SetLog>[];
            if (sets.isEmpty) return const SizedBox.shrink();
            return Column(children: [LiftRecords(s: s, e: e, sets: sets), if (!s.settings.simple) LiftTables(s: s, e: e, sets: sets)]);
          },
        ),
      ]);
}

class _Week extends StatelessWidget {
  final AppState s;
  const _Week({required this.s});

  @override
  Widget build(BuildContext context) {
    final since = DateTime.now().subtract(const Duration(days: 7));
    return FutureBuilder<List<SetLog>>(
      future: s.repo.setsSince(since),
      builder: (c, snap) {
        final sets = snap.data ?? const [];
        final workouts = sets.map((x) => x.sessionId).toSet().length;
        final vol = sets.fold<double>(0, (a, x) => a + volumeOf(x, s.lib.byId(x.exerciseId)));
        // main muscles a full set, helpers half (F224)
        final muscles = <String, double>{};
        for (final x in sets.where((x) => x.counts)) {
          final e = s.lib.byId(x.exerciseId);
          if (e == null) continue;
          for (final m in setShare(e).entries) {
            muscles[m.key] = (muscles[m.key] ?? 0) + m.value;
          }
        }
        final ms = muscles.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('Last 7 days', style: TextStyle(fontWeight: FontWeight.w600))),
                TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MusclesScreen(s: s))), icon: const Icon(Icons.accessibility_new, size: 18), label: const Text('Muscles')),
              ]),
              const SizedBox(height: 4),
              Dim('$workouts workouts · ${fmtNum(toUnit(vol, s.unit))} ${unitLabel(s.unit)} lifted', size: 14),
              const SizedBox(height: 6),
              Dim(ms.isEmpty ? 'No sets this week yet.' : 'Sets per muscle: ${ms.map((m) => '${m.key.replaceAll('_', ' ')} ${fmtSets(m.value)}').join(', ')}'),
            ]),
          ),
        );
      },
    );
  }
}

class BodyCard extends StatefulWidget {
  final AppState s;
  const BodyCard({super.key, required this.s});
  @override
  State<BodyCard> createState() => _BodyCardState();
}

class _BodyCardState extends State<BodyCard> {
  Future<void> _add() async {
    if (await showWeighIn(context, widget.s) && mounted) setState(() {}); // one sheet, one check (review 4, P2-3)
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final u = s.unit;
    return FutureBuilder<List<(String, DateTime, double?, double?)>>(
      future: s.repo.bodyLog(),
      builder: (c, snap) {
        final l = [for (final x in snap.data ?? const <(String, DateTime, double?, double?)>[]) if (x.$3 != null) x];
        final week = l.where((x) => x.$2.isAfter(DateTime.now().subtract(const Duration(days: 7)))).toList();
        final avg = week.isEmpty ? null : week.map((x) => x.$3!).reduce((a, b) => a + b) / week.length;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('Body weight', style: TextStyle(fontWeight: FontWeight.w600))),
                FilledButton.tonalIcon(onPressed: _add, icon: const Icon(Icons.monitor_weight_outlined), label: const Text('Weigh in')),
              ]),
              if (l.isEmpty) const Dim('No weigh-ins yet. Stays on this phone.', size: 12),
              if (l.isNotEmpty) ...[
                Text('${fmtWeight(l.first.$3!, u)} ${unitLabel(u)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                // a body weight goal (F295)
                for (final g in s.aims.where((g) => g.kind == 'body'))
                  Dim('Goal ${fmtWeight(g.target, u)} ${unitLabel(u)}: ${(l.first.$3! - g.target).abs() < 0.05 ? 'reached' : '${fmtWeight((l.first.$3! - g.target).abs(), u)} ${unitLabel(u)} to go'}${g.by == null ? '' : ' by ${g.by!.year}-${g.by!.month}-${g.by!.day}'}', size: 12),
                if (avg != null && week.length > 1) Dim('7-day average ${fmtWeight(avg, u)} ${unitLabel(u)} (${week.length} weigh-ins)', size: 12),
                const SizedBox(height: 4),
                for (final x in l.take(5))
                  Row(children: [
                    Expanded(child: Dim('${x.$2.year}-${x.$2.month.toString().padLeft(2, '0')}-${x.$2.day.toString().padLeft(2, '0')}', size: 13)),
                    Text('${fmtWeight(x.$3!, u)} ${unitLabel(u)}'),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16, color: C.dim),
                      onPressed: () async {
                        await s.repo.deleteBody(x.$1);
                        if (mounted) setState(() {});
                      },
                    ),
                  ]),
              ],
              // batch 19: chart, body fat, tape, photos, strength scores
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => BodyScreen(s: s)));
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.accessibility_new, size: 18),
                  label: const Text('Body and strength'),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
