import 'dart:math' as math;

import 'stats.dart';

/// Body and strength scores (batch 19, F299-F309). Worked out on the phone; nothing here is
/// sent anywhere.

// ---------- body weight (F299) ----------

/// The average of the last 7 days at each weigh-in (F299: smooths out daily swings).
List<double> sevenDayAverage(List<Pt> l) => [
      for (var i = 0; i < l.length; i++)
        () {
          final w = [for (final p in l.take(i + 1)) if (l[i].at.difference(p.at).inDays < 7) p.v];
          return w.reduce((a, b) => a + b) / w.length;
        }()
    ];

/// kg a week over the last 4 weeks, from the 7-day average, not the raw weigh-ins (review 4,
/// P2-4: daily swings of 1-2 kg are water). Null with fewer than 4 weigh-ins or under 14 days.
double? ratePerWeek(List<Pt> l) {
  if (l.length < 4 || l.last.at.difference(l.first.at).inDays < 14) return null;
  final a = sevenDayAverage(l);
  final smooth = [for (var i = 0; i < l.length; i++) Pt(l[i].at, a[i], '')];
  // the first week's averages hold fewer days; leave them out when there is enough after them
  final full = [for (final p in smooth) if (p.at.difference(l.first.at).inDays >= 6) p];
  return projection(full.length >= 3 ? full : smooth, weeks: 4)?.$1;
}

/// The 7-day average is shown only when the last 7 days hold 2 or more weigh-ins (P2-4).
bool showSevenDay(List<Pt> l, DateTime now) => l.where((p) => now.difference(p.at).inDays < 7).length >= 2;

/// One check for a body weight everywhere (review 4, P2-3): 20-400 kg.
const bodyKgMin = 20.0, bodyKgMax = 400.0;
bool validBodyKg(double kg) => kg >= bodyKgMin && kg <= bodyKgMax;

/// Body fat % that is taken (review 4, P2-3).
const fatMin = 3.0, fatMax = 60.0;
bool validFat(double pct) => pct >= fatMin && pct <= fatMax;

// ---------- body fat and derived numbers (F300) ----------

double bmi(double kg, double cm) => kg / math.pow(cm / 100, 2);

double leanMass(double kg, double fatPct) => kg * (1 - fatPct / 100);

/// Fat-free mass index, height-normalised (the usual +6.1 x (1.8 - height) form).
double ffmi(double kg, double fatPct, double cm) {
  final h = cm / 100;
  return leanMass(kg, fatPct) / (h * h) + 6.1 * (1.8 - h);
}

// ---------- tape measurements (F301) ----------

/// Body parts to measure; the ones with a side are measured left and right.
const tapeParts = {'neck': false, 'shoulders': false, 'chest': false, 'waist': false, 'hips': false, 'arm': true, 'forearm': true, 'thigh': true, 'calf': true};

class Tape {
  final DateTime at;
  final String part; // a tapeParts key or the person's own name
  final String side; // '', 'L', 'R'
  final double cm;
  const Tape(this.at, this.part, this.side, this.cm);
  Map<String, dynamic> toJson() => {'at': at.millisecondsSinceEpoch, 'p': part, if (side.isNotEmpty) 's': side, 'cm': cm};
  factory Tape.fromJson(Map<String, dynamic> j) => Tape(DateTime.fromMillisecondsSinceEpoch(j['at'] as int), j['p'] as String, (j['s'] ?? '') as String, (j['cm'] as num).toDouble());
  String get label => '${part[0].toUpperCase()}${part.substring(1)}${side.isEmpty ? '' : (side == 'L' ? ' left' : ' right')}';
}

// ---------- standard points (F306) ----------

/// DOTS points for a total (kg) at a body weight (kg). [female]: the women's formula.
/// A plain line when [bw] is outside the body weights the points formulas cover, saying which
/// weight they used (review 5, P3-N31); null inside the range.
String? pointsEdge(double bw, {required bool female}) {
  final hi = female ? 150.0 : 210.0;
  if (bw < 40) return 'Under 40 kg body weight the points count it as 40 kg: the formulas stop there.';
  if (bw > hi) return 'Over ${hi.round()} kg body weight DOTS counts it as ${hi.round()} kg (Wilks ${female ? 154.53 : 201.9} kg): the formulas stop there.';
  return null;
}

double dots(double total, double bw, {required bool female}) {
  final c = female ? const [-57.96288, 13.6175032, -0.1126655495, 0.0005158568, -0.0000010706] : const [-307.75076, 24.0900756, -0.1918759221, 0.0007391293, -0.000001093];
  final x = bw.clamp(female ? 40.0 : 40.0, female ? 150.0 : 210.0);
  final den = c[0] + c[1] * x + c[2] * x * x + c[3] * x * x * x + c[4] * x * x * x * x;
  return total * 500 / den;
}

/// Wilks points (the original formula, with OpenPowerlifting's body weight clamps).
double wilks(double total, double bw, {required bool female}) {
  final c = female ? const [594.31747775582, -27.23842536447, 0.82112226871, -0.00930733913, 4.731582e-05, -9.054e-08] : const [-216.0475144, 16.2606339, -0.002388645, -0.00113732, 7.01863e-06, -1.291e-08];
  final x = female ? bw.clamp(26.51, 154.53) : bw.clamp(40.0, 201.9);
  final den = c[0] + c[1] * x + c[2] * x * x + c[3] * math.pow(x, 3) + c[4] * math.pow(x, 4) + c[5] * math.pow(x, 5);
  return total * 500 / den;
}

/// IPF GL points (classic, raw, full powerlifting).
double ipfGl(double total, double bw, {required bool female}) {
  final (a, b, c) = female ? (610.32796, 1045.59282, 0.03048) : (1199.72839, 1025.18162, 0.00921);
  return total * 100 / (a - b * math.exp(-c * math.max(bw, 40.0)));
}

// ---------- strength levels and the score (F305, F307) ----------

const levelNames5 = ['Beginner', 'Novice', 'Intermediate', 'Advanced', 'Elite'];

/// Our own rough guide (not a published table): a lift's est. 1-rep max as a multiple of body
/// weight at the start of each level.
const _men = {
  'back_squat': [0.75, 1.25, 1.5, 2.0, 2.5],
  'bench_press': [0.5, 0.75, 1.0, 1.5, 2.0],
  'deadlift': [1.0, 1.5, 2.0, 2.5, 3.0],
  'overhead_press': [0.35, 0.55, 0.7, 0.95, 1.2],
  'barbell_row': [0.5, 0.75, 1.0, 1.25, 1.5],
};
const _women = {
  'back_squat': [0.5, 0.75, 1.0, 1.5, 1.75],
  'bench_press': [0.25, 0.5, 0.65, 0.9, 1.2],
  'deadlift': [0.6, 1.0, 1.25, 1.75, 2.25],
  'overhead_press': [0.2, 0.35, 0.5, 0.65, 0.85],
  'barbell_row': [0.3, 0.5, 0.65, 0.85, 1.1],
};

Set<String> get levelLifts => _men.keys.toSet();

/// The level thresholds in kg for a lift at a body weight (null when the lift has none).
List<double>? levelWeights(String lift, double bw, {required bool female}) {
  final m = (female ? _women : _men)[lift];
  return m == null ? null : [for (final x in m) x * bw];
}

/// Where a max sits: the level (-1 = below Beginner), the next threshold (kg) and 0-1 of the way.
(int level, double? next, double part) strengthLevelOf(String lift, double max, double bw, {required bool female}) {
  final w = levelWeights(lift, bw, female: female);
  if (w == null) return (-1, null, 0);
  var lvl = -1;
  for (var i = 0; i < w.length; i++) {
    if (max >= w[i] - 0.01) lvl = i;
  }
  if (lvl == w.length - 1) return (lvl, null, 1);
  final lo = lvl < 0 ? 0.0 : w[lvl], hi = w[lvl + 1];
  return (lvl, hi, ((max - lo) / (hi - lo)).clamp(0.0, 1.0));
}

/// A 0-100 strength score (F305): each main lift's place from below Beginner (0) to Elite (100),
/// averaged over the lifts you have. Fair for body weight, since levels are multiples of it.
int strengthScore(Map<String, double> maxes, double bw, {required bool female}) {
  final parts = <double>[];
  for (final e in maxes.entries) {
    final (lvl, _, part) = strengthLevelOf(e.key, e.value, bw, female: female);
    if (levelWeights(e.key, bw, female: female) == null) continue;
    parts.add(((lvl + 1 + (lvl == 4 ? 0 : part)) / 5).clamp(0.0, 1.0));
  }
  if (parts.isEmpty) return 0;
  return (parts.reduce((a, b) => a + b) / parts.length * 100).round();
}

// ---------- lift ratios (F308) ----------

/// The usual ratio of two lifts' maxes, and the words for it.
const liftRatios = [
  ('bench_press', 'back_squat', 0.75),
  ('deadlift', 'back_squat', 1.2),
  ('overhead_press', 'bench_press', 0.65),
  ('barbell_row', 'bench_press', 0.9),
];

/// The pairs where a lift is low next to another: (low lift, the other, actual ratio, usual ratio).
/// With [workouts], both lifts need [minWorkouts] workouts behind them (review 4, P2-7: one light
/// session says nothing).
List<(String, String, double, double)> laggingLifts(Map<String, double> maxes, {Map<String, int>? workouts, int minWorkouts = 3}) => [
      for (final (a, b, usual) in liftRatios)
        if (maxes[a] != null && maxes[b] != null && maxes[b]! > 0 && (workouts == null || ((workouts[a] ?? 0) >= minWorkouts && (workouts[b] ?? 0) >= minWorkouts)))
          () {
            final r = maxes[a]! / maxes[b]!;
            if (r < usual * 0.85) return (a, b, r, usual);
            if (r > usual * 1.2) return (b, a, maxes[b]! / maxes[a]!, 1 / usual);
            return null;
          }()
    ].whereType<(String, String, double, double)>().toList();

// ---------- the powerlifting total (F309) ----------

/// Squat + bench + deadlift best est. 1-rep max, by month (a lift's best carries forward), from
/// the first month all three are there.
List<(DateTime, double)> totalByMonth(Map<String, List<Pt>> e1rms) {
  const lifts = ['back_squat', 'bench_press', 'deadlift'];
  if (lifts.any((l) => (e1rms[l] ?? const []).isEmpty)) return const [];
  final months = {for (final l in lifts) for (final p in e1rms[l]!) DateTime(p.at.year, p.at.month)}.toList()..sort();
  final best = <String, double>{};
  final out = <(DateTime, double)>[];
  for (final m in months) {
    for (final l in lifts) {
      for (final p in e1rms[l]!) {
        if (DateTime(p.at.year, p.at.month) == m && p.v > (best[l] ?? 0)) best[l] = p.v;
      }
    }
    if (best.length == 3) out.add((m, best.values.reduce((a, b) => a + b)));
  }
  return out;
}
