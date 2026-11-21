import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/units.dart';
import 'app_state.dart';
import 'calculators_screen.dart';
import 'history_screen.dart';
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
              const SizedBox(height: 30),
              BodyCard(s: s),
            ]);
          }
          final cur = ids.contains(pick) ? pick! : ids.first;
          return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
            Row(children: [const Expanded(child: Text('Progress', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))), TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CalculatorsScreen(s: s))), icon: const Icon(Icons.calculate_outlined), label: const Text('Calculators'))]),
            const SizedBox(height: 8),
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
            _Lift(s: s, e: s.lib.byId(cur)!),
            _Week(s: s),
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
  const _Lift({required this.s, required this.e});

  @override
  Widget build(BuildContext context) {
    final u = s.unit;
    return FutureBuilder<List<SetLog>>(
      future: s.repo.setsOf(e.id),
      builder: (c, snap) {
        final sets = [for (final x in snap.data ?? const <SetLog>[]) if (x.counts) x]; // no warm-ups or drop sets in records
        if (sets.isEmpty) return const SizedBox(height: 160);
        // best estimated 1-rep max per workout
        final per = <String, (DateTime, double)>{};
        for (final x in sets) {
          final v = e.bodyweight ? x.reps.toDouble() : e1rm(x.kg, x.reps);
          final cur = per[x.sessionId];
          if (cur == null || v > cur.$2) per[x.sessionId] = (x.at ?? DateTime.now(), v);
        }
        final pts = per.values.toList()..sort((a, b) => a.$1.compareTo(b.$1));
        final heaviest = sets.reduce((a, b) => b.kg > a.kg || (b.kg == a.kg && b.reps > a.reps) ? b : a);
        final best = sets.reduce((a, b) => e1rm(b.kg, b.reps) > e1rm(a.kg, a.reps) ? b : a);
        final mostReps = sets.where((x) => x.kg == heaviest.kg).map((x) => x.reps).reduce(math.max);
        final rising = pts.length > 1 && pts.last.$2 >= pts.map((p) => p.$2).reduce(math.max);
        return Column(children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Dim(e.bodyweight ? 'Best reps per workout' : 'Best set, estimated 1-rep max (${unitLabel(u)})'),
                const SizedBox(height: 8),
                SizedBox(height: 150, width: double.infinity, child: CustomPaint(painter: _Chart([for (final p in pts) e.bodyweight ? p.$2 : toUnit(p.$2, u)]))),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Dim(fmtDate(pts.first.$1), size: 11), Dim(fmtDate(pts.last.$1), size: 11)]),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Personal bests', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _row('Heaviest', '${fmtWeight(heaviest.kg, u)} × ${heaviest.reps}'),
                _row('Most reps at ${fmtWeight(heaviest.kg, u)}', '$mostReps'),
                if (!e.bodyweight) _row('Est. 1-rep max', '${fmtWeight(e1rm(best.kg, best.reps), u)} ${unitLabel(u)}${rising ? ' ↑' : ''}', gold: true),
                _row('Workouts', '${pts.length}'),
              ]),
            ),
          ),
        ]);
      },
    );
  }

  Widget _row(String a, String b, {bool gold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(a), Text(b, style: TextStyle(color: gold ? C.gold : C.text, fontWeight: FontWeight.w600))]),
      );
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
        final muscles = <String, int>{};
        for (final x in sets.where((x) => x.counts)) {
          for (final m in s.lib.byId(x.exerciseId)?.primary ?? const <String>[]) {
            muscles[m] = (muscles[m] ?? 0) + 1;
          }
        }
        final ms = muscles.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Last 7 days', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Dim('$workouts workouts · ${fmtNum(toUnit(vol, s.unit))} ${unitLabel(s.unit)} lifted', size: 14),
              const SizedBox(height: 6),
              Dim(ms.isEmpty ? 'No sets this week yet.' : 'Sets per muscle: ${ms.map((m) => '${m.key.replaceAll('_', ' ')} ${m.value}').join(', ')}'),
            ]),
          ),
        );
      },
    );
  }
}

class _Chart extends CustomPainter {
  final List<double> v;
  _Chart(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.isEmpty) return;
    final lo = v.reduce(math.min), hi = v.reduce(math.max);
    final pad = (hi - lo) * .15 + 1;
    final a = lo - pad, b = hi + pad;
    final grid = Paint()..color = C.line;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    Offset pt(int i) => Offset(v.length == 1 ? size.width / 2 : size.width * i / (v.length - 1), size.height * (1 - (v[i] - a) / (b - a)));
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < v.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(path, Paint()
      ..color = C.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < v.length; i++) {
      canvas.drawCircle(pt(i), i == v.length - 1 ? 4.5 : 2.5, Paint()..color = i == v.length - 1 ? C.gold : C.teal);
    }
    final tp = TextPainter(text: TextSpan(text: fmtNum(hi), style: const TextStyle(color: C.dim, fontSize: 10)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, const Offset(0, 0));
  }

  @override
  bool shouldRepaint(_Chart old) => old.v != v;
}

/// Body weight: weigh in with one tap; the last few and the 7-day average.
class BodyCard extends StatefulWidget {
  final AppState s;
  const BodyCard({super.key, required this.s});
  @override
  State<BodyCard> createState() => _BodyCardState();
}

class _BodyCardState extends State<BodyCard> {
  Future<void> _add() async {
    final s = widget.s;
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.card,
        title: const Text('Weigh in'),
        content: TextField(enableIMEPersonalizedLearning: false, controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(suffixText: unitLabel(s.unit))),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save'))],
      ),
    );
    final n = double.tryParse((v ?? '').replaceAll(',', '.'));
    if (n == null || n <= 0) return;
    await s.repo.logBody(fromUnit(n, s.unit));
    if (mounted) setState(() {});
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
            ]),
          ),
        );
      },
    );
  }
}
