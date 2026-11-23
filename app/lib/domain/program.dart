import 'exercise.dart';
import 'progression.dart';
import 'units.dart';

/// The program engine (F210): week-based plans whose template brings its own rules.
///
/// A program is an ordinary [Plan] whose rotation runs through every week of the template
/// (week 1's days, then week 2's ...), so the rotation, "Week N", skipping and picking a day all
/// keep working. What makes it a program:
/// - a plan item can carry one target per set ([SetSpec]): reps, a % of the lift's training max,
///   as-many-as-possible;
/// - each main lift has a [LiftRule] that says how it moves on (linear, stages, training-max
///   cycles, AMRAP-driven training max, ladders, double progression, or a tiny script);
/// - the training max and the stage are kept per lift ([LiftState.tm], [LiftState.stage]).

/// One planned set.
class SetSpec {
  final int reps; // target reps (bottom of the range when [hi] is set)
  final int? hi; // top of a rep range, null = exact
  final double? pct; // fraction of the training max; null = the working weight
  final bool amrap; // as many reps as possible (the target is the minimum)
  const SetSpec(this.reps, {this.hi, this.pct, this.amrap = false});

  Map<String, dynamic> toJson() => {'r': reps, if (hi != null) 'h': hi, if (pct != null) 'p': pct, if (amrap) 'a': 1};
  factory SetSpec.fromJson(Map<String, dynamic> j) => SetSpec(j['r'] as int, hi: j['h'] as int?, pct: (j['p'] as num?)?.toDouble(), amrap: j['a'] == 1);

  @override
  bool operator ==(Object other) => other is SetSpec && other.reps == reps && other.hi == hi && other.pct == pct && other.amrap == amrap;
  @override
  int get hashCode => Object.hash(reps, hi, pct, amrap);
}

/// "1x5@65 1x5@75 1x5+@85", "5x5", "3x8-12", "2x5 1x5+" -> one [SetSpec] per set.
/// Throws [FormatException] with a plain message on a bad text.
List<SetSpec> parseSets(String text) {
  final out = <SetSpec>[];
  final re = RegExp(r'^(\d+)x(\d+)(?:-(\d+))?(\+)?(?:@(\d+(?:\.\d+)?)%?)?$');
  for (final tok in text.trim().toLowerCase().replaceAll('×', 'x').split(RegExp(r'[\s,]+'))) {
    if (tok.isEmpty) continue;
    final m = re.firstMatch(tok);
    if (m == null) throw FormatException('"$tok" is not a set (write it like 3x5, 3x8-12, 1x5+ or 1x5@85).');
    final n = int.parse(m[1]!), r = int.parse(m[2]!);
    final hi = m[3] == null ? null : int.parse(m[3]!);
    final pct = m[5] == null ? null : double.parse(m[5]!) / 100;
    if (n < 1 || n > 20 || r < 1 || r > 100 || (hi != null && hi < r) || (pct != null && (pct <= 0 || pct > 1.2))) {
      throw FormatException('"$tok" is out of range (1-20 sets, 1-100 reps, up to 120%).');
    }
    for (var i = 0; i < n; i++) {
      out.add(SetSpec(r, hi: hi, pct: pct, amrap: m[4] != null && i == n - 1));
    }
  }
  if (out.isEmpty) throw const FormatException('write at least one set, like 3x5.');
  if (out.length > 30) throw const FormatException('at most 30 sets.');
  return out;
}

/// Back to the short text: equal sets in a row are grouped ("3x5@75"); an AMRAP last set is "+".
String setsText(List<SetSpec> l) {
  final b = <String>[];
  var i = 0;
  while (i < l.length) {
    var j = i;
    while (j + 1 < l.length && l[j + 1] == l[i] && !l[i].amrap) {
      j++;
    }
    final x = l[i];
    // 2x5 then 1x5+ reads better as one group with a + at the end
    var n = j - i + 1;
    if (j + 1 < l.length && l[j + 1].amrap && l[j + 1].reps == x.reps && l[j + 1].pct == x.pct && l[j + 1].hi == x.hi) {
      n++;
      j++;
      b.add('${n}x${x.reps}${x.hi == null ? '' : '-${x.hi}'}+${x.pct == null ? '' : '@${_pc(x.pct!)}'}');
    } else {
      b.add('${n}x${x.reps}${x.hi == null ? '' : '-${x.hi}'}${x.amrap ? '+' : ''}${x.pct == null ? '' : '@${_pc(x.pct!)}'}');
    }
    i = j + 1;
  }
  return b.join(' ');
}

String _pc(double p) {
  final v = p * 100;
  return v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}

/// A plain line for the workout screen: "65% × 5, 75% × 5, 85% × 5+".
String setsPlain(List<SetSpec> l) =>
    setsText(l).split(' ').map((g) => g.replaceAll('x', ' × ').replaceAllMapped(RegExp(r'@(\d+(?:\.\d)?)'), (m) => ' at ${m[1]}%')).join(', ');

/// Just the reps of each set, "5, 3, 1+" (P2-3): Today's row and the coach line.
String repsShort(List<SetSpec> l) => l.map((x) => '${x.reps}${x.hi != null && x.hi != x.reps ? '-${x.hi}' : ''}${x.amrap ? '+' : ''}').join(', ');

/// "1 rep" / "5 reps".
String repsWord(int n) => n == 1 ? '1 rep' : '$n reps';

const ruleKinds = {
  'double': 'Double progression: reps climb to the top of the range, then the weight goes up',
  'linear': 'Linear: weight goes up every session you hit all the reps',
  'tm': 'Training max: sets are a % of a training max that goes up after a cycle',
  'stage': 'Stages: on a miss the sets change (5×3 → 6×2 → 10×1), then a reset',
  'ladder': 'Ladder: at the top of the range you move to a harder exercise',
  'script': 'My own rule, written as a few lines',
};

const bumpKinds = {
  '': 'nothing',
  'tm': 'training max goes up when the last set hits its reps',
  'amrap': 'training max goes up by how many reps the + set got',
  'over': 'training max goes up a little for every rep over the target',
  'test': 'new training max from the best set of the day',
  'check': 'training max checked: kept when the + set gets its reps, 10% down when not',
};

/// How one lift moves on inside a program.
class LiftRule {
  final String kind; // see [ruleKinds]
  final double inc; // steps added on a success (or to the training max)
  final int misses; // misses in a row before the reset
  final double reset; // weight after the reset, 0.9 = 90 %
  final List<String> stages; // stage rule: one set text per stage, e.g. ['5x3+', '6x2+', '10x1+']
  final List<String> ladder; // ladder rule: exercise ids, easiest first
  final int amrapGoal; // the weight goes up only when the + set reaches this many reps (0 = off)
  final String script; // script rule: see [runScript]
  /// Stage rule: after the last stage go back to stage 1 at the last stage-1 weight plus this many
  /// steps (GZCLP T2: +15-20 lb, P3-5); 0 = [reset] x the current weight.
  final double resetUp;

  const LiftRule({this.kind = 'double', this.inc = 1, this.misses = 2, this.reset = 0.9, this.stages = const [], this.ladder = const [], this.amrapGoal = 0, this.script = '', this.resetUp = 0});

  LiftRule copyWith({String? kind, double? inc, int? misses, double? reset, List<String>? stages, List<String>? ladder, int? amrapGoal, String? script, double? resetUp}) => LiftRule(
        kind: kind ?? this.kind,
        inc: inc ?? this.inc,
        misses: misses ?? this.misses,
        reset: reset ?? this.reset,
        stages: stages ?? this.stages,
        ladder: ladder ?? this.ladder,
        amrapGoal: amrapGoal ?? this.amrapGoal,
        script: script ?? this.script,
        resetUp: resetUp ?? this.resetUp,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (inc != 1) 'inc': inc,
        if (misses != 2) 'misses': misses,
        if (reset != 0.9) 'reset': reset,
        if (stages.isNotEmpty) 'stages': stages,
        if (ladder.isNotEmpty) 'ladder': ladder,
        if (amrapGoal != 0) 'amrapGoal': amrapGoal,
        if (script.isNotEmpty) 'script': script,
        if (resetUp != 0) 'resetUp': resetUp,
      };

  factory LiftRule.fromJson(Map<String, dynamic> j) => LiftRule(
        kind: (j['kind'] ?? 'double') as String,
        inc: ((j['inc'] ?? 1) as num).toDouble(),
        misses: (j['misses'] ?? 2) as int,
        reset: ((j['reset'] ?? 0.9) as num).toDouble(),
        stages: List<String>.from((j['stages'] ?? const []) as List),
        ladder: List<String>.from((j['ladder'] ?? const []) as List),
        amrapGoal: (j['amrapGoal'] ?? 0) as int,
        script: (j['script'] ?? '') as String,
        resetUp: ((j['resetUp'] ?? 0) as num).toDouble(),
      );

  /// One plain line about the rule, for the plan and the rules page.
  String describe(Unit u, StepKind step) {
    final st = fmtNum(stepIn(step, u) * inc);
    final w = '$st ${unitLabel(u)}';
    return switch (kind) {
      'linear' => '+$w each time all reps are done${amrapGoal > 0 ? ' (twice that when the + set gets $amrapGoal)' : ''}; $misses misses in a row: ${(reset * 100).round()}% of the weight',
      'tm' => 'Sets from the training max; it goes up $w when the cycle says so',
      'stage' => 'Stages ${stages.join(' → ')}; +$w on a success; a miss moves to the next stage; after the last: ${resetUp > 0 ? 'stage 1 at its last weight +${fmtNum(stepIn(step, u) * resetUp)} ${unitLabel(u)}' : '${(reset * 100).round()}% and stage 1'}',
      'ladder' => 'Moves to the next exercise at the top of the range; $misses misses in a row: one step back',
      'script' => 'My own rule (${script.split('\n').where((l) => l.trim().isNotEmpty && !l.trim().startsWith('#')).length} lines)',
      _ => 'Reps climb to the top of the range, then +$w',
    };
  }
}

/// A program running in a plan: which template it came from, and the rule of each lift.
/// Keys are lift keys ([liftKey]): the exercise id, or "id#T2" for a second slot of the same lift.
/// What a program's "training max" means (P1-5): 'tm90' about 90% of a 1-rep max (5/3/1, nSuns),
/// '1rm' the 1-rep max itself (Smolov, Candito, Sheiko-style), '5rm' the best set of 5 (Madcow, Texas).
const tmBases = {'tm90': 0.9, '1rm': 1.0, '5rm': 1 / 1.1667};

const tmBasisText = {
  'tm90': 'About 90% of the most you could lift once.',
  '1rm': 'The most you could lift once (your 1-rep max).',
  '5rm': 'The most you can lift for 5 good reps.',
};

/// A training max on [basis] from an estimated 1-rep max.
double maxOnBasis(double e1rmKg, String basis) => e1rmKg * (tmBases[basis] ?? 0.9);

/// What someone types in a training-max box (P2-5): the max itself ("100"), or a recent set
/// ("100 x 5", "100x5", "100×5"), worked out on the program's [basis]. kg, or null when unclear.
double? parseMaxInput(String text, Unit u, String basis) {
  // "100", "100kg", "225 lb x 5" (a unit typed wins over the app's unit, P3-N4)
  final m = RegExp(r'^\s*(\d+(?:[.,]\d+)?)\s*(kgs?|kilos?|lbs?|pounds?)?\s*(?:[x×*]\s*(\d{1,2}))?\s*$').firstMatch(text.toLowerCase());
  if (m == null) return null;
  final w = double.parse(m.group(1)!.replaceAll(',', '.'));
  if (w <= 0) return null;
  final reps = int.tryParse(m.group(3) ?? '');
  final unit = m.group(2) == null ? u : (m.group(2)!.startsWith('k') ? Unit.kg : Unit.lb);
  final kg = fromUnit(w, unit);
  return reps == null ? kg : maxOnBasis(e1rm(kg, reps), basis);
}

class ProgramInfo {
  final String id; // template id
  final Map<String, LiftRule> rules;
  final String basis; // see [tmBases]
  const ProgramInfo({required this.id, this.rules = const {}, this.basis = 'tm90'});

  ProgramInfo copyWith({Map<String, LiftRule>? rules}) => ProgramInfo(id: id, rules: rules ?? this.rules, basis: basis);

  Map<String, dynamic> toJson() => {'id': id, 'rules': {for (final e in rules.entries) e.key: e.value.toJson()}, if (basis != 'tm90') 'basis': basis};
  factory ProgramInfo.fromJson(Map<String, dynamic> j) => ProgramInfo(
      id: j['id'] as String,
      rules: {for (final e in ((j['rules'] ?? const {}) as Map).entries) e.key as String: LiftRule.fromJson(e.value as Map<String, dynamic>)},
      basis: (j['basis'] ?? 'tm90') as String);
}

/// What happened to a lift after a program workout.
class ProgramStep {
  final LiftState state;
  final String? climbTo; // ladder: the plan should use this exercise from now on
  final String? note; // a plain line for the finish screen ("Squat: next stage, 6 × 2")
  const ProgramStep(this.state, {this.climbTo, this.note});
}

/// The sets of the lift's current stage (stage rule), as the plan item will show them.
List<SetSpec>? stageSets(LiftRule r, int stage) {
  if (r.kind != 'stage' || r.stages.isEmpty) return null;
  try {
    return parseSets(r.stages[stage.clamp(0, r.stages.length - 1)]);
  } on FormatException {
    return null;
  }
}

double _best(List<SetLog> sets) => sets.fold<double>(0, (a, x) => e1rm(x.kg, x.reps) > a ? e1rm(x.kg, x.reps) : a);

/// One program workout for lift [s] (its sets [sets], planned as [plan]) under rule [r].
/// [bump] is the plan item's training-max change (see [bumpKinds]).
ProgramStep programNext(LiftState s, LiftRule r, Exercise e, List<SetLog> sets, List<SetSpec> plan, Unit u, {String bump = '', String basis = 'tm90'}) {
  if (sets.isEmpty) return ProgramStep(s);
  final step = progressRules.stepKg[e.id] ?? stepKg(e.step, u);
  double round(double kg) => progressRules.stepKg.containsKey(e.id) ? kg : roundToStep(kg, e.step, u);
  final worked = sets.map((x) => x.kg).reduce((a, b) => a > b ? a : b);
  final amrapSets = [for (var i = 0; i < sets.length && i < plan.length; i++) if (plan[i].amrap) (sets[i], plan[i])];
  // every planned set reached its reps (sets logged beyond the plan count too)
  var hit = sets.length >= plan.length;
  for (var i = 0; i < plan.length && i < sets.length; i++) {
    if (sets[i].reps < plan[i].reps) hit = false;
  }
  final top = sets.every((x) => x.reps >= (plan.isEmpty ? e.repHigh : (plan.first.hi ?? plan.first.reps)));
  // the + set that moves the training max is the heaviest one (nSuns: the 1+ at 95%, not the
  // back-off 65%+); with equal %s the later one
  final plus = amrapSets.isEmpty ? null : amrapSets.reduce((a, b) => (b.$2.pct ?? 0) >= (a.$2.pct ?? 0) ? b : a);
  final name = e.name;

  switch (r.kind) {
    case 'tm':
      var tm = s.tm;
      if (tm == null || tm <= 0) {
        // no training max yet: from today's best set, on the program's basis
        final t = round(maxOnBasis(_best(sets), basis));
        return ProgramStep(s.copyWith(tm: t), note: '$name: training max set to ${fmtWeight(t, u)} ${unitLabel(u)} from today');
      }
      switch (bump) {
        case 'tm':
          // plain sets with no % (PHAT power days): the weight moves like double progression, and
          // the training max the % days read moves with it (P1-3)
          if (plan.every((x) => x.pct == null)) {
            if (top) return ProgramStep(s.copyWith(tm: round(tm + step * r.inc), workKg: round(worked + step * r.inc), misses: 0), note: '$name: up to ${fmtWeight(round(worked + step * r.inc), u)}');
            return ProgramStep(s.copyWith(workKg: worked, misses: hit ? 0 : s.misses + 1), note: hit ? null : '$name: same weight (a set was short)');
          }
          // with a + set it decides; without one (Madcow's Friday triple) every planned set must hit (P1-4)
          if (plus == null ? hit : plus.$1.reps >= plus.$2.reps) {
            return ProgramStep(s.copyWith(tm: round(tm + step * r.inc), misses: 0), note: '$name: training max up to ${fmtWeight(round(tm + step * r.inc), u)}');
          }
          final m = s.misses + 1;
          if (m >= r.misses) return ProgramStep(s.copyWith(tm: round(tm * r.reset), misses: 0), note: '$name: training max down to ${fmtWeight(round(tm * r.reset), u)} (missed $m cycles)');
          return ProgramStep(s.copyWith(misses: m), note: '$name: training max stays (${plus == null ? 'a set was short' : 'the + set was short'})');
        case 'check':
          // 5/3/1's 7th-week test: the max is not raised here, only lowered when it was too heavy (P1-6)
          if (plus == null || plus.$1.reps >= plus.$2.reps) return ProgramStep(s.copyWith(misses: 0), note: '$name: training max checked, kept');
          return ProgramStep(s.copyWith(tm: round(tm * 0.9), misses: 0), note: '$name: training max down to ${fmtWeight(round(tm * 0.9), u)} (the 3+ set was short)');
        case 'amrap':
          final reps = plus?.$1.reps ?? 0;
          final n = reps <= 1 ? 0 : (reps <= 3 ? 1 : (reps <= 5 ? 2 : 3));
          if (n == 0) return ProgramStep(s.copyWith(), note: '$name: training max stays');
          final t = round(tm + step * r.inc * n);
          return ProgramStep(s.copyWith(tm: t, misses: 0), note: '$name: training max up to ${fmtWeight(t, u)}');
        case 'over':
          final over = plus == null ? 0 : (plus.$1.reps - plus.$2.reps).clamp(-5, 10);
          if (over < 0) return ProgramStep(s.copyWith(tm: round(tm * r.reset)), note: '$name: training max down (the + set was short)');
          final t = round(tm + step * r.inc * 0.5 * over);
          return ProgramStep(s.copyWith(tm: t), note: over == 0 ? '$name: training max stays' : '$name: training max up to ${fmtWeight(t, u)}');
        case 'test':
          // the test sets the max on the program's basis; a bad test can lower it (P1-5)
          final t = round(maxOnBasis(_best(sets), basis));
          if ((t - tm).abs() < 0.01) return ProgramStep(s.copyWith(), note: '$name: training max stays');
          return ProgramStep(s.copyWith(tm: t), note: '$name: training max ${t > tm ? 'up' : 'down'} to ${fmtWeight(t, u)} from the test');
      }
      return ProgramStep(s.copyWith());

    case 'linear':
      if (hit) {
        final n = (r.amrapGoal > 0 && plus != null && plus.$1.reps >= r.amrapGoal) ? 2 : 1;
        // a part step the equipment cannot load is carried to next time (P1-7)
        final want = worked + step * r.inc * n + s.carry;
        final w = progressRules.stepKg.containsKey(e.id) ? want : round(want - step / 2); // round down; the rest is carried
        final carry = (want - w).abs() < step * 0.99 && want - w > 0.01 ? want - w : 0.0;
        return ProgramStep(s.copyWith(workKg: w, misses: 0, carry: carry), note: n == 2 ? '$name: double jump' : (carry > 0 && (w - worked).abs() < 0.01 ? '$name: same weight, half a step saved for next time' : null));
      }
      final m = s.misses + 1;
      if (m >= r.misses) return ProgramStep(s.copyWith(workKg: round(worked * r.reset), misses: 0, carry: 0), note: '$name: missed $m times, down to ${(r.reset * 100).round()}%');
      return ProgramStep(s.copyWith(workKg: worked, misses: m));

    case 'stage':
      final n = r.stages.length;
      final base = s.stage == 0 ? worked : s.base; // the weight last done on stage 1
      if (hit) {
        if (r.amrapGoal > 0 && (plus == null || plus.$1.reps < r.amrapGoal)) return ProgramStep(s.copyWith(workKg: worked, misses: 0, base: base));
        return ProgramStep(s.copyWith(workKg: round(worked + step * r.inc), misses: 0, base: base));
      }
      if (s.stage + 1 < n) {
        return ProgramStep(s.copyWith(workKg: worked, stage: s.stage + 1, misses: 0, base: base), note: '$name: next stage, ${r.stages[s.stage + 1]}');
      }
      if (r.resetUp > 0 && base != null) {
        final w = round(base + step * r.resetUp);
        return ProgramStep(s.copyWith(workKg: w, stage: 0, misses: 0, base: w), note: '$name: back to ${r.stages.first} at ${fmtWeight(w, u)} ${unitLabel(u)}');
      }
      return ProgramStep(s.copyWith(workKg: round(worked * r.reset), stage: 0, misses: 0), note: n > 1 ? '$name: back to ${r.stages.first} at ${(r.reset * 100).round()}%' : null);

    case 'ladder':
      final i = r.ladder.indexOf(e.id);
      if (top) {
        if (i >= 0 && i + 1 < r.ladder.length) return ProgramStep(s.copyWith(misses: 0), climbTo: r.ladder[i + 1], note: '$name done: on to the next step');
        return ProgramStep(nextLift(s, e, sets, u, repLow: plan.isEmpty ? null : plan.first.reps, repHigh: plan.isEmpty ? null : plan.first.hi));
      }
      if (sets.any((x) => x.reps < (plan.isEmpty ? e.repLow : plan.first.reps))) {
        final m = s.misses + 1;
        if (m >= r.misses && i > 0) return ProgramStep(s.copyWith(misses: 0), climbTo: r.ladder[i - 1], note: '$name: one step back for now');
        return ProgramStep(s.copyWith(misses: m));
      }
      return ProgramStep(s.copyWith(misses: 0));

    case 'script':
      return runScript(r.script, s, e, sets, plan, u);
  }
  return ProgramStep(nextLift(s, e, sets, u, repLow: plan.isEmpty ? null : plan.first.reps, repHigh: plan.isEmpty ? null : (plan.first.hi ?? plan.first.reps)));
}

// ---------- the progression script (F222) ----------
//
// One rule per line, the first that matches is used:
//   if top: add 1          every set at the top of the range: one weight step more
//   if hit: add 1          every set got its planned reps
//   if amrap >= 10: add 2  the + set got 10 or more reps
//   if reps >= 12: add 1   every set got 12 or more reps
//   if miss 3: times 0.9   the 3rd workout in a row with a short set: 90 % of the weight
//   if miss: same          a short set: keep the weight (counts the miss)
//   else: reps +1          anything else: one rep more next time
// Actions: add N (weight steps), add 5kg / add 5lb, times 0.9, same, reps +1 / reps -1.
// Lines starting with # are notes.

final _line = RegExp(r'^(?:if\s+(top|hit|always|miss(?:\s+(\d+))?|amrap\s*>=\s*(\d+)|reps\s*>=\s*(\d+))|else)\s*:\s*(add\s+(-?\d+(?:\.\d+)?)\s*(kg|lb)?|times\s+(\d+(?:\.\d+)?)|same|reps\s*([+-]\d+))$');

/// Null when [script] is fine, otherwise a plain message naming the bad line.
String? checkScript(String script) {
  // a rule is a few lines; a long one is refused before it is read (batch 20: scripts can come from a shared plan)
  if (script.length > 2000 || '\n'.allMatches(script).length >= 40) return 'the rule is too long (40 lines at most).';
  var n = 0;
  for (final raw in script.split('\n')) {
    n++;
    final l = raw.trim().toLowerCase();
    if (l.isEmpty || l.startsWith('#')) continue;
    final m = _line.firstMatch(l);
    if (m == null) return 'line $n: "${raw.trim()}" is not a rule. Write it like "if top: add 1" or "if miss 3: times 0.9".';
    final t = m[8] == null ? null : double.parse(m[8]!);
    if (t != null && (t <= 0 || t > 1.5)) return 'line $n: times must be between 0 and 1.5.';
    final a = m[6] == null ? null : double.parse(m[6]!);
    if (a != null && a.abs() > (m[7] == null ? 10 : 50)) return 'line $n: that is a very big jump.';
  }
  return null;
}

/// Each rule line of [script] in plain words, and whether it is a big change (adds more than
/// 5 kg / 10 lb or 2 steps, or multiplies the weight above 1), for a received plan's preview
/// (review 5, P2-2). Notes (#) are left out.
List<(String, bool)> scriptWords(String script) {
  final out = <(String, bool)>[];
  for (final raw in script.split('\n')) {
    final l = raw.trim().toLowerCase();
    if (l.isEmpty || l.startsWith('#')) continue;
    final m = _line.firstMatch(l);
    if (m == null) {
      out.add(('Not a rule: "${raw.trim()}"', true));
      continue;
    }
    final c = m[1];
    final when = switch (c) {
      null => 'Otherwise',
      'top' => 'Every set at the top of the range',
      'hit' => 'Every set got its reps',
      'always' => 'Every workout',
      _ when c.startsWith('miss') => m[2] == null ? 'After a short set' : 'After ${m[2]} workouts in a row with a short set',
      _ when c.startsWith('amrap') => 'The + set got ${m[3]} or more reps',
      _ => 'Every set got ${m[4]} or more reps',
    };
    final act = m[5]!;
    String what;
    var big = false;
    if (act == 'same') {
      what = 'keep the weight';
    } else if (act.startsWith('reps')) {
      what = '${m[9]!.startsWith('-') ? 'one rep less' : 'one rep more'} next time';
    } else if (act.startsWith('times')) {
      final x = double.parse(m[8]!);
      what = 'weight × ${m[8]}${x > 1 ? ' (goes UP)' : x < 1 ? ' (goes down)' : ''}';
      big = x > 1;
    } else {
      final n = double.parse(m[6]!);
      final unit = m[7];
      what = '${unit == null ? 'add ${m[6]} weight step${n.abs() == 1 ? '' : 's'}' : 'add ${m[6]} $unit'}${n < 0 ? ' (goes down)' : ''}';
      big = unit == null ? n.abs() > 2 : (unit == 'kg' ? n.abs() > 5 : n.abs() > 10);
    }
    out.add(('$when: $what', big));
  }
  return out;
}

/// Runs a progression script (see above). A broken script keeps the weight.
ProgramStep runScript(String script, LiftState s, Exercise e, List<SetLog> sets, List<SetSpec> plan, Unit u) {
  if (sets.isEmpty || checkScript(script) != null) return ProgramStep(s);
  final worked = sets.map((x) => x.kg).reduce((a, b) => a > b ? a : b);
  final minReps = sets.map((x) => x.reps).reduce((a, b) => a < b ? a : b);
  final lo = plan.isEmpty ? e.repLow : plan.first.reps;
  final hi = plan.isEmpty ? e.repHigh : (plan.first.hi ?? plan.first.reps);
  final miss = minReps < lo;
  var hit = sets.length >= plan.length;
  for (var i = 0; i < plan.length && i < sets.length; i++) {
    if (sets[i].reps < plan[i].reps) hit = false;
  }
  final plusReps = [for (var i = 0; i < sets.length && i < plan.length; i++) if (plan[i].amrap) sets[i].reps].lastOrNull; // null: no + set planned
  for (final raw in script.split('\n')) {
    final l = raw.trim().toLowerCase();
    if (l.isEmpty || l.startsWith('#')) continue;
    final m = _line.firstMatch(l)!;
    final cond = m[1];
    final ok = switch (cond) {
      null => true, // else
      'top' => minReps >= hi,
      'hit' => hit,
      'always' => true,
      _ when cond.startsWith('miss') => miss && s.misses + 1 >= (m[2] == null ? 1 : int.parse(m[2]!)),
      _ when cond.startsWith('amrap') => plusReps != null && plusReps >= int.parse(m[3]!),
      _ => minReps >= int.parse(m[4]!),
    };
    if (!ok) continue;
    final act = m[5]!;
    final misses = miss ? s.misses + 1 : 0;
    if (act == 'same') return ProgramStep(s.copyWith(workKg: worked, misses: misses));
    if (act.startsWith('reps')) {
      final d = int.parse(m[9]!);
      return ProgramStep(s.copyWith(workKg: worked, workReps: ((s.workReps ?? lo) + d).clamp(1, 100), misses: misses));
    }
    if (act.startsWith('times')) return ProgramStep(s.copyWith(workKg: roundToStep(worked * double.parse(m[8]!), e.step, u), misses: 0), note: '${e.name}: my rule changed the weight');
    final n = double.parse(m[6]!);
    final kg = m[7] == null ? n * stepKg(e.step, u) : (m[7] == 'kg' ? n : lbToKg(n));
    return ProgramStep(s.copyWith(workKg: (worked + kg).clamp(0, 2000).toDouble(), misses: 0));
  }
  return ProgramStep(s.copyWith(workKg: worked, misses: miss ? s.misses + 1 : 0));
}
