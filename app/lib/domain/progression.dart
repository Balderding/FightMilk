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

  const LiftState({required this.exerciseId, required this.workKg, this.misses = 0, this.workReps, this.updated});

  LiftState copyWith({double? workKg, int? misses, int? workReps}) => LiftState(
        exerciseId: exerciseId,
        workKg: workKg ?? this.workKg,
        misses: misses ?? this.misses,
        workReps: workReps ?? this.workReps,
        updated: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'exercise_id': exerciseId,
        'work_kg': workKg,
        'misses': misses,
        'work_reps': workReps,
        'updated': updated?.millisecondsSinceEpoch,
      };

  factory LiftState.fromJson(Map<String, dynamic> j) => LiftState(
        exerciseId: j['exercise_id'] as String,
        workKg: (j['work_kg'] as num).toDouble(),
        misses: (j['misses'] ?? 0) as int,
        workReps: j['work_reps'] as int?,
        updated: j['updated'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['updated'] as int),
      );
}

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
  final lo = repLow ?? e.repLow, hi = repHigh ?? e.repHigh;
  final worked = sets.map((x) => x.kg).reduce((a, b) => a > b ? a : b);
  final minReps = sets.map((x) => x.reps).reduce((a, b) => a < b ? a : b);

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

  if (minReps >= hi) {
    return s.copyWith(workKg: roundToStep(worked + stepKg(e.step, u), e.step, u), misses: 0);
  }
  if (minReps < lo) {
    final m = s.misses + 1;
    if (m >= 2) return s.copyWith(workKg: roundToStep(worked * 0.9, e.step, u), misses: 0);
    return s.copyWith(workKg: worked, misses: m);
  }
  return s.copyWith(workKg: worked, misses: 0);
}
