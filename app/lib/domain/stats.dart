import 'exercise.dart';
import 'library.dart';
import 'units.dart';

/// Charts and records (batch 17, F252-F274): worked out on the phone from the sets.

// ---------- chart series (F252, F259, F262, F265) ----------

enum ChartKind { e1rm, heaviest, bestSetVolume, workoutVolume, totalReps, sets, weightAt, length, effort, rest, perBody }

const chartLabel = {
  ChartKind.e1rm: 'Est. 1-rep max',
  ChartKind.heaviest: 'Heaviest weight',
  ChartKind.bestSetVolume: 'Best set (weight × reps)',
  ChartKind.workoutVolume: 'Workout volume',
  ChartKind.totalReps: 'Total reps',
  ChartKind.sets: 'Sets',
  ChartKind.weightAt: 'Weight at N reps',
  ChartKind.length: 'Workout length',
  ChartKind.effort: 'How hard it felt',
  ChartKind.rest: 'Rest between sets',
  ChartKind.perBody: '1-rep max per body weight',
};

/// Kinds whose values are weights (shown in the person's unit).
bool isWeightKind(ChartKind k) => const {ChartKind.e1rm, ChartKind.heaviest, ChartKind.bestSetVolume, ChartKind.workoutVolume, ChartKind.weightAt}.contains(k);

/// The unit word for a chart's values.
String kindUnit(ChartKind k, Unit u) => switch (k) {
      ChartKind.totalReps => 'reps',
      ChartKind.sets => 'sets',
      ChartKind.length => 'min',
      ChartKind.effort => 'RPE',
      ChartKind.rest => 's',
      ChartKind.perBody => '× body weight',
      _ => unitLabel(u),
    };

/// One workout's value on a chart.
class Pt {
  final DateTime at;
  final double v;
  final String session;
  const Pt(this.at, this.v, this.session);
}

/// One point per workout, oldest first. [minutes]: workout length per session (for
/// [ChartKind.length]); [body]: weigh-ins (for [ChartKind.perBody]); [reps] for weight-at-N-reps.
List<Pt> seriesOf(List<SetLog> sets, ChartKind k, {int reps = 5, bool bodyweight = false, Map<String, int> minutes = const {}, List<(DateTime, double)> body = const []}) {
  final by = <String, List<SetLog>>{};
  for (final x in sets) {
    if (!x.counts || x.at == null) continue;
    (by[x.sessionId] ??= []).add(x);
  }
  double best(List<SetLog> l, double Function(SetLog) f) => l.map(f).reduce((a, b) => a > b ? a : b);
  final out = <Pt>[];
  for (final e in by.entries) {
    final l = e.value;
    final at = l.map((x) => x.at!).reduce((a, b) => a.isBefore(b) ? a : b);
    double? v;
    switch (k) {
      case ChartKind.e1rm:
        v = bodyweight ? best(l, (x) => x.reps.toDouble()) : best(l, (x) => e1rm(x.kg, x.reps));
      case ChartKind.heaviest:
        final done = l.where((x) => x.reps > 0 || (x.secs ?? 0) > 0).toList(); // a missed rep lifted nothing
        v = done.isEmpty ? null : best(done, (x) => x.kg);
      case ChartKind.bestSetVolume:
        v = best(l, (x) => x.kg * x.reps);
      case ChartKind.workoutVolume:
        v = l.fold<double>(0, (a, x) => a + x.kg * x.reps);
      case ChartKind.totalReps:
        v = l.fold<double>(0, (a, x) => a + x.reps);
      case ChartKind.sets:
        v = l.length.toDouble();
      case ChartKind.weightAt:
        final ok = l.where((x) => x.reps >= reps && x.reps > 0).toList();
        v = ok.isEmpty ? null : best(ok, (x) => x.kg);
      case ChartKind.length:
        v = minutes[e.key]?.toDouble();
      case ChartKind.effort:
        final r = [for (final x in l) if (x.rpeOrEffort != null) x.rpeOrEffort!];
        v = r.isEmpty ? null : r.reduce((a, b) => a + b) / r.length;
      case ChartKind.rest:
        final r = [for (final x in l) if (x.rest != null && x.rest! > 0 && x.rest! < 1200) x.rest!.toDouble()];
        v = r.isEmpty ? null : r.reduce((a, b) => a + b) / r.length;
      case ChartKind.perBody:
        final bw = bodyAt(body, at);
        v = bw == null || bw <= 0 || bodyweight ? null : best(l, (x) => e1rm(x.kg, x.reps)) / bw;
    }
    // a workout of only missed sets is no point on these charts, not a dive to 0 (review 3, P2-9)
    if (v != null && !(v <= 0 && (k == ChartKind.e1rm || k == ChartKind.bestSetVolume || k == ChartKind.perBody))) out.add(Pt(at, v, e.key));
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// The body weight on a day: the last weigh-in before it, else the first after.
double? bodyAt(List<(DateTime, double)> body, DateTime at) {
  if (body.isEmpty) return null;
  final l = [...body]..sort((a, b) => a.$1.compareTo(b.$1));
  double? v;
  for (final b in l) {
    if (b.$1.isAfter(at)) break;
    v = b.$2;
  }
  return v ?? l.first.$2;
}

// ---------- ranges, trend, projection (F253, F256, F263) ----------

/// Chart ranges in months; 0 = all.
const chartRanges = [(1, '1 month'), (3, '3 months'), (6, '6 months'), (12, '1 year'), (0, 'All')];

List<Pt> inRange(List<Pt> p, int months, DateTime now) {
  if (months <= 0) return p;
  final from = DateTime(now.year, now.month - months, now.day);
  return [for (final x in p) if (!x.at.isBefore(from)) x];
}

/// A moving average over the last [n] workouts (F256).
List<double> movingAverage(List<Pt> p, {int n = 4}) => [
      for (var i = 0; i < p.length; i++)
        () {
          final s = p.sublist((i - n + 1).clamp(0, i), i + 1);
          return s.fold<double>(0, (a, x) => a + x.v) / s.length;
        }()
    ];

/// Where the line is heading (F263): the least-squares rate over the last [weeks] weeks, and the
/// value [ahead] days after the last point. Null with fewer than 3 points or a flat time span.
(double perWeek, DateTime at, double v)? projection(List<Pt> p, {int weeks = 8, int ahead = 28}) {
  if (p.length < 3) return null;
  final from = p.last.at.subtract(Duration(days: weeks * 7));
  final q = [for (final x in p) if (!x.at.isBefore(from)) x];
  if (q.length < 3) return null;
  final t0 = q.first.at;
  final xs = [for (final x in q) x.at.difference(t0).inHours / 24.0];
  final ys = [for (final x in q) x.v];
  final mx = xs.reduce((a, b) => a + b) / xs.length, my = ys.reduce((a, b) => a + b) / ys.length;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < xs.length; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  if (den < 1) return null;
  final slope = num / den;
  final at = p.last.at.add(Duration(days: ahead));
  final v = my + slope * (at.difference(t0).inHours / 24.0 - mx);
  return (slope * 7, at, v);
}

// ---------- tables (F260, F261) ----------

/// 100% down to 50% of a max, in 5% steps (F260). kg, not rounded.
List<(int, double)> percentTable(double max) => [for (var p = 100; p >= 50; p -= 5) (p, max * p / 100)];

/// The best weight actually lifted for each rep count 1-12 (a heavier weight for more reps
/// counts too), and what the best set says you could do (F261).
List<(int reps, double? best, double est)> repMaxGrid(List<SetLog> sets) {
  final w = [for (final x in sets) if (x.counts && x.reps > 0) x];
  final max = w.fold<double>(0, (a, x) => e1rm(x.kg, x.reps) > a ? e1rm(x.kg, x.reps) : a);
  return [
    for (var r = 1; r <= 12; r++)
      (r, w.where((x) => x.reps >= r).fold<double?>(null, (a, x) => a == null || x.kg > a ? x.kg : a), repsAt(max, r))
  ];
}

// ---------- records (F268-F274) ----------

enum RecordKind { e1rm, heaviest, bestSetVolume, bestWorkoutVolume, mostReps, addedWeight, longestHold, farthest }

const recordLabel = {
  RecordKind.e1rm: 'Est. 1-rep max',
  RecordKind.heaviest: 'Heaviest',
  RecordKind.bestSetVolume: 'Best set',
  RecordKind.bestWorkoutVolume: 'Best workout volume',
  RecordKind.mostReps: 'Most reps in a set',
  RecordKind.addedWeight: 'Most added weight',
  RecordKind.longestHold: 'Longest',
  RecordKind.farthest: 'Farthest',
};

/// One record: what it was, when, which set (null for a whole-workout record), and what it beat.
class Rec {
  final RecordKind kind;
  final double value;
  final DateTime at;
  final String session;
  final String? setId;
  final double? before;
  final SetLog? set;
  final SetLog? beforeSet; // the set it beat, so "was" reads like the record (review 2, P3-N5)
  const Rec(this.kind, this.value, this.at, this.session, {this.setId, this.before, this.set, this.beforeSet});
}

/// The record kinds that make sense for an exercise (F273, F274).
List<RecordKind> recordKinds(Exercise e, List<SetLog> sets) {
  if (e.timed) return [RecordKind.longestHold, if (sets.any((x) => (x.meters ?? 0) > 0)) RecordKind.farthest, if (sets.any((x) => x.kg > 0)) RecordKind.heaviest];
  if (e.bodyweight) return [RecordKind.mostReps, if (sets.any((x) => x.kg > 0)) RecordKind.addedWeight];
  return const [RecordKind.e1rm, RecordKind.heaviest, RecordKind.bestSetVolume, RecordKind.bestWorkoutVolume, RecordKind.mostReps];
}

double? _setValue(RecordKind k, SetLog x) => switch (k) {
      RecordKind.e1rm => e1rm(x.kg, x.reps),
      RecordKind.heaviest => x.reps > 0 || (x.secs ?? 0) > 0 ? x.kg : null,
      RecordKind.bestSetVolume => x.kg * x.reps,
      RecordKind.mostReps => x.reps.toDouble(),
      RecordKind.addedWeight => x.kg > 0 && x.reps > 0 ? x.kg : null,
      RecordKind.longestHold => (x.secs ?? (x.reps > 0 ? x.reps : null))?.toDouble(),
      RecordKind.farthest => x.meters,
      RecordKind.bestWorkoutVolume => null,
    };

/// Every time a record was set, oldest first (F270). Each workout is compared with the best of
/// the workouts BEFORE it, and gives at most one record per kind, its best set (review 2, P2-1):
/// the first workout of a lift sets the records with no [Rec.before] (nothing was broken), and a
/// ramp of rising sets in one workout is one record, not one per set.
List<Rec> recordHistory(List<SetLog> sets, Exercise e) {
  final l = [for (final x in sets) if (x.counts && x.at != null) x]..sort((a, b) => a.at!.compareTo(b.at!));
  final kinds = recordKinds(e, l);
  final bySes = <String, List<SetLog>>{};
  for (final x in l) {
    (bySes[x.sessionId] ??= []).add(x);
  }
  final order = bySes.keys.toList()..sort((a, b) => bySes[a]!.first.at!.compareTo(bySes[b]!.first.at!));
  final best = <RecordKind, double>{};
  final bestSet = <RecordKind, SetLog?>{};
  final out = <Rec>[];
  for (final sid in order) {
    final ses = bySes[sid]!;
    final at = ses.first.at!;
    for (final k in kinds) {
      double? v;
      SetLog? top;
      if (k == RecordKind.bestWorkoutVolume) {
        v = ses.fold<double>(0, (a, x) => a + x.kg * x.reps);
      } else {
        for (final x in ses) {
          final sv = _setValue(k, x);
          if (sv != null && (v == null || sv > v)) {
            v = sv;
            top = x;
          }
        }
      }
      if (v == null || v <= 0) continue;
      final b = best[k];
      if (b == null || v > b + 0.05) {
        out.add(Rec(k, v, top?.at ?? at, sid, setId: top?.id, before: b, set: top, beforeSet: bestSet[k]));
        best[k] = v;
        bestSet[k] = top;
      }
    }
  }
  return out;
}

/// The current record of each kind (the last one set).
Map<RecordKind, Rec> currentRecords(List<Rec> history) => {for (final r in history) r.kind: r};

/// Sets that beat an earlier record when they were done: the medals in History (F269).
Set<String> medalSets(List<Rec> history) => {for (final r in history) if (r.before != null && r.setId != null) r.setId!};

/// The best of each kind inside a time window (F271): this week, month or year.
Map<RecordKind, Rec> bestSince(List<SetLog> sets, Exercise e, DateTime since) {
  final l = [for (final x in sets) if (x.counts && x.at != null && !x.at!.isBefore(since)) x];
  final out = <RecordKind, Rec>{};
  final vol = <String, (DateTime, double)>{};
  for (final x in l) {
    for (final k in recordKinds(e, l)) {
      final v = _setValue(k, x);
      if (v == null || v <= 0) continue;
      if (out[k] == null || v > out[k]!.value) out[k] = Rec(k, v, x.at!, x.sessionId, setId: x.id, set: x);
    }
    final c = vol[x.sessionId];
    vol[x.sessionId] = (c?.$1 ?? x.at!, (c?.$2 ?? 0) + x.kg * x.reps);
  }
  if (recordKinds(e, l).contains(RecordKind.bestWorkoutVolume)) {
    for (final s in vol.entries) {
      if (out[RecordKind.bestWorkoutVolume] == null || s.value.$2 > out[RecordKind.bestWorkoutVolume]!.value) {
        out[RecordKind.bestWorkoutVolume] = Rec(RecordKind.bestWorkoutVolume, s.value.$2, s.value.$1, s.key);
      }
    }
  }
  return out;
}

/// Start of this week (Monday), month or year (F271).
DateTime windowStart(String w, DateTime now) => switch (w) {
      'week' => DateTime(now.year, now.month, now.day - (now.weekday - 1)), // by the calendar (DST)
      'month' => DateTime(now.year, now.month),
      'year' => DateTime(now.year),
      _ => DateTime(2000),
    };

/// A record's value in words: "120 kg", "12 reps", "1:30", "40 m".
String recordText(Rec r, Unit u, {bool bodyweight = false}) => switch (r.kind) {
      RecordKind.mostReps => '${r.value.round()} reps${r.set != null && r.set!.kg > 0 && !bodyweight ? ' at ${fmtWeight(r.set!.kg, u)} ${unitLabel(u)}' : (r.set != null && r.set!.kg > 0 ? ' +${fmtWeight(r.set!.kg, u)} ${unitLabel(u)}' : '')}',
      RecordKind.longestHold => '${r.value ~/ 60}:${(r.value.round() % 60).toString().padLeft(2, '0')}',
      RecordKind.farthest => '${fmtNum(r.value)} m',
      RecordKind.addedWeight => '+${fmtWeight(r.value, u)} ${unitLabel(u)}${r.set == null ? '' : ' × ${r.set!.reps}'}',
      RecordKind.e1rm || RecordKind.heaviest => '${fmtWeight(r.value, u)} ${unitLabel(u)}${r.kind == RecordKind.heaviest && r.set != null ? ' × ${r.set!.reps}' : ''}',
      RecordKind.bestSetVolume when r.set != null => '${fmtWeight(r.set!.kg, u)} ${unitLabel(u)} × ${r.set!.reps}',
      _ => '${fmtNum(toUnit(r.value, u).roundToDouble())} ${unitLabel(u)}',
    };

// ---------- variants (F266) ----------

const _modifiers = {'db', 'barbell', 'smith', 'machine', 'cable', 'kb', 'band', 'single', 'arm', 'leg', 'seated', 'standing', 'one', 'weighted', 'assisted', 'close', 'grip', 'wide', 'reverse', 'pause', 'deficit', 'incline', 'decline', 'chest', 'supported', 'lying', 'hammer', 'ez', 'bar', 'trap', 'safety', 'box', 'front', 'back', 'sumo', 'stiff', 'romanian', 'push', 'floor'};

/// The exercise's core word ("bench", "squat", "deadlift", "row") for grouping variants.
String coreWord(Exercise e) {
  final w = e.id.split('_').where((x) => x.length > 2 && !_modifiers.contains(x)).toList();
  if (w.contains('bench')) return 'bench';
  if (w.isEmpty) return e.id;
  w.sort((a, b) => b.length.compareTo(a.length));
  return w.first;
}

/// "All bench press kinds" (F266): exercises sharing the core word and the main muscle.
List<Exercise> variantsOf(Exercise e, Library lib) {
  final c = coreWord(e);
  // bench kinds go by the movement (close-grip bench is still a bench press, a bench dip is not)
  bool same(Exercise x) => c == 'bench' ? x.pattern != 'dip' : x.primary.first == e.primary.first;
  return [for (final x in lib.all) if (x.id == e.id || (same(x) && x.bodyweight == e.bodyweight && x.id.split('_').contains(c))) x];
}
