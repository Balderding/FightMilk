import 'exercise.dart';
import 'library.dart';
import 'plan.dart';
import 'program.dart';

/// The program library (F211-F220). Every template is data: weeks of days, each item an
/// exercise id with its sets written short ("1x5@65 1x5@75 1x5+@85", "3x8-12"), and a rule per
/// main lift. Descriptions are our own words. Named programs follow their published set and rep
/// schemes; where a scheme has many versions we picked one and say so.

class TItem {
  final String ex;
  final String sets;
  final String tier; // a second slot of the same lift keeps its own weights ("T2")
  final String tmOf; // % sets use this lift's training max
  final String bump; // see bumpKinds
  final int rest; // 0 = from the reps
  const TItem(this.ex, this.sets, {this.tier = '', this.tmOf = '', this.bump = '', this.rest = 0});
}

class TDay {
  final String name;
  final List<TItem> items;
  const TDay(this.name, this.items);
}

class ProgramTemplate {
  final String id, name, group, about, who, length;
  final int level; // 0 new, 1 some experience, 2 years
  final Set<String> goals; // strength, size, both, fitness, powerlifting
  final Set<Equipment> needs; // what it really needs (others get swapped)
  final List<List<TDay>> weeks;
  final Map<String, LiftRule> rules; // lift key as written in the template -> rule
  final String credit;
  final int? perWeek; // training days a week when it differs from the days in a week (A/B programs)
  final String tmBasis; // what its training max means (tmBases): 'tm90', '1rm' or '5rm'
  const ProgramTemplate({
    required this.id,
    required this.name,
    required this.group,
    required this.about,
    required this.who,
    required this.length,
    required this.level,
    required this.goals,
    this.needs = const {Equipment.barbell},
    required this.weeks,
    this.rules = const {},
    this.credit = '',
    this.perWeek,
    this.tmBasis = 'tm90',
  });

  int get days => perWeek ?? weeks.first.length;
}

const programGroups = ['Beginner', 'Strength', '5/3/1', 'GZCL', 'Size and simple', 'Powerlifting blocks', 'Bodyweight'];

const levelLabel = ['New', 'Some experience', 'Years of training'];

// ---------- rules ----------
const _lin = LiftRule(kind: 'linear', inc: 1, misses: 3, reset: 0.9);
const _lin2 = LiftRule(kind: 'linear', inc: 2, misses: 3, reset: 0.9);
const _tm1 = LiftRule(kind: 'tm', inc: 1);
const _tm2 = LiftRule(kind: 'tm', inc: 2);
const _t1Up = LiftRule(kind: 'stage', inc: 1, stages: ['5x3+', '6x2+', '10x1+'], reset: 0.85);
const _t1Low = LiftRule(kind: 'stage', inc: 2, stages: ['5x3+', '6x2+', '10x1+'], reset: 0.85);
// GZCLP T2: after 3x6 fails, back to 3x10 at the last 3x10 weight + about 15 lb upper / 20 lb lower (P3-5)
const _t2Up = LiftRule(kind: 'stage', inc: 1, stages: ['3x10', '3x8', '3x6'], reset: 0.85, resetUp: 3);
const _t2Low = LiftRule(kind: 'stage', inc: 2, stages: ['3x10', '3x8', '3x6'], reset: 0.85, resetUp: 4);
const _t3 = LiftRule(kind: 'stage', inc: 1, stages: ['3x15+'], amrapGoal: 25, reset: 1);

LiftRule _ladder(List<String> ids) => LiftRule(kind: 'ladder', ladder: ids, misses: 2);

// ---------- helpers ----------
List<List<TDay>> _repeat(List<TDay> week) => [week];

/// The four 5/3/1 weeks of main-lift sets (% of the training max); the 3rd week's + set decides
/// the training max for the next cycle.
const _w531 = ['1x5@65 1x5@75 1x5+@85', '1x3@70 1x3@80 1x3+@90', '1x5@75 1x3@85 1x1+@95', '1x5@40 1x5@50 1x5@60'];
const _fslW = ['5x5@65', '5x5@70', '5x5@75', ''];
const _sslW = ['5x5@75', '5x5@80', '5x5@85', ''];
const _bbsW = ['10x5@65', '10x5@70', '10x5@75', ''];

/// 5/3/1 weeks for the four main lifts, each day built by [extra] (the work after the main lift).
List<List<TDay>> _five31(List<TItem> Function(String lift, int week) extra, {int weeks = 4, List<String>? sets}) {
  const lifts = [('Press', 'overhead_press'), ('Deadlift', 'deadlift'), ('Bench', 'bench_press'), ('Squat', 'back_squat')];
  return [
    for (var w = 0; w < weeks; w++)
      [
        for (final (n, id) in lifts) TDay(n, [TItem(id, (sets ?? _w531)[w], bump: w == 2 ? 'tm' : ''), ...extra(id, w)])
      ]
  ];
}

/// Assistance after a 5/3/1 main lift: push, pull, legs or core, 50-100 reps total each.
List<TItem> _assist(String lift) => switch (lift) {
      'overhead_press' => const [TItem('dips', '3x10-15'), TItem('chin_up', '3x6-10'), TItem('face_pull', '3x15-20')],
      'deadlift' => const [TItem('walking_lunge', '3x10-12'), TItem('hanging_leg_raise', '3x10-15'), TItem('one_arm_db_row', '3x10-12')],
      'bench_press' => const [TItem('db_bench_press', '3x10-12'), TItem('barbell_row', '3x8-12'), TItem('triceps_pushdown', '3x12-15')],
      _ => const [TItem('leg_press', '3x10-15'), TItem('lying_leg_curl', '3x10-12'), TItem('ab_wheel', '3x10-15')],
    };

List<TItem> _bbbAssist(String lift) => switch (lift) {
      'overhead_press' || 'bench_press' => const [TItem('lat_pulldown', '5x10')],
      _ => const [TItem('hanging_leg_raise', '5x10-15')],
    };

/// Triumvirate: main lift plus two assistance exercises, 5 sets each.
List<TItem> _tri(String lift) => switch (lift) {
      'overhead_press' => const [TItem('dips', '5x10-15'), TItem('chin_up', '5x8-10')],
      'deadlift' => const [TItem('good_morning', '5x10-12'), TItem('hanging_leg_raise', '5x10-15')],
      'bench_press' => const [TItem('db_bench_press', '5x10-15'), TItem('one_arm_db_row', '5x10')],
      _ => const [TItem('leg_press', '5x15'), TItem('lying_leg_curl', '5x10')],
    };

/// nSuns main sets: 9 sets around a 1+ and a final + set.
const _nT1 = '1x5@75 1x3@85 1x1+@95 1x3@90 1x3@85 1x3@80 1x5@75 1x5@70 1x5+@65';
const _nT1d = '1x5@75 1x3@85 1x1+@95 1x3@90 1x3@85 1x3@80 1x3@75 1x3@70 1x3+@65';
const _nT1v = '1x8@65 1x6@75 1x4+@85 1x4@85 1x4@85 1x5@80 1x6@75 1x7@70 1x8+@65';
const _nT2 = '1x6@50 1x5@60 1x3@70 1x5@70 1x7@70 1x4@70 1x6@70 1x8@70';
const _nT2b = '1x6@40 1x5@50 1x3@60 1x5@60 1x7@60 1x4@60 1x6@60 1x8@60';
const _nT2f = '1x5@35 1x5@45 1x3@55 1x5@55 1x7@55 1x4@55 1x6@55 1x8@55';

List<TDay> _nsuns(int days) => [
      const TDay('Bench and press', [TItem('bench_press', _nT1, bump: 'amrap'), TItem('overhead_press', _nT2, tier: 'T2', tmOf: 'overhead_press'), TItem('lat_pulldown', '3x8-12'), TItem('db_lateral_raise', '3x12-15')]),
      const TDay('Squat and sumo', [TItem('back_squat', _nT1, bump: 'amrap'), TItem('sumo_deadlift', _nT2, tier: 'T2', tmOf: 'deadlift'), TItem('lying_leg_curl', '3x10-12'), TItem('hanging_leg_raise', '3x10-15')]),
      const TDay('Press and incline', [TItem('overhead_press', _nT1, bump: 'amrap'), TItem('incline_bench_press', _nT2b, tier: 'T2', tmOf: 'bench_press'), TItem('barbell_row', '3x8-12'), TItem('face_pull', '3x15-20')]),
      const TDay('Deadlift and front squat', [TItem('deadlift', _nT1d, bump: 'amrap'), TItem('front_squat', _nT2f, tier: 'T2', tmOf: 'back_squat'), TItem('ab_wheel', '3x10-15')]),
      if (days >= 5) const TDay('Bench volume', [TItem('bench_press', _nT1v, tier: 'V', tmOf: 'bench_press'), TItem('close_grip_bench', _nT2b, tier: 'T2', tmOf: 'bench_press'), TItem('chin_up', '3x6-10'), TItem('hammer_curl', '3x10-12')]),
      if (days >= 6) const TDay('Squat and deadlift', [TItem('back_squat', '1x5@75 1x3@85 1x1+@95 1x3@90 1x3@85 1x3@80', tier: 'V', tmOf: 'back_squat'), TItem('romanian_deadlift', '3x8-10'), TItem('leg_press', '3x10-15')]),
    ];

/// Juggernaut waves: accumulation, intensification, realization (+ set), deload, % of the TM.
const _jug = [
  ['5x10@60', '3x10@67.5', '1x5@50 1x3@60 1x1@70 1x10+@75', '1x5@40 1x5@50 1x5@60'],
  ['5x8@65', '3x8@72.5', '1x5@50 1x3@60 1x2@70 1x1@75 1x8+@80', '1x5@40 1x5@50 1x5@60'],
  ['6x6@70', '4x6@77.5', '1x5@50 1x3@60 1x2@70 1x1@80 1x6+@85', '1x5@40 1x5@50 1x5@60'],
  ['7x3@75', '5x3@82.5', '1x5@50 1x3@60 1x2@70 1x1@80 1x1@85 1x3+@90', '1x5@40 1x5@50 1x5@60'],
];

List<List<TDay>> _juggernaut() => [
      for (var wave = 0; wave < 4; wave++)
        for (var ph = 0; ph < 4; ph++)
          [
            for (final (n, id, acc) in const [
              ('Squat', 'back_squat', [TItem('lying_leg_curl', '3x10-12'), TItem('ab_wheel', '3x10-15')]),
              ('Bench', 'bench_press', [TItem('barbell_row', '4x8-12'), TItem('triceps_pushdown', '3x12-15')]),
              ('Deadlift', 'deadlift', [TItem('good_morning', '3x8-10'), TItem('hanging_leg_raise', '3x10-15')]),
              ('Press', 'overhead_press', [TItem('chin_up', '4x6-10'), TItem('db_lateral_raise', '3x12-15')]),
            ])
              TDay('${['10s', '8s', '6s', '3s'][wave]} · $n', [TItem(id, _jug[wave][ph], bump: ph == 2 ? 'over' : ''), ...acc])
          ]
    ];

/// A test day at the end of a block: work up to a heavy single, the new training max comes from it.
const _test = '1x3@70 1x2@80 1x1@90 1x1+@100';

final List<ProgramTemplate> programTemplates = [
  // ---------------- Beginner (F212, F223) ----------------
  ProgramTemplate(
    id: 'machine_starter',
    name: 'Machine starter',
    group: 'Beginner',
    about: 'Three full-body days on machines and cables, the easiest way in. Reps climb to the top of the range, then the weight goes up a step.',
    who: 'Your first months in a gym, or coming back after a long break. Nothing to balance, nothing to learn first.',
    length: 'Repeats; after 8-12 weeks try a barbell beginner program',
    level: 0,
    goals: const {'size', 'both', 'fitness'},
    needs: const {Equipment.machine, Equipment.cable},
    weeks: _repeat(const [
      TDay('Day A', [TItem('leg_press', '3x10-12'), TItem('machine_chest_press', '3x10-12'), TItem('seated_cable_row', '3x10-12'), TItem('lying_leg_curl', '3x10-12'), TItem('machine_lateral_raise', '2x12-15'), TItem('plank', '2x20-40')]),
      TDay('Day B', [TItem('hack_squat', '3x10-12'), TItem('lat_pulldown', '3x10-12'), TItem('machine_shoulder_press', '3x10-12'), TItem('leg_extension', '2x12-15'), TItem('cable_curl', '2x12-15'), TItem('triceps_pushdown', '2x12-15')]),
      TDay('Day C', [TItem('leg_press', '3x10-12'), TItem('incline_machine_press', '3x10-12'), TItem('machine_row', '3x10-12'), TItem('seated_leg_curl', '3x10-12'), TItem('pec_deck', '2x12-15'), TItem('cable_crunch', '2x12-15')]),
    ]),
  ),
  ProgramTemplate(
    id: 'stronglifts',
    perWeek: 3,
    name: 'StrongLifts 5×5',
    group: 'Beginner',
    about: 'Two workouts, A and B, three times a week. Five sets of five on the big barbell lifts; add a little weight every time you get all the reps. Three misses in a row and the weight drops 10%.',
    who: 'New to the barbell and want to get strong with as few exercises as possible.',
    length: 'Repeats until the weights stop climbing (often 3-6 months)',
    level: 0,
    goals: const {'strength', 'both'},
    weeks: _repeat(const [
      TDay('Workout A', [TItem('back_squat', '5x5'), TItem('bench_press', '5x5'), TItem('barbell_row', '5x5')]),
      TDay('Workout B', [TItem('back_squat', '5x5'), TItem('overhead_press', '5x5'), TItem('deadlift', '1x5')]),
    ]),
    rules: const {'back_squat': _lin, 'bench_press': _lin, 'barbell_row': _lin, 'overhead_press': _lin, 'deadlift': _lin2},
    credit: 'Follows the published StrongLifts 5×5 scheme.',
  ),
  ProgramTemplate(
    id: 'starting_strength',
    perWeek: 3,
    name: 'Starting Strength',
    group: 'Beginner',
    about: 'Three sets of five on squat every workout, presses alternating, deadlift or power clean to finish. Weight goes up every session you finish the sets.',
    who: 'New lifters who want strength first and are happy with short workouts.',
    length: 'Repeats until progress slows',
    level: 0,
    goals: const {'strength'},
    weeks: _repeat(const [
      TDay('Workout A', [TItem('back_squat', '3x5'), TItem('overhead_press', '3x5'), TItem('deadlift', '1x5')]),
      TDay('Workout B', [TItem('back_squat', '3x5'), TItem('bench_press', '3x5'), TItem('power_clean', '5x3')]),
    ]),
    rules: const {'back_squat': _lin, 'bench_press': _lin, 'overhead_press': _lin, 'deadlift': _lin2, 'power_clean': _lin},
    credit: 'Follows the published Starting Strength novice scheme (the later phase with power cleans).',
  ),
  ProgramTemplate(
    id: 'bbr',
    perWeek: 3,
    name: 'Basic beginner routine',
    group: 'Beginner',
    about: 'The r/Fitness basic beginner routine: rows, presses, squats and deadlifts for 3 sets of 5, the last set as many reps as you can.',
    who: 'New to lifting; wants a simple, well-known start with rows and chin-ups for balance.',
    length: 'Repeats; about 3 months',
    level: 0,
    goals: const {'strength', 'both'},
    weeks: _repeat(const [
      TDay('Workout A', [TItem('barbell_row', '3x5+'), TItem('bench_press', '3x5+'), TItem('back_squat', '3x5+')]),
      TDay('Workout B', [TItem('chin_up', '3x5+'), TItem('overhead_press', '3x5+'), TItem('deadlift', '1x5+')]),
    ]),
    rules: const {'back_squat': _lin, 'bench_press': _lin, 'barbell_row': _lin, 'overhead_press': _lin, 'deadlift': _lin2},
    credit: 'Follows the r/Fitness wiki basic beginner routine.',
  ),
  ProgramTemplate(
    id: 'greyskull',
    perWeek: 3,
    name: 'Greyskull LP',
    group: 'Beginner',
    about: 'Two sets of five and a last set of as many as you can. Get 10 or more on that last set and the weight jumps twice as much; miss and it drops 10%.',
    who: 'Beginners who like a push at the end of each lift and fewer total sets.',
    length: 'Repeats until progress slows',
    level: 0,
    goals: const {'strength', 'both'},
    weeks: _repeat(const [
      TDay('Workout A', [TItem('bench_press', '2x5 1x5+'), TItem('barbell_row', '2x5 1x5+'), TItem('back_squat', '2x5 1x5+')]),
      TDay('Workout B', [TItem('overhead_press', '2x5 1x5+'), TItem('chin_up', '2x5 1x5+'), TItem('deadlift', '1x5+')]),
    ]),
    rules: const {
      'bench_press': LiftRule(kind: 'linear', inc: 0.5, misses: 1, reset: 0.9, amrapGoal: 10),
      'barbell_row': LiftRule(kind: 'linear', inc: 0.5, misses: 1, reset: 0.9, amrapGoal: 10),
      'overhead_press': LiftRule(kind: 'linear', inc: 0.5, misses: 1, reset: 0.9, amrapGoal: 10),
      'back_squat': LiftRule(kind: 'linear', inc: 1, misses: 1, reset: 0.9, amrapGoal: 10),
      'deadlift': LiftRule(kind: 'linear', inc: 1, misses: 1, reset: 0.9, amrapGoal: 10),
    },
    credit: 'Follows the published Greyskull LP base scheme.',
  ),
  ProgramTemplate(
    id: 'ivysaur',
    perWeek: 3,
    name: 'Ivysaur 4-4-8',
    group: 'Beginner',
    about: 'Alternating A and B days with a heavy main press, a squat or deadlift, and a lighter press for 8s. Last sets are as many as you can.',
    who: 'Beginners who want a bit more upper-body work than 5×5 gives.',
    length: 'Repeats until progress slows',
    level: 0,
    goals: const {'strength', 'both', 'size'},
    weeks: _repeat(const [
      TDay('Workout A', [TItem('bench_press', '4x6+'), TItem('back_squat', '4x6+'), TItem('overhead_press', '4x8+', tier: 'L'), TItem('barbell_row', '3x8-12')]),
      TDay('Workout B', [TItem('overhead_press', '4x6+'), TItem('deadlift', '4x4+'), TItem('bench_press', '4x8+', tier: 'L'), TItem('chin_up', '3x6-10')]),
    ]),
    rules: const {'bench_press': _lin, 'back_squat': _lin, 'overhead_press': _lin, 'deadlift': _lin2, 'bench_press#L': _lin, 'overhead_press#L': _lin},
    credit: 'In the style of the Ivysaur 4-4-8 beginner program (one of its versions).',
  ),
  ProgramTemplate(
    id: 'madcow',
    tmBasis: '5rm',
    name: 'Madcow 5×5',
    group: 'Strength',
    about: 'A week-by-week step up from beginner 5×5: Monday heavy ramp, Wednesday light, Friday a new top triple. The top weights go up about 2.5% a week.',
    who: 'You finished a beginner program and can no longer add weight every workout.',
    length: 'Repeats weekly; usually 8-16 weeks',
    level: 1,
    goals: const {'strength', 'both'},
    weeks: _repeat(const [
      TDay('Monday heavy', [
        TItem('back_squat', '1x5@50 1x5@62.5 1x5@75 1x5@87.5 1x5@100'),
        TItem('bench_press', '1x5@50 1x5@62.5 1x5@75 1x5@87.5 1x5@100'),
        TItem('barbell_row', '1x5@50 1x5@62.5 1x5@75 1x5@87.5 1x5@100'),
      ]),
      TDay('Wednesday light', [
        TItem('back_squat', '1x5@50 1x5@62.5 1x5@75 1x5@75', tier: 'L', tmOf: 'back_squat'),
        TItem('overhead_press', '1x5@50 1x5@62.5 1x5@75 1x5@100', bump: 'tm'),
        TItem('deadlift', '1x5@50 1x5@62.5 1x5@75 1x5@100', bump: 'tm'),
      ]),
      TDay('Friday new top', [
        TItem('back_squat', '1x5@50 1x5@62.5 1x5@75 1x5@87.5 1x3@102.5 1x8@75', bump: 'tm'),
        TItem('bench_press', '1x5@50 1x5@62.5 1x5@75 1x5@87.5 1x3@102.5 1x8@75', bump: 'tm'),
        TItem('barbell_row', '1x5@50 1x5@62.5 1x5@75 1x5@87.5 1x3@102.5 1x8@75', bump: 'tm'),
      ]),
    ]),
    rules: const {'back_squat': _tm1, 'bench_press': _tm1, 'barbell_row': _tm1, 'overhead_press': _tm1, 'deadlift': _tm1},
    credit: 'Follows the published Madcow 5×5 ramping scheme; the training max is your Monday top set of 5.',
  ),
  ProgramTemplate(
    id: 'texas',
    tmBasis: '5rm',
    name: 'Texas Method',
    group: 'Strength',
    about: 'Volume on Monday, a light day Wednesday, a new five-rep best on Friday. Bench and press take turns each week.',
    who: 'Past the beginner stage and recover well from a hard Monday.',
    length: 'Repeats in two-week turns',
    level: 1,
    goals: const {'strength'},
    weeks: [
      const [
        TDay('Volume', [TItem('back_squat', '5x5@90'), TItem('bench_press', '5x5@90'), TItem('deadlift', '1x5@90')]),
        TDay('Recovery', [TItem('back_squat', '2x5@72', tier: 'L', tmOf: 'back_squat'), TItem('overhead_press', '3x5@90'), TItem('chin_up', '3x5-8')]),
        TDay('Intensity', [TItem('back_squat', '1x5+@100', bump: 'tm'), TItem('bench_press', '1x5+@100', bump: 'tm'), TItem('power_clean', '5x3')]),
      ],
      const [
        TDay('Volume', [TItem('back_squat', '5x5@90'), TItem('overhead_press', '5x5@90'), TItem('deadlift', '1x5+@100', bump: 'tm')]),
        TDay('Recovery', [TItem('back_squat', '2x5@72', tier: 'L', tmOf: 'back_squat'), TItem('bench_press', '3x5@90'), TItem('chin_up', '3x5-8')]),
        TDay('Intensity', [TItem('back_squat', '1x5+@100', bump: 'tm'), TItem('overhead_press', '1x5+@100', bump: 'tm'), TItem('power_clean', '5x3')]),
      ],
    ],
    rules: const {'back_squat': _tm1, 'bench_press': _tm1, 'overhead_press': _tm1, 'deadlift': _tm2, 'power_clean': _lin},
    credit: 'Follows the published Texas Method; the training max is your best set of 5.',
  ),

  // ---------------- 5/3/1 (F214) ----------------
  ProgramTemplate(
    id: '531_base',
    name: '5/3/1',
    group: '5/3/1',
    about: 'Four days, one main lift each. Three weeks of 5s, 3s and 5/3/1 at a % of a training max, then a light week. The last set of each main lift is as many as you can. The training max goes up after each cycle.',
    who: 'Past the beginner stage; want steady, slow progress for years.',
    length: '4-week cycles, repeats',
    level: 1,
    goals: const {'strength', 'both'},
    weeks: _five31((l, w) => _assist(l)),
    rules: const {'overhead_press': _tm1, 'bench_press': _tm1, 'deadlift': _tm2, 'back_squat': _tm2},
    credit: 'Follows the published 5/3/1 percentages (training max = 90% of your max).',
  ),
  ProgramTemplate(
    id: '531_beginners',
    name: '5/3/1 for beginners',
    group: '5/3/1',
    about: 'Three full-body days, two main lifts each with 5/3/1 sets plus five sets of five at the first-set weight. Push, pull and leg work after.',
    who: 'Early on but want the 5/3/1 way: a lot of practice on the big lifts.',
    length: '3-week cycles, repeats',
    level: 0,
    goals: const {'strength', 'both'},
    weeks: [
      for (var w = 0; w < 3; w++)
        [
          for (final (n, a, b) in const [('Day 1', 'back_squat', 'bench_press'), ('Day 2', 'deadlift', 'overhead_press'), ('Day 3', 'bench_press', 'back_squat')])
            TDay(n, [
              TItem(a, _w531[w], bump: w == 2 ? 'tm' : ''), // squat, deadlift, bench: once a cycle each
              TItem(a, _fslW[w], tier: 'F', tmOf: a),
              TItem(b, _w531[w], tier: n == 'Day 2' ? '' : 'B', tmOf: n == 'Day 2' ? '' : b, bump: w == 2 && n == 'Day 2' ? 'tm' : ''), // press
              TItem(b, _fslW[w], tier: 'F', tmOf: b),
              const TItem('chin_up', '3x6-10'),
              const TItem('dips', '3x8-12'),
            ])
        ]
    ],
    rules: const {'overhead_press': _tm1, 'bench_press': _tm1, 'deadlift': _tm2, 'back_squat': _tm2},
    credit: 'Follows the published 5/3/1 for Beginners layout.',
  ),
  ProgramTemplate(
    id: '531_bbb',
    name: '5/3/1 Boring But Big',
    group: '5/3/1',
    about: 'The main 5/3/1 lift, then five sets of ten of the same lift at 50% of the training max, and one more exercise. Big volume, simple choices.',
    who: 'Want size and strength together and like long, simple workouts.',
    length: '4-week cycles, repeats',
    level: 1,
    goals: const {'size', 'both'},
    weeks: _five31((l, w) => [if (w < 3) TItem(l, '5x10@50', tier: 'B', tmOf: l), ..._bbbAssist(l)]),
    rules: const {'overhead_press': _tm1, 'bench_press': _tm1, 'deadlift': _tm2, 'back_squat': _tm2},
    credit: 'Follows the published Boring But Big template.',
  ),
  ProgramTemplate(
    id: '531_fsl',
    name: '5/3/1 First Set Last',
    group: '5/3/1',
    about: 'After the main 5/3/1 sets, five sets of five at the first set\'s weight. Plus assistance.',
    who: 'Want more practice on the main lifts without the BBB fatigue.',
    length: '4-week cycles, repeats',
    level: 1,
    goals: const {'strength', 'both'},
    weeks: _five31((l, w) => [if (w < 3) TItem(l, _fslW[w], tier: 'F', tmOf: l), ..._assist(l).take(2)]),
    rules: const {'overhead_press': _tm1, 'bench_press': _tm1, 'deadlift': _tm2, 'back_squat': _tm2},
    credit: 'Follows the published First Set Last supplement.',
  ),
  ProgramTemplate(
    id: '531_ssl',
    name: '5/3/1 Second Set Last',
    group: '5/3/1',
    about: 'Like First Set Last but heavier: five sets of five at the second set\'s weight.',
    who: 'FSL feels easy and you recover well.',
    length: '4-week cycles, repeats',
    level: 2,
    goals: const {'strength'},
    weeks: _five31((l, w) => [if (w < 3) TItem(l, _sslW[w], tier: 'S', tmOf: l), ..._assist(l).take(2)]),
    rules: const {'overhead_press': _tm1, 'bench_press': _tm1, 'deadlift': _tm2, 'back_squat': _tm2},
    credit: 'Follows the published Second Set Last supplement.',
  ),
  ProgramTemplate(
    id: '531_triumvirate',
    name: '5/3/1 Triumvirate',
    group: '5/3/1',
    about: 'The main lift and exactly two assistance exercises, five sets each. Short and focused.',
    who: 'Little time; want the main lift plus a couple of helpers.',
    length: '4-week cycles, repeats',
    level: 1,
    goals: const {'strength', 'both'},
    weeks: _five31((l, w) => _tri(l)),
    rules: const {'overhead_press': _tm1, 'bench_press': _tm1, 'deadlift': _tm2, 'back_squat': _tm2},
    credit: 'Follows the published Triumvirate template.',
  ),
  ProgramTemplate(
    id: '531_bbs',
    name: '5/3/1 Boring But Strong',
    group: '5/3/1',
    about: 'After the main sets, ten sets of five at the first-set weight. A lot of heavy practice.',
    who: 'Strength first; you recover well from volume.',
    length: '4-week cycles, repeats',
    level: 2,
    goals: const {'strength'},
    weeks: _five31((l, w) => [if (w < 3) TItem(l, _bbsW[w], tier: 'S', tmOf: l), ..._bbbAssist(l)]),
    rules: const {'overhead_press': _tm1, 'bench_press': _tm1, 'deadlift': _tm2, 'back_squat': _tm2},
    credit: 'In the style of the Boring But Strong supplement.',
  ),
  ProgramTemplate(
    id: '531_leader_anchor',
    name: '5/3/1 Leader and Anchor',
    group: '5/3/1',
    about: 'Two Leader cycles (all sets of 5, more volume after), a 7th-week test of the training max, one Anchor cycle with + sets, then another 7th week.',
    who: 'Run 5/3/1 for a while and want planned volume and test blocks.',
    length: '11 weeks, then repeat',
    level: 2,
    goals: const {'strength', 'both'},
    weeks: [
      for (var c = 0; c < 2; c++) ..._five31((l, w) => [TItem(l, _fslW[w], tier: 'F', tmOf: l), ..._assist(l).take(2)], weeks: 3, sets: const ['1x5@65 1x5@75 1x5@85', '1x5@70 1x5@80 1x5@90', '1x5@75 1x5@85 1x5@95']), // each Leader cycle ends with a step up (week 3, every set hit)
      [for (final (n, id) in const [('Press', 'overhead_press'), ('Deadlift', 'deadlift'), ('Bench', 'bench_press'), ('Squat', 'back_squat')]) TDay('7th week · $n', [TItem(id, '1x5@70 1x5@80 1x1@90 1x3+@100', bump: 'check')])],
      ..._five31((l, w) => _assist(l).take(2).toList(), weeks: 3),
      [for (final (n, id) in const [('Press', 'overhead_press'), ('Deadlift', 'deadlift'), ('Bench', 'bench_press'), ('Squat', 'back_squat')]) TDay('7th week · $n', [TItem(id, '1x5@70 1x5@80 1x1@90 1x3+@100', bump: 'check')])],
    ],
    rules: const {'overhead_press': _tm1, 'bench_press': _tm1, 'deadlift': _tm2, 'back_squat': _tm2},
    credit: 'In the style of the published Leader / Anchor layout with the 7th-week training max test.',
  ),

  // ---------------- nSuns (F215) ----------------
  for (final d in const [4, 5, 6])
    ProgramTemplate(
      id: 'nsuns_$d',
      name: 'nSuns 5/3/1 LP · $d days',
      group: 'Strength',
      about: 'Lots of sets around a heavy single. How many reps you get on the 1+ set decides how much the training max goes up for next week (0-1 reps: stays; 2-3: one step; 4-5: two; 6+: three).',
      who: 'Late beginner to intermediate; long workouts and fast progress.',
      length: 'Weekly, repeats',
      level: 1,
      goals: const {'strength', 'both'},
      weeks: _repeat(_nsuns(d)),
      rules: const {'bench_press': _tm1, 'back_squat': _tm1, 'overhead_press': _tm1, 'deadlift': _tm1},
      credit: d == 4
          ? 'In the style of the nSuns 5/3/1 LP 4-day layout: here day 3 is an overhead press T1 day, where the published one has a second bench day with close-grip bench.'
          : 'Follows the published nSuns 5/3/1 LP layout.',
    ),

  // ---------------- GZCL (F213) ----------------
  ProgramTemplate(
    id: 'gzclp',
    perWeek: 3,
    name: 'GZCLP',
    group: 'GZCL',
    about: 'Three tiers each day. T1 heavy (5×3, last set +), T2 moderate (3×10), T3 light (3×15+). Miss and the sets change instead of the weight (5×3 → 6×2 → 10×1); T3 goes up when the last set reaches 25.',
    who: 'Beginners who want more than 5×5 and a clear plan for when a lift stalls.',
    length: 'Repeats until progress slows',
    level: 0,
    goals: const {'strength', 'both', 'size'},
    weeks: _repeat(const [
      TDay('Day 1', [TItem('back_squat', '5x3+'), TItem('bench_press', '3x10', tier: 'T2'), TItem('lat_pulldown', '3x15+')]),
      TDay('Day 2', [TItem('overhead_press', '5x3+'), TItem('deadlift', '3x10', tier: 'T2'), TItem('one_arm_db_row', '3x15+')]),
      TDay('Day 3', [TItem('bench_press', '5x3+'), TItem('back_squat', '3x10', tier: 'T2'), TItem('lat_pulldown', '3x15+')]),
      TDay('Day 4', [TItem('deadlift', '5x3+'), TItem('overhead_press', '3x10', tier: 'T2'), TItem('one_arm_db_row', '3x15+')]),
    ]),
    rules: const {
      'back_squat': _t1Low,
      'deadlift': _t1Low,
      'bench_press': _t1Up,
      'overhead_press': _t1Up,
      'back_squat#T2': _t2Low,
      'deadlift#T2': _t2Low,
      'bench_press#T2': _t2Up,
      'overhead_press#T2': _t2Up,
      'lat_pulldown': _t3,
      'one_arm_db_row': _t3,
    },
    credit: 'Follows the published GZCLP linear progression.',
  ),
  ProgramTemplate(
    id: 'gzcl_jt2',
    name: 'Jacked & Tan 2.0',
    group: 'GZCL',
    about: 'A 6-week block where the heavy T1 set gets lower in reps each week (10, 8, 6, 4, 2, 1) with back-off sets after, then T2 and T3 work for size. The last week sets a new training max.',
    who: 'Intermediate; want strength and size with a lot of variety in reps.',
    length: '6 weeks, then repeat with new maxes',
    level: 2,
    goals: const {'both', 'size', 'strength'},
    weeks: [
      for (final (w, t1) in const [
        (0, '1x10+@70 3x10@63'),
        (1, '1x8+@75 3x8@68'),
        (2, '1x6+@80 3x6@72'),
        (3, '1x4+@85 3x4@77'),
        (4, '1x2+@90 3x2@81'),
        (5, '1x1+@95 1x1+@100'),
      ])
        [
          TDay('Squat', [TItem('back_squat', t1, bump: w == 5 ? 'test' : ''), const TItem('romanian_deadlift', '4x8-10'), const TItem('leg_extension', '3x12-15')]),
          TDay('Bench', [TItem('bench_press', t1, bump: w == 5 ? 'test' : ''), const TItem('incline_db_press', '4x8-10'), const TItem('cable_fly', '3x12-15')]),
          TDay('Deadlift', [TItem('deadlift', t1, bump: w == 5 ? 'test' : ''), const TItem('front_squat', '4x6-8'), const TItem('lying_leg_curl', '3x12-15')]),
          TDay('Press', [TItem('overhead_press', t1, bump: w == 5 ? 'test' : ''), const TItem('chin_up', '4x6-10'), const TItem('db_lateral_raise', '3x12-15')]),
        ]
    ],
    rules: const {'back_squat': _tm1, 'bench_press': _tm1, 'deadlift': _tm1, 'overhead_press': _tm1},
    credit: 'In the style of GZCL Jacked & Tan 2.0 (block 1, simplified).',
  ),
  ProgramTemplate(
    id: 'gzcl_uhf',
    name: 'GZCL UHF',
    group: 'GZCL',
    about: 'Ultra high frequency: five shorter days with squat and bench almost every day, heavy one day and lighter the next. 4-week blocks that end with a test.',
    who: 'Intermediate; like training often and short sessions.',
    length: '4-week blocks',
    level: 2,
    goals: const {'strength', 'both'},
    weeks: [
      for (final (w, p) in const [(0, 80), (1, 85), (2, 90), (3, 70)])
        [
          TDay('Day 1', [TItem('back_squat', w == 3 ? _test : '5x3@$p', bump: w == 3 ? 'test' : ''), TItem('bench_press', '3x8@${p - 20}', tier: 'T2', tmOf: 'bench_press'), const TItem('lat_pulldown', '3x12-15')]),
          TDay('Day 2', [TItem('bench_press', w == 3 ? _test : '5x3@$p', bump: w == 3 ? 'test' : ''), TItem('deadlift', '3x6@${p - 15}', tier: 'T2', tmOf: 'deadlift'), const TItem('face_pull', '3x15-20')]),
          TDay('Day 3', [TItem('back_squat', '3x8@${p - 20}', tier: 'T2', tmOf: 'back_squat'), TItem('overhead_press', w == 3 ? _test : '5x3@$p', bump: w == 3 ? 'test' : ''), const TItem('barbell_row', '3x8-12')]),
          TDay('Day 4', [TItem('deadlift', w == 3 ? _test : '5x2@$p', bump: w == 3 ? 'test' : ''), TItem('bench_press', '3x8@${p - 20}', tier: 'T2', tmOf: 'bench_press'), const TItem('hanging_leg_raise', '3x10-15')]),
          TDay('Day 5', [TItem('back_squat', '3x5@${p - 10}', tier: 'T2', tmOf: 'back_squat'), TItem('overhead_press', '3x8@${p - 20}', tier: 'T2', tmOf: 'overhead_press'), const TItem('chin_up', '3x6-10')]),
        ]
    ],
    rules: const {'back_squat': _tm1, 'bench_press': _tm1, 'deadlift': _tm1, 'overhead_press': _tm1},
    credit: 'In the style of GZCL UHF (simplified).',
  ),
  ProgramTemplate(
    id: 'gzcl_rippler',
    name: 'The Rippler',
    group: 'GZCL',
    about: 'Twelve weeks where the heavy sets ripple up and back down in waves, the reps getting lower as the block goes on, with a test week at the end.',
    who: 'Intermediate; want a long, planned strength block.',
    length: '12 weeks',
    level: 2,
    goals: const {'strength', 'powerlifting'},
    weeks: [
      for (final (w, t1, t2) in const [
        (0, '3x5@80', '3x10@60'),
        (1, '3x5@82.5', '3x10@62.5'),
        (2, '3x5@80', '3x8@65'),
        (3, '3x5@85', '3x8@67.5'),
        (4, '3x3@85', '3x8@65'),
        (5, '3x3@87.5', '3x6@70'),
        (6, '3x3@85', '3x6@72.5'),
        (7, '3x3@90', '3x6@70'),
        (8, '3x2@90', '3x5@75'),
        (9, '3x2@92.5', '3x5@77.5'),
        (10, '2x1@95', '3x3@75'),
        (11, _test, ''),
      ])
        [
          for (final (n, a, b) in const [('Squat', 'back_squat', 'front_squat'), ('Bench', 'bench_press', 'close_grip_bench'), ('Deadlift', 'deadlift', 'romanian_deadlift'), ('Press', 'overhead_press', 'incline_bench_press')])
            TDay(n, [TItem(a, t1, bump: w == 11 ? 'test' : ''), if (t2.isNotEmpty) TItem(b, t2, tmOf: a, tier: 'T2'), if (w < 11) const TItem('lat_pulldown', '3x12-15')])
        ]
    ],
    rules: const {'back_squat': _tm1, 'bench_press': _tm1, 'deadlift': _tm1, 'overhead_press': _tm1},
    credit: 'In the style of GZCL\'s Rippler (simplified waves).',
  ),

  // ---------------- Size and simple (F216, F219) ----------------
  ProgramTemplate(
    id: 'reddit_ppl',
    name: 'Reddit PPL',
    group: 'Size and simple',
    about: 'Push, pull, legs, twice a week. A heavy 5×5 (last set +) leads each day, the rest is 8-12 and 15-20 rep work. Main lifts go up every session, the rest by reps first.',
    who: 'Beginner to intermediate with time for six days.',
    length: 'Repeats',
    level: 0,
    goals: const {'size', 'both'},
    weeks: _repeat(const [
      TDay('Pull A', [TItem('deadlift', '1x5+'), TItem('lat_pulldown', '3x8-12'), TItem('seated_cable_row', '3x8-12'), TItem('face_pull', '5x15-20'), TItem('hammer_curl', '4x8-12'), TItem('db_curl', '4x8-12')]),
      TDay('Push A', [TItem('bench_press', '4x5 1x5+'), TItem('overhead_press', '3x8-12', tier: 'L'), TItem('incline_db_press', '3x8-12'), TItem('triceps_pushdown', '3x8-12'), TItem('db_overhead_ext', '3x8-12'), TItem('db_lateral_raise', '3x15-20')]),
      TDay('Legs A', [TItem('back_squat', '2x5 1x5+'), TItem('romanian_deadlift', '3x8-12'), TItem('leg_press', '3x8-12'), TItem('lying_leg_curl', '3x8-12'), TItem('standing_calf_raise', '5x8-12')]),
      TDay('Pull B', [TItem('barbell_row', '4x5 1x5+'), TItem('pull_up', '3x8-12'), TItem('seated_cable_row', '3x8-12'), TItem('face_pull', '5x15-20'), TItem('hammer_curl', '4x8-12'), TItem('db_curl', '4x8-12')]),
      TDay('Push B', [TItem('overhead_press', '4x5 1x5+'), TItem('bench_press', '3x8-12', tier: 'L'), TItem('incline_db_press', '3x8-12'), TItem('triceps_pushdown', '3x8-12'), TItem('db_overhead_ext', '3x8-12'), TItem('db_lateral_raise', '3x15-20')]),
      TDay('Legs B', [TItem('back_squat', '2x5 1x5+'), TItem('romanian_deadlift', '3x8-12'), TItem('leg_press', '3x8-12'), TItem('lying_leg_curl', '3x8-12'), TItem('standing_calf_raise', '5x8-12')]),
    ]),
    rules: const {'deadlift': _lin2, 'bench_press': _lin, 'barbell_row': _lin, 'overhead_press': _lin, 'back_squat': _lin},
    credit: 'Follows the published r/Fitness "Reddit PPL" (Metallicadpa) layout.',
  ),
  ProgramTemplate(
    id: 'phul',
    name: 'PHUL',
    group: 'Size and simple',
    about: 'Power hypertrophy upper lower: two heavy days (3-5 reps) and two size days (8-12 reps) a week.',
    who: 'Some experience; want strength and size in four days.',
    length: 'Repeats',
    level: 1,
    goals: const {'both', 'size'},
    weeks: _repeat(const [
      TDay('Upper power', [TItem('bench_press', '4x3-5'), TItem('incline_db_press', '4x6-10'), TItem('barbell_row', '4x3-5'), TItem('lat_pulldown', '4x6-10'), TItem('overhead_press', '3x5-8'), TItem('barbell_curl', '3x6-10'), TItem('skull_crusher', '3x6-10')]),
      TDay('Lower power', [TItem('back_squat', '4x3-5'), TItem('deadlift', '3x3-5'), TItem('leg_press', '4x10-15'), TItem('lying_leg_curl', '4x6-10'), TItem('standing_calf_raise', '4x6-10')]),
      TDay('Upper hypertrophy', [TItem('incline_bench_press', '4x8-12'), TItem('db_fly', '3x8-12'), TItem('seated_cable_row', '4x8-12'), TItem('one_arm_db_row', '3x8-12'), TItem('db_lateral_raise', '3x8-12'), TItem('incline_db_curl', '3x8-12'), TItem('overhead_cable_ext', '3x8-12')]),
      TDay('Lower hypertrophy', [TItem('front_squat', '4x8-12'), TItem('walking_lunge', '3x8-12'), TItem('leg_extension', '3x10-15'), TItem('seated_leg_curl', '3x10-15'), TItem('seated_calf_raise', '4x8-12')]),
    ]),
    credit: 'Follows the published PHUL layout.',
  ),
  ProgramTemplate(
    id: 'phat',
    name: 'PHAT',
    group: 'Size and simple',
    about: 'Power hypertrophy adaptive training: two power days and three body-part size days, five days a week.',
    who: 'Intermediate with time for five days; size first, strength kept up.',
    length: 'Repeats',
    level: 2,
    goals: const {'size', 'both'},
    weeks: _repeat(const [
      TDay('Upper power', [TItem('pendlay_row', '3x3-5', bump: 'tm'), TItem('pull_up', '2x6-10'), TItem('bench_press', '3x3-5', bump: 'tm'), TItem('dips', '2x6-10'), TItem('seated_db_press', '3x6-10'), TItem('barbell_curl', '3x6-10'), TItem('skull_crusher', '3x6-10')]),
      TDay('Lower power', [TItem('back_squat', '3x3-5', bump: 'tm'), TItem('hack_squat', '2x6-10'), TItem('leg_extension', '2x6-10'), TItem('stiff_leg_deadlift', '3x5-8'), TItem('lying_leg_curl', '2x6-10'), TItem('standing_calf_raise', '3x6-10')]),
      TDay('Back and shoulders', [TItem('barbell_row', '6x3@70', tier: 'S', tmOf: 'pendlay_row'), TItem('chest_supported_row', '3x8-12'), TItem('lat_pulldown', '3x8-12'), TItem('seated_cable_row', '2x12-15'), TItem('db_lateral_raise', '3x12-20'), TItem('db_rear_delt_fly', '3x12-20')]),
      TDay('Legs', [TItem('back_squat', '6x3@70', tier: 'S', tmOf: 'back_squat'), TItem('hack_squat', '3x8-12'), TItem('leg_press', '2x12-15'), TItem('leg_extension', '3x15-20'), TItem('romanian_deadlift', '3x8-12'), TItem('seated_leg_curl', '2x12-15'), TItem('seated_calf_raise', '4x10-15')]),
      TDay('Chest and arms', [TItem('db_bench_press', '6x3@70', tier: 'S', tmOf: 'bench_press'), TItem('incline_db_press', '3x8-12'), TItem('cable_fly', '2x15-20'), TItem('preacher_curl_machine', '3x8-12'), TItem('triceps_pushdown', '3x8-12'), TItem('hammer_curl', '2x12-15'), TItem('overhead_cable_ext', '2x12-15')]),
    ]),
    rules: const {'pendlay_row': _tm1, 'back_squat': _tm1, 'bench_press': _tm1},
    credit: 'In the style of PHAT; the speed sets use 70% of the power-day weight.',
  ),
  ProgramTemplate(
    id: 'glutes',
    name: 'Glute focus',
    group: 'Size and simple',
    about: 'Three lower-body days built around hip thrusts, hinges and single-leg work, with a short upper-body finisher. Our own program.',
    who: 'Want glutes and legs to grow most; any level.',
    length: 'Repeats',
    level: 0,
    goals: const {'size', 'fitness'},
    needs: const {},
    weeks: _repeat(const [
      TDay('Heavy hips', [TItem('hip_thrust', '4x6-10'), TItem('romanian_deadlift', '3x8-10'), TItem('db_split_squat', '3x8-12'), TItem('hip_abduction', '3x15-20'), TItem('lat_pulldown', '3x10-12')]),
      TDay('Squat and step', [TItem('goblet_squat', '3x8-12'), TItem('db_step_up', '3x10-12'), TItem('cable_pull_through', '3x12-15'), TItem('glute_kickback', '3x12-15'), TItem('db_bench_press', '3x10-12')]),
      TDay('Pump', [TItem('barbell_glute_bridge', '3x12-15'), TItem('walking_lunge', '3x12-16'), TItem('back_extension', '3x12-15'), TItem('cable_hip_abduction', '3x15-20'), TItem('seated_cable_row', '3x10-12')]),
    ]),
  ),
  ProgramTemplate(
    id: 'minimal_2',
    perWeek: 2,
    name: 'Minimalist 2-day',
    group: 'Size and simple',
    about: 'Two full-body workouts a week, four or five exercises each. The least that keeps strength and muscle climbing. Our own program.',
    who: 'Busy weeks, or lifting next to a sport.',
    length: 'Repeats',
    level: 0,
    goals: const {'both', 'fitness', 'strength'},
    weeks: _repeat(const [
      TDay('Day A', [TItem('back_squat', '3x5-8'), TItem('bench_press', '3x5-8'), TItem('barbell_row', '3x6-10'), TItem('lying_leg_curl', '2x10-12'), TItem('plank', '2x30-60')]),
      TDay('Day B', [TItem('deadlift', '2x4-6'), TItem('overhead_press', '3x5-8'), TItem('pull_up', '3x5-10'), TItem('walking_lunge', '2x8-12'), TItem('hanging_leg_raise', '2x8-12')]),
    ]),
  ),
  ProgramTemplate(
    id: 'dumbbell_home',
    name: 'Home dumbbells',
    group: 'Size and simple',
    about: 'Three full-body days with only dumbbells, a bench and your body weight. Reps climb before the weight. Our own program.',
    who: 'Training at home or in a small gym.',
    length: 'Repeats',
    level: 0,
    goals: const {'size', 'both', 'fitness'},
    needs: const {Equipment.dumbbell},
    weeks: _repeat(const [
      TDay('Day A', [TItem('goblet_squat', '3x8-12'), TItem('db_bench_press', '3x8-12'), TItem('one_arm_db_row', '3x8-12'), TItem('db_romanian_deadlift', '3x8-12'), TItem('db_lateral_raise', '2x12-15'), TItem('db_curl', '2x10-12')]),
      TDay('Day B', [TItem('db_split_squat', '3x8-12'), TItem('standing_db_press', '3x8-12'), TItem('chest_supported_db_row', '3x8-12'), TItem('db_hip_thrust', '3x10-12'), TItem('push_up', '2x8-20'), TItem('db_overhead_ext', '2x10-12')]),
      TDay('Day C', [TItem('db_reverse_lunge', '3x8-12'), TItem('incline_db_press', '3x8-12'), TItem('db_pullover', '3x10-12'), TItem('db_leg_curl', '3x10-12'), TItem('hammer_curl', '2x10-12'), TItem('dead_bug', '2x10-12')]),
    ]),
  ),
  ProgramTemplate(
    id: 'rising_ul',
    name: 'Rising volume upper / lower',
    group: 'Size and simple',
    about: 'A 5-week size block: sets go up a little each week while you stay a rep or two short of failure, then an easy week before the next block. Our own program in the style of modern science-based plans.',
    who: 'Some experience; size is the goal.',
    length: '5-week blocks, repeats',
    level: 1,
    goals: const {'size'},
    needs: const {},
    weeks: [
      for (final n in const [2, 3, 3, 4, 2])
        [
          TDay('Upper A', [TItem('incline_db_press', '${n}x6-10'), TItem('chest_supported_row', '${n}x8-12'), TItem('machine_shoulder_press', '${n}x8-12'), TItem('lat_pulldown', '${n}x10-12'), TItem('bayesian_curl', '${n}x10-15'), TItem('overhead_cable_ext', '${n}x10-15')]),
          TDay('Lower A', [TItem('hack_squat', '${n}x6-10'), TItem('romanian_deadlift', '${n}x8-10'), TItem('seated_leg_curl', '${n}x10-12'), TItem('leg_extension', '${n}x10-15'), TItem('standing_calf_raise', '${n}x10-15')]),
          TDay('Upper B', [TItem('machine_chest_press', '${n}x8-12'), TItem('single_arm_pulldown', '${n}x10-12'), TItem('cable_lateral_raise', '${n}x12-15'), TItem('seated_cable_row', '${n}x8-12'), TItem('low_cable_fly', '${n}x12-15'), TItem('incline_db_curl', '${n}x10-12')]),
          TDay('Lower B', [TItem('leg_press', '${n}x10-15'), TItem('db_split_squat', '${n}x8-12'), TItem('lying_leg_curl', '${n}x10-12'), TItem('hip_thrust', '${n}x8-12'), TItem('seated_calf_raise', '${n}x12-15')]),
        ]
    ],
  ),
  ProgramTemplate(
    id: 'rising_fb',
    name: 'Full body size, 3 days',
    group: 'Size and simple',
    about: 'Three full-body days with a different main exercise for each muscle each day, sets rising over 4 weeks, then an easy week. Our own program.',
    who: 'Size on three days a week; beginner to intermediate.',
    length: '5-week blocks, repeats',
    level: 0,
    goals: const {'size', 'both'},
    needs: const {},
    weeks: [
      for (final n in const [2, 3, 3, 4, 2])
        [
          TDay('Day 1', [TItem('back_squat', '${n}x6-10'), TItem('bench_press', '${n}x6-10'), TItem('lat_pulldown', '${n}x8-12'), TItem('lying_leg_curl', '${n}x10-12'), TItem('db_lateral_raise', '${n}x12-15')]),
          TDay('Day 2', [TItem('romanian_deadlift', '${n}x6-10'), TItem('seated_db_press', '${n}x8-12'), TItem('chest_supported_row', '${n}x8-12'), TItem('leg_extension', '${n}x12-15'), TItem('incline_db_curl', '${n}x10-12')]),
          TDay('Day 3', [TItem('leg_press', '${n}x10-15'), TItem('incline_db_press', '${n}x8-12'), TItem('seated_cable_row', '${n}x8-12'), TItem('hip_thrust', '${n}x8-12'), TItem('overhead_cable_ext', '${n}x10-15')]),
        ]
    ],
  ),

  // ---------------- Powerlifting blocks (F217, F218) ----------------
  ProgramTemplate(
    id: 'smolov_jr',
    tmBasis: '1rm',
    name: 'Smolov Jr',
    group: 'Powerlifting blocks',
    about: 'Three hard weeks of one lift four days a week (6×6, 7×5, 8×4, 10×3), heavier each week, then a test. Swap the bench in for the squat if you want it for bench.',
    who: 'Experienced lifters wanting a fast jump on one lift. Hard on the joints.',
    length: '3 weeks + test',
    level: 2,
    goals: const {'strength', 'powerlifting'},
    weeks: [
      for (final add in const [0, 2.5, 5])
        [
          for (final (n, s, p) in const [('Day 1', '6x6', 70), ('Day 2', '7x5', 75), ('Day 3', '8x4', 80), ('Day 4', '10x3', 85)]) TDay(n, [TItem('back_squat', '$s@${p + add}')])
        ],
      [TDay('Test', [TItem('back_squat', _test, bump: 'test')])],
    ],
    rules: const {'back_squat': _tm1},
    credit: 'Follows the published Smolov Jr percentages (of your max).',
  ),
  ProgramTemplate(
    id: 'smolov_base',
    tmBasis: '1rm',
    name: 'Smolov base cycle',
    group: 'Powerlifting blocks',
    about: 'The base mesocycle of Smolov for the squat: four days a week, very high volume (4×9, 5×7, 7×5, 10×3), three weeks, then a test.',
    who: 'Experienced squatters only; plan around little else heavy.',
    length: '3 weeks + test',
    level: 2,
    goals: const {'strength', 'powerlifting'},
    weeks: [
      for (final add in const [0, 5, 7.5])
        [
          for (final (n, s, p) in const [('Day 1', '4x9', 70), ('Day 2', '5x7', 75), ('Day 3', '7x5', 80), ('Day 4', '10x3', 85)]) TDay(n, [TItem('back_squat', '$s@${p + add}')])
        ],
      [TDay('Test', [TItem('back_squat', _test, bump: 'test')])],
    ],
    rules: const {'back_squat': _tm1},
    credit: 'Follows the published Smolov base mesocycle.',
  ),
  ProgramTemplate(
    id: 'candito',
    tmBasis: '1rm',
    name: 'Candito 6-week strength',
    group: 'Powerlifting blocks',
    about: 'Six weeks from volume to heavy: conditioning and size work first, then heavier triples, doubles and singles, ending with a test of squat, bench and deadlift.',
    who: 'Intermediate powerlifters before a meet or a test day.',
    length: '6 weeks',
    level: 2,
    goals: const {'powerlifting', 'strength'},
    weeks: [
      for (final (w, sq, bp, dl) in const [
        (0, '4x6@80', '4x6@80', '2x6@80'),
        (1, '3x8@75', '3x8@75', '3x6@75'),
        (2, '3x4@85', '3x4@85', '2x4@85'),
        (3, '3x3@87.5', '3x3@87.5', '2x3@87.5'),
        (4, '1x2@92.5 1x1@95', '1x2@92.5 1x1@95', '1x1@92.5'),
        (5, _test, _test, _test),
      ])
        [
          TDay('Lower', [TItem('back_squat', sq, bump: w == 5 ? 'test' : ''), TItem('deadlift', dl, bump: w == 5 ? 'test' : ''), if (w < 5) const TItem('lying_leg_curl', '3x8-12')]),
          TDay('Upper', [TItem('bench_press', bp, bump: w == 5 ? 'test' : ''), if (w < 5) const TItem('barbell_row', '3x8-10'), if (w < 5) const TItem('seated_db_press', '3x8-10')]),
          if (w < 5) TDay('Lower 2', [TItem('back_squat', w < 2 ? '3x8@70' : '3x5@75', tier: 'L', tmOf: 'back_squat'), const TItem('romanian_deadlift', '3x8-10')]),
          if (w < 5) TDay('Upper 2', [TItem('bench_press', w < 2 ? '3x10@65' : '4x5@75', tier: 'L', tmOf: 'bench_press'), const TItem('pull_up', '3x6-10'), const TItem('dips', '3x8-12')]),
        ]
    ],
    rules: const {'back_squat': _tm1, 'bench_press': _tm1, 'deadlift': _tm1},
    credit: 'In the style of Candito\'s 6-week strength program (simplified).',
  ),
  ProgramTemplate(
    id: 'sheiko_style',
    tmBasis: '1rm',
    name: 'Sheiko-style prep',
    group: 'Powerlifting blocks',
    about: 'Three days a week, many sets of few reps at moderate weights, squat, bench and deadlift practised often. Four weeks, the last lighter. Our own program in the Russian high-practice style.',
    who: 'Intermediate powerlifters who like technique practice over max effort.',
    length: '4 weeks, repeats',
    level: 2,
    goals: const {'powerlifting', 'strength'},
    weeks: [
      for (final p in const [0.0, 2.5, 5.0, -10.0])
        [
          TDay('Day 1', [TItem('back_squat', '1x5@${50 + p} 1x4@${60 + p} 2x3@${70 + p} 4x3@${75 + p}', bump: p == 5.0 ? 'tm' : ''), TItem('bench_press', '1x5@${50 + p} 1x4@${60 + p} 2x3@${70 + p} 4x4@${75 + p}', bump: p == 5.0 ? 'tm' : ''), const TItem('db_fly', '4x10'), const TItem('good_morning', '4x5')]),
          TDay('Day 2', [TItem('deadlift', '1x4@${50 + p} 1x4@${60 + p} 2x3@${70 + p} 3x3@${75 + p}', bump: p == 5.0 ? 'tm' : ''), TItem('bench_press', '1x6@${50 + p} 4x5@${65 + p}', tier: 'L', tmOf: 'bench_press'), const TItem('dips', '4x8-10'), const TItem('hanging_leg_raise', '3x10')]),
          TDay('Day 3', [TItem('back_squat', '1x5@${50 + p} 1x4@${60 + p} 5x3@${70 + p}', tier: 'L', tmOf: 'back_squat'), TItem('bench_press', '1x5@${50 + p} 1x4@${60 + p} 2x3@${70 + p} 3x2@${80 + p}'), const TItem('lat_pulldown', '4x8-10')]),
        ]
    ],
    rules: const {'back_squat': _tm1, 'bench_press': _tm1, 'deadlift': _tm1},
    credit: 'Our own program in the style of Sheiko\'s layouts.',
  ),
  ProgramTemplate(
    id: 'juggernaut',
    name: 'Juggernaut',
    group: 'Powerlifting blocks',
    about: 'Four 4-week waves (10s, 8s, 6s, 3s). Each wave builds, peaks with a + set, then deloads. Every rep past the target on the + set adds to the training max.',
    who: 'Intermediate; want 16 weeks planned from volume to strength.',
    length: '16 weeks',
    level: 2,
    goals: const {'strength', 'powerlifting', 'both'},
    weeks: _juggernaut(),
    rules: const {'back_squat': LiftRule(kind: 'tm', inc: 2), 'deadlift': LiftRule(kind: 'tm', inc: 2), 'bench_press': _tm1, 'overhead_press': _tm1},
    credit: 'In the style of the Juggernaut method waves.',
  ),
  ProgramTemplate(
    id: 'conjugate',
    tmBasis: '1rm',
    name: 'Conjugate',
    group: 'Powerlifting blocks',
    about: 'Four days: max-effort lower and upper (work up to a heavy single on a variation that changes every week) and dynamic-effort lower and upper (fast sets at 50-60% in 3-week waves).',
    who: 'Experienced lifters who like variety and heavy singles.',
    length: '3-week waves, repeats',
    level: 2,
    goals: const {'powerlifting', 'strength'},
    weeks: [
      for (final (me1, me2, de) in const [('box_squat', 'floor_press', 50), ('good_morning', 'close_grip_bench', 55), ('deficit_deadlift', 'incline_bench_press', 60)])
        [
          TDay('Max effort lower', [TItem(me1, _test, bump: 'test'), const TItem('reverse_hyper', '3x10-15'), const TItem('glute_ham_raise', '3x8-12'), const TItem('hanging_leg_raise', '3x10-15')]),
          TDay('Max effort upper', [TItem(me2, _test, bump: 'test'), const TItem('dips', '3x8-12'), const TItem('barbell_row', '4x8-10'), const TItem('face_pull', '3x15-20')]),
          TDay('Dynamic lower', [TItem('box_squat', '12x2@$de', tier: 'D', tmOf: 'back_squat', bump: de == 60 ? 'tm' : ''), TItem('deadlift', '6x1@${de + 10}', tier: 'D', tmOf: 'deadlift', bump: de == 60 ? 'tm' : ''), const TItem('lying_leg_curl', '3x10-12'), const TItem('ab_wheel', '3x10-15')]),
          TDay('Dynamic upper', [TItem('bench_press', '9x3@$de', tier: 'D', tmOf: 'bench_press', bump: de == 60 ? 'tm' : ''), const TItem('triceps_pushdown', '4x12-15'), const TItem('lat_pulldown', '4x10-12'), const TItem('db_rear_delt_fly', '3x15-20')]),
        ]
    ],
    rules: const {'box_squat': _tm1, 'good_morning': _tm1, 'deficit_deadlift': _tm1, 'floor_press': _tm1, 'close_grip_bench': _tm1, 'incline_bench_press': _tm1, 'back_squat': _tm1, 'deadlift': _tm1, 'bench_press': _tm1},
    credit: 'In the style of Westside conjugate training.',
  ),

  // ---------------- Bodyweight (F220) ----------------
  ProgramTemplate(
    id: 'bwf_rr',
    perWeek: 3,
    name: 'Bodyweight recommended routine',
    group: 'Bodyweight',
    about: 'The r/bodyweightfitness recommended routine as ladders: pull, squat, dip, hinge, row and push. When every set reaches the top of the range you move up to the harder exercise; miss twice and you step back.',
    who: 'Any level, no gym needed (a bar and rings or a table help).',
    length: 'Repeats',
    level: 0,
    goals: const {'fitness', 'both', 'size'},
    needs: const {},
    weeks: _repeat(const [
      TDay('Routine', [
        TItem('band_assisted_pull_up', '3x5-8'),
        TItem('air_squat', '3x5-8'),
        TItem('bench_dip', '3x5-8'),
        TItem('glute_bridge', '3x5-8'),
        TItem('inverted_row', '3x5-8'),
        TItem('incline_push_up', '3x5-8'),
        TItem('plank', '3x20-40'),
      ]),
    ]),
    rules: {
      'band_assisted_pull_up': _ladder(const ['band_assisted_pull_up', 'chin_up', 'pull_up']),
      'air_squat': _ladder(const ['air_squat', 'bodyweight_lunge', 'band_split_squat', 'pistol_squat']),
      'bench_dip': _ladder(const ['bench_dip', 'dips', 'weighted_dip']),
      'glute_bridge': _ladder(const ['glute_bridge', 'single_leg_hip_thrust', 'back_extension', 'nordic_curl']),
      'inverted_row': _ladder(const ['trx_row', 'inverted_row']),
      'incline_push_up': _ladder(const ['incline_push_up', 'push_up', 'diamond_push_up', 'decline_push_up', 'pike_push_up', 'handstand_push_up']),
      'plank': _ladder(const ['plank', 'side_plank', 'hollow_hold']),
    },
    credit: 'Follows the r/bodyweightfitness recommended routine, with this library\'s exercises as the steps.',
  ),
  ProgramTemplate(
    id: 'cali_ladders',
    perWeek: 4,
    name: 'Calisthenics ladders',
    group: 'Bodyweight',
    about: 'Push-up, pull-up, squat and hold ladders on alternating days, four sets each. Each exercise is a step; reach the top of the range on every set and you climb.',
    who: 'Want to build up to pull-ups, pistols and handstand push-ups.',
    length: 'Repeats',
    level: 0,
    goals: const {'fitness', 'strength'},
    needs: const {},
    weeks: _repeat(const [
      TDay('Push and legs', [TItem('incline_push_up', '4x6-12'), TItem('air_squat', '4x8-15'), TItem('bench_dip', '3x6-12'), TItem('plank', '3x20-45')]),
      TDay('Pull and core', [TItem('band_assisted_pull_up', '4x4-8'), TItem('inverted_row', '3x6-12'), TItem('glute_bridge', '3x8-15'), TItem('lying_leg_raise', '3x8-12')]),
    ]),
    rules: {
      'incline_push_up': _ladder(const ['incline_push_up', 'push_up', 'diamond_push_up', 'decline_push_up', 'pike_push_up', 'handstand_push_up']),
      'band_assisted_pull_up': _ladder(const ['band_assisted_pull_up', 'chin_up', 'pull_up']),
      'air_squat': _ladder(const ['air_squat', 'bodyweight_lunge', 'band_split_squat', 'pistol_squat']),
      'bench_dip': _ladder(const ['bench_dip', 'dips', 'weighted_dip']),
      'inverted_row': _ladder(const ['trx_row', 'inverted_row']),
      'glute_bridge': _ladder(const ['glute_bridge', 'single_leg_hip_thrust', 'nordic_curl']),
      'plank': _ladder(const ['plank', 'side_plank', 'hollow_hold']),
      'lying_leg_raise': _ladder(const ['lying_leg_raise', 'hanging_leg_raise', 'toes_to_bar', 'dragon_flag']),
    },
  ),
];

ProgramTemplate? templateById(String id) => programTemplates.where((t) => t.id == id).firstOrNull;

int _restFor(List<SetSpec> l) {
  final low = l.map((x) => x.reps).reduce((a, b) => a < b ? a : b);
  final heavy = l.any((x) => (x.pct ?? 0) >= 0.8);
  if (heavy || low <= 3) return 180;
  if (low <= 6) return 150;
  if (low <= 10) return 105;
  return 75;
}

const _equipOrder = [Equipment.barbell, Equipment.smith, Equipment.dumbbell, Equipment.machine, Equipment.cable, Equipment.kettlebell, Equipment.bodyweight, Equipment.band];

/// The exercise this gym can do for [id]: itself, or the closest one in its swap group.
String? resolveFor(String id, Profile p, Library lib) {
  final e = lib.byId(id);
  if (e == null) return null;
  if (lib.usable(e, p.have, p.avoid, items: p.items)) return id;
  final c = [for (final x in lib.all) if (x.swap == e.swap && x.bodyweight == e.bodyweight && lib.usable(x, p.have, p.avoid, items: p.items)) x];
  if (c.isEmpty) {
    c.addAll([for (final x in lib.all) if (x.swap == e.swap && lib.usable(x, p.have, p.avoid, items: p.items)) x]);
  }
  if (c.isEmpty) return null;
  c.sort((a, b) {
    if (a.compound != b.compound) return a.compound == e.compound ? -1 : 1;
    return _equipOrder.indexOf(a.equipment).compareTo(_equipOrder.indexOf(b.equipment));
  });
  return c.first.id;
}

String _key(String id, String tier) => tier.isEmpty ? id : '$id#$tier';

/// Builds a program for this person and gym. Exercises the gym lacks are swapped for the closest
/// one it has; ladders start on the first step this gym can do.
Plan buildProgram(ProgramTemplate t, Profile p, Library lib) {
  final map = <String, String?>{};
  String? res(String id) => map.putIfAbsent(id, () => resolveFor(id, p, lib));
  final rules = <String, LiftRule>{};
  // ladders: only the steps this gym can do; the first of them is where you start
  for (final e in t.rules.entries) {
    final r = e.value;
    if (r.kind == 'ladder') {
      final steps = [for (final id in r.ladder) if (lib.byId(id) != null && lib.usable(lib.byId(id)!, p.have, p.avoid, items: p.items)) id];
      if (steps.isEmpty) continue;
      map[e.key] = steps.first;
      rules[steps.first] = r.copyWith(ladder: steps);
    }
  }
  for (final e in t.rules.entries) {
    if (e.value.kind == 'ladder') continue;
    final parts = e.key.split('#');
    final id = res(parts.first);
    if (id == null) continue;
    rules[_key(id, parts.length > 1 ? parts[1] : '')] = e.value;
  }
  final days = <PlanDay>[];
  for (var w = 0; w < t.weeks.length; w++) {
    for (final d in t.weeks[w]) {
      final items = <PlanItem>[];
      for (final it in d.items) {
        final id = res(it.ex);
        if (id == null || it.sets.isEmpty) continue;
        final specs = parseSets(it.sets);
        items.add(PlanItem.of(id, specs, rest: it.rest > 0 ? it.rest : _restFor(specs), tier: it.tier, tmOf: it.tmOf.isEmpty ? '' : (res(it.tmOf) ?? ''), bump: it.bump));
      }
      days.add(PlanDay(name: t.weeks.length > 1 ? 'W${w + 1} · ${d.name}' : d.name, items: items));
    }
  }
  return Plan(name: t.name, source: 'program', days: days, program: ProgramInfo(id: t.id, rules: rules, basis: t.tmBasis), weeksPerCycle: t.weeks.length);
}

/// What this gym changes in the template: "Back squat → Leg press", or "no Power clean".
List<String> programSwaps(ProgramTemplate t, Profile p, Library lib) {
  final out = <String>[];
  final seen = <String>{};
  for (final w in t.weeks) {
    for (final d in w) {
      for (final it in d.items) {
        if (!seen.add(it.ex)) continue;
        final e = lib.byId(it.ex);
        final ladder = t.rules[it.ex]?.kind == 'ladder';
        if (e == null || ladder) continue;
        final r = resolveFor(it.ex, p, lib);
        if (r == null) {
          out.add('no ${e.name}');
        } else if (r != it.ex) {
          out.add('${e.name} → ${lib.byId(r)!.name}');
        }
      }
    }
  }
  return out;
}

/// The training maxes a program needs: lift key -> exercise id (for the name).
Map<String, String> programMaxes(Plan plan) {
  final out = <String, String>{};
  for (final d in plan.days) {
    for (final it in d.items) {
      if (it.perSet == null || !it.perSet!.any((x) => x.pct != null)) continue;
      final k = it.tmOf.isNotEmpty ? it.tmOf : liftKey(it);
      out.putIfAbsent(k, () => k.split('#').first);
    }
  }
  return out;
}

/// "Which is right for me?" (F211): the templates ranked for these answers, best first.
List<ProgramTemplate> suggestPrograms({required int level, required int days, required String goal, required Set<Equipment> have}) {
  int score(ProgramTemplate t) {
    var s = 0;
    s -= (t.level - level).abs() * 4;
    if (t.level > level) s -= 3; // too advanced is worse than too easy
    s -= (t.days - days).abs() * 2;
    if (t.goals.contains(goal)) s += 4;
    if (!t.needs.every(have.contains)) s -= 10;
    if (!have.contains(Equipment.barbell) && t.needs.isEmpty) s += 2;
    return s;
  }

  final l = [...programTemplates]..sort((a, b) => score(b).compareTo(score(a)));
  return l;
}
