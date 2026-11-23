import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/programs.dart';
import '../domain/units.dart';
import '../domain/volume.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Progress → Muscles (F225, F228, F230-F232): weekly sets per muscle against its range, the
/// trend over a time range, a balance chart, and how rested each muscle is.
class MusclesScreen extends StatefulWidget {
  final AppState s;
  const MusclesScreen({super.key, required this.s});
  @override
  State<MusclesScreen> createState() => _MusclesScreenState();
}

const _ranges = [(4, '4 weeks'), (13, '3 months'), (26, '6 months'), (52, '1 year')];

Color volumeColor(VolumeStatus v) => switch (v) { VolumeStatus.under => C.sky, VolumeStatus.on => C.green, _ => C.gold };

class _MusclesScreenState extends State<MusclesScreen> {
  int weeks = 4;
  String? open;
  late Future<List<SetLog>> _log = _fetch();

  Future<List<SetLog>> _fetch() => widget.s.repo.setsSince(DateTime.now().subtract(Duration(days: 14 * weeks + 1)));

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: const Text('Muscles')),
      body: FutureBuilder<List<SetLog>>(
        future: _log,
        builder: (c, snap) {
          if (snap.data == null) return const Center(child: CircularProgressIndicator());
          final now = DateTime.now();
          final w = weeklyMuscles(snap.data!, s.lib, now, weeks * 2);
          final rec = recovery(snap.data!, s.lib, now);
          double avg(List<double> l) => l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length;
          // the balance chart averages over the weeks since the first workout, not empty weeks before it (P3-2)
          final first = snap.data!.where((x) => x.counts && x.at != null).map((x) => x.at!).fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
          final since = first == null ? weeks : (now.difference(first).inDays ~/ 7 + 1).clamp(1, weeks);
          double avgSince(List<double> l) => avg(l.sublist(l.length - since));
          final cur = {for (final m in volumeMuscles) m: w.sets[m]!.sublist(weeks)};
          final prev = {for (final m in volumeMuscles) m: w.sets[m]!.sublist(0, weeks)};
          return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: [
            Pills<int>(
              values: [for (final r in _ranges) r.$1],
              label: (v) => _ranges.firstWhere((r) => r.$1 == v).$2,
              selected: {weeks},
              onTap: (v) => setState(() {
                weeks = v;
                _log = _fetch();
              }),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Balance, last ${_ranges.firstWhere((r) => r.$1 == weeks).$2}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Dim('Average sets a week. The ring is the top of each muscle\'s range.', size: 12),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 260,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: RadarPainter([
                        for (final m in volumeMuscles.take(10)) (muscleName(m), avgSince(cur[m]!) / math.max(1, muscleTarget(m, s.profile).hi)),
                      ], paintLabel(context)),
                    ),
                  ),
                ]),
              ),
            ),
            for (final m in volumeMuscles) _muscle(m, cur[m]!, prev[m]!, w.kg[m]!.sublist(weeks), rec[m]!, now),
            const SizedBox(height: 6),
            const Dim(
                'How it counts: an exercise\'s main muscle gets a full set, the helpers half a set (a bench press is 1 for chest, ½ for triceps and shoulders). '
                'Warm-ups and drop sets do not count. Ranges follow your goal and experience; a muscle you marked for more work aims higher.',
                size: 12),
          ]);
        },
      ),
    );
  }

  Widget _muscle(String m, List<double> cur, List<double> prev, List<double> kg, MuscleRecovery r, DateTime now) {
    final s = widget.s;
    final t = muscleTarget(m, s.profile);
    final thisWeek = cur.last;
    final st = statusOf(m, thisWeek, s.profile);
    final a = cur.reduce((x, y) => x + y) / cur.length, b = prev.reduce((x, y) => x + y) / prev.length;
    final isOpen = open == m;
    return Card(
      child: InkWell(
        onTap: () => setState(() => open = isOpen ? null : m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(muscleName(m), style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(volumeWord[st]!, style: TextStyle(color: volumeColor(st), fontSize: 12.5)),
              Icon(isOpen ? Icons.expand_less : Icons.expand_more, size: 18, color: C.dim),
            ]),
            const SizedBox(height: 2),
            Dim('Last 7 days ${volumeText(thisWeek, t)} sets · ${r.pct}% recovered · ${agoText(r.last, now)}', size: 12),
            const SizedBox(height: 6),
            SizedBox(height: 8, child: CustomPaint(size: Size.infinite, painter: RangeBar(thisWeek, t, volumeColor(st)))),
            if (isOpen) ...[
              const SizedBox(height: 10),
              SizedBox(height: 90, child: CustomPaint(size: Size.infinite, painter: WeekBars(cur, t))),
              const SizedBox(height: 6),
              Dim('Average ${fmtSets(a)} sets a week; ${fmtSets(b)} in the ${cur.length} weeks before${b > 0 ? ' (${a >= b ? '+' : ''}${((a - b) / b * 100).round()}%)' : ''}.', size: 12),
              Dim('Lifted for it: about ${fmtNum(toUnit(kg.reduce((x, y) => x + y) / kg.length, s.unit))} ${unitLabel(s.unit)} a week (weight × reps, helpers half).', size: 12),
              Dim('Least that still grows ${landmarks[m]?.mev ?? 0} · good range ${t.lo}-${t.hi} · most you can recover from about ${t.mrv} sets a week.', size: 12),
              Dim('Rested again about ${recoveryHours(m)} hours after a hard session.', size: 12),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A bar with the muscle's range marked and this week's sets filled.
class RangeBar extends CustomPainter {
  final double v;
  final Landmarks t;
  final Color c;
  RangeBar(this.v, this.t, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final top = math.max(t.mrv.toDouble(), v) * 1.05;
    double x(double n) => size.width * (n / top).clamp(0, 1);
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = C.card2);
    canvas.drawRect(Rect.fromLTRB(x(t.lo.toDouble()), 0, x(t.hi.toDouble()), size.height), Paint()..color = C.grid);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(0, 1, math.max(x(v), 2), size.height - 1), r), Paint()..color = c);
  }

  @override
  bool shouldRepaint(RangeBar o) => o.v != v || o.c != c;
}

/// Weekly sets as bars, the range shaded behind.
class WeekBars extends CustomPainter {
  final List<double> v;
  final Landmarks t;
  WeekBars(this.v, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.isEmpty) return;
    final top = [t.hi.toDouble(), ...v].reduce(math.max) * 1.1;
    double y(double n) => size.height - size.height * (n / top);
    canvas.drawRect(Rect.fromLTRB(0, y(t.hi.toDouble()), size.width, y(t.lo.toDouble())), Paint()..color = C.card2);
    final w = size.width / v.length;
    for (var i = 0; i < v.length; i++) {
      final c = v[i] + 0.01 < t.lo ? C.sky : (v[i] <= t.hi + 0.01 ? C.green : C.gold);
      canvas.drawRect(Rect.fromLTRB(i * w + w * 0.15, y(v[i]), (i + 1) * w - w * 0.15, size.height), Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(WeekBars o) => o.v != v;
}

/// A spider chart (F231): each axis one muscle, 1.0 = the top of its range.
class RadarPainter extends CustomPainter {
  final List<(String, double)> v;
  final TextStyle label;
  RadarPainter(this.v, this.label);

  @override
  void paint(Canvas canvas, Size size) {
    final n = v.length;
    if (n < 3) return;
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 26;
    Offset at(int i, double f) {
      final a = -math.pi / 2 + 2 * math.pi * i / n;
      return c + Offset(math.cos(a), math.sin(a)) * r * f;
    }

    final grid = Paint()
      ..color = C.grid
      ..style = PaintingStyle.stroke;
    for (final f in const [0.5, 1.0]) {
      canvas.drawPath(Path()..addPolygon([for (var i = 0; i < n; i++) at(i, f)], true), grid..strokeWidth = f == 1 ? 1.6 : 0.8);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(c, at(i, 1), grid..strokeWidth = 0.6);
    }
    final pts = [for (var i = 0; i < n; i++) at(i, v[i].$2.clamp(0.0, 1.4))];
    canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = C.teal.withValues(alpha: 0.25));
    canvas.drawPath(
        Path()..addPolygon(pts, true),
        Paint()
          ..color = C.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    for (var i = 0; i < n; i++) {
      final tp = TextPainter(text: TextSpan(text: v[i].$1, style: label), textDirection: TextDirection.ltr)..layout();
      final p = at(i, 1.14);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(RadarPainter o) => true;
}

/// "This plan's week" (F226, F227): days, minutes per day and sets per muscle against the ranges,
/// shown before starting a plan and on the Plan tab. [onFit] adds a "fit the sets" button.
class PlanWeekCard extends StatelessWidget {
  final AppState s;
  final Plan plan;
  final bool folded;
  final VoidCallback? onFit;
  const PlanWeekCard({super.key, required this.s, required this.plan, this.folded = false, this.onFit});

  @override
  Widget build(BuildContext context) {
    final tpl = plan.program == null ? null : templateById(plan.program!.id);
    final perWeek = plan.weeksPerCycle > 1 ? plan.daysPerWeek : (tpl?.days ?? s.profile?.days ?? plan.days.length);
    final w = planWeekSets(plan, s.lib, perWeek: perWeek);
    final days = plan.weeksPerCycle > 1 ? plan.days.take(plan.daysPerWeek).toList() : plan.days;
    final st = {for (final m in priorityMuscles) m: statusOf(m, w[m] ?? 0, s.profile)};
    final off = st.values.where((v) => v == VolumeStatus.under || v == VolumeStatus.tooMuch).length;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Dim('$perWeek days a week · about ${days.map((d) => dayMinutes(d, s.lib)).join(', ')} min a day', size: 12.5),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final m in priorityMuscles)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(8), border: Border.all(color: volumeColor(st[m]!).withValues(alpha: 0.6))),
            child: Text('${muscleName(m)} ${volumeText(w[m] ?? 0, muscleTarget(m, s.profile))}', style: TextStyle(fontSize: 12, color: volumeColor(st[m]!))),
          ),
      ]),
      const SizedBox(height: 6),
      const Dim('Sets a week per muscle against its range (helpers count half). Blue = under, green = on target, gold = above.', size: 12),
      if (onFit != null && off > 0 && plan.program == null && plan.weeksPerCycle <= 1) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: onFit, icon: const Icon(Icons.tune, size: 18), label: const Text('Fit sets to the ranges'))),
    ]);
    if (!folded) return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("This plan's week", style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 4), body])));
    return Card(
      child: ExpansionTile(
        key: const ValueKey('planweek'),
        shape: const Border(),
        title: const Text("This plan's week", style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Dim(off == 0 ? 'Every muscle in its range' : '$off muscle${off == 1 ? '' : 's'} outside the range', size: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        children: [body],
      ),
    );
  }
}
