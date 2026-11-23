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
  final double? tm; // training max (programs: sets are a % of it)
  final int stage; // programs with stages: 0 = the first
  final String? why; // F238: why the weight is what it is, in plain words ("+2.5 kg: every set hit 8")
  /// P1-7: the part of an increase too small for the equipment (kg), kept for next time, so two
  /// half steps (Greyskull's 2.5 lb on a 5 lb bar) make one whole step instead of none.
  final double carry;
  /// Stage rules: the weight last done on stage 1 (GZCLP T2 restarts from it, P3-5).
  final double? base;

  const LiftState({required this.exerciseId, required this.workKg, this.misses = 0, this.workReps, this.updated, this.tops = 0, this.tm, this.stage = 0, this.why, this.carry = 0, this.base});

  LiftState copyWith({String? exerciseId, double? workKg, int? misses, int? workReps, int? tops, double? tm, bool clearTm = false, int? stage, String? why, double? carry, double? base}) => LiftState(
        exerciseId: exerciseId ?? this.exerciseId,
        workKg: workKg ?? this.workKg,
        misses: misses ?? this.misses,
        workReps: workReps ?? this.workReps,
        updated: DateTime.now(),
        tops: tops ?? this.tops,
        tm: clearTm ? null : (tm ?? this.tm),
        stage: stage ?? this.stage,
        why: why ?? this.why,
        carry: carry ?? this.carry,
        base: base ?? this.base,
      );

  Map<String, dynamic> toJson() => {
        'exercise_id': exerciseId,
        'work_kg': workKg,
        'misses': misses,
        'work_reps': workReps,
        'updated': updated?.millisecondsSinceEpoch,
        if (tops != 0) 'tops': tops,
        if (tm != null) 'tm': tm,
        if (stage != 0) 'stage': stage,
        if (why != null) 'why': why,
        if (carry != 0) 'carry': carry,
        if (base != null) 'base': base,
      };

  factory LiftState.fromJson(Map<String, dynamic> j) => LiftState(
        exerciseId: j['exercise_id'] as String,
        workKg: (j['work_kg'] as num).toDouble(),
        misses: (j['misses'] ?? 0) as int,
        workReps: j['work_reps'] as int?,
        updated: j['updated'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['updated'] as int),
        tops: (j['tops'] ?? 0) as int,
        tm: (j['tm'] as num?)?.toDouble(),
        stage: (j['stage'] ?? 0) as int,
        why: j['why'] as String?,
        carry: (j['carry'] as num?)?.toDouble() ?? 0,
        base: (j['base'] as num?)?.toDouble(),
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
  String plus(double kg) => '+${fmtWeight(kg - worked, u)} ${unitLabel(u)}';

  if (e.bodyweight) {
    final target = s.workReps ?? lo;
    if (minReps < lo) {
      final back = s.misses + 1 >= 2;
      return s.copyWith(misses: back ? 0 : s.misses + 1, workReps: back ? lo : target, why: back ? 'Back to $lo reps: two workouts in a row short of $lo' : 'Same reps: a set was short of $lo');
    }
    if (minReps >= hi) {
      final w = roundToStep(worked + stepKg(e.step, u), e.step, u);
      return s.copyWith(workKg: w, workReps: lo, misses: 0, why: '${plus(w)} and back to $lo reps: every set hit $hi');
    }
    final next = minReps >= target ? target + 1 : target;
    return s.copyWith(workKg: worked, workReps: next, misses: 0, why: next > target ? 'One more rep: every set hit $target' : 'Same reps: aim for $target on every set (lowest was $minReps)');
  }

  // linear: a step every session that reaches the bottom of the range
  if (rules.scheme[e.id] == 'linear' && minReps >= lo) {
    return s.copyWith(workKg: up(1), misses: 0, tops: 0, why: '${plus(up(1))}: every set reached $lo (this lift adds weight every workout)');
  }
  if (minReps >= hi) {
    final efforts = [for (final x in sets) if (x.effort != null) x.effort!];
    final easy = rules.effort && efforts.isNotEmpty && efforts.every((x) => x == 1);
    final allOut = rules.effort && efforts.contains(4);
    final amrapBig = sets.any((x) => x.type == SetType.amrap && x.reps >= hi + 3);
    if (rules.speed == 'slow' && !easy && s.tops < 1) {
      return s.copyWith(workKg: worked, misses: 0, tops: s.tops + 1, why: 'Same weight once more: every set hit $hi (the slow setting waits for two workouts)');
    }
    var n = rules.speed == 'fast' ? 2 : 1;
    if (easy || amrapBig) n += 1;
    if (allOut) n = 1; // it was a grind: one step only
    final extra = allOut ? ' (a set was all-out, so one step)' : (easy ? ' and felt easy' : (amrapBig ? ' and the last set beat it by 3+' : ''));
    return s.copyWith(workKg: up(n), misses: 0, tops: 0, why: '${plus(up(n))}: every set hit $hi$extra');
  }
  if (minReps < lo) {
    final m = s.misses + 1;
    if (m >= drop) {
      return s.copyWith(
          workKg: roundToStep(worked * (1 - rules.dropPct), e.step, u), misses: 0, tops: 0, why: '-${(rules.dropPct * 100).round()}%: $drop workout${drop == 1 ? '' : 's'} in a row short of $lo reps');
    }
    return s.copyWith(workKg: worked, misses: m, tops: 0, why: 'Same weight: a set was short of $lo reps ($m of $drop before it drops)');
  }
  return s.copyWith(workKg: worked, misses: 0, tops: 0, why: 'Same weight: get every set to $hi reps to move up (lowest was $minReps)');
}
