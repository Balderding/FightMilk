import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../domain/body.dart';
import '../domain/exercise.dart';
import '../domain/plates.dart';
import '../domain/reports.dart';
import '../domain/stats.dart';
import '../domain/units.dart';
import 'app_state.dart';
import 'history_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'share_card.dart';

/// Progress, batch 17 (F252-F274): the lift chart with its choices, the tables, the records,
/// the records board and the dashboard tiles.

/// Everything the chart needs for one lift, loaded once.
class _Data {
  final List<SetLog> sets; // this lift (or all its kinds)
  final List<SetLog> other; // the lift it is compared with
  final Map<String, int> minutes; // workout length per session
  final List<(DateTime, double)> body;
  final Map<String, Session> sessions;
  const _Data(this.sets, this.other, this.minutes, this.body, this.sessions);
}

class LiftChart extends StatefulWidget {
  final AppState s;
  final Exercise e;
  const LiftChart({super.key, required this.s, required this.e});
  @override
  State<LiftChart> createState() => _LiftChartState();
}

class _LiftChartState extends State<LiftChart> {
  ChartKind kind = ChartKind.e1rm;
  int months = 6, reps = 5;
  bool trend = false, proj = false, variants = false, showBody = false;
  Exercise? compare;
  double v0 = 0, v1 = 1; // the visible part of the time span (zoom and scroll, F257)
  double _s0 = 0, _s1 = 1, _fx = 0;
  Pt? sel;
  late Future<_Data> _data = _load();

  AppState get s => widget.s;
  Exercise get e => widget.e;

  Future<_Data> _load() async {
    final ids = variants ? [for (final x in variantsOf(e, s.lib)) x.id] : [e.id];
    final sets = <SetLog>[for (final id in ids) ...await s.repo.setsOf(id)]..sort((a, b) => (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0)));
    final other = compare == null ? const <SetLog>[] : await s.repo.setsOf(compare!.id);
    final hist = await s.repo.history();
    final minutes = {for (final h in hist) if (h.finished != null) h.id: h.finished!.difference(h.started).inMinutes};
    final body = [for (final b in await s.repo.bodyLog()) if (b.$3 != null) (b.$2, b.$3!)];
    return _Data(sets, other, minutes, body, {for (final h in hist) h.id: h});
  }

  void _reload() => setState(() {
        sel = null;
        _data = _load();
      });

  List<ChartKind> get _kinds => [
        for (final k in ChartKind.values)
          if (!(e.bodyweight && (k == ChartKind.perBody || k == ChartKind.weightAt || k == ChartKind.bestSetVolume)) && !(e.timed && k == ChartKind.weightAt)) k
      ];

  @override
  Widget build(BuildContext context) {
    final u = s.unit;
    final label = paintLabel(context);
    return FutureBuilder<_Data>(
      future: _data,
      builder: (c, snap) {
        final d = snap.data;
        if (d == null) return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
        final now = DateTime.now();
        final all = seriesOf(d.sets, kind, reps: reps, bodyweight: e.bodyweight, minutes: d.minutes, body: d.body);
        final pts = inRange(all, months, now);
        final cmp = compare == null ? const <Pt>[] : inRange(seriesOf(d.other, kind, reps: reps, bodyweight: compare!.bodyweight, minutes: d.minutes, body: d.body), months, now);
        final bodyPts = showBody ? [for (final b in d.body) if (months == 0 || !b.$1.isBefore(DateTime(now.year, now.month - months, now.day))) Pt(b.$1, b.$2, '')] : const <Pt>[];
        final pr = proj ? projection(pts) : null;
        double show(double v) => isWeightKind(kind) ? toUnit(v, u) : v;
        final vs = variantsOf(e, s.lib);
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!s.settings.simple)
              SizedBox(
                height: 36,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final k in _kinds)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                          label: Text(chartLabel[k]!, style: TextStyle(fontSize: 12, color: k == kind ? C.onTeal : C.text)),
                          selected: k == kind,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() {
                                kind = k;
                                sel = null;
                              })),
                    ),
                  // F322: the est. 1-rep max chart as a picture (never body weight)
                  IconButton(
                    tooltip: 'Share as a picture',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.share, size: 18),
                    onPressed: () => shareCardSheet(context, chartCard(e, [for (final p in seriesOf(d.sets, ChartKind.e1rm)) Pt(p.at, toUnit(p.v, u), '')], u)),
                  ),
                ]),
              ),
              if (kind == ChartKind.weightAt)
                Wrap(spacing: 4, children: [
                  for (final r in const [1, 3, 5, 8, 10, 12])
                    ChoiceChip(label: Text('$r'), selected: reps == r, showCheckmark: false, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => reps = r)),
                ]),
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 2, children: [
                for (final (m, l) in chartRanges)
                  ChoiceChip(
                      label: Text(l, style: const TextStyle(fontSize: 12)),
                      selected: months == m,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() {
                            months = m;
                            v0 = 0;
                            v1 = 1;
                            sel = null;
                          })),
              ]),
              const SizedBox(height: 4),
              if (!s.settings.simple)
              Wrap(spacing: 4, runSpacing: 2, children: [
                FilterChip(label: const Text('Trend', style: TextStyle(fontSize: 12)), selected: trend, visualDensity: VisualDensity.compact, onSelected: (v) => setState(() => trend = v)),
                FilterChip(label: const Text('Where it is heading', style: TextStyle(fontSize: 12)), selected: proj, visualDensity: VisualDensity.compact, onSelected: (v) => setState(() => proj = v)),
                if (vs.length > 1)
                  FilterChip(
                      label: Text('All ${coreWord(e)} kinds (${vs.length})', style: const TextStyle(fontSize: 12)),
                      selected: variants,
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) {
                        variants = v;
                        _reload();
                      }),
                FilterChip(
                    label: Text(compare == null ? 'Compare…' : 'vs ${compare!.name}', style: const TextStyle(fontSize: 12)),
                    selected: compare != null,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _pickCompare()),
                if (d.body.isNotEmpty) FilterChip(label: const Text('Body weight', style: TextStyle(fontSize: 12)), selected: showBody, visualDensity: VisualDensity.compact, onSelected: (v) => setState(() => showBody = v)),
              ]),
              const SizedBox(height: 8),
              if (pts.isEmpty)
                const SizedBox(height: 180, child: Center(child: Dim('Nothing to show in this range for this chart.')))
              else
                LayoutBuilder(
                  builder: (c, box) => GestureDetector(
                    onScaleStart: (g) {
                      _s0 = v0;
                      _s1 = v1;
                      _fx = g.localFocalPoint.dx / box.maxWidth;
                    },
                    onScaleUpdate: (g) => setState(() {
                      // pinch to zoom around the fingers, drag to scroll (F257)
                      final span = ((_s1 - _s0) / g.horizontalScale).clamp(0.05, 1.0);
                      final focus = _s0 + _fx * (_s1 - _s0);
                      final shift = -(g.focalPointDelta.dx / box.maxWidth) * span;
                      var a = focus - _fx * span + shift, b = a + span;
                      if (a < 0) (a, b) = (0, span);
                      if (b > 1) (a, b) = (1 - span, 1);
                      _s0 = a;
                      _s1 = b;
                      _fx = g.localFocalPoint.dx / box.maxWidth;
                      v0 = a;
                      v1 = b;
                    }),
                    onTapUp: (g) => setState(() => sel = ChartPainter.nearest(pts, g.localPosition, Size(box.maxWidth, 200), v0, v1, pr == null ? null : (pr.$2, pr.$3))),
                    child: CustomPaint(
                      size: Size(box.maxWidth, 200),
                      painter: ChartPainter(
                        pts: [for (final p in pts) Pt(p.at, show(p.v), p.session)],
                        avg: trend ? movingAverage(pts).map(show).toList() : null,
                        proj: pr == null ? null : (pr.$2, show(pr.$3)),
                        cmp: [for (final p in cmp) Pt(p.at, show(p.v), p.session)],
                        body: [for (final p in bodyPts) Pt(p.at, toUnit(p.v, u), '')],
                        sel: sel,
                        v0: v0,
                        v1: v1,
                        smooth: s.settings.chartSmooth,
                        dots: s.settings.chartDots,
                        label: label,
                        lines: _levelLine(all, show),
                      ),
                    ),
                  ),
                ),
              if (v0 > 0 || v1 < 1) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() {
                    v0 = 0;
                    v1 = 1;
                  }), child: const Text('Show all'))),
              Wrap(spacing: 10, children: [
                Dim('${chartLabel[kind]}${kind == ChartKind.weightAt ? ' ($reps+)' : ''} · ${kindUnit(kind, u)}', size: 12),
                if (compare != null) Text('— ${compare!.name}', style: const TextStyle(color: C.gold, fontSize: 12)),
                if (showBody) const Text('— body weight', style: TextStyle(color: C.sky, fontSize: 12)),
                if (pr != null) Dim('Heading: ${pr.$1 >= 0 ? '+' : ''}${fmtNum(show(pr.$1))} ${kindUnit(kind, u)} a week', size: 12),
              ]),
              if (sel != null) _point(d, sel!),
              if (pts.length > 1 && sel == null) const Dim('Tap a point for that workout. Pinch or drag to zoom into a long history.', size: 12),
            ]),
          ),
        );
      },
    );
  }

  /// The next strength level as a dashed line on the 1-rep max chart (F307).
  List<(double, String)> _levelLine(List<Pt> all, double Function(double) show) {
    final bw = s.bodyKgNow;
    if (s.settings.simple || kind != ChartKind.e1rm || variants || bw == null || !levelLifts.contains(e.id) || all.isEmpty) return const [];
    // the best of the last 90 days, the same as the Body screen's levels (review 4, P3-N20)
    final since = DateTime.now().subtract(const Duration(days: 90));
    final recent = [for (final p in all) if (p.at.isAfter(since)) p.v];
    if (recent.isEmpty) return const [];
    final best = recent.reduce((a, b) => a > b ? a : b);
    final (lvl, next, _) = strengthLevelOf(e.id, best, bw, female: s.female);
    if (next == null) return const [];
    return [(show(next), 'Next: ${levelNames5[lvl + 1]}')];
  }

  /// A tapped point (F255): that workout's sets; tap again (Open) for the whole workout.
  Widget _point(_Data d, Pt p) {
    final sets = [for (final x in d.sets) if (x.sessionId == p.session && x.counts) x];
    final ses = d.sessions[p.session];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fmtDate(p.at), style: const TextStyle(fontWeight: FontWeight.w600)),
            Dim(sets.map((x) => '${s.lib.byId(x.exerciseId)?.id == e.id ? '' : '${s.lib.byId(x.exerciseId)?.name}: '}${fmtWeight(x.kg, s.unit)}×${x.reps}').join(', '), size: 12),
          ]),
        ),
        if (ses != null) TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SessionDetail(s: s, session: ses))), child: const Text('Open')),
      ]),
    );
  }

  Future<void> _pickCompare() async {
    if (compare != null) {
      compare = null;
      return _reload();
    }
    final ids = await s.repo.loggedExercises();
    if (!mounted) return;
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
          const Text('Compare with', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          for (final id in ids)
            if (id != e.id && s.lib.byId(id) != null) ListTile(title: Text(s.lib.byId(id)!.name), onTap: () => Navigator.pop(c, id)),
        ]),
      ),
    );
    if (pick == null) return;
    compare = s.lib.byId(pick);
    _reload();
  }
}

/// The chart (F254): points by date, month labels under it, values at the side, an optional trend,
/// projection (dotted), a compared lift (gold) and body weight (sky, in the bottom band).
class ChartPainter extends CustomPainter {
  final List<Pt> pts, cmp, body;
  final List<double>? avg;
  final (DateTime, double)? proj;
  final Pt? sel;
  final double v0, v1;
  final bool smooth, dots;
  final TextStyle label;
  /// Dashed level lines across the chart: a goal, or the next strength level (F299, F307).
  final List<(double, String)> lines;
  ChartPainter({required this.pts, this.avg, this.proj, this.cmp = const [], this.body = const [], this.sel, this.v0 = 0, this.v1 = 1, this.smooth = false, this.dots = true, required this.label, this.lines = const []});

  // room for the side values and the months at the largest label size (chartScaleMax)
  static const _left = 44.0, _bottom = 22.0;

  static (DateTime, DateTime) span(List<Pt> pts, (DateTime, double)? proj) {
    var a = pts.first.at, b = pts.last.at;
    if (proj != null && proj.$1.isAfter(b)) b = proj.$1;
    if (!b.isAfter(a)) b = a.add(const Duration(days: 1));
    return (a, b);
  }

  /// The workout nearest a tap (by time), or null when the tap is off the chart.
  static Pt? nearest(List<Pt> pts, Offset at, Size size, double v0, double v1, (DateTime, double)? proj) {
    if (pts.isEmpty || at.dx < _left) return null;
    final (a, b) = span(pts, proj);
    final total = b.difference(a).inMinutes.toDouble();
    final f = v0 + (at.dx - _left) / (size.width - _left) * (v1 - v0);
    final t = a.add(Duration(minutes: (f * total).round()));
    return pts.reduce((x, y) => (x.at.difference(t).inMinutes.abs() <= y.at.difference(t).inMinutes.abs()) ? x : y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;
    final (a, b) = span(pts, proj);
    final total = b.difference(a).inMinutes.toDouble();
    final w = size.width - _left, h = size.height - _bottom;
    final mainH = body.isEmpty ? h : h * 0.72;
    double xOf(DateTime t) => _left + ((t.difference(a).inMinutes / total) - v0) / (v1 - v0) * w;
    final vals = [...pts.map((p) => p.v), ...cmp.map((p) => p.v), ...?avg, if (proj != null) proj!.$2, for (final l in lines) l.$1];
    var lo = vals.reduce(math.min), hi = vals.reduce(math.max);
    final pad = (hi - lo) * 0.12 + (hi.abs() * 0.02) + 0.5;
    lo -= pad;
    hi += pad;
    // side values on round steps: 1, 2 or 5 times a power of ten (review 2, P3-N7)
    final step = niceStep((hi - lo) / 3);
    lo = (lo / step).floorToDouble() * step;
    hi = (hi / step).ceilToDouble() * step;
    double yOf(double v) => mainH * (1 - (v - lo) / (hi - lo));
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    // side values and grid
    final grid = Paint()..color = C.grid;
    for (var v = lo; v <= hi + step * 0.01; v += step) {
      final y = yOf(v);
      canvas.drawLine(Offset(_left, y), Offset(size.width, y), grid);
      final lh = textHeight(label);
      _text(canvas, fmtNum(v), Offset(0, (y - lh / 2).clamp(0, math.max(0, h - lh))), _left - 4);
    }
    // month labels along the bottom
    var m = DateTime(a.year, a.month + 1);
    final months = (b.difference(a).inDays / 30 / (v1 - v0)).ceil();
    final every = months <= 4 ? 1 : (months <= 9 ? 2 : (months <= 18 ? 3 : 6));
    var k = 0;
    while (!m.isAfter(b)) {
      if (k++ % every == 0) {
        final x = xOf(m);
        if (x >= _left && x <= size.width) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), grid..color = C.grid.withValues(alpha: 0.5));
          _text(canvas, '${_mon[m.month - 1]}${m.month == 1 ? ' ${m.year % 100}' : ''}', Offset(x + 2, h + 2), 60);
        }
      }
      m = DateTime(m.year, m.month + 1);
    }
    canvas.clipRect(Rect.fromLTWH(_left, 0, w, size.height));
    // body weight, in its own band at the bottom (F259)
    if (body.isNotEmpty) {
      final bl = body.map((p) => p.v).reduce(math.min) - 1, bh = body.map((p) => p.v).reduce(math.max) + 1;
      final top = mainH + 6;
      double by(double v) => top + (h - top) * (1 - (v - bl) / (bh - bl));
      _line(canvas, [for (final p in body) Offset(xOf(p.at), by(p.v))], C.sky, 1.5);
    }
    for (final (v, name) in lines) {
      final y = yOf(v);
      for (var x = _left; x < size.width; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 5, size.width), y), Paint()
          ..color = C.gold.withValues(alpha: 0.8)
          ..strokeWidth = 1.2);
      }
      _text(canvas, name, Offset(_left + 4, y - textHeight(label) - 1), 140);
    }
    if (cmp.isNotEmpty) _line(canvas, [for (final p in cmp) Offset(xOf(p.at), yOf(p.v))], C.gold, 2);
    final main = [for (final p in pts) Offset(xOf(p.at), yOf(p.v))];
    _line(canvas, main, C.teal, 2.4);
    if (avg != null) _line(canvas, [for (var i = 0; i < pts.length; i++) Offset(xOf(pts[i].at), yOf(avg![i]))], C.green.withValues(alpha: 0.8), 1.6);
    if (proj != null) {
      // dotted line from the last workout to where it is heading (F263)
      final p0 = main.last, p1 = Offset(xOf(proj!.$1), yOf(proj!.$2));
      final n = ((p1 - p0).distance / 6).floor();
      for (var i = 0; i < n; i += 2) {
        canvas.drawLine(Offset.lerp(p0, p1, i / n)!, Offset.lerp(p0, p1, (i + 1) / n)!, Paint()
          ..color = C.gold
          ..strokeWidth = 1.6);
      }
    }
    if (dots) {
      for (final o in main) {
        canvas.drawCircle(o, 3, Paint()..color = C.teal);
      }
    }
    if (sel != null) canvas.drawCircle(Offset(xOf(sel!.at), yOf(sel!.v)), 6, Paint()
      ..color = C.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    canvas.restore();
  }

  void _line(Canvas canvas, List<Offset> o, Color c, double w) {
    if (o.isEmpty) return;
    final p = Path()..moveTo(o.first.dx, o.first.dy);
    for (var i = 1; i < o.length; i++) {
      if (smooth) {
        final mx = (o[i - 1].dx + o[i].dx) / 2;
        p.cubicTo(mx, o[i - 1].dy, mx, o[i].dy, o[i].dx, o[i].dy); // smooth curves (F267)
      } else {
        p.lineTo(o[i].dx, o[i].dy);
      }
    }
    canvas.drawPath(p, Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w);
  }

  void _text(Canvas canvas, String t, Offset at, double maxW) {
    final tp = TextPainter(text: TextSpan(text: t, style: label), textDirection: TextDirection.ltr, maxLines: 1)..layout(maxWidth: maxW);
    tp.paint(canvas, at);
  }

  static const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  bool shouldRepaint(ChartPainter o) => true;
}

/// A round chart step near [rough]: 1, 2 or 5 times a power of ten.
double niceStep(double rough) {
  if (rough <= 0) return 1;
  final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final f = rough / mag;
  return (f < 1.5 ? 1 : (f < 3 ? 2 : (f < 7 ? 5 : 10))) * mag;
}

/// % of the current max, rounded to what the bar can be loaded with, and the rep-max grid (F260, F261).
class LiftTables extends StatelessWidget {
  final AppState s;
  final Exercise e;
  final List<SetLog> sets;
  const LiftTables({super.key, required this.s, required this.e, required this.sets});

  @override
  Widget build(BuildContext context) {
    final u = s.unit;
    final grid = repMaxGrid(sets);
    final max = grid.first.$3;
    if (max <= 0 || e.bodyweight || e.timed) return const SizedBox.shrink();
    final ps = s.plateSetup;
    final bar = barFor(e, barKg: ps.bar, smithKg: ps.smith);
    String w(double kg) => fmtWeight(roundToStep(kg, e.step, u), u);
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: const Text('Tables', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Dim('% of your est. 1-rep max (${w(max)} ${unitLabel(u)}), and your best at 1-12 reps', size: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Percent of max', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final (p, kg) in percentTable(max))
            Row(children: [
              SizedBox(width: 44, child: Text('$p%')),
              SizedBox(width: 70, child: Text('${w(kg)} ${unitLabel(u)}')),
              if (bar != null)
                Expanded(
                    child: Dim(plateLine(roundToStep(kg, e.step, u), bar, ps.plates, u), size: 12)),
            ]),
          const SizedBox(height: 10),
          const Text('Best weight for reps', style: TextStyle(fontWeight: FontWeight.w600)),
          const Dim('Done = the most you lifted for at least that many reps. Could do = from your best set.', size: 12),
          for (final (r, best, est) in grid)
            Row(children: [
              SizedBox(width: 44, child: Text('$r')),
              SizedBox(width: 90, child: Text(best == null ? '–' : '${fmtWeight(best, u)} ${unitLabel(u)}')),
              Dim('could do ~${w(est)}', size: 12),
            ]),
        ],
      ),
    );
  }
}

/// This lift's records, when each was set and what it beat, and the best this week / month / year
/// (F268, F270, F271, F273, F274).
class LiftRecords extends StatefulWidget {
  final AppState s;
  final Exercise e;
  final List<SetLog> sets;
  const LiftRecords({super.key, required this.s, required this.e, required this.sets});
  @override
  State<LiftRecords> createState() => _LiftRecordsState();
}

class _LiftRecordsState extends State<LiftRecords> {
  String window = 'all';

  @override
  Widget build(BuildContext context) {
    final s = widget.s, e = widget.e, u = s.unit;
    final hist = recordHistory(widget.sets, e);
    if (hist.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final cur = window == 'all' ? currentRecords(hist) : bestSince(widget.sets, e, windowStart(window, now));
    final kinds = recordKinds(e, widget.sets);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Records', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            // the window chips wrap when they do not fit (larger text, narrow phones; F364)
            Expanded(
              child: Wrap(alignment: WrapAlignment.end, spacing: 4, runSpacing: 4, children: [
                for (final (k, l) in const [('week', 'Week'), ('month', 'Month'), ('year', 'Year'), ('all', 'Ever')])
                  ChoiceChip(label: Text(l, style: const TextStyle(fontSize: 12)), selected: window == k, showCheckmark: false, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => window = k)),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          for (final k in kinds)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text(recordLabel[k]!)),
                Text(cur[k] == null ? '–' : recordText(cur[k]!, u, bodyweight: e.bodyweight), style: const TextStyle(color: C.gold, fontWeight: FontWeight.w600)),
                SizedBox(width: 84, child: Text(cur[k] == null ? '' : fmtDate(cur[k]!.at), textAlign: TextAlign.right, style: const TextStyle(color: C.dim, fontSize: 12))),
              ]),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            title: Text('Record history (${hist.where((r) => r.before != null).length} broken)', style: const TextStyle(fontSize: 13.5)),
            children: [
              for (final r in hist.reversed.take(40))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(width: 80, child: Dim(fmtDate(r.at), size: 12)),
                    Expanded(child: Text('${recordLabel[r.kind]}: ${recordText(r, u, bodyweight: e.bodyweight)}', style: const TextStyle(fontSize: 12.5))),
                    Dim(r.before == null ? 'first' : 'was ${recordText(Rec(r.kind, r.before!, r.at, '', set: r.beforeSet), u, bodyweight: e.bodyweight)}', size: 12),
                  ]),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}

/// Progress → Records: the top records of every lift on one screen (F272), this week, month,
/// year or ever (F271).
class RecordsScreen extends StatefulWidget {
  final AppState s;
  const RecordsScreen({super.key, required this.s});
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  String window = 'all';
  late final Future<List<(Exercise, List<SetLog>)>> _all = () async {
    final s = widget.s;
    return [
      for (final id in await s.repo.loggedExercises())
        if (s.lib.byId(id) != null) (s.lib.byId(id)!, await s.repo.setsOf(id))
    ];
  }();

  @override
  Widget build(BuildContext context) {
    final s = widget.s, u = s.unit;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Records')),
      body: FutureBuilder<List<(Exercise, List<SetLog>)>>(
        future: _all,
        builder: (c, snap) {
          final l = snap.data;
          if (l == null) return const Center(child: CircularProgressIndicator());
          final rows = <Widget>[];
          for (final (e, sets) in l) {
            final cur = window == 'all' ? currentRecords(recordHistory(sets, e)) : bestSince(sets, e, windowStart(window, now));
            final top = [for (final k in recordKinds(e, sets).take(3)) if (cur[k] != null) cur[k]!];
            if (top.isEmpty) continue;
            rows.add(Card(
              child: ListTile(
                title: Text(e.name),
                subtitle: Dim(top.map((r) => '${recordLabel[r.kind]} ${recordText(r, u, bodyweight: e.bodyweight)}').join(' · '), size: 12),
                trailing: Dim(fmtDate(top.map((r) => r.at).reduce((a, b) => a.isAfter(b) ? a : b)), size: 12),
                onLongPress: () => shareCardSheet(context, recordCard(e, top.reduce((a, b) => a.at.isAfter(b.at) ? a : b), u)),
              ),
            ));
          }
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
            const Padding(padding: EdgeInsets.only(bottom: 6), child: Dim('Long-press a lift to share its newest record as a picture.', size: 12)),
            Wrap(spacing: 6, children: [
              for (final (k, lab) in const [('week', 'This week'), ('month', 'This month'), ('year', 'This year'), ('all', 'Ever')])
                ChoiceChip(label: Text(lab), selected: window == k, showCheckmark: false, onSelected: (_) => setState(() => window = k)),
            ]),
            const SizedBox(height: 8),
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Center(child: Dim('No records in this time yet.'))),
            ...rows,
          ]);
        },
      ),
    );
  }
}

/// Your own tiles at the top of Progress (F264).
class DashboardCard extends StatelessWidget {
  final AppState s;
  const DashboardCard({super.key, required this.s});

  Future<Map<String, String>> _values() async {
    final now = DateTime.now();
    final week = await s.repo.setsSince(windowStart('week', now));
    final u = s.unit;
    final out = <String, String>{};
    for (final t in s.dash) {
      switch (t) {
        case 'week_workouts':
          out[t] = '${{for (final x in week) x.sessionId}.length}';
        case 'week_volume':
          out[t] = '${fmtNum(toUnit(week.where((x) => x.counts).fold<double>(0, (a, x) => a + x.kg * x.reps), u).roundToDouble())} ${unitLabel(u)}';
        case 'week_sets':
          out[t] = '${week.where((x) => x.counts).length}';
        case 'streak':
          out[t] = '${weekStreak(await s.workouts(), now, perWeek: s.perWeekGoal)}';
        case 'records_month':
          final from = windowStart('month', now);
          final days = <String>{}; // days with any new record, however many lifts and kinds
          for (final id in await s.repo.loggedExercises()) {
            final e = s.lib.byId(id);
            if (e == null) continue;
            days.addAll({for (final r in recordHistory(await s.repo.setsOf(id), e)) if (r.before != null && !r.at.isBefore(from)) '${r.at.year}-${r.at.month}-${r.at.day}'});
          }
          out[t] = '${days.length}';
        case 'body':
          final b = await s.repo.bodyLog();
          final kg = b.map((x) => x.$3).whereType<double>().firstOrNull;
          out[t] = kg == null ? '–' : '${fmtWeight(kg, u)} ${unitLabel(u)}';
        case 'top_lift':
          final ids = await s.repo.loggedExercises();
          final e = ids.map(s.lib.byId).whereType<Exercise>().where((x) => !x.bodyweight && !x.timed).firstOrNull;
          if (e == null) {
            out[t] = '–';
          } else {
            final r = currentRecords(recordHistory(await s.repo.setsOf(e.id), e))[RecordKind.e1rm];
            out[t] = r == null ? '–' : '${e.name.length <= 16 ? e.name : '${e.name.substring(0, 15)}…'} ${fmtWeight(r.value, u)}'; // a name you can read (P3-N8)
          }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) => CachedFuture<Map<String, String>>(
        cacheKey: '${s.historyVersion}|${s.dash.join(',')}|${s.unit}',
        load: _values,
        builder: (c, snap) {
          final v = snap.data ?? const {};
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Text('At a glance', style: TextStyle(fontWeight: FontWeight.w600))),
                  IconButton(tooltip: 'Choose tiles', icon: const Icon(Icons.tune, size: 20), onPressed: () => _edit(context)),
                ]),
                Wrap(spacing: 16, runSpacing: 8, children: [
                  for (final t in s.dash)
                    SizedBox(
                      width: 140,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(v[t] ?? '…', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: C.teal)),
                        Dim(dashTiles[t]!, size: 12),
                      ]),
                    ),
                ]),
              ]),
            ),
          );
        },
      );

  Future<void> _edit(BuildContext context) async {
    final sel = [...s.dash];
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
            const Text('Tiles at the top of Progress', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            for (final e in dashTiles.entries)
              CheckboxListTile(value: sel.contains(e.key), title: Text(e.value), onChanged: (v) => set(() => v == true ? sel.add(e.key) : sel.remove(e.key))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Done')),
          ]),
        ),
      ),
    );
    if (ok == true) await s.setDash(sel);
  }
}
