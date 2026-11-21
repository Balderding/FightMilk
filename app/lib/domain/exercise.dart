enum Equipment { barbell, dumbbell, machine, cable, smith, kettlebell, band, bodyweight }

enum Joint { shoulders, lowerBack, knees, wrists }

enum StepKind { barbell, dumbbell, machine, cable, bodyweight }

const equipmentLabel = {
  Equipment.barbell: 'Barbells',
  Equipment.dumbbell: 'Dumbbells',
  Equipment.machine: 'Machines',
  Equipment.cable: 'Cables',
  Equipment.smith: 'Smith',
  Equipment.kettlebell: 'Kettlebells',
  Equipment.band: 'Bands',
  Equipment.bodyweight: 'Bodyweight',
};

const jointLabel = {
  Joint.shoulders: 'Shoulders',
  Joint.lowerBack: 'Lower back',
  Joint.knees: 'Knees',
  Joint.wrists: 'Wrists',
};

class Exercise {
  final String id, name, pattern, swap, icon;
  final Equipment equipment;
  final List<String> primary, secondary;
  final Set<Joint> joints;
  final int repLow, repHigh;
  final StepKind step;
  final bool bodyweight, compound;
  final bool _timed;
  final String about; // what it works and how to do it, in our own words

  const Exercise({
    required this.id,
    required this.name,
    required this.equipment,
    required this.primary,
    this.secondary = const [],
    required this.pattern,
    required this.swap,
    this.joints = const {},
    required this.repLow,
    required this.repHigh,
    required this.step,
    this.bodyweight = false,
    this.compound = false,
    required this.icon,
    bool? timed,
    this.about = '',
  }) : _timed = timed ?? (pattern == 'plank' || pattern == 'carry');

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        id: j['id'] as String,
        name: j['name'] as String,
        equipment: Equipment.values.byName(j['equipment'] as String),
        primary: List<String>.from(j['primary'] as List),
        secondary: List<String>.from((j['secondary'] ?? const []) as List),
        pattern: j['pattern'] as String,
        swap: j['swap'] as String,
        joints: {for (final s in (j['joints'] ?? const []) as List) Joint.values.byName(s as String)},
        repLow: j['repLow'] as int,
        repHigh: j['repHigh'] as int,
        step: StepKind.values.byName(j['step'] as String),
        bodyweight: (j['bodyweight'] ?? false) as bool,
        compound: (j['compound'] ?? false) as bool,
        icon: j['icon'] as String,
        timed: j['timed'] as bool?,
        about: (j['about'] ?? '') as String,
      );

  /// Exercises whose "reps" are seconds held (planks, hangs, carries).
  bool get timed => _timed;

  /// Muscles in plain words.
  String get muscles => [...primary, ...secondary].map((m) => m.replaceAll('_', ' ')).join(', ');

  Exercise copyWith({String? id, String? name, Equipment? equipment, int? repLow, int? repHigh, bool? timed, String? about, bool? compound}) => Exercise(
        id: id ?? this.id,
        name: name ?? this.name,
        equipment: equipment ?? this.equipment,
        primary: primary,
        secondary: secondary,
        pattern: pattern,
        swap: swap,
        joints: joints,
        repLow: repLow ?? this.repLow,
        repHigh: repHigh ?? this.repHigh,
        step: step,
        bodyweight: bodyweight,
        compound: compound ?? this.compound,
        icon: icon,
        timed: timed ?? _timed,
        about: about ?? this.about,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'equipment': equipment.name,
        'primary': primary,
        'secondary': secondary,
        'pattern': pattern,
        'swap': swap,
        'joints': [for (final j in joints) j.name],
        'repLow': repLow,
        'repHigh': repHigh,
        'step': step.name,
        'bodyweight': bodyweight,
        'compound': compound,
        'icon': icon,
        'timed': _timed,
        'about': about,
      };
}

/// One logged set. Weight in kg (per dumbbell for dumbbell/kettlebell work).
/// What kind of set it was. Warm-ups and drop sets do not count toward the planned sets, records
/// or next time's weights.
enum SetType { warmup, work, drop, failure, amrap, restpause }

const setTypeLabel = {
  SetType.warmup: 'Warm-up',
  SetType.work: 'Working',
  SetType.drop: 'Drop set',
  SetType.failure: 'To failure',
  SetType.amrap: 'As many as possible',
  SetType.restpause: 'Rest-pause',
};

/// The short letter shown next to a set (W, D, F, +, RP); working sets show none.
const setTypeLetter = {SetType.warmup: 'W', SetType.work: '', SetType.drop: 'D', SetType.failure: 'F', SetType.amrap: '+', SetType.restpause: 'RP'};

class SetLog {
  final String id;
  final String sessionId;
  final String exerciseId;
  final double kg;
  final int reps;
  final int ord;
  final DateTime? at;
  final SetType type;
  final int? effort; // 1 easy, 2 good, 3 hard, 4 all-out (the tap after a set)
  final double? rpe; // 6-10, optional
  final String note;
  final int? rest; // seconds rested before this set
  final String side; // '' both, 'L', 'R'
  final int? secs; // time (holds, cardio)
  final double? meters; // distance (carries, cardio)

  const SetLog({
    this.id = '',
    this.sessionId = '',
    required this.exerciseId,
    required this.kg,
    required this.reps,
    this.ord = 0,
    this.at,
    this.type = SetType.work,
    this.effort,
    this.rpe,
    this.note = '',
    this.rest,
    this.side = '',
    this.secs,
    this.meters,
  });

  /// Counts toward the planned sets, records and progression.
  bool get counts => type != SetType.warmup && type != SetType.drop;

  /// RPE for exports: the one typed, or roughly from the effort tap.
  double? get rpeOrEffort => rpe ?? switch (effort) { 1 => 6.5, 2 => 7.5, 3 => 9.0, 4 => 10.0, _ => null };

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_id': sessionId,
        'exercise_id': exerciseId,
        'kg': kg,
        'reps': reps,
        'ord': ord,
        'at': at?.millisecondsSinceEpoch,
        'type': type.name,
        'effort': effort,
        'rpe': rpe,
        'note': note,
        'rest': rest,
        'side': side,
        'secs': secs,
        'meters': meters,
      };

  factory SetLog.fromJson(Map<String, dynamic> j) => SetLog(
        id: j['id'] as String,
        sessionId: j['session_id'] as String,
        exerciseId: j['exercise_id'] as String,
        kg: (j['kg'] as num).toDouble(),
        reps: j['reps'] as int,
        ord: j['ord'] as int,
        at: j['at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
        type: SetType.values.where((t) => t.name == j['type']).firstOrNull ?? SetType.work,
        effort: j['effort'] as int?,
        rpe: (j['rpe'] as num?)?.toDouble(),
        note: (j['note'] ?? '') as String,
        rest: j['rest'] as int?,
        side: (j['side'] ?? '') as String,
        secs: j['secs'] as int?,
        meters: (j['meters'] as num?)?.toDouble(),
      );
}
