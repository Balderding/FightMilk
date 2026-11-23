import 'exercise.dart';
import 'library.dart';
import 'plan.dart';

/// Weekly sets per muscle, targets, recovery and fatigue (batch 15, F224-F237). All worked out on
/// the phone from the plan and the log; nothing here needs the AI.

/// The muscles counted. The exercise data's finer names fold into these.
const volumeMuscles = ['chest', 'back', 'shoulders', 'biceps', 'triceps', 'quads', 'hamstrings', 'glutes', 'calves', 'core', 'traps', 'forearms'];
const _fold = {'lats': 'back', 'rear_delts': 'shoulders', 'adductors': 'quads'};
String muscleOf(String m) => _fold[m] ?? m;
String muscleName(String m) => '${m[0].toUpperCase()}${m.substring(1).replaceAll('_', ' ')}';

/// How much of a set each muscle gets (F224): the main muscles a full set, helpers half.
Map<String, double> setShare(Exercise e) {
  final r = <String, double>{};
  for (final m in e.secondary) {
    r[muscleOf(m)] = 0.5;
  }
  for (final m in e.primary) {
    r[muscleOf(m)] = 1;
  }
  return r;
}

/// Sets a week, for building muscle (F228). [mev] the least that still grows, [lo]-[hi] the range
/// most people grow best in, [mrv] about the most you can recover from.
class Landmarks {
  final int mev, lo, hi, mrv;
  const Landmarks(this.mev, this.lo, this.hi, this.mrv);
}

const landmarks = {
  'chest': Landmarks(8, 10, 20, 22),
  'back': Landmarks(10, 12, 22, 25),
  'shoulders': Landmarks(8, 12, 22, 26),
  'biceps': Landmarks(6, 8, 18, 24),
  'triceps': Landmarks(6, 8, 16, 20),
  'quads': Landmarks(8, 10, 18, 20),
  'hamstrings': Landmarks(6, 8, 16, 20),
  'glutes': Landmarks(2, 6, 14, 18),
  'calves': Landmarks(6, 8, 16, 20),
  'core': Landmarks(2, 6, 16, 25),
  'traps': Landmarks(0, 4, 14, 24),
  'forearms': Landmarks(0, 2, 10, 16),
};

/// The weekly range for this person (F225): lower for strength, fitness and new lifters; the
/// middle of the range for a priority muscle, the bottom for a "less work" one.
Landmarks muscleTarget(String m, Profile? p) {
  final l = landmarks[m] ?? const Landmarks(0, 4, 12, 20);
  var (lo, hi) = (l.lo.toDouble(), l.hi.toDouble());
  final g = p?.goal ?? Goal.both;
  if (g == Goal.strength || g == Goal.powerlifting) {
    lo *= 0.7;
    hi *= 0.8;
  } else if (g == Goal.fatLoss || g == Goal.fitness || g == Goal.sport) {
    lo *= 0.6;
    hi *= 0.7;
  }
  if (p?.experience == 'new') {
    lo *= 0.8;
    hi *= 0.8;
  }
  if (p?.special == m || (p?.priority.contains(m) ?? false)) lo = (lo + hi) / 2;
  if (p?.low.contains(m) ?? false) {
    hi = lo;
    lo = l.mev * 0.7;
  }
  return Landmarks(l.mev, lo.round(), hi.round(), l.mrv);
}

enum VolumeStatus { under, on, over, tooMuch }

const volumeWord = {VolumeStatus.under: 'under', VolumeStatus.on: 'on target', VolumeStatus.over: 'above', VolumeStatus.tooMuch: 'too much'};

VolumeStatus statusOf(String m, double sets, Profile? p) {
  final t = muscleTarget(m, p);
  if (sets + 0.01 < t.lo) return VolumeStatus.under;
  if (sets <= t.hi + 0.01) return VolumeStatus.on;
  if (sets <= t.mrv + 0.01) return VolumeStatus.over;
  return VolumeStatus.tooMuch;
}

/// "8 of 10-20" (F225).
String volumeText(double sets, Landmarks t) => '${fmtSets(sets)} of ${t.lo}-${t.hi}';
String fmtSets(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Plan days that make up one week: a program's first week, or the whole rotation.
List<PlanDay> _weekDays(Plan plan) => plan.weeksPerCycle > 1 ? plan.days.take(plan.daysPerWeek).toList() : plan.days;

/// Sets a week per muscle in a plan (F224-F226). [perWeek] = training days a week (a 3-day
/// rotation trained 2 days a week counts two thirds).
Map<String, double> planWeekSets(Plan plan, Library lib, {int? perWeek}) {
  final days = _weekDays(plan);
  if (days.isEmpty) return {};
  final f = plan.weeksPerCycle > 1 || perWeek == null ? 1.0 : perWeek / days.length;
  final out = <String, double>{};
  for (final d in days) {
    for (final it in d.items) {
      final e = lib.byId(it.exerciseId);
      if (e == null) continue;
      for (final x in setShare(e).entries) {
        out[x.key] = (out[x.key] ?? 0) + x.value * hardSets(it) * f;
      }
    }
  }
  return out;
}

/// Sets that count as hard work (P2-7): a % set under 65% of the training max is a ramp or
/// warm-up (nSuns' 40-60%, Madcow's 50 and 62.5%) and does not count, unless it is a long set:
/// 10+ reps at 45%+ is taken close enough to failure to count (5/3/1 BBB's 5x10 at 50%,
/// review 2 P3-N1).
int hardSets(PlanItem it) => it.perSet == null ? it.sets : it.perSet!.where((x) => x.pct == null || x.pct! >= 0.65 || (x.pct! >= 0.45 && x.reps >= 10)).length;

/// About how long a day takes, in minutes: work, rest, and a minute to set up each exercise.
int dayMinutes(PlanDay d, Library lib) {
  var secs = 0;
  for (final it in d.items) {
    final e = lib.byId(it.exerciseId);
    final work = e?.timed ?? false ? it.repHigh : 40;
    secs += 60 + it.sets * work + (it.sets - 1).clamp(0, 99) * it.restSec;
  }
  secs += (d.items.length - 1).clamp(0, 99) * 60; // rest before the next exercise
  return (secs / 60).round();
}

/// The plan maker's last step (F227): add a set where a muscle is under its range, take one off
/// where it is past what you can recover from, staying inside the time per session. Programs keep
/// their own sets.
Plan fitVolume(Plan plan, Profile p, Library lib) {
  if (plan.program != null || plan.weeksPerCycle > 1 || plan.days.isEmpty) return plan;
  final days = [for (final d in plan.days) [...d.items]];
  final f = p.days / days.length;
  final limit = p.minutes * 1.15;
  Map<String, double> week() => planWeekSets(Plan(name: '', days: [for (final d in days) PlanDay(name: '', items: d)]), lib, perWeek: p.days);
  int mins(int d) => dayMinutes(PlanDay(name: '', items: days[d]), lib);
  for (final m in priorityMuscles) {
    final t = muscleTarget(m, p);
    final top = p.low.contains(m) ? t.hi : t.mrv;
    for (var guard = 0; guard < 40; guard++) {
      final cur = week()[m] ?? 0;
      final under = cur + 0.01 < t.lo, over = cur > top + 0.01;
      if (!under && !over) break;
      if (under && cur + f > t.hi + 0.01) break; // one more set would overshoot
      final c = <(int, int)>[];
      for (var d = 0; d < days.length; d++) {
        for (var i = 0; i < days[d].length; i++) {
          final it = days[d][i];
          final e = lib.byId(it.exerciseId);
          if (e == null || it.perSet != null || setShare(e)[m] != 1) continue;
          if (under && it.sets < 5 && mins(d) + (40 + it.restSec) / 60 <= limit) c.add((d, i));
          if (over && it.sets > 2) c.add((d, i));
        }
      }
      if (c.isEmpty) break;
      c.sort((a, b) => under ? days[a.$1][a.$2].sets.compareTo(days[b.$1][b.$2].sets) : days[b.$1][b.$2].sets.compareTo(days[a.$1][a.$2].sets));
      final (d, i) = c.first;
      days[d][i] = days[d][i].copyWith(sets: days[d][i].sets + (under ? 1 : -1));
    }
  }
  return plan.copyWith(days: [for (var d = 0; d < days.length; d++) plan.days[d].copyWith(items: days[d])]);
}

/// Sets per muscle in a plan that look lopsided (F229): legs against upper body.
List<String> volumeWarnings(Plan plan, Library lib, {int? perWeek}) {
  final w = planWeekSets(plan, lib, perWeek: perWeek);
  double sum(List<String> ms) => ms.fold(0.0, (a, m) => a + (w[m] ?? 0));
  final legs = sum(const ['quads', 'hamstrings', 'glutes', 'calves']);
  final upper = sum(const ['chest', 'back', 'shoulders', 'biceps', 'triceps']);
  if (plan.days.length < 2 || upper == 0) return const [];
  if (legs == 0) return ['No leg work in this plan.'];
  if (upper > legs * 3) return ['Light on legs: about ${fmtSets(legs)} leg sets against ${fmtSets(upper)} upper-body sets a week.'];
  if (legs > upper * 2) return ['Light on upper body: about ${fmtSets(upper)} upper-body sets against ${fmtSets(legs)} leg sets a week.'];
  return const [];
}

/// Weekly sets (and kg lifted) per muscle from the log, oldest week first (F230). Week 0 starts
/// [weeks] weeks before [now].
({Map<String, List<double>> sets, Map<String, List<double>> kg}) weeklyMuscles(List<SetLog> log, Library lib, DateTime now, int weeks) {
  final start = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).subtract(Duration(days: 7 * weeks));
  final sets = {for (final m in volumeMuscles) m: List<double>.filled(weeks, 0)};
  final kg = {for (final m in volumeMuscles) m: List<double>.filled(weeks, 0)};
  for (final x in log) {
    if (!x.counts || x.at == null || x.at!.isBefore(start)) continue;
    final w = x.at!.difference(start).inDays ~/ 7;
    if (w >= weeks) continue;
    final e = lib.byId(x.exerciseId);
    if (e == null) continue;
    for (final s in setShare(e).entries) {
      if (!sets.containsKey(s.key)) continue;
      sets[s.key]![w] += s.value;
      kg[s.key]![w] += s.value * x.kg * x.reps;
    }
  }
  return (sets: sets, kg: kg);
}

// ---------- recovery (F232-F234) ----------

const _slow = {'quads', 'hamstrings', 'back', 'chest', 'glutes'};

/// Hours a hard session's tiredness takes to wear off: big muscles 72, the rest 48.
int recoveryHours(String m) => _slow.contains(m) ? 72 : 48;

class MuscleRecovery {
  final int pct; // 100 = fresh
  final DateTime? last; // last trained
  const MuscleRecovery(this.pct, this.last);
}

/// How rested each muscle is (F232): every recent set adds tiredness that fades over
/// [recoveryHours]; about ten hard sets just now = fully tired.
Map<String, MuscleRecovery> recovery(List<SetLog> log, Library lib, DateTime now) {
  final tired = <String, double>{}, last = <String, DateTime>{};
  for (final x in log) {
    if (!x.counts || x.at == null) continue;
    final e = lib.byId(x.exerciseId);
    if (e == null) continue;
    final h = now.difference(x.at!).inMinutes / 60;
    final hard = switch (x.effort) { 4 => 1.3, 1 => 0.7, _ => 1.0 };
    for (final s in setShare(e).entries) {
      final l = last[s.key];
      if (l == null || x.at!.isAfter(l)) last[s.key] = x.at!;
      final r = recoveryHours(s.key);
      if (h >= 0 && h < r) tired[s.key] = (tired[s.key] ?? 0) + s.value * hard * (1 - h / r);
    }
  }
  return {for (final m in volumeMuscles) m: MuscleRecovery((100 - (tired[m] ?? 0) * 10).clamp(0, 100).round(), last[m])};
}

/// How rested a day's main muscles are, weighted by their sets (100 = fresh).
int dayReadiness(PlanDay d, Map<String, MuscleRecovery> r, Library lib) {
  var w = 0.0, sum = 0.0;
  for (final it in d.items) {
    final e = lib.byId(it.exerciseId);
    if (e == null) continue;
    for (final s in setShare(e).entries) {
      if (s.value < 1) continue;
      w += it.sets;
      sum += it.sets * (r[s.key]?.pct ?? 100);
    }
  }
  return w == 0 ? 100 : (sum / w).round();
}

/// The day's least rested main muscle, for "too soon" (F232).
(String, MuscleRecovery)? leastRested(PlanDay d, Map<String, MuscleRecovery> r, Library lib) {
  (String, MuscleRecovery)? out;
  for (final it in d.items) {
    final e = lib.byId(it.exerciseId);
    if (e == null) continue;
    for (final m in e.primary.map(muscleOf)) {
      final x = r[m];
      if (x != null && (out == null || x.pct < out.$2.pct)) out = (m, x);
    }
  }
  return out;
}

/// "1 day ago" for a muscle's last workout.
String agoText(DateTime? t, DateTime now) {
  if (t == null) return 'not yet';
  final d = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  return d <= 0 ? 'today' : (d == 1 ? 'yesterday' : '$d days ago');
}

/// Days in a row with a workout, ending yesterday or today (F234).
int trainingStreak(Iterable<DateTime> workoutDays, DateTime now) {
  final days = {for (final t in workoutDays) DateTime(t.year, t.month, t.day)};
  var d = DateTime(now.year, now.month, now.day);
  if (!days.contains(d)) d = d.subtract(const Duration(days: 1));
  var n = 0;
  while (days.contains(d)) {
    n++;
    d = d.subtract(const Duration(days: 1));
  }
  return n;
}

/// Within a workout (F233): sets the muscle already did today beyond what the plan puts before
/// this exercise. Three or more extra sets make the next weight a little lighter.
double extraSetsBefore(Exercise e, List<SetLog> done, List<PlanItem> planned, Library lib) {
  final muscles = e.primary.map(muscleOf).toSet();
  double load(Exercise x, int sets) => muscles.fold(0.0, (a, m) => a + (setShare(x)[m] ?? 0)) / muscles.length * sets;
  var did = 0.0;
  for (final x in done) {
    if (!x.counts || x.exerciseId == e.id) continue;
    final xe = lib.byId(x.exerciseId);
    if (xe != null) did += load(xe, 1);
  }
  var plan = 0.0;
  for (final it in planned) {
    if (it.exerciseId == e.id) break;
    final xe = lib.byId(it.exerciseId);
    if (xe != null) plan += load(xe, it.sets);
  }
  return did - plan;
}

/// 2.5% lighter per three extra sets, at most 10% (F233).
double fatigueFactor(double extra) => extra < 3 ? 1 : (1 - 0.025 * (extra / 3).floor()).clamp(0.9, 1.0);

// ---------- pregnancy / after a birth (F237) ----------

const pregnancyLabel = {'pregnant': 'Pregnant', 'postpartum': 'Had a baby (last year)'};

const _crunching = {'crunch', 'cable_crunch', 'machine_crunch', 'decline_situp', 'russian_twist', 'lying_leg_raise', 'hanging_leg_raise', 'captains_chair', 'toes_to_bar', 'dragon_flag', 'ab_wheel', 'hollow_hold', 'reverse_crunch', 'weighted_plank'};
const _impact = {'box_jump', 'power_clean', 'hang_clean', 'hang_power_snatch', 'clean_and_jerk', 'db_snatch', 'kb_snatch', 'thruster', 'db_thruster', 'med_ball_slam', 'kb_swing', 'push_press', 'pistol_squat', 'nordic_curl', 'glute_ham_raise'};

/// Exercises left out while pregnant or after a birth: crunches and sit-ups, jumps and fast
/// Olympic lifts, and (pregnant) lying flat on the back or front. A starting point to talk
/// over with a midwife or doctor, not medical advice.
/// Lying on the back or front comes from the exercise data ([Exercise.position]); pass the library.
Set<String> cautionIds(String? mode, [Library? lib]) => switch (mode) {
      'pregnant' => {..._crunching, ..._impact, for (final e in lib?.all ?? const <Exercise>[]) if (e.position.isNotEmpty) e.id},
      'postpartum' => {..._crunching, ..._impact},
      _ => const {},
    };

const pregnancyHelp = 'Leaves out crunches and sit-ups, jumps and fast Olympic lifts, and while pregnant also moves lying '
    'flat on your back or front. No all-out or + sets. Get your midwife\'s or doctor\'s OK first, and stop and ask them '
    'if anything hurts, you feel dizzy, faint or short of breath, or you bleed or leak fluid.';
