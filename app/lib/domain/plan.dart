import 'package:uuid/uuid.dart';

import 'exercise.dart';
import 'program.dart';
import 'units.dart';

enum Goal { strength, size, both, fatLoss, fitness, sport, powerlifting, powerbuilding }

const goalLabel = {
  Goal.strength: 'Strength',
  Goal.size: 'Size',
  Goal.both: 'Both',
  Goal.fatLoss: 'Lose fat',
  Goal.fitness: 'General fitness',
  Goal.sport: 'For a sport',
  Goal.powerlifting: 'Powerlifting',
  Goal.powerbuilding: 'Powerbuilding',
};

const goalHelp = {
  Goal.strength: 'Heavier, fewer reps, longer rests.',
  Goal.size: 'Moderate weights, 8-12 reps, more sets.',
  Goal.both: 'Heavy main lift, size work after it.',
  Goal.fatLoss: 'Keep the strength while you eat less: moderate reps, shorter rests.',
  Goal.fitness: 'Lighter, 10-15 reps, short rests, a bit of everything.',
  Goal.sport: 'Strong and quick: heavy main lifts, low reps, leg and core work.',
  Goal.powerlifting: 'Squat, bench and deadlift first, low reps.',
  Goal.powerbuilding: 'Heavy main lifts like powerlifting, then size work.',
};

/// New / some / years of training: changes volume and how fast weights climb (F196).
const experienceLabel = {'new': 'New to lifting', 'some': 'Up to 2 years', 'years': 'Years of training'};

/// Muscles you can give priority to (or less of it), as named in the exercise library.
const priorityMuscles = ['chest', 'back', 'shoulders', 'biceps', 'triceps', 'quads', 'hamstrings', 'glutes', 'calves', 'core'];

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The setup answers.
class Profile {
  final Goal goal;
  final int days; // per week, 2-6
  final int minutes; // per session: 45, 60, 90
  final Set<Equipment> have;
  final Set<Joint> avoid;
  final Unit unit;
  final String? split; // null = let the app choose; 'full_body' | 'upper_lower' | 'ppl' | 'bro'
  /// The active gym's items minus anything taken today (see gym.dart). null = no gym set up,
  /// [have] alone decides. Not saved with the profile: it comes from the gym list.
  final Set<String>? items;
  final String experience; // 'new' | 'some' | 'years'
  final List<int> weekdays; // 1 = Monday; empty = keep the loop (any day)
  final int? age; // optional, only for start weights and standards
  final double? bodyKg;
  final String? sex; // 'm' | 'f' | null
  final Set<String> priority; // more sets for these muscles
  final Set<String> low; // fewer sets for these
  final Set<int> sportDays; // weekdays with a sport or a long run: legs lighter around them
  final String? special; // a specialisation block for this muscle (extra volume, others held)
  final String? pregnancy; // F237: 'pregnant' | 'postpartum' | null; leaves risky moves out
  final double? heightCm; // F300: optional, for BMI and FFMI

  const Profile({
    required this.goal,
    required this.days,
    required this.minutes,
    required this.have,
    required this.avoid,
    required this.unit,
    this.split,
    this.items,
    this.experience = 'some',
    this.weekdays = const [],
    this.age,
    this.bodyKg,
    this.sex,
    this.priority = const {},
    this.low = const {},
    this.sportDays = const {},
    this.special,
    this.pregnancy,
    this.heightCm,
  });

  Profile copyWith(
          {Goal? goal,
          int? days,
          int? minutes,
          Set<Equipment>? have,
          Set<Joint>? avoid,
          Unit? unit,
          String? split,
          bool clearSplit = false,
          Set<String>? items,
          bool clearItems = false,
          String? experience,
          List<int>? weekdays,
          int? age,
          double? bodyKg,
          String? sex,
          bool clearBody = false,
          Set<String>? priority,
          Set<String>? low,
          Set<int>? sportDays,
          String? special,
          bool clearSpecial = false,
          String? pregnancy,
          bool clearPregnancy = false,
          double? heightCm}) =>
      Profile(
        goal: goal ?? this.goal,
        days: days ?? this.days,
        minutes: minutes ?? this.minutes,
        have: have ?? this.have,
        avoid: avoid ?? this.avoid,
        unit: unit ?? this.unit,
        split: clearSplit ? null : (split ?? this.split),
        items: clearItems ? null : (items ?? this.items),
        experience: experience ?? this.experience,
        weekdays: weekdays ?? this.weekdays,
        age: clearBody ? null : (age ?? this.age),
        bodyKg: clearBody ? null : (bodyKg ?? this.bodyKg),
        sex: clearBody ? null : (sex ?? this.sex),
        priority: priority ?? this.priority,
        low: low ?? this.low,
        sportDays: sportDays ?? this.sportDays,
        special: clearSpecial ? null : (special ?? this.special),
        pregnancy: clearPregnancy ? null : (pregnancy ?? this.pregnancy),
        heightCm: heightCm ?? this.heightCm,
      );

  Map<String, dynamic> toJson() => {
        'goal': goal.name,
        'days': days,
        'minutes': minutes,
        'have': [for (final e in have) e.name],
        'avoid': [for (final j in avoid) j.name],
        'unit': unit.name,
        'split': split,
        if (experience != 'some') 'experience': experience,
        if (weekdays.isNotEmpty) 'weekdays': weekdays,
        if (age != null) 'age': age,
        if (bodyKg != null) 'bodyKg': bodyKg,
        if (sex != null) 'sex': sex,
        if (priority.isNotEmpty) 'priority': [...priority],
        if (low.isNotEmpty) 'low': [...low],
        if (sportDays.isNotEmpty) 'sportDays': [...sportDays],
        if (special != null) 'special': special,
        if (pregnancy != null) 'pregnancy': pregnancy,
        if (heightCm != null) 'height': heightCm,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        goal: Goal.values.byName(j['goal'] as String),
        days: j['days'] as int,
        minutes: j['minutes'] as int,
        have: {for (final s in j['have'] as List) Equipment.values.byName(s as String)},
        avoid: {for (final s in j['avoid'] as List) Joint.values.byName(s as String)},
        unit: Unit.values.byName(j['unit'] as String),
        split: j['split'] as String?,
        experience: (j['experience'] ?? 'some') as String,
        weekdays: [for (final d in (j['weekdays'] ?? const []) as List) d as int],
        age: j['age'] as int?,
        bodyKg: (j['bodyKg'] as num?)?.toDouble(),
        sex: j['sex'] as String?,
        priority: {for (final m in (j['priority'] ?? const []) as List) m as String},
        low: {for (final m in (j['low'] ?? const []) as List) m as String},
        sportDays: {for (final d in (j['sportDays'] ?? const []) as List) d as int},
        special: j['special'] as String?,
        pregnancy: j['pregnancy'] as String?,
        heightCm: (j['height'] as num?)?.toDouble(),
      );
}

/// How the last planned set of an exercise is done.
const lastSetStyles = {'': 'Like the others', 'drop': 'Drop set', 'amrap': 'As many reps as possible', 'failure': 'To failure', 'restpause': 'Rest-pause'};

class PlanItem {
  final String exerciseId;
  final int sets, repLow, repHigh, restSec;
  final String style; // last set: '' normal, 'drop', 'amrap', 'failure', 'restpause'
  final int? group; // superset / circuit group (same number = done together)
  /// Programs: one target per set (reps, % of the training max, +). null = [sets] x [repLow]-[repHigh].
  final List<SetSpec>? perSet;
  final String tier; // programs: a second slot of the same lift ("T2") keeps its own weights
  final String tmOf; // programs: the % sets use this lift's training max ('' = its own)
  final String bump; // programs: what this workout does to the training max (see bumpKinds)

  const PlanItem(
      {required this.exerciseId, required this.sets, required this.repLow, required this.repHigh, required this.restSec, this.style = '', this.group, this.perSet, this.tier = '', this.tmOf = '', this.bump = ''});

  /// A plan item from per-set targets: sets, the rep range and the last-set style follow them.
  factory PlanItem.of(String exerciseId, List<SetSpec> sets, {int rest = 120, String tier = '', String tmOf = '', String bump = '', int? group}) {
    final plain = sets.every((x) => x.pct == null && x.reps == sets.first.reps && x.hi == sets.first.hi) && sets.take(sets.length - 1).every((x) => !x.amrap);
    final lo = sets.map((x) => x.reps).reduce((a, b) => a < b ? a : b);
    final hi = sets.map((x) => x.hi ?? x.reps).reduce((a, b) => a > b ? a : b);
    return PlanItem(
      exerciseId: exerciseId,
      sets: sets.length,
      repLow: lo,
      repHigh: hi,
      restSec: rest,
      style: sets.last.amrap ? 'amrap' : '',
      perSet: plain ? null : sets,
      tier: tier,
      tmOf: tmOf,
      bump: bump,
      group: group,
    );
  }

  /// The planned sets one by one.
  List<SetSpec> get specs => perSet ?? [for (var i = 0; i < sets; i++) SetSpec(repLow, hi: repHigh == repLow ? null : repHigh, amrap: style == 'amrap' && i == sets - 1)];

  PlanItem copyWith(
          {String? exerciseId,
          int? sets,
          int? repLow,
          int? repHigh,
          int? restSec,
          String? style,
          int? group,
          bool clearGroup = false,
          List<SetSpec>? perSet,
          bool clearPerSet = false,
          String? tier,
          String? tmOf,
          String? bump}) =>
      PlanItem(
        exerciseId: exerciseId ?? this.exerciseId,
        sets: sets ?? this.sets,
        repLow: repLow ?? this.repLow,
        repHigh: repHigh ?? this.repHigh,
        restSec: restSec ?? this.restSec,
        style: style ?? this.style,
        group: clearGroup ? null : (group ?? this.group),
        perSet: clearPerSet ? null : (perSet ?? this.perSet),
        tier: tier ?? this.tier,
        tmOf: tmOf ?? this.tmOf,
        bump: bump ?? this.bump,
      );

  Map<String, dynamic> toJson() => {
        'exercise': exerciseId,
        'sets': sets,
        'repLow': repLow,
        'repHigh': repHigh,
        'rest': restSec,
        if (style.isNotEmpty) 'style': style,
        if (group != null) 'group': group,
        if (perSet != null) 'perSet': [for (final x in perSet!) x.toJson()],
        if (tier.isNotEmpty) 'tier': tier,
        if (tmOf.isNotEmpty) 'tmOf': tmOf,
        if (bump.isNotEmpty) 'bump': bump,
      };

  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
        exerciseId: j['exercise'] as String,
        style: (j['style'] ?? '') as String,
        group: j['group'] as int?,
        perSet: j['perSet'] == null ? null : [for (final x in j['perSet'] as List) SetSpec.fromJson(x as Map<String, dynamic>)],
        tier: (j['tier'] ?? '') as String,
        tmOf: (j['tmOf'] ?? '') as String,
        bump: (j['bump'] ?? '') as String,
        sets: j['sets'] as int,
        repLow: j['repLow'] as int,
        repHigh: j['repHigh'] as int,
        restSec: j['rest'] as int,
      );
}

/// Where a plan item's weights live: the exercise, or "id#T2" for a second slot of the same lift.
String liftKey(PlanItem it) => it.tier.isEmpty ? it.exerciseId : '${it.exerciseId}#${it.tier}';

/// The training max a plan item's % sets use.
String tmKey(PlanItem it) => it.tmOf.isNotEmpty ? it.tmOf : liftKey(it);

/// The rule a program gives this item: its own, or "training max" for % sets with none.
LiftRule? ruleFor(ProgramInfo? p, PlanItem it) {
  if (p == null) return null;
  return p.rules[liftKey(it)] ?? ((it.perSet?.any((x) => x.pct != null) ?? false) ? const LiftRule(kind: 'tm') : null);
}

class PlanDay {
  final String name;
  final List<PlanItem> items;

  const PlanDay({required this.name, required this.items});

  PlanDay copyWith({String? name, List<PlanItem>? items}) => PlanDay(name: name ?? this.name, items: items ?? this.items);

  Map<String, dynamic> toJson() => {'name': name, 'items': [for (final i in items) i.toJson()]};

  factory PlanDay.fromJson(Map<String, dynamic> j) =>
      PlanDay(name: j['name'] as String, items: [for (final i in j['items'] as List) PlanItem.fromJson(i as Map<String, dynamic>)]);
}

/// A rotation of named days. Immutable: every edit returns a new Plan with userEdited = true.
class Plan {
  final String id;
  final String name;
  final String source; // 'built-in' | 'ai' | 'mine'
  final List<PlanDay> days;
  final bool userEdited;
  final DateTime created;
  final ProgramInfo? program; // a program from the library: its rules per lift
  final String folder; // plan folders (F207): '' = none
  final int rotateWeeks; // accessories change every N weeks (F205); 0 = off
  final int weeksPerCycle; // programs: weeks in one pass through the rotation (1 for plain plans)

  Plan(
      {String? id,
      required this.name,
      this.source = 'built-in',
      required this.days,
      this.userEdited = false,
      DateTime? created,
      this.program,
      this.folder = '',
      this.rotateWeeks = 0,
      this.weeksPerCycle = 1})
      : id = id ?? const Uuid().v4(),
        created = created ?? DateTime.now();

  Plan copyWith(
          {String? id,
          String? name,
          String? source,
          List<PlanDay>? days,
          bool? userEdited,
          DateTime? created,
          ProgramInfo? program,
          bool clearProgram = false,
          String? folder,
          int? rotateWeeks,
          int? weeksPerCycle}) =>
      Plan(
        id: id ?? this.id,
        name: name ?? this.name,
        source: source ?? this.source,
        days: days ?? this.days,
        userEdited: userEdited ?? this.userEdited,
        created: created ?? this.created,
        program: clearProgram ? null : (program ?? this.program),
        folder: folder ?? this.folder,
        rotateWeeks: rotateWeeks ?? this.rotateWeeks,
        weeksPerCycle: weeksPerCycle ?? this.weeksPerCycle,
      );

  /// A full copy with a new id (F208): kept as a saved plan, not made active.
  Plan duplicate(String newName) =>
      Plan(name: newName, source: 'mine', days: days, userEdited: true, program: program, folder: folder, rotateWeeks: rotateWeeks, weeksPerCycle: weeksPerCycle);

  Plan _edit(List<PlanDay> d) => copyWith(days: d, userEdited: true);

  Plan renamed(String n) => copyWith(name: n, userEdited: true);

  /// Days of one week (programs run several weeks through one rotation).
  int get daysPerWeek => weeksPerCycle <= 1 || days.length % weeksPerCycle != 0 ? days.length : days.length ~/ weeksPerCycle;

  Plan duplicateDay(int i) => _edit([...days]..insert(i + 1, days[i].copyWith(name: '${days[i].name} (copy)')));

  Plan moveDay(int from, int to) {
    final d = [...days];
    final x = d.removeAt(from);
    d.insert(to.clamp(0, d.length), x);
    return _edit(d);
  }

  Plan addDay(String n) => _edit([...days, PlanDay(name: n, items: const [])]);

  Plan removeDay(int i) => _edit([...days]..removeAt(i));

  Plan renameDay(int i, String n) => _edit([...days]..[i] = days[i].copyWith(name: n));

  Plan _items(int day, List<PlanItem> Function(List<PlanItem>) f) =>
      _edit([...days]..[day] = days[day].copyWith(items: f([...days[day].items])));

  Plan moveItem(int day, int from, int to) => _items(day, (l) {
        final x = l.removeAt(from);
        l.insert(to.clamp(0, l.length), x);
        return l;
      });

  Plan addItem(int day, PlanItem it) => _items(day, (l) => l..add(it));

  Plan removeItem(int day, int i) => _items(day, (l) => l..removeAt(i));

  Plan updateItem(int day, int i, PlanItem it) => _items(day, (l) => l..[i] = it);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'source': source,
        'userEdited': userEdited,
        'created': created.millisecondsSinceEpoch,
        'days': [for (final d in days) d.toJson()],
        if (program != null) 'program': program!.toJson(),
        if (folder.isNotEmpty) 'folder': folder,
        if (rotateWeeks != 0) 'rotateWeeks': rotateWeeks,
        if (weeksPerCycle != 1) 'weeksPerCycle': weeksPerCycle,
      };

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
        id: j['id'] as String,
        name: j['name'] as String,
        source: (j['source'] ?? 'built-in') as String,
        userEdited: (j['userEdited'] ?? false) as bool,
        created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int),
        days: [for (final d in j['days'] as List) PlanDay.fromJson(d as Map<String, dynamic>)],
        program: j['program'] == null ? null : ProgramInfo.fromJson(j['program'] as Map<String, dynamic>),
        folder: (j['folder'] ?? '') as String,
        rotateWeeks: (j['rotateWeeks'] ?? 0) as int,
        weeksPerCycle: (j['weeksPerCycle'] ?? 1) as int,
      );
}

/// Where each day of [old] ended up in [neu] (null = deleted). Days moved or removed keep their
/// identity (plans are immutable); a day edited in place keeps its index.
List<int?> dayMap(Plan old, Plan neu) {
  final out = <int?>[];
  for (var i = 0; i < old.days.length; i++) {
    final j = neu.days.indexWhere((d) => identical(d, old.days[i]));
    if (j >= 0) {
      out.add(j);
    } else if (old.days.length == neu.days.length || (neu.days.length > old.days.length && i < neu.days.length)) {
      out.add(i); // edited in place (or days only added at the end)
    } else {
      out.add(null);
    }
  }
  return out;
}

/// Next day in the rotation. A stale or missing index starts over at day 0.
int nextDayIndex(Plan plan, int? lastDoneIndex) {
  if (plan.days.isEmpty) return 0;
  if (lastDoneIndex == null || lastDoneIndex < 0 || lastDoneIndex >= plan.days.length) return 0;
  return (lastDoneIndex + 1) % plan.days.length;
}
