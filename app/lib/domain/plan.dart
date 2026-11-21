import 'package:uuid/uuid.dart';

import 'exercise.dart';
import 'units.dart';

enum Goal { strength, size, both }

const goalLabel = {Goal.strength: 'Strength', Goal.size: 'Size', Goal.both: 'Both'};

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

  const Profile({
    required this.goal,
    required this.days,
    required this.minutes,
    required this.have,
    required this.avoid,
    required this.unit,
    this.split,
    this.items,
  });

  Profile copyWith({Goal? goal, int? days, int? minutes, Set<Equipment>? have, Set<Joint>? avoid, Unit? unit, String? split, bool clearSplit = false, Set<String>? items, bool clearItems = false}) =>
      Profile(
        goal: goal ?? this.goal,
        days: days ?? this.days,
        minutes: minutes ?? this.minutes,
        have: have ?? this.have,
        avoid: avoid ?? this.avoid,
        unit: unit ?? this.unit,
        split: clearSplit ? null : (split ?? this.split),
        items: clearItems ? null : (items ?? this.items),
      );

  Map<String, dynamic> toJson() => {
        'goal': goal.name,
        'days': days,
        'minutes': minutes,
        'have': [for (final e in have) e.name],
        'avoid': [for (final j in avoid) j.name],
        'unit': unit.name,
        'split': split,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        goal: Goal.values.byName(j['goal'] as String),
        days: j['days'] as int,
        minutes: j['minutes'] as int,
        have: {for (final s in j['have'] as List) Equipment.values.byName(s as String)},
        avoid: {for (final s in j['avoid'] as List) Joint.values.byName(s as String)},
        unit: Unit.values.byName(j['unit'] as String),
        split: j['split'] as String?,
      );
}

/// How the last planned set of an exercise is done.
const lastSetStyles = {'': 'Normal', 'drop': 'Drop set', 'amrap': 'As many reps as possible', 'failure': 'To failure', 'restpause': 'Rest-pause'};

class PlanItem {
  final String exerciseId;
  final int sets, repLow, repHigh, restSec;
  final String style; // last set: '' normal, 'drop', 'amrap', 'failure', 'restpause'
  final int? group; // superset / circuit group (same number = done together)

  const PlanItem({required this.exerciseId, required this.sets, required this.repLow, required this.repHigh, required this.restSec, this.style = '', this.group});

  PlanItem copyWith({String? exerciseId, int? sets, int? repLow, int? repHigh, int? restSec, String? style, int? group, bool clearGroup = false}) => PlanItem(
        exerciseId: exerciseId ?? this.exerciseId,
        sets: sets ?? this.sets,
        repLow: repLow ?? this.repLow,
        repHigh: repHigh ?? this.repHigh,
        restSec: restSec ?? this.restSec,
        style: style ?? this.style,
        group: clearGroup ? null : (group ?? this.group),
      );

  Map<String, dynamic> toJson() => {'exercise': exerciseId, 'sets': sets, 'repLow': repLow, 'repHigh': repHigh, 'rest': restSec, if (style.isNotEmpty) 'style': style, if (group != null) 'group': group};

  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
        exerciseId: j['exercise'] as String,
        style: (j['style'] ?? '') as String,
        group: j['group'] as int?,
        sets: j['sets'] as int,
        repLow: j['repLow'] as int,
        repHigh: j['repHigh'] as int,
        restSec: j['rest'] as int,
      );
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

  Plan({String? id, required this.name, this.source = 'built-in', required this.days, this.userEdited = false, DateTime? created})
      : id = id ?? const Uuid().v4(),
        created = created ?? DateTime.now();

  Plan _edit(List<PlanDay> d) => Plan(id: id, name: name, source: source, days: d, userEdited: true, created: created);

  Plan renamed(String n) => Plan(id: id, name: n, source: source, days: days, userEdited: true, created: created);

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
      };

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
        id: j['id'] as String,
        name: j['name'] as String,
        source: (j['source'] ?? 'built-in') as String,
        userEdited: (j['userEdited'] ?? false) as bool,
        created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int),
        days: [for (final d in j['days'] as List) PlanDay.fromJson(d as Map<String, dynamic>)],
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
