import 'exercise.dart';
import 'units.dart';

/// What the app remembers per exercise (not per plan slot), so progress follows the lift
/// through plan edits, remakes and swaps.
class LiftState {
  final String exerciseId;
  final double workKg; // working weight (added weight for bodyweight lifts)
  final int misses; // sessions in a row with a set below the rep range
  final int? workReps; // bodyweight lifts: target reps
  final DateTime? updated;
  final int tops; // sessions in a row at the top of the range (the slow setting waits for 2)

  const LiftState({required this.exerciseId, required this.workKg, this.misses = 0, this.workReps, this.updated, this.tops = 0});

  LiftState copyWith({double? workKg, int? misses, int? workReps, int? tops}) => LiftState(
        exerciseId: exerciseId,
        workKg: workKg ?? this.workKg,
        misses: misses ?? this.misses,
        workReps: workReps ?? this.workReps,
        updated: DateTime.now(),
        tops: tops ?? this.tops,
      );

  Map<String, dynamic> toJson() => {
        'exercise_id': exerciseId,
        'work_kg': workKg,
        'misses': misses,
        'work_reps': workReps,
        'updated': updated?.millisecondsSinceEpoch,
        if (tops != 0) 'tops': tops,
      };

  factory LiftState.fromJson(Map<String, dynamic> j) => LiftState(
        exerciseId: j['exercise_id'] as String,
        workKg: (j['work_kg'] as num).toDouble(),
        misses: (j['misses'] ?? 0) as int,
        workReps: j['work_reps'] as int?,
        updated: j['updated'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['updated'] as int),
        tops: (j['tops'] ?? 0) as int,
      );
}

/// The person's progression settings (Settings → Progression), set by the app before use.
class ProgressRules {
  final String speed; // 'slow' (2 sessions at the top), 'steady' (1 step), 'fast' (2 steps)
  final int missesToDrop; // sessions in a row short of the range before the weight drops
  final double dropPct; // how much it drops, 0.10 = 10 %
  final bool effort; // the Easy/Hard taps change the jump
  final Map<String, String> scheme; // exercise id -> 'double' (default) | 'linear'
  final Map<String, double> stepKg; // exercise id -> its own weight step (kg)
  const ProgressRules({this.speed = 'steady', this.missesToDrop = 2, this.dropPct = 0.10, this.effort = true, this.scheme = const {}, this.stepKg = const {}});
}

ProgressRules progressRules = const ProgressRules();

/// Double progression, applied after a session in which [sets] of exercise [e] were logged.
///
/// [repLow]/[repHigh] default to the exercise's own range; pass the plan item's range when known.
/// - every set at the top of the range  -> add one step next time
/// - any set below the bottom of range  -> a miss; the 2nd miss in a row drops ~10 % (to a step)
/// - otherwise                          -> same weight, misses reset
/// Bodyweight lifts (no added weight yet, or any added weight) climb reps first; at the top of
/// the range they add one step of weight and go back to the bottom of the range.
LiftState nextLift(LiftState s, Exercise e, List<SetLog> sets, Unit u, {int? repLow, int? repHigh}) {
  if (sets.isEmpty) return s;
  final rules = progressRules;
  final lo = repLow ?? e.repLow, hi = repHigh ?? e.repHigh;
  final worked = sets.map((x) => x.kg).reduce((a, b) => a > b ? a : b);
  final minReps = sets.map((x) => x.reps).reduce((a, b) => a < b ? a : b);
  final step = rules.stepKg[e.id] ?? stepKg(e.step, u);
  double up(int n) => rules.stepKg.containsKey(e.id) ? worked + n * step : roundToStep(worked + n * step, e.step, u);
  final drop = rules.missesToDrop.clamp(1, 9);

  if (e.bodyweight) {
    final target = s.workReps ?? lo;
    if (minReps < lo) {
      return s.copyWith(misses: s.misses + 1 >= 2 ? 0 : s.misses + 1, workReps: s.misses + 1 >= 2 ? lo : target);
    }
    if (minReps >= hi) {
      return s.copyWith(workKg: roundToStep(worked + stepKg(e.step, u), e.step, u), workReps: lo, misses: 0);
    }
    return s.copyWith(workKg: worked, workReps: minReps >= target ? target + 1 : target, misses: 0);
  }

  // linear: a step every session that reaches the bottom of the range
  if (rules.scheme[e.id] == 'linear' && minReps >= lo) {
    return s.copyWith(workKg: up(1), misses: 0, tops: 0);
  }
  if (minReps >= hi) {
    final efforts = [for (final x in sets) if (x.effort != null) x.effort!];
    final easy = rules.effort && efforts.isNotEmpty && efforts.every((x) => x == 1);
    final allOut = rules.effort && efforts.contains(4);
    final amrapBig = sets.any((x) => x.type == SetType.amrap && x.reps >= hi + 3);
    if (rules.speed == 'slow' && !easy && s.tops < 1) return s.copyWith(workKg: worked, misses: 0, tops: s.tops + 1);
    var n = rules.speed == 'fast' ? 2 : 1;
    if (easy || amrapBig) n += 1;
    if (allOut) n = 1; // it was a grind: one step only
    return s.copyWith(workKg: up(n), misses: 0, tops: 0);
  }
  if (minReps < lo) {
    final m = s.misses + 1;
    if (m >= drop) return s.copyWith(workKg: roundToStep(worked * (1 - rules.dropPct), e.step, u), misses: 0, tops: 0);
    return s.copyWith(workKg: worked, misses: m, tops: 0);
  }
  return s.copyWith(workKg: worked, misses: 0, tops: 0);
}
