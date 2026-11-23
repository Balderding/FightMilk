import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../domain/exercise.dart';
import '../domain/reports.dart';
import '../domain/stats.dart';
import '../domain/units.dart';
import '../domain/volume.dart';
import 'app_state.dart';
import 'history_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'share_card.dart';

/// Batch 18 screens: Reports (History → Reports), Calendar (History → Calendar), Goals
/// (Progress → Goals) and the week strip on Today.

/// Workouts and sets, loaded once per history change.
class _All {
  final List<Workout> ws;
  final List<SetLog> sets;
  final List<(DateTime, double)> body;
  final List<Session> sessions;
  const _All(this.ws, this.sets, this.body, this.sessions);
}

Future<_All> _loadAll(AppState s) async => _All(await s.workouts(), await s.allSets(), await s.bodySeries(), await s.repo.history(limit: 100000));

Widget _loader(AppState s, Widget Function(_All a) child) => CachedFuture<_All>(
      cacheKey: s.historyVersion,
      load: () => _loadAll(s),
      builder: (c, snap) => snap.data == null ? const Center(child: CircularProgressIndicator()) : child(snap.data!),
    );

String _hours(int minutes) => minutes < 60 ? '$minutes min' : '${(minutes / 60).toStringAsFixed(minutes < 600 ? 1 : 0)} h';

// ---------- Today: the week strip, the weekly goal ring and the streak (F291-F293) ----------

class WeekStripCard extends StatelessWidget {
  final AppState s;
  const WeekStripCard({super.key, required this.s});

  @override
  Widget build(BuildContext context) => CachedFuture<List<Workout>>(
        cacheKey: s.historyVersion,
        load: s.workouts,
        builder: (c, snap) {
          final ws = snap.data;
          // nothing to show before the first workout (and the first screen stays short)
          if (ws == null || ws.isEmpty) return const SizedBox.shrink();
          final now = DateTime.now();
          final strip = weekStrip(ws, now);
          final done = strip.where((x) => x).length;
          final goal = s.perWeekGoal;
          final streak = weekStreak(ws, now, perWeek: goal);
          final planned = s.profile?.weekdays ?? const <int>[];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              // "3 of 4 this week" ring (F293)
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(value: (done / goal).clamp(0, 1).toDouble(), strokeWidth: 4, backgroundColor: C.card2, color: done >= goal ? C.green : C.teal),
                  Text('$done/$goal', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Column(children: [
                          Text(const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i], style: TextStyle(fontSize: 12, color: i == now.weekday - 1 ? C.teal : C.dim)),
                          const SizedBox(height: 2),
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: strip[i] ? C.green : C.card2,
                              border: planned.contains(i + 1) && !strip[i] ? Border.all(color: C.teal, width: 1.5) : null,
                            ),
                            child: strip[i] ? const Icon(Icons.check, size: 12, color: C.onTeal) : null,
                          ),
                        ]),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Dim('$done of $goal training days this week${streak > 0 && !s.settings.simple ? ' · $streak week${streak == 1 ? '' : 's'} in a row on plan' : ''}', size: 12),
                ]),
              ),
            ]),
          );
        },
      );
}

// ---------- History → Reports (F275-F287, F297, F298) ----------

class ReportsScreen extends StatelessWidget {
  final AppState s;
  const ReportsScreen({super.key, required this.s});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Reports'),
            bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'Week'), Tab(text: 'Month'), Tab(text: 'Year'), Tab(text: 'Dates'), Tab(text: 'All time')]),
          ),
          body: _loader(
              s,
              (a) => TabBarView(children: [
                    _WeekTab(s: s, a: a),
                    _MonthTab(s: s, a: a),
                    _YearTab(s: s, a: a),
                    _DatesTab(s: s, a: a),
                    _AllTimeTab(s: s, a: a),
                  ])),
        ),
      );
}

/// The numbers of one report, with the change against another one.
Widget _reportCard(AppState s, String title, Report r, {Report? vs, String vsLabel = '', Report? vs2, String vs2Label = ''}) {
  final u = s.unit;
  String ch(num a, num b) => changeText(a, b);
  Widget row(String k, String v, [String c = '', String c2 = '']) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (vs != null) SizedBox(width: 64, child: Text(c, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c.startsWith('+') || c == 'new' ? C.green : C.dim))),
          if (vs2 != null) SizedBox(width: 64, child: Text(c2, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c2.startsWith('+') || c2 == 'new' ? C.green : C.dim))),
        ]),
      );
  final ms = r.muscles.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (vs != null) SizedBox(width: 64, child: Dim(vsLabel, size: 12)),
          if (vs2 != null) SizedBox(width: 64, child: Dim(vs2Label, size: 12)),
        ]),
        const SizedBox(height: 4),
        row('Workouts', '${r.workouts}', vs == null ? '' : ch(r.workouts, vs.workouts), vs2 == null ? '' : ch(r.workouts, vs2.workouts)),
        row('Sets', '${r.sets}', vs == null ? '' : ch(r.sets, vs.sets), vs2 == null ? '' : ch(r.sets, vs2.sets)),
        row('Lifted', bigWeight(r.volume, u), vs == null ? '' : ch(r.volume, vs.volume), vs2 == null ? '' : ch(r.volume, vs2.volume)),
        row('Time', _hours(r.minutes), vs == null ? '' : ch(r.minutes, vs.minutes), vs2 == null ? '' : ch(r.minutes, vs2.minutes)),
        row('Records', '${r.records}', vs == null ? '' : ch(r.records, vs.records), vs2 == null ? '' : ch(r.records, vs2.records)),
        if (r.bodyChange != null) row('Body weight', '${r.bodyChange! >= 0 ? '+' : ''}${fmtWeight(r.bodyChange!, u)} ${unitLabel(u)}'),
        if (ms.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Dim('Sets per muscle: ${ms.take(8).map((m) => '${muscleName(m.key).toLowerCase()} ${fmtSets(m.value)}').join(', ')}', size: 12)),
        if (r.mostDone.isNotEmpty) Dim('Most done: ${r.mostDone.take(3).map((x) => '${x.$1.name} (${x.$2} set${x.$2 == 1 ? '' : 's'})').join(', ')}', size: 12),
        if (r.mostImproved.isNotEmpty) Dim('Most improved: ${r.mostImproved.take(3).map((x) => '${x.$1.name} +${fmtWeight(x.$2, u)} ${unitLabel(u)}').join(', ')}', size: 12),
      ]),
    ),
  );
}

class _WeekTab extends StatelessWidget {
  final AppState s;
  final _All a;
  const _WeekTab({required this.s, required this.a});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final (w, last, ago) = weekReports(now, a.ws, a.sets, s.lib);
    final pw = perWeek(a.ws, now);
    final (acute, usual, loadWeeks) = trainingLoad(a.sets, now);
    final kept = planKept(a.ws, a.sets, now, s.perWeekGoal);
    return ListView(padding: const EdgeInsets.all(12), children: [
      _reportCard(s, now.weekday == 7 ? 'This week' : 'This week so far', w, vs: last, vsLabel: 'last wk', vs2: ago, vs2Label: '4 wk ago'),
      Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Dim(now.weekday == 7 ? 'Compared with those whole weeks.' : 'Compared with the same days of those weeks: Monday to ${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][now.weekday - 1]}, whole days.', size: 12)),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Workouts per week', style: TextStyle(fontWeight: FontWeight.w700)),
            Dim('Bars: workouts a week (gold line: your ${s.perWeekGoal}); under each: average minutes.', size: 12),
            const SizedBox(height: 6),
            SizedBox(height: 96 + textHeight(paintLabel(context)), child: CustomPaint(size: Size.infinite, painter: _Bars([for (final x in pw) x.$2.toDouble()], goal: s.perWeekGoal.toDouble(), labels: [for (final x in pw) x.$3 == 0 ? '' : '${x.$3}'], label: paintLabel(context)))),
          ]),
        ),
      ),
      Card(
        child: ListTile(
          title: const Text('Training load'),
          subtitle: Dim(
              loadWeeks < 3 || usual <= 0
                  ? 'Not enough weeks yet to compare.'
                  : 'Last 7 days ${(acute / usual).toStringAsFixed(1)}× your usual (sets weighted by how hard they felt). ${acute / usual > 1.5 ? 'A heavy week: sleep and eat well.' : (acute / usual < 0.6 ? 'A light week.' : 'About your usual.')}',
              size: 12),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Plan kept', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final (wk, done, planned, sd, sp) in kept.reversed.take(6))
              Row(children: [
                SizedBox(width: 70, child: Dim(fmtDate(wk).split(' ').skip(1).join(' '), size: 12)),
                Expanded(child: Text('$done of $planned workouts${addDays(wk, 7).isAfter(now) ? ' so far' : ''}')),
                Dim(sp == 0 ? '' : '$sd of $sp sets', size: 12),
              ]),
          ]),
        ),
      ),
    ]);
  }
}

class _MonthTab extends StatefulWidget {
  final AppState s;
  final _All a;
  const _MonthTab({required this.s, required this.a});
  @override
  State<_MonthTab> createState() => _MonthTabState();
}

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

class _MonthTabState extends State<_MonthTab> {
  DateTime? m;
  @override
  Widget build(BuildContext context) {
    final s = widget.s, a = widget.a;
    final months = monthsWithWorkouts(a.ws);
    if (months.isEmpty) return const Center(child: Dim('No workouts yet.'));
    final cur = m ?? months.first;
    final r = reportFor(cur, DateTime(cur.year, cur.month + 1), a.ws, a.sets, s.lib, body: a.body);
    final prev = reportFor(DateTime(cur.year, cur.month - 1), cur, a.ws, a.sets, s.lib);
    return ListView(padding: const EdgeInsets.all(12), children: [
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final x in months)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text('${_monthNames[x.month - 1].substring(0, 3)} ${x.year}'), selected: x == cur, showCheckmark: false, onSelected: (_) => setState(() => m = x)),
            ),
        ]),
      ),
      _reportCard(s, '${_monthNames[cur.month - 1]} ${cur.year}', r, vs: prev, vsLabel: 'vs month before'),
      if (r.mostImproved.isNotEmpty) Card(child: ListTile(leading: const Icon(Icons.emoji_events_outlined, color: C.gold), title: const Text('Lift of the month'), subtitle: Dim('${r.mostImproved.first.$1.name}: +${fmtWeight(r.mostImproved.first.$2, s.unit)} ${unitLabel(s.unit)} est. 1-rep max', size: 12))),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _recap(context, s, '${_monthNames[cur.month - 1]} ${cur.year}', r), icon: const Icon(Icons.auto_stories_outlined), label: const Text('Recap pages'))),
    ]);
  }
}

class _YearTab extends StatelessWidget {
  final AppState s;
  final _All a;
  const _YearTab({required this.s, required this.a});
  @override
  Widget build(BuildContext context) {
    final years = {for (final x in a.ws) x.start.year}.toList()..sort((x, y) => y.compareTo(x));
    if (years.isEmpty) return const Center(child: Dim('No workouts yet.'));
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final y in years)
        () {
          final w = yearWrap(y, a.ws, a.sets, s.lib, perWeek: s.perWeekGoal);
          final r = reportFor(DateTime(y), DateTime(y + 1), a.ws, a.sets, s.lib, body: a.body);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$y wrapped', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${w.workouts} workouts · ${_hours(w.minutes)} · ${bigWeight(w.volume, s.unit)}'),
                if (funWeight(w.volume).isNotEmpty) Dim('That is ${funWeight(w.volume)}.', size: 12),
                Dim('${w.records} records · longest run: ${w.longestStreak} weeks on plan', size: 12),
                if (w.bestMonth != null) Dim('Best month: ${_monthNames[w.bestMonth!.month - 1]}', size: 12),
                if (w.favourite != null) Dim('Favourite lift: ${w.favourite!.name}', size: 12),
                Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _recap(context, s, '$y', r), icon: const Icon(Icons.auto_stories_outlined), label: const Text('Recap pages'))),
              ]),
            ),
          );
        }(),
    ]);
  }
}

class _DatesTab extends StatefulWidget {
  final AppState s;
  final _All a;
  const _DatesTab({required this.s, required this.a});
  @override
  State<_DatesTab> createState() => _DatesTabState();
}

class _DatesTabState extends State<_DatesTab> {
  late DateTimeRange range = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 28)), end: DateTime.now());
  @override
  Widget build(BuildContext context) {
    final s = widget.s, a = widget.a;
    final r = reportFor(dayOf(range.start), addDays(dayOf(range.end), 1), a.ws, a.sets, s.lib, body: a.body);
    return ListView(padding: const EdgeInsets.all(12), children: [
      OutlinedButton.icon(
        onPressed: () async {
          final p = await showDateRangePicker(context: context, firstDate: DateTime(2015), lastDate: DateTime.now(), initialDateRange: range);
          if (p != null) setState(() => range = p);
        },
        icon: const Icon(Icons.date_range),
        label: Text('${fmtDate(range.start)} – ${fmtDate(range.end)}'),
      ),
      const SizedBox(height: 8),
      _reportCard(s, 'These dates', r),
    ]);
  }
}

class _AllTimeTab extends StatelessWidget {
  final AppState s;
  final _All a;
  const _AllTimeTab({required this.s, required this.a});
  @override
  Widget build(BuildContext context) {
    final u = s.unit;
    final r = reportFor(DateTime(2000), DateTime.now().add(const Duration(days: 1)), a.ws, a.sets, s.lib);
    final (h, m, l) = repSplit(a.sets);
    final run = runningVolume(a.ws, a.sets);
    final grid = whenGrid(a.ws);
    final (level, into, need) = levelOf(a.ws.length);
    final badges = badgesEarned(a.ws, a.sets, s.lib, perWeek: s.perWeekGoal);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('All time', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text('${r.workouts} workouts · ${r.reps} reps · ${_hours(r.minutes)}'),
            Text('${bigWeight(r.volume, u)} lifted${funWeight(r.volume).isEmpty ? '' : ': ${funWeight(r.volume)}'}'),
          ]),
        ),
      ),
      if (run.length > 1)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Running total lifted', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SizedBox(height: 90, child: CustomPaint(size: Size.infinite, painter: _Line([for (final x in run) toUnit(x.$2, u)]))),
            ]),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Heavy, medium, light', style: TextStyle(fontWeight: FontWeight.w700)),
            Dim('Sets of 1-5 reps ${(h * 100).round()}% · 6-12 reps ${(m * 100).round()}% · 13+ reps ${(l * 100).round()}%', size: 12.5),
            const SizedBox(height: 10),
            const Text('When you train', style: TextStyle(fontWeight: FontWeight.w700)),
            const Dim('Weekday by hour; darker = more workouts.', size: 12),
            const SizedBox(height: 4),
            SizedBox(height: _When.heightFor(paintLabel(context)), child: CustomPaint(size: Size.infinite, painter: _When(grid, paintLabel(context)))),
          ]),
        ),
      ),
      if (s.settings.badges && !s.settings.simple)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Level $level · ${levelName(level)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: need == 0 ? 0 : into / need, backgroundColor: C.card2, color: C.gold),
              Dim('${need - into} workout${need - into == 1 ? '' : 's'} to level ${level + 1}', size: 12),
              const SizedBox(height: 10),
              Text('Badges (${badges.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final b in badges) Tooltip(message: b.how, child: Chip(avatar: const Icon(Icons.military_tech, size: 16, color: C.gold), label: Text(b.name, style: const TextStyle(fontSize: 12)))),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

/// Recap as swipe pages (F287): one card a page.
Future<void> _recap(BuildContext context, AppState s, String title, Report r) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) {
        final u = s.unit;
        final pages = <(String, String, String)>[
          (title, '${r.workouts} workouts', '${_hours(r.minutes)} of training'),
          ('Lifted', bigWeight(r.volume, u), funWeight(r.volume).isEmpty ? '${r.sets} sets, ${r.reps} reps' : 'That is ${funWeight(r.volume)}.'),
          ('Records', '${r.records}', r.records == 0 ? 'Next time.' : 'new bests'),
          if (r.mostDone.isNotEmpty) ('Most done', r.mostDone.first.$1.name, '${r.mostDone.first.$2} set${r.mostDone.first.$2 == 1 ? '' : 's'}'),
          if (r.mostImproved.isNotEmpty) ('Most improved', r.mostImproved.first.$1.name, '+${fmtWeight(r.mostImproved.first.$2, u)} ${unitLabel(u)} est. 1-rep max'),
        ];
        return Scaffold(
          appBar: AppBar(title: Text('$title recap'), actions: [
            Builder(
              builder: (c) => IconButton(
                tooltip: 'Share as a picture',
                icon: const Icon(Icons.share),
                onPressed: () => shareCardSheet(c, recapCard(title, r, u), withBody: r.bodyChange == null ? null : recapCard(title, r, u, body: true)),
              ),
            ),
          ]),
          body: PageView(children: [
            for (final (a, b, c) in pages)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  color: C.card2,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(a, style: const TextStyle(fontSize: 18, color: C.dim)),
                      const SizedBox(height: 12),
                      Text(b, textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: C.teal)),
                      const SizedBox(height: 12),
                      Text(c, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
                    ]),
                  ),
                ),
              ),
          ]),
        );
      }),
    );

class _Bars extends CustomPainter {
  final List<double> v;
  final double goal;
  final List<String> labels;
  final TextStyle label;
  _Bars(this.v, {required this.goal, this.labels = const [], this.label = const TextStyle(color: C.dim, fontSize: minText)});
  @override
  void paint(Canvas canvas, Size size) {
    if (v.isEmpty) return;
    final top = math.max(goal, v.reduce(math.max)) + 1;
    final h = size.height - textHeight(label) - 2; // the labels' own height under the bars
    final w = size.width / v.length;
    final gy = h * (1 - goal / top);
    canvas.drawLine(Offset(0, gy), Offset(size.width, gy), Paint()..color = C.gold.withValues(alpha: 0.6));
    for (var i = 0; i < v.length; i++) {
      final y = h * (1 - v[i] / top);
      canvas.drawRect(Rect.fromLTRB(i * w + w * 0.18, y, (i + 1) * w - w * 0.18, h), Paint()..color = v[i] >= goal ? C.green : C.teal);
      if (i < labels.length && labels[i].isNotEmpty) {
        final tp = TextPainter(text: TextSpan(text: labels[i], style: label), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(i * w + (w - tp.width) / 2, h + 2));
      }
    }
  }

  @override
  bool shouldRepaint(_Bars o) => true;
}

class _Line extends CustomPainter {
  final List<double> v;
  _Line(this.v);
  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final hi = v.last <= 0 ? 1.0 : v.last;
    final p = Path();
    for (var i = 0; i < v.length; i++) {
      final o = Offset(size.width * i / (v.length - 1), size.height * (1 - v[i] / hi));
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(p, Paint()
      ..color = C.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_Line o) => true;
}

class _When extends CustomPainter {
  final List<List<int>> g;
  final TextStyle label;
  _When(this.g, this.label);

  /// A row is as tall as one label; the hours go under the last row.
  static double rowFor(TextStyle l) => math.max(12.0, textHeight(l));
  static double heightFor(TextStyle l) => 7 * rowFor(l) + textHeight(l) + 2;

  @override
  void paint(Canvas canvas, Size size) {
    final mx = g.expand((r) => r).fold(0, math.max);
    final left = (TextPainter(text: TextSpan(text: 'M', style: label), textDirection: TextDirection.ltr)..layout()).width + 4;
    final cw = (size.width - left) / 24, ch = rowFor(label);
    for (var d = 0; d < 7; d++) {
      final tp = TextPainter(text: TextSpan(text: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d], style: label), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(0, d * ch));
      for (var h = 0; h < 24; h++) {
        final v = mx == 0 ? 0.0 : g[d][h] / mx;
        canvas.drawRect(Rect.fromLTWH(left + h * cw + 0.5, d * ch + 0.5, cw - 1, ch - 1), Paint()..color = v == 0 ? C.card2 : C.teal.withValues(alpha: 0.25 + 0.75 * v));
      }
    }
    for (final h in const [6, 12, 18]) {
      final tp = TextPainter(text: TextSpan(text: '$h', style: label), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(left + h * cw, 7 * ch + 1));
    }
  }

  @override
  bool shouldRepaint(_When o) => true;
}

// ---------- History → Calendar (F288-F290) ----------

class CalendarScreen extends StatefulWidget {
  final AppState s;
  const CalendarScreen({super.key, required this.s});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String? filterEx;
  double filterKg = 0;
  int filterReps = 1;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: _loader(s, (a) {
        final vol = dayVolumes(a.ws, a.sets);
        final match = filterEx == null ? null : daysMatching(a.sets, filterEx!, kg: filterKg, reps: filterReps);
        final now = DateTime.now();
        final planned = s.profile?.weekdays ?? const <int>[];
        final first = DateTime(month.year, month.month);
        final days = DateTime(month.year, month.month + 1, 0).day;
        final lead = first.weekday - 1;
        final ids = {for (final x in a.sets) x.exerciseId};
        return ListView(padding: const EdgeInsets.all(12), children: [
          Row(children: [
            IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text('${_monthNames[month.month - 1]} ${month.year}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right)),
          ]),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S']) Center(child: Dim(d, size: 12)),
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (var d = 1; d <= days; d++)
                () {
                  final day = DateTime(month.year, month.month, d);
                  final trained = vol.containsKey(day);
                  final hit = match?.contains(day) ?? false;
                  final ahead = day.isAfter(dayOf(now)) && planned.contains(day.weekday);
                  return InkWell(
                    onTap: trained ? () => _day(context, a, day) : null,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hit ? C.gold : (trained ? C.teal.withValues(alpha: match == null ? 0.85 : 0.35) : null),
                        border: ahead ? Border.all(color: C.teal, width: 1.5) : (day == dayOf(now) ? Border.all(color: C.dim) : null),
                      ),
                      child: Center(child: Text('$d', style: TextStyle(color: trained ? C.onTeal : C.text, fontWeight: trained ? FontWeight.w700 : FontWeight.normal))),
                    ),
                  );
                }(),
            ],
          ),
          const Dim('Filled: you trained (tap for the workout). Ringed: a planned day ahead.', size: 12),
          const SizedBox(height: 12),
          // the calendar filter (F290)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Days I did…', style: TextStyle(fontWeight: FontWeight.w700)),
                DropdownButton<String?>(
                  isExpanded: true,
                  value: filterEx,
                  hint: const Text('Pick a lift'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('No filter')),
                    for (final id in ids)
                      if (s.lib.byId(id) != null) DropdownMenuItem<String?>(value: id, child: Text(s.lib.byId(id)!.name)),
                  ],
                  onChanged: (v) => setState(() => filterEx = v),
                ),
                if (filterEx != null)
                  Row(children: [
                    Expanded(
                        child: TextField(
                            enableIMEPersonalizedLearning: false,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: 'At least', suffixText: unitLabel(s.unit), isDense: true),
                            onChanged: (v) => setState(() => filterKg = fromUnit(double.tryParse(v.replaceAll(',', '.')) ?? 0, s.unit)))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            enableIMEPersonalizedLearning: false,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'for reps', isDense: true),
                            onChanged: (v) => setState(() => filterReps = int.tryParse(v) ?? 1))),
                  ]),
                if (match != null) Padding(padding: const EdgeInsets.only(top: 6), child: Dim('${match.length} day${match.length == 1 ? '' : 's'} (gold).', size: 12)),
              ]),
            ),
          ),
          // the year heatmap (F289)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${month.year}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const Dim('Each square a day; darker = more lifted.', size: 12),
                const SizedBox(height: 6),
                SizedBox(height: 7 * 7.0 + 2, child: CustomPaint(size: Size.infinite, painter: _Year(month.year, vol))),
              ]),
            ),
          ),
        ]);
      }),
    );
  }

  Future<void> _day(BuildContext context, _All a, DateTime day) async {
    final ses = [for (final x in a.sessions) if (dayOf(x.started) == day) x];
    if (ses.length == 1) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SessionDetail(s: widget.s, session: ses.single)));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.card,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
          for (final x in ses)
            ListTile(
              title: Text(x.day.name),
              subtitle: Dim(fmtDate(x.started), size: 12),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => SessionDetail(s: widget.s, session: x)));
              },
            ),
        ]),
      ),
    );
  }
}

class _Year extends CustomPainter {
  final int year;
  final Map<DateTime, double> vol;
  _Year(this.year, this.vol);
  @override
  void paint(Canvas canvas, Size size) {
    final first = DateTime(year);
    final mx = vol.entries.where((e) => e.key.year == year).fold<double>(0, (a, e) => math.max(a, e.value));
    final cell = math.min(7.0, size.width / 54);
    for (var d = first; d.year == year; d = addDays(d, 1)) {
      final col = (d.difference(first).inDays + first.weekday - 1) ~/ 7, row = d.weekday - 1;
      final v = vol[d];
      final c = v == null ? C.card2 : C.teal.withValues(alpha: mx <= 0 ? 0.6 : (0.3 + 0.7 * v / mx));
      canvas.drawRect(Rect.fromLTWH(col * cell, row * cell, cell - 1, cell - 1), Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_Year o) => true;
}

// ---------- Progress → Goals (F294-F296) ----------

const aimKinds = {'lift': 'A lift (est. 1-rep max)', 'reps': 'Reps on a lift', 'body': 'Body weight', 'volume': 'Tonnes this month'};

class GoalsScreen extends StatefulWidget {
  final AppState s;
  const GoalsScreen({super.key, required this.s});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('New goal')),
      body: ListenableBuilder(
        listenable: s,
        builder: (c, _) => s.aims.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Dim('No goals yet. "Bench 100 kg by June", "10 pull-ups", "80 kg body weight" or "20 tonnes a month".', size: 14)))
            : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [for (final a in s.aims) _AimCard(s: s, a: a)]),
      ),
    );
  }

  Future<void> _add() async {
    final s = widget.s;
    var kind = 'lift';
    String? ex;
    DateTime? by;
    final value = TextEditingController();
    final ids = [for (final id in await s.repo.loggedExercises()) if (s.lib.byId(id) != null) id];
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('New goal', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in aimKinds.entries) ChoiceChip(label: Text(k.value), selected: kind == k.key, showCheckmark: false, onSelected: (_) => set(() => kind = k.key)),
              ]),
              if (kind == 'lift' || kind == 'reps')
                DropdownButton<String>(
                  isExpanded: true,
                  value: ex,
                  hint: const Text('Pick a lift'),
                  items: [for (final id in ids) DropdownMenuItem(value: id, child: Text(s.lib.byId(id)!.name))],
                  onChanged: (v) => set(() => ex = v),
                ),
              TextField(
                enableIMEPersonalizedLearning: false,
                controller: value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: kind == 'reps' ? 'Reps in one set' : (kind == 'volume' ? 'Tonnes a month' : 'Target'), suffixText: kind == 'reps' ? 'reps' : (kind == 'volume' ? 't' : unitLabel(s.unit))),
              ),
              const SizedBox(height: 6),
              if (kind != 'volume') // a monthly total starts fresh each month: no date
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(context: c, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: DateTime.now().add(const Duration(days: 90)));
                  if (d != null) set(() => by = d);
                },
                icon: const Icon(Icons.event),
                label: Text(by == null ? 'By a date (optional)' : 'By ${fmtDate(by!)}'),
              ),
              const SizedBox(height: 10),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save goal')),
            ]),
          ),
        ),
      ),
    );
    final v = double.tryParse(value.text.replaceAll(',', '.'));
    if (ok != true || v == null || v <= 0 || ((kind == 'lift' || kind == 'reps') && ex == null)) return;
    await s.addAim(kind, kind == 'reps' || kind == 'volume' ? v : fromUnit(v, s.unit), exercise: ex ?? '', by: kind == 'volume' ? null : by);
    // already past a lift or reps target: say so (it counts as reached, review 3 P1-2)
    final g = s.aims.last;
    final st = aimState(g, await s.aimSeries(g), DateTime.now());
    if (st.reached && mounted) toast(context, "You're already past this, so it counts as reached.");
  }
}

class _AimCard extends StatelessWidget {
  final AppState s;
  final Aim a;
  const _AimCard({required this.s, required this.a});

  String _v(double x) => a.kind == 'reps' ? '${x.round()} reps' : (a.kind == 'volume' ? '${fmtNum(x)} t' : '${fmtWeight(x, s.unit)} ${unitLabel(s.unit)}');

  @override
  Widget build(BuildContext context) => CachedFuture<List<Pt>>(
        cacheKey: '${s.historyVersion}|${a.id}',
        load: () => s.aimSeries(a),
        builder: (c, snap) {
          final st = aimState(a, snap.data ?? const [], DateTime.now());
          final name = a.exercise.isEmpty ? aimKinds[a.kind]! : (s.lib.byId(a.exercise)?.name ?? a.exercise);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('$name: ${_v(a.target)}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () async {
                      // one tap removes, and Undo puts it back as it was (review 3, P3-N14)
                      final gone = await s.removeAim(a.id);
                      if (gone == null || !context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(content: const Text('Goal removed.'), action: SnackBarAction(label: 'Undo', onPressed: () => s.restoreAim(gone.$1, gone.$2))));
                    },
                  ),
                ]),
                LinearProgressIndicator(value: st.done, backgroundColor: C.card2, color: st.reached ? C.green : (st.onTrack == false ? C.gold : C.teal)),
                const SizedBox(height: 4),
                Dim(
                    [
                      // plain, never shaming (review 3, P2-6)
                      if (st.waiting) 'Weigh in to start' else 'Now ${_v(st.now)}',
                      if (st.reached)
                        'reached'
                      else if (!st.waiting) ...[
                        a.by == null ? '${_v((a.target - st.now).abs())} to go' : '${_v((a.target - st.now).abs())} to go by ${fmtDate(a.by!)}',
                        if (st.onTrack == true) 'on track',
                        // the gold bar says it in words too, never by colour alone (F360)
                        if (st.onTrack == false) 'slower than that date needs',
                      ],
                      if (st.eta != null) 'at this rate ${aroundMonth(st.eta!, DateTime.now())}',
                    ].join(' · '),
                    size: 12),
              ]),
            ),
          );
        },
      );
}
