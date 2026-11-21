import 'exercise.dart';
import 'library.dart';
import 'plan.dart';

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
};

/// Same content as A, plainer name when a split has only one of each.
const _alias = {'Upper': 'Upper A', 'Lower': 'Lower A', 'Push': 'Push A', 'Pull': 'Pull A', 'Legs': 'Legs A'};

const splitLabel = {
  'full_body': 'Full body',
  'upper_lower': 'Upper / lower',
  'ppl': 'Push / pull / legs',
  'bro': 'One muscle group a day',
};

List<String> dayNames(int days, String? split) {
  switch (split) {
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
    <= 2 => ['Full body A', 'Full body B'],
    3 => ['Full body A', 'Full body B', 'Full body C'],
    4 => ['Upper A', 'Lower A', 'Upper B', 'Lower B'],
    5 => ['Upper', 'Lower', 'Push', 'Pull', 'Legs'],
    _ => ['Push A', 'Pull A', 'Legs A', 'Push B', 'Pull B', 'Legs B'],
  };
}

int capFor(int minutes) => minutes <= 45 ? 5 : (minutes <= 60 ? 6 : 8);

const _mainPref = [Equipment.barbell, Equipment.machine, Equipment.dumbbell, Equipment.smith, Equipment.cable, Equipment.kettlebell, Equipment.bodyweight, Equipment.band];
const _accPref = [Equipment.machine, Equipment.cable, Equipment.dumbbell, Equipment.barbell, Equipment.smith, Equipment.kettlebell, Equipment.band, Equipment.bodyweight];

/// Sets / reps / rest for one exercise in a given role.
PlanItem itemFor(Exercise e, Goal goal, {required bool main}) {
  if (e.timed) return PlanItem(exerciseId: e.id, sets: 3, repLow: e.repLow, repHigh: e.repHigh, restSec: 60);
  if (main) {
    final (lo, hi, rest) = switch (goal) { Goal.strength => (3, 6, 180), Goal.size => (8, 12, 120), Goal.both => (5, 8, 150) };
    return PlanItem(exerciseId: e.id, sets: 4, repLow: lo, repHigh: hi, restSec: rest);
  }
  if (e.compound) {
    final (lo, hi) = goal == Goal.strength ? (5, 8) : (8, 12);
    return PlanItem(exerciseId: e.id, sets: 3, repLow: lo, repHigh: hi, restSec: 120);
  }
  return PlanItem(exerciseId: e.id, sets: 3, repLow: 10, repHigh: 15, restSec: 75);
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
      final fa = lib.favs.contains(a.id), fb = lib.favs.contains(b.id);
      if (fa != fb) return fa ? -1 : 1; // your favourites first
      final u = (uses[a.id] ?? 0).compareTo(uses[b.id] ?? 0);
      if (u != 0) return u;
      return pref.indexOf(a.equipment).compareTo(pref.indexOf(b.equipment));
    });
    picked.add(cands.first);
    uses[cands.first.id] = (uses[cands.first.id] ?? 0) + 1;
  }
  // Lead with a compound if the day has one.
  final ci = picked.indexWhere((e) => e.compound);
  if (ci > 0) picked.insert(0, picked.removeAt(ci));
  return picked;
}

Plan makePlan(Profile p, Library lib, {String? name}) {
  final names = dayNames(p.days, p.split);
  final cap = capFor(p.minutes);
  final uses = <String, int>{}; // spread variety across the week
  final days = <PlanDay>[];
  for (final dn in names) {
    final picked = _pick(_slots[_alias[dn] ?? dn]!, p, lib, uses, cap);
    days.add(PlanDay(name: dn, items: [for (var i = 0; i < picked.length; i++) itemFor(picked[i], p.goal, main: i == 0)]));
  }
  return Plan(name: name ?? (p.split != null ? splitLabel[p.split]! : '${p.days}-day plan'), days: days);
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
  return PlanDay(name: name ?? areas.join(' '), items: [for (var i = 0; i < picked.length; i++) itemFor(picked[i], p.goal, main: i == 0)]);
}
