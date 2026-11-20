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
}

/// One logged set. Weight in kg (per dumbbell for dumbbell/kettlebell work).
class SetLog {
  final String id;
  final String sessionId;
  final String exerciseId;
  final double kg;
  final int reps;
  final int ord;
  final DateTime? at;

  const SetLog({
    this.id = '',
    this.sessionId = '',
    required this.exerciseId,
    required this.kg,
    required this.reps,
    this.ord = 0,
    this.at,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_id': sessionId,
        'exercise_id': exerciseId,
        'kg': kg,
        'reps': reps,
        'ord': ord,
        'at': at?.millisecondsSinceEpoch,
      };

  factory SetLog.fromJson(Map<String, dynamic> j) => SetLog(
        id: j['id'] as String,
        sessionId: j['session_id'] as String,
        exerciseId: j['exercise_id'] as String,
        kg: (j['kg'] as num).toDouble(),
        reps: j['reps'] as int,
        ord: j['ord'] as int,
        at: j['at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
}
