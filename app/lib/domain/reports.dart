import 'exercise.dart';
import 'library.dart';
import 'stats.dart';
import 'units.dart';
import 'volume.dart';

/// Reports, calendar, streaks, goals and badges (batch 18, F275-F298). Everything is worked out
/// on the phone from the finished workouts.

/// A finished workout as reports see it.
class Workout {
  final String id;
  final DateTime start;
  final int minutes;
  final int plannedSets;
  const Workout(this.id, this.start, this.minutes, {this.plannedSets = 0});
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// [n] days on by the calendar, so a day stays a day across clock changes (review 3, P2-2:
/// adding 24 hours lands on 01:00 after the spring change).
DateTime addDays(DateTime t, int n) => DateTime(t.year, t.month, t.day + n, t.hour, t.minute, t.second, t.millisecond);

/// Monday of the week [t] is in.
DateTime weekOf(DateTime t) => addDays(dayOf(t), -(t.weekday - 1));

// ---------- a report for any dates (F275, F276, F278, F280) ----------

class Report {
  final DateTime from, to; // to is exclusive
  final int workouts, sets, reps, minutes, records;
  final double volume; // kg lifted (weight x reps)
  final Map<String, double> muscles; // sets per muscle, helpers half
  final List<(Exercise, int)> mostDone; // by sets
  final List<(Exercise, double)> mostImproved; // e1RM gain in the period, kg
  final double? bodyChange; // kg, last weigh-in minus first in the period
  const Report(this.from, this.to,
      {this.workouts = 0, this.sets = 0, this.reps = 0, this.minutes = 0, this.records = 0, this.volume = 0, this.muscles = const {}, this.mostDone = const [], this.mostImproved = const [], this.bodyChange});
}

Report reportFor(DateTime from, DateTime to, List<Workout> ws, List<SetLog> sets, Library lib, {List<(DateTime, double)> body = const []}) {
  bool inside(DateTime t) => !t.isBefore(from) && t.isBefore(to);
  final w = [for (final x in ws) if (inside(x.start)) x];
  final ids = {for (final x in w) x.id};
  final s = [for (final x in sets) if (x.counts && ids.contains(x.sessionId)) x];
  final muscles = <String, double>{};
  final count = <String, int>{};
  for (final x in s) {
    count[x.exerciseId] = (count[x.exerciseId] ?? 0) + 1;
    final e = lib.byId(x.exerciseId);
    if (e == null) continue;
    for (final m in setShare(e).entries) {
      muscles[m.key] = (muscles[m.key] ?? 0) + m.value;
    }
  }
  // records broken inside the period: compared with everything before (one per kind per workout)
  var records = 0;
  final improved = <(Exercise, double)>[];
  for (final id in count.keys) {
    final e = lib.byId(id);
    if (e == null) continue;
    final all = [for (final x in sets) if (x.exerciseId == id) x];
    // a lift that set any new record in a workout counts once, however many kinds it broke
    records += {for (final r in recordHistory(all, e)) if (r.before != null && inside(r.at)) r.session}.length;
    if (e.bodyweight || e.timed) continue;
    final per = seriesOf([for (final x in all) if (x.at != null && inside(x.at!)) x], ChartKind.e1rm);
    if (per.length >= 2) improved.add((e, per.last.v - per.first.v));
  }
  improved.sort((a, b) => b.$2.compareTo(a.$2));
  final done = [for (final e in count.entries) if (lib.byId(e.key) != null) (lib.byId(e.key)!, e.value)]..sort((a, b) => b.$2.compareTo(a.$2));
  final b = [for (final x in body) if (inside(x.$1)) x]..sort((a, c) => a.$1.compareTo(c.$1));
  return Report(from, to,
      workouts: w.length,
      sets: s.length,
      reps: s.fold(0, (a, x) => a + x.reps),
      minutes: w.fold(0, (a, x) => a + x.minutes),
      records: records,
      volume: s.fold(0.0, (a, x) => a + x.kg * x.reps),
      muscles: muscles,
      mostDone: done.take(5).toList(),
      mostImproved: [for (final x in improved) if (x.$2 > 0.05) x].take(5).toList(),
      bodyChange: b.length >= 2 ? b.last.$2 - b.first.$2 : null);
}

/// This week next to last week and the week 4 weeks back (F275 with "vs 4 weeks ago").
/// The week so far is set against the same days (Monday to now) of the earlier weeks, so an early
/// Sunday with one workout does not read as a row of minuses (review 3, P2-3).
(Report, Report, Report) weekReports(DateTime now, List<Workout> ws, List<SetLog> sets, Library lib) {
  final w = weekOf(now);
  // whole calendar days since Monday; counted in UTC so a clock change in between is not a day short
  final days = DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(w.year, w.month, w.day)).inDays;
  Report r(int back) {
    final from = addDays(w, -7 * back);
    // the earlier weeks count whole days, Monday through today's weekday (review 4, P3-N18: not
    // only up to this time of day)
    final to = addDays(from, days + 1);
    return reportFor(from, back == 0 ? now.add(const Duration(seconds: 1)) : to, ws, sets, lib);
  }

  return (r(0), r(1), r(4));
}

/// "+12%" / "−3%" / "new" for a change between two numbers.
String changeText(num now, num before) {
  if (before == 0) return now == 0 ? '' : 'new';
  final p = ((now - before) / before * 100).round();
  return p == 0 ? 'same' : '${p > 0 ? '+' : '−'}${p.abs()}%';
}

/// The months with any workout, newest first (F276: past months are kept).
List<DateTime> monthsWithWorkouts(List<Workout> ws) {
  final m = {for (final x in ws) DateTime(x.start.year, x.start.month)}.toList()..sort((a, b) => b.compareTo(a));
  return m;
}

// ---------- year wrapped and lifetime (F277, F279) ----------

class YearWrap {
  final int year, workouts, records, longestStreak;
  final double volume;
  final int minutes;
  final DateTime? bestMonth; // most volume
  final Exercise? favourite; // most sets
  const YearWrap(this.year, {this.workouts = 0, this.records = 0, this.longestStreak = 0, this.volume = 0, this.minutes = 0, this.bestMonth, this.favourite});
}

YearWrap yearWrap(int year, List<Workout> ws, List<SetLog> sets, Library lib, {int perWeek = 3}) {
  final r = reportFor(DateTime(year), DateTime(year + 1), ws, sets, lib);
  DateTime? best;
  var bestV = 0.0;
  for (var m = 1; m <= 12; m++) {
    final v = reportFor(DateTime(year, m), DateTime(year, m + 1), ws, sets, lib).volume;
    if (v > bestV) {
      bestV = v;
      best = DateTime(year, m);
    }
  }
  final inYear = [for (final x in ws) if (x.start.year == year) x];
  return YearWrap(year,
      workouts: r.workouts, records: r.records, longestStreak: longestWeekStreak(inYear, perWeek: perWeek), volume: r.volume, minutes: r.minutes, bestMonth: best, favourite: r.mostDone.isEmpty ? null : r.mostDone.first.$1);
}

/// A fun way to say a total weight (F279): cars (1,500 kg), elephants (6,000 kg), blue whales (150 t).
String funWeight(double kg) {
  if (kg >= 150000) return 'about ${(kg / 150000).toStringAsFixed(1)} blue whales';
  if (kg >= 6000) return 'about ${(kg / 6000).toStringAsFixed(kg >= 60000 ? 0 : 1)} elephants';
  if (kg >= 1500) return 'about ${(kg / 1500).toStringAsFixed(1)} cars';
  if (kg >= 100) return 'about ${(kg / 80).toStringAsFixed(0)} people';
  return '';
}

// ---------- charts and splits (F281-F286) ----------

/// Workouts and average length per week, oldest first (F281).
List<(DateTime week, int workouts, int avgMinutes)> perWeek(List<Workout> ws, DateTime now, {int weeks = 12}) {
  final start = addDays(weekOf(now), -7 * (weeks - 1));
  return [
    for (var i = 0; i < weeks; i++)
      () {
        final a = addDays(start, 7 * i), b = addDays(a, 7);
        final w = [for (final x in ws) if (!x.start.isBefore(a) && x.start.isBefore(b)) x];
        return (a, w.length, w.isEmpty ? 0 : (w.fold(0, (s, x) => s + x.minutes) / w.length).round());
      }()
  ];
}

/// Workouts by weekday (rows, Monday first) and hour (columns) (F282).
List<List<int>> whenGrid(List<Workout> ws) {
  final g = [for (var d = 0; d < 7; d++) List<int>.filled(24, 0)];
  for (final x in ws) {
    g[x.start.weekday - 1][x.start.hour]++;
  }
  return g;
}

/// Share of sets with 1-5, 6-12 and 13+ reps (F283).
(double heavy, double medium, double light) repSplit(List<SetLog> sets) {
  final l = [for (final x in sets) if (x.counts && x.reps > 0 && x.secs == null) x];
  if (l.isEmpty) return (0, 0, 0);
  final h = l.where((x) => x.reps <= 5).length, m = l.where((x) => x.reps > 5 && x.reps <= 12).length;
  return (h / l.length, m / l.length, (l.length - h - m) / l.length);
}

/// Training load (F284): sets weighted by how hard they felt (RPE / effort taps), last 7 days
/// against the weekly average of the 6 weeks before. 1.0 = usual; well above = a heavy week.
/// [weeks]: full weeks with any set among the 6 before; below 3 there is nothing to compare with
/// (review 3, P2-4: a new lifter got "6.0x your usual").
(double week, double usual, int weeks) trainingLoad(List<SetLog> sets, DateTime now) {
  double w(SetLog x) => (x.rpeOrEffort ?? 8) / 8;
  final day = addDays(dayOf(now), 1);
  var acute = 0.0, chronic = 0.0;
  final withData = <int>{};
  for (final x in sets) {
    if (!x.counts || x.at == null) continue;
    final d = day.difference(x.at!).inDays;
    if (d < 7) acute += w(x);
    if (d >= 7 && d < 49) {
      chronic += w(x);
      withData.add((d - 7) ~/ 7);
    }
  }
  return (acute, withData.isEmpty ? 0 : chronic / withData.length, withData.length);
}

/// Running total of weight lifted, one point per workout (F285).
List<(DateTime, double)> runningVolume(List<Workout> ws, List<SetLog> sets) {
  final vol = <String, double>{};
  for (final x in sets) {
    if (x.counts) vol[x.sessionId] = (vol[x.sessionId] ?? 0) + x.kg * x.reps;
  }
  final l = [...ws]..sort((a, b) => a.start.compareTo(b.start));
  var t = 0.0;
  return [
    for (final x in l)
      () {
        t += vol[x.id] ?? 0;
        return (x.start, t);
      }()
  ];
}

/// Plan kept (F286), per week: workouts done against the plan's days, sets done against planned.
List<(DateTime week, int done, int planned, int setsDone, int setsPlanned)> planKept(List<Workout> ws, List<SetLog> sets, DateTime now, int perWeekPlanned, {int weeks = 8}) {
  final counted = <String, int>{};
  for (final x in sets) {
    if (x.counts) counted[x.sessionId] = (counted[x.sessionId] ?? 0) + 1;
  }
  final first = ws.isEmpty ? now : weekOf(ws.map((x) => x.start).reduce((a, b) => a.isBefore(b) ? a : b));
  return [
    for (final (wk, n, _) in perWeek(ws, now, weeks: weeks))
      if (!wk.isBefore(first)) // no "0 of 3" weeks from before you started (review 3, P2-5)
      () {
        final w = [for (final x in ws) if (!x.start.isBefore(wk) && x.start.isBefore(addDays(wk, 7))) x];
        return (wk, n, perWeekPlanned, w.fold(0, (a, x) => a + (counted[x.id] ?? 0)), w.fold(0, (a, x) => a + x.plannedSets));
      }()
  ];
}

// ---------- calendar (F288-F290) ----------

/// Volume per training day (kg), for the month calendar and the year heatmap.
Map<DateTime, double> dayVolumes(List<Workout> ws, List<SetLog> sets) {
  final byWs = {for (final w in ws) w.id: dayOf(w.start)};
  final out = <DateTime, double>{for (final w in ws) dayOf(w.start): 0};
  for (final x in sets) {
    final d = byWs[x.sessionId];
    if (d != null && x.counts) out[d] = (out[d] ?? 0) + x.kg * x.reps;
  }
  return out;
}

/// Days a lift was done at or above [kg] for at least [reps] reps (F290: "days I benched 80 x 5").
Set<DateTime> daysMatching(List<SetLog> sets, String exerciseId, {double kg = 0, int reps = 1}) =>
    {for (final x in sets) if (x.counts && x.exerciseId == exerciseId && x.kg >= kg - 0.01 && x.reps >= reps && x.at != null) dayOf(x.at!)};

// ---------- streaks and the weekly goal (F291-F293) ----------

/// Weeks in a row with at least [perWeek] workouts (F292). Rest days never break it; this week
/// counts once it has reached the goal, and a week still going does not break the run.
int weekStreak(List<Workout> ws, DateTime now, {required int perWeek}) {
  final need = perWeek.clamp(1, 7);
  // training days, like the ring: two workouts on one day are one day (review 3, P2-8)
  int inWeek(DateTime wk) => {for (final x in ws) if (!x.start.isBefore(wk) && x.start.isBefore(addDays(wk, 7))) dayOf(x.start)}.length;
  var wk = weekOf(now);
  var n = 0;
  if (inWeek(wk) >= need) n++;
  wk = addDays(wk, -7);
  while (inWeek(wk) >= need) {
    n++;
    wk = addDays(wk, -7);
  }
  return n;
}

int longestWeekStreak(List<Workout> ws, {required int perWeek}) {
  if (ws.isEmpty) return 0;
  final weeks = <DateTime, int>{};
  for (final d in {for (final x in ws) dayOf(x.start)}) {
    weeks[weekOf(d)] = (weeks[weekOf(d)] ?? 0) + 1;
  }
  final l = weeks.keys.toList()..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final wk in l) {
    if ((weeks[wk] ?? 0) < perWeek.clamp(1, 7)) {
      run = 0;
      prev = wk;
      continue;
    }
    run = prev != null && wk.difference(prev).inDays <= 7 && run > 0 ? run + 1 : 1;
    if (run > best) best = run;
    prev = wk;
  }
  return best;
}

/// This week's 7 days, Monday first: trained or not (F291).
List<bool> weekStrip(List<Workout> ws, DateTime now) {
  final wk = weekOf(now);
  final days = {for (final x in ws) dayOf(x.start)};
  return [for (var i = 0; i < 7; i++) days.contains(addDays(wk, i))];
}

// ---------- goals (F294-F296) ----------

/// One personal goal (an "aim", so it is not mixed up with the training goal of the setup): a
/// lift's max, body weight, reps on a lift, or tonnes a month.
class Aim {
  final String id, kind; // 'lift' | 'body' | 'reps' | 'volume'
  final String exercise; // lift / reps goals
  final double target; // kg (lift, body, volume per month) or reps
  final double start; // the value when it was set
  final DateTime created;
  final DateTime? by;
  const Aim({required this.id, required this.kind, this.exercise = '', required this.target, required this.start, required this.created, this.by});

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind, if (exercise.isNotEmpty) 'ex': exercise, 't': target, 's': start, 'c': created.millisecondsSinceEpoch, if (by != null) 'by': by!.millisecondsSinceEpoch};
  factory Aim.fromJson(Map<String, dynamic> j) => Aim(
      id: j['id'] as String,
      kind: j['kind'] as String,
      exercise: (j['ex'] ?? '') as String,
      target: (j['t'] as num).toDouble(),
      start: (j['s'] as num).toDouble(),
      created: DateTime.fromMillisecondsSinceEpoch(j['c'] as int),
      by: j['by'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['by'] as int));
}

/// Where a goal stands: 0-1 done, on track (null without a date), and when it gets there at the
/// current rate (null when not moving towards it).
class AimState {
  final double now, done;
  final bool? onTrack; // null = too early to say (review 3, P2-6)
  final DateTime? eta; // shown as a month only
  final bool reached;
  final bool waiting; // a body goal with no weigh-in yet: "Weigh in to start"
  const AimState(this.now, this.done, {this.onTrack, this.eta, this.reached = false, this.waiting = false});
}

/// [series]: the goal's value over time (e1RM per workout, body weight, best reps, or volume this
/// month as one point). Review 3, P1-2 and P2-6:
///  - only a body weight goal can go down; a lift, reps or tonnes goal below today's value is
///    simply reached;
///  - tonnes a month count from 0 each month;
///  - a body goal set before any weigh-in starts at the first weigh-in after it;
///  - "at this rate" needs 4+ workouts over 3+ weeks, uses the trend line and is at most a year
///    out; "on track" waits for a quarter of the time and 2 points.
AimState aimState(Aim g, List<Pt> series, DateTime now) {
  final after = [for (final p in series) if (!p.at.isBefore(g.created)) p];
  if (g.kind == 'body') {
    final start = g.start > 0 ? g.start : (after.isEmpty ? null : after.first.v);
    if (start == null || series.isEmpty) return AimState(g.start, 0, waiting: true);
    final cur = series.last.v;
    final down = g.target < start;
    final span = (g.target - start).abs();
    final done = span <= 0 ? 1.0 : ((down ? start - cur : cur - start) / span).clamp(0.0, 1.0);
    final reached = down ? cur <= g.target + 0.01 : cur >= g.target - 0.01;
    return AimState(cur, done, reached: reached, onTrack: reached ? true : _onTrack(g, after, done, now), eta: reached ? null : _eta(g, after, cur, now, down: down));
  }
  final cur = series.isEmpty ? (g.kind == 'volume' ? 0.0 : g.start) : series.last.v;
  final from = g.kind != 'volume' && g.start < g.target ? g.start : 0.0;
  final done = g.target - from <= 0 ? 1.0 : ((cur - from) / (g.target - from)).clamp(0.0, 1.0);
  final reached = cur >= g.target - 0.01;
  if (reached) return AimState(cur, 1, reached: true, onTrack: true);
  return AimState(cur, done, onTrack: g.kind == 'volume' ? null : _onTrack(g, after, done, now), eta: g.kind == 'volume' ? null : _eta(g, after, cur, now));
}

bool? _onTrack(Aim g, List<Pt> after, double done, DateTime now) {
  if (g.by == null || after.length < 2) return null;
  final total = g.by!.difference(g.created).inDays;
  final passed = now.difference(g.created).inDays;
  if (total <= 0 || passed < total / 4) return null;
  return done + 0.05 >= (passed / total).clamp(0.0, 1.0);
}

DateTime? _eta(Aim g, List<Pt> after, double cur, DateTime now, {bool down = false}) {
  if (after.length < 4 || after.last.at.difference(after.first.at).inDays < 21) return null;
  // the trend line over the last 8 weeks, not the raw ups and downs
  final avg = movingAverage(after);
  final smooth = [for (var i = 0; i < after.length; i++) Pt(after[i].at, avg[i], after[i].session)];
  final pr = projection(smooth, weeks: 8);
  if (pr == null || pr.$1 == 0) return null;
  final left = g.target - cur;
  final days = left / (pr.$1 / 7);
  if (days <= 0 || days > 365) return null;
  final eta = now.add(Duration(days: days.ceil()));
  if (g.by != null && eta.isAfter(g.by!.add(const Duration(days: 120)))) return null;
  return eta;
}

/// "around March" / "around March 2028": a month, never a day.
String aroundMonth(DateTime t, DateTime now) {
  const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return 'around ${m[t.month - 1]}${t.year == now.year ? '' : ' ${t.year}'}';
}

// ---------- badges and levels (F297, F298) ----------

class Award {
  final String id, name, how;
  const Award(this.id, this.name, this.how);
}

/// The badges earned so far (F297). Quiet: they show in Reports and play the badge sound once.
List<Award> badgesEarned(List<Workout> ws, List<SetLog> sets, Library lib, {int perWeek = 3}) {
  final out = <Award>[];
  final n = ws.length;
  if (n >= 1) out.add(const Award('first', 'First workout', 'You started.'));
  for (final k in const [10, 50, 100, 250, 500]) {
    if (n >= k) out.add(Award('w$k', '$k workouts', '$k workouts done.'));
  }
  final tonnes = sets.where((x) => x.counts).fold<double>(0, (a, x) => a + x.kg * x.reps) / 1000;
  for (final k in const [1, 10, 100, 1000]) {
    if (tonnes >= k) out.add(Award('t$k', '$k tonne${k == 1 ? '' : 's'}', '$k ${k == 1 ? 'tonne' : 'tonnes'} lifted in all.'));
  }
  final byEx = <String, List<SetLog>>{};
  for (final x in sets) {
    (byEx[x.exerciseId] ??= []).add(x);
  }
  var pr = false;
  for (final e in byEx.entries) {
    final ex = lib.byId(e.key);
    if (ex != null && recordHistory(e.value, ex).any((r) => r.before != null)) pr = true;
  }
  if (pr) out.add(const Award('pr', 'First record', 'You beat your own best.'));
  // plate clubs: 1, 2, 3 plates a side (20 kg bar + 20 kg plates = 60 / 100 / 140 kg)
  for (final (id, name) in const [('bench_press', 'Bench'), ('back_squat', 'Squat'), ('deadlift', 'Deadlift')]) {
    final top = (byEx[id] ?? const []).where((x) => x.counts && x.reps > 0).fold<double>(0, (a, x) => x.kg > a ? x.kg : a);
    for (final (p, kg) in const [(1, 60.0), (2, 100.0), (3, 140.0), (4, 180.0)]) {
      if (top >= kg - 0.01) out.add(Award('${id}_$p', '$p-plate ${name.toLowerCase()}', '$name with $p plate${p == 1 ? '' : 's'} a side.'));
    }
  }
  final longest = longestWeekStreak(ws, perWeek: perWeek);
  for (final k in const [4, 12, 26, 52]) {
    if (longest >= k) out.add(Award('s$k', '$k weeks in a row', '$k weeks on plan in a row.'));
  }
  return out;
}

/// Level from workouts done (F298): each level needs a few more workouts than the one before.
(int level, int intoLevel, int forNext) levelOf(int workouts) {
  var level = 1, need = 3, left = workouts;
  while (left >= need) {
    left -= need;
    level++;
    need = 3 + level; // 3, 5, 6, 7, ...
  }
  return (level, left, need);
}

const levelNames = ['Starter', 'Regular', 'Committed', 'Strong', 'Seasoned', 'Iron', 'Steel', 'Titan'];
String levelName(int level) => levelNames[((level - 1) ~/ 4).clamp(0, levelNames.length - 1)];

/// "1,234 kg" in the person's unit, rounded.
String bigWeight(double kg, Unit u) => '${fmtNum(toUnit(kg, u).roundToDouble())} ${unitLabel(u)}';
