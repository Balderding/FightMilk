import 'exercise.dart';
import 'library.dart';
import 'plan.dart';
import 'volume.dart';

/// Built-in plan maker (used when the AI is off, and as the fallback when an AI answer is bad).
///
/// Each day is a list of swap groups in priority order; the first is the day's main lift.
/// The maker walks the list, picks the best exercise this gym has for each group (skipping
/// sore joints and exercises already in the day), and stops at the session-length cap.

const _slots = <String, List<String>>{
  'Full body A': ['squat', 'chest_press', 'row', 'ham_curl', 'lateral_raise', 'biceps', 'triceps', 'calf'],
  'Full body B': ['hinge', 'incline_press', 'vertical_pull', 'lunge', 'rear_delt', 'triceps', 'core', 'calf'],
  'Full body C': ['chest_press', 'squat', 'row', 'glute', 'overhead_press', 'biceps', 'ham_curl', 'core'],
  'Upper A': ['chest_press', 'row', 'overhead_press', 'vertical_pull', 'biceps', 'triceps', 'lateral_raise', 'rear_delt'],
  'Lower A': ['squat', 'hinge', 'quad_iso', 'ham_curl', 'calf', 'core', 'glute_iso', 'adductor'],
  'Upper B': ['incline_press', 'vertical_pull', 'row', 'lateral_raise', 'chest_fly', 'biceps', 'triceps', 'rear_delt'],
  'Lower B': ['hinge', 'squat', 'lunge', 'ham_curl', 'glute', 'calf', 'quad_iso', 'core'],
  'Push A': ['chest_press', 'overhead_press', 'incline_press', 'lateral_raise', 'triceps', 'chest_fly', 'triceps', 'core'],
  'Pull A': ['row', 'vertical_pull', 'rear_delt', 'biceps', 'lat_iso', 'shrug', 'biceps', 'forearm'],
  'Legs A': ['squat', 'hinge', 'quad_iso', 'ham_curl', 'calf', 'glute_iso', 'core', 'adductor'],
  'Push B': ['overhead_press', 'incline_press', 'chest_press', 'chest_fly', 'lateral_raise', 'triceps', 'triceps', 'rear_delt'],
  'Pull B': ['vertical_pull', 'row', 'lat_iso', 'rear_delt', 'biceps', 'biceps', 'shrug', 'core'],
  'Legs B': ['hinge', 'squat', 'lunge', 'ham_curl', 'glute', 'calf', 'quad_iso', 'core'],
  'Chest': ['chest_press', 'incline_press', 'chest_fly', 'chest_press', 'triceps', 'core', 'chest_fly', 'triceps'],
  'Back': ['row', 'vertical_pull', 'lat_iso', 'row', 'rear_delt', 'shrug', 'biceps', 'forearm'],
  'Shoulders': ['overhead_press', 'lateral_raise', 'rear_delt', 'lateral_raise', 'shrug', 'overhead_press', 'core', 'rear_delt'],
  'Arms': ['triceps', 'biceps', 'triceps', 'biceps', 'forearm', 'biceps', 'triceps', 'core'],
  // PHUL: power days lead with heavy compounds, hypertrophy days with more isolation
  'Upper power': ['chest_press', 'row', 'incline_press', 'vertical_pull', 'overhead_press', 'biceps', 'triceps', 'rear_delt'],
  'Lower power': ['squat', 'hinge', 'lunge', 'ham_curl', 'calf', 'core', 'quad_iso', 'glute'],
  'Upper hypertrophy': ['incline_press', 'chest_fly', 'row', 'lat_iso', 'lateral_raise', 'biceps', 'triceps', 'rear_delt'],
  'Lower hypertrophy': ['squat', 'lunge', 'quad_iso', 'ham_curl', 'glute_iso', 'calf', 'adductor', 'core'],
  'Full body': ['squat', 'chest_press', 'row', 'hinge', 'overhead_press', 'biceps', 'triceps', 'calf'],
  // Arnold: chest and back together, shoulders and arms together
  'Chest & back': ['chest_press', 'row', 'incline_press', 'vertical_pull', 'chest_fly', 'lat_iso', 'core', 'shrug'],
  'Shoulders & arms': ['overhead_press', 'lateral_raise', 'biceps', 'triceps', 'rear_delt', 'biceps', 'triceps', 'forearm'],
  // torso / limbs
  'Torso': ['chest_press', 'row', 'overhead_press', 'vertical_pull', 'incline_press', 'chest_fly', 'rear_delt', 'core'],
  'Limbs': ['squat', 'hinge', 'biceps', 'triceps', 'quad_iso', 'ham_curl', 'lateral_raise', 'calf'],
};

/// Same content as A, plainer name when a split has only one of each.
const _alias = {'Upper': 'Upper A', 'Lower': 'Lower A', 'Push': 'Push A', 'Pull': 'Pull A', 'Legs': 'Legs A'};

const splitLabel = {
  'full_body': 'Full body',
  'upper_lower': 'Upper / lower',
  'ppl': 'Push / pull / legs',
  'bro': 'One muscle group a day',
  'phul': 'Power and size upper / lower (PHUL)',
  'ul_fb': 'Upper / lower + full body',
  'arnold': 'Chest & back, shoulders & arms, legs',
  'torso_limbs': 'Torso / limbs',
  'pplul': 'Push / pull / legs / upper / lower',
};

/// Plain help for each split, shown in setup.
const splitHelp = {
  'full_body': 'The whole body each time. Best for 1-3 days.',
  'upper_lower': 'Upper body one day, legs the next. Good for 2-4 days.',
  'ppl': 'Pushing, pulling, then legs. 3 or 6 days.',
  'bro': 'One area a day, lots of sets for it. 5 days.',
  'phul': 'Two heavy days and two size days. 4 days.',
  'ul_fb': 'Upper, lower, then a full-body day. 3 days.',
  'arnold': 'Chest with back, shoulders with arms, legs. 3 or 6 days.',
  'torso_limbs': 'Trunk muscles one day, arms and legs the next. 2 or 4 days.',
  'pplul': 'Push, pull, legs, then upper and lower. 5 days.',
};

List<String> dayNames(int days, String? split) {
  switch (split) {
    case 'phul':
      return ['Upper power', 'Lower power', 'Upper hypertrophy', 'Lower hypertrophy'];
    case 'ul_fb':
      return ['Upper', 'Lower', 'Full body'];
    case 'arnold':
      return days >= 6 ? ['Chest & back', 'Shoulders & arms', 'Legs A', 'Chest & back', 'Shoulders & arms', 'Legs B'] : ['Chest & back', 'Shoulders & arms', 'Legs'];
    case 'torso_limbs':
      return days >= 4 ? ['Torso', 'Limbs', 'Torso', 'Limbs'] : ['Torso', 'Limbs'];
    case 'pplul':
      return ['Push', 'Pull', 'Legs', 'Upper', 'Lower'];
    case 'full_body':
      return days <= 2 ? ['Full body A', 'Full body B'] : ['Full body A', 'Full body B', 'Full body C'];
    case 'upper_lower':
      return days <= 3 ? ['Upper', 'Lower'] : ['Upper A', 'Lower A', 'Upper B', 'Lower B'];
    case 'ppl':
      return days >= 6 ? ['Push A', 'Pull A', 'Legs A', 'Push B', 'Pull B', 'Legs B'] : ['Push', 'Pull', 'Legs'];
    case 'bro':
      return ['Chest', 'Back', 'Shoulders', 'Legs', 'Arms'];
  }
  return switch (days) {
    <= 1 => ['Full body'],
    2 => ['Full body A', 'Full body B'],
    3 => ['Full body A', 'Full body B', 'Full body C'],
    4 => ['Upper A', 'Lower A', 'Upper B', 'Lower B'],
    5 => ['Upper', 'Lower', 'Push', 'Pull', 'Legs'],
    6 => ['Push A', 'Pull A', 'Legs A', 'Push B', 'Pull B', 'Legs B'],
    _ => ['Push A', 'Pull A', 'Legs A', 'Push B', 'Pull B', 'Legs B', 'Full body'],
  };
}

/// Session lengths the setup offers (F198).
const sessionLengths = [20, 30, 45, 60, 75, 90, 120];

int capFor(int minutes) => switch (minutes) { <= 20 => 3, <= 30 => 4, <= 45 => 5, <= 60 => 6, <= 75 => 7, <= 90 => 8, _ => 9 };

const _mainPref = [Equipment.barbell, Equipment.machine, Equipment.dumbbell, Equipment.smith, Equipment.cable, Equipment.kettlebell, Equipment.bodyweight, Equipment.band];
/// Accessories that change at a new block (F205): the next exercise of the same kind this gym has.
Plan rotateAccessories(Plan plan, Profile p, Library lib) {
  final days = <PlanDay>[];
  for (final d in plan.days) {
    final used = {for (final it in d.items) it.exerciseId};
    days.add(d.copyWith(items: [
      for (var i = 0; i < d.items.length; i++)
        () {
          final it = d.items[i];
          final e = lib.byId(it.exerciseId);
          if (i == 0 || e == null || e.compound || it.perSet != null || (plan.program?.rules.containsKey(liftKey(it)) ?? false)) return it;
          final cands = [for (final x in lib.all) if (x.swap == e.swap && x.id != e.id && !used.contains(x.id) && lib.usable(x, p.have, p.avoid, items: p.items)) x];
          if (cands.isEmpty) return it;
          // the one after this in library order, so a rotation walks through the group
          final all = [for (final x in lib.all) if (x.swap == e.swap) x.id];
          final at = all.indexOf(e.id);
          final next = cands.firstWhere((x) => all.indexOf(x.id) > at, orElse: () => cands.first);
          used.add(next.id);
          return it.copyWith(exerciseId: next.id);
        }()
    ]));
  }
  return plan.copyWith(days: days);
}

const _accPref = [Equipment.machine, Equipment.cable, Equipment.dumbbell, Equipment.barbell, Equipment.smith, Equipment.kettlebell, Equipment.band, Equipment.bodyweight];

/// Sets / reps / rest for one exercise in a given role. [experience]: 'new' does a set less on the
/// main lift, 'years' a set more on the others (F196).
PlanItem itemFor(Exercise e, Goal goal, {required bool main, String experience = 'some'}) {
  final short = goal == Goal.fitness || goal == Goal.fatLoss; // shorter rests
  if (e.timed) return PlanItem(exerciseId: e.id, sets: 3, repLow: e.repLow, repHigh: e.repHigh, restSec: 60);
  if (main) {
    final (lo, hi, rest) = switch (goal) {
      Goal.strength || Goal.powerlifting || Goal.sport => (3, 6, 180),
      Goal.size => (8, 12, 120),
      Goal.both || Goal.powerbuilding => (5, 8, 150),
      Goal.fatLoss => (6, 10, 120),
      Goal.fitness => (10, 15, 75),
    };
    return PlanItem(exerciseId: e.id, sets: experience == 'new' ? 3 : 4, repLow: lo, repHigh: hi, restSec: rest);
  }
  final extra = experience == 'years' ? 1 : 0;
  if (e.compound) {
    final (lo, hi) = switch (goal) { Goal.strength || Goal.powerlifting || Goal.sport || Goal.powerbuilding => (5, 8), Goal.fitness => (12, 15), _ => (8, 12) };
    return PlanItem(exerciseId: e.id, sets: 3 + extra, repLow: lo, repHigh: hi, restSec: short ? 75 : 120);
  }
  return PlanItem(exerciseId: e.id, sets: 3 + extra, repLow: goal == Goal.fitness ? 12 : 10, repHigh: goal == Goal.fitness ? 20 : 15, restSec: short ? 60 : 75);
}

/// One-leg / one-arm work (F204: bilateral first, a unilateral option on leg days).
bool unilateral(Exercise e) => RegExp(r'single|one_arm|lunge|split_squat|pistol|step_up|curtsy|suitcase').hasMatch(e.id);

/// Exercises that load the muscle at its longest (F204 stretch options): chosen first among equals.
const stretchFirst = {'incline_db_curl', 'bayesian_curl', 'overhead_cable_ext', 'db_overhead_ext', 'seated_leg_curl', 'romanian_deadlift', 'db_fly', 'low_cable_fly', 'deficit_push_up', 'lean_away_lateral', 'single_arm_pulldown', 'kneeling_lat_pulldown', 'sissy_squat', 'standing_calf_raise'};

/// Push or pull for the balance check: null for legs and core.
String? pushPull(Exercise e) {
  final m = e.primary.first;
  if (m == 'chest' || m == 'triceps' || (m == 'shoulders' && e.pattern != 'rear_delt' && e.swap != 'rear_delt')) return 'push';
  if (m == 'back' || m == 'lats' || m == 'biceps' || e.swap == 'rear_delt' || e.swap == 'row' || e.swap == 'vertical_pull') return 'pull';
  return null;
}

List<Exercise> _pick(List<String> groups, Profile p, Library lib, Map<String, int> uses, int cap) {
  final picked = <Exercise>[];
  for (final g in groups) {
    if (picked.length >= cap) break;
    final main = picked.isEmpty;
    final pref = main ? _mainPref : _accPref;
    final cands = [
      for (final e in lib.all)
        if (e.swap == g && lib.usable(e, p.have, p.avoid, items: p.items) && !picked.contains(e)) e
    ];
    if (cands.isEmpty) continue;
    cands.sort((a, b) {
      if (main && a.compound != b.compound) return a.compound ? -1 : 1;
      if (main && unilateral(a) != unilateral(b)) return unilateral(a) ? 1 : -1; // two legs before one
      final fa = lib.favs.contains(a.id), fb = lib.favs.contains(b.id);
      if (fa != fb) return fa ? -1 : 1; // your favourites first
      final u = (uses[a.id] ?? 0).compareTo(uses[b.id] ?? 0);
      if (u != 0) return u;
      if (!main && stretchFirst.contains(a.id) != stretchFirst.contains(b.id)) return stretchFirst.contains(a.id) ? -1 : 1;
      if (p.experience == 'new' && !main && (a.equipment == Equipment.machine) != (b.equipment == Equipment.machine)) return a.equipment == Equipment.machine ? -1 : 1;
      return pref.indexOf(a.equipment).compareTo(pref.indexOf(b.equipment));
    });
    picked.add(cands.first);
    uses[cands.first.id] = (uses[cands.first.id] ?? 0) + 1;
  }
  // Lead with a compound if the day has one.
  final ci = picked.indexWhere((e) => e.compound);
  if (ci > 0) picked.insert(0, picked.removeAt(ci));
  return orderDay(picked);
}

/// Big before small (F204): the main lift stays first, then two-leg compounds, one-leg
/// compounds, then isolation work; the order inside each group is kept.
List<Exercise> orderDay(List<Exercise> l) {
  if (l.length < 3) return l;
  int rank(Exercise e) => e.compound ? (unilateral(e) ? 1 : 0) : (e.timed ? 3 : 2);
  final rest = [...l.skip(1)];
  final idx = {for (var i = 0; i < rest.length; i++) rest[i]: i};
  rest.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : idx[a]!.compareTo(idx[b]!);
  });
  return [l.first, ...rest];
}

/// Sets after priority / low-priority muscles and a specialisation block (F200, F201).
PlanItem _weighted(PlanItem it, Exercise e, Profile p, {required bool main}) {
  final m = e.primary.first;
  var n = it.sets;
  if (p.special != null) {
    if (m == p.special) {
      n += 2;
    } else if (!main) {
      n -= 1; // the others are held, not grown
    }
  } else if (p.priority.contains(m)) {
    n += 1;
  } else if (p.low.contains(m) && !main) {
    n -= 1;
  }
  return n == it.sets ? it : it.copyWith(sets: n.clamp(2, 6));
}

/// Swap groups that give a muscle its main work (for the twice-a-week and balance checks).
const _muscleGroup = {'chest': 'chest_press', 'back': 'row', 'quads': 'squat', 'hamstrings': 'ham_curl', 'shoulders': 'lateral_raise', 'glutes': 'glute', 'biceps': 'biceps', 'triceps': 'triceps', 'calves': 'calf', 'core': 'core'};

Plan makePlan(Profile p, Library lib, {String? name}) {
  final names = dayNames(p.days, p.split);
  final cap = capFor(p.minutes);
  final uses = <String, int>{}; // spread variety across the week
  final picks = <List<Exercise>>[];
  for (final dn in names) {
    var groups = _slots[_alias[dn] ?? dn]!;
    // a priority or focus muscle gets one more exercise on days that train it (F200, F201)
    final extra = {if (p.special != null) p.special!, ...p.priority};
    for (final m in extra) {
      final g = _muscleGroup[m];
      if (g != null && groups.contains(g)) groups = [...groups.take(2), g, ...groups.skip(2)];
    }
    picks.add(_pick(groups, p, lib, uses, cap + (extra.isEmpty ? 0 : 1)));
  }
  _balance(picks, p, lib, cap);
  final days = <PlanDay>[
    for (var d = 0; d < names.length; d++)
      PlanDay(name: names[d], items: [for (var i = 0; i < picks[d].length; i++) _weighted(itemFor(picks[d][i], p.goal, main: i == 0, experience: p.experience), picks[d][i], p, main: i == 0)])
  ];
  final label = p.special != null ? '${p.special![0].toUpperCase()}${p.special!.substring(1)} focus block' : (p.split != null ? splitLabel[p.split]! : '${p.days}-day plan');
  return fitVolume(Plan(name: name ?? label, days: days), p, lib);
}

/// Week-level checks (F204): each big muscle at least twice a week when there are 3+ days, and
/// not much more pushing than pulling. Fixes add one exercise to a day that has room.
void _balance(List<List<Exercise>> days, Profile p, Library lib, int cap) {
  if (days.length < 2) return;
  bool hits(List<Exercise> d, String m) => d.any((e) => e.primary.first == m);
  void addTo(String group, {required bool Function(List<Exercise>) where}) {
    final order = [for (var i = 0; i < days.length; i++) i]..sort((a, b) => days[a].length.compareTo(days[b].length));
    for (final i in order) {
      final d = days[i];
      if (!where(d) || d.length > cap) continue;
      final got = _pick([group], p, lib, {}, 1).where((e) => !d.contains(e)).toList();
      if (got.isNotEmpty) {
        d.add(got.first);
        days[i] = orderDay(d);
        return;
      }
    }
  }

  if (days.length >= 3 && p.split != 'bro') {
    for (final m in const ['chest', 'back', 'quads', 'hamstrings']) {
      final n = days.where((d) => hits(d, m)).length;
      if (n == 1) {
        final upper = m == 'chest' || m == 'back';
        addTo(_muscleGroup[m]!, where: (d) => !hits(d, m) && d.any((e) => upper ? pushPull(e) != null : pushPull(e) == null));
      }
    }
  }
  var push = 0, pull = 0;
  for (final d in days) {
    for (final e in d) {
      final k = pushPull(e);
      if (k == 'push') push++;
      if (k == 'pull') pull++;
    }
  }
  if (pull > 0 && push > pull * 1.5 || (pull == 0 && push >= 3)) addTo('rear_delt', where: (d) => d.any((e) => pushPull(e) == 'push'));
}

/// Lopsided plan check for the plan page: plain warnings, empty when it looks fine.
List<String> planWarnings(Plan plan, Library lib) {
  var push = 0, pull = 0;
  final seen = <String, int>{};
  for (final d in plan.days) {
    final today = <String>{};
    for (final it in d.items) {
      final e = lib.byId(it.exerciseId);
      if (e == null) continue;
      final k = pushPull(e);
      if (k == 'push') push += it.sets;
      if (k == 'pull') pull += it.sets;
      today.add(e.primary.first);
    }
    for (final m in today) {
      seen[m] = (seen[m] ?? 0) + 1;
    }
  }
  return [
    if (pull > 0 && push > pull * 2) 'About ${(push / pull).toStringAsFixed(1)}× more pushing than pulling sets: think about a row or face pulls.',
    if (push + pull > 0 && pull == 0) 'No pulling work (rows, pull-downs).',
    if ((seen['quads'] ?? 0) > 0 && (seen['hamstrings'] ?? 0) == 0) 'No hamstring work: a leg curl or a hinge would balance it.',
    ...volumeWarnings(plan, lib),
  ];
}

/// The muscle areas a one-off day can be built from (see [makeDayFor]).
const dayAreas = <String, List<String>>{
  'chest': ['chest_press', 'incline_press', 'chest_fly'],
  'back': ['row', 'vertical_pull', 'lat_iso', 'shrug'],
  'shoulders': ['overhead_press', 'lateral_raise', 'rear_delt'],
  'biceps': ['biceps', 'biceps'],
  'triceps': ['triceps', 'triceps'],
  'arms': ['triceps', 'biceps', 'forearm'],
  'quads': ['squat', 'quad_iso', 'lunge'],
  'hamstrings': ['hinge', 'ham_curl'],
  'glutes': ['glute', 'glute_iso'],
  'calves': ['calf'],
  'legs': ['squat', 'hinge', 'quad_iso', 'ham_curl', 'calf', 'glute_iso'],
  'core': ['core', 'core'],
  'upper': ['chest_press', 'row', 'overhead_press', 'vertical_pull', 'biceps', 'triceps'],
  'lower': ['squat', 'hinge', 'quad_iso', 'ham_curl', 'calf'],
  'push': ['chest_press', 'overhead_press', 'incline_press', 'lateral_raise', 'triceps'],
  'pull': ['row', 'vertical_pull', 'rear_delt', 'biceps', 'shrug'],
  'full': ['squat', 'chest_press', 'row', 'hinge', 'overhead_press', 'biceps', 'triceps'],
};

/// A one-off day for the areas asked for ("chest, shoulders and arms"): their slots taken in turn,
/// from this gym's exercises, within the session length.
PlanDay makeDayFor(List<String> areas, Profile p, Library lib, {int? minutes, String? name}) {
  final lists = [for (final a in areas) dayAreas[a] ?? const <String>[]];
  final groups = <String>[];
  for (var i = 0; lists.any((l) => i < l.length); i++) {
    for (final l in lists) {
      if (i < l.length) groups.add(l[i]);
    }
  }
  final picked = _pick(groups, p, lib, {}, capFor(minutes ?? p.minutes));
  return PlanDay(name: name ?? areas.join(' '), items: [for (var i = 0; i < picked.length; i++) itemFor(picked[i], p.goal, main: i == 0, experience: p.experience)]);
}
