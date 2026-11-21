import '../domain/exercise.dart';
import '../domain/library.dart';
import '../domain/plan.dart';
import '../domain/plan_maker.dart';

/// Grammars (llama.cpp GBNF) that lock the on-phone model to:
///  - the workout list format,
///  - the day names of the person's split, in order (so the week is always balanced),
///  - for each day, only exercises for that day's muscles that this gym has and these joints
///    allow, with a compound lift first.
/// A small model can then only choose and tune exercises, never break the plan. The app's normal
/// checks still run afterwards.

const _upper = {'chest', 'back', 'lats', 'shoulders', 'rear_delts', 'biceps', 'triceps', 'traps', 'forearms'};
const _lower = {'quads', 'hamstrings', 'glutes', 'calves', 'adductors'};
const _push = {'chest', 'shoulders', 'triceps'};
const _pull = {'back', 'lats', 'rear_delts', 'biceps', 'traps', 'forearms'};

/// Which main muscles belong on a day, from its name. Null = anything (full body).
Set<String>? musclesFor(String dayName) {
  final n = dayName.toLowerCase();
  if (n.contains('upper')) return _upper;
  if (n.contains('lower') || n.contains('legs') || n.contains('leg ')) return _lower;
  if (n.contains('push')) return _push;
  if (n.contains('pull')) return _pull;
  if (n.contains('chest')) return {'chest', 'triceps'};
  if (n.contains('back')) return {'back', 'lats', 'biceps', 'rear_delts', 'traps', 'forearms'};
  if (n.contains('shoulder')) return {'shoulders', 'rear_delts', 'traps'};
  if (n.contains('arm')) return {'biceps', 'triceps', 'forearms'};
  return null;
}

List<Exercise> _for(Library lib, Profile p, String dayName, {bool compound = false}) {
  final m = musclesFor(dayName);
  return [
    for (final e in lib.available(p.have, p.avoid, items: p.items))
      if ((m == null || m.contains(e.primary.first) || e.primary.first == 'core') && (!compound || (e.compound && e.primary.first != 'core'))) e
  ];
}

String _alt(List<Exercise> l) => l.map((e) => '"${e.id}"').join(' | ');

String _lit(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

const _common = '''
name ::= [A-Za-z0-9 /&()+-]{1,40}
sets ::= [1-8]
reps ::= num "-" num
num ::= [1-9] [0-9]? [0-9]?
rest ::= [3-9] [05] | [1-2] [0-9] [05] | "300"
''';

String _dayRules(Library lib, Profile p, String rule, String name, int cap) {
  final all = _for(lib, p, name);
  var first = _for(lib, p, name, compound: true);
  if (first.isEmpty) first = all;
  return '$rule ::= "DAY: " ${_lit(name)} "\\n" ${rule}f ${rule}i{2,${cap - 1}}\n'
      '${rule}f ::= (${_alt(first)}) " | " sets " | " reps " | " rest "\\n"\n'
      '${rule}i ::= (${_alt(all)}) " | " sets " | " reps " | " rest "\\n"\n';
}

String planGrammar(Library lib, Profile p) {
  final names = dayNames(p.days, p.split);
  final cap = capFor(p.minutes);
  final b = StringBuffer('root ::= "PLAN: " name "\\n" ${[for (var i = 0; i < names.length; i++) 'd$i'].join(' ')}\n');
  for (var i = 0; i < names.length; i++) {
    b.write(_dayRules(lib, p, 'd$i', names[i], cap));
  }
  b.write(_common);
  return b.toString();
}

/// One day, keeping its name and its muscles (for "adjust today").
String dayGrammar(Library lib, Profile p, String dayName) {
  final cap = capFor(p.minutes);
  return 'root ::= d0\n${_dayRules(lib, p, 'd0', dayName, cap)}$_common';
}

/// The exercise list in few words (ids grouped by main muscle), so a small model on a phone reads
/// the prompt quickly. The grammar already stops it from using anything else.
String compactExerciseList(Library lib, Profile p) {
  final by = <String, List<String>>{};
  for (final e in lib.available(p.have, p.avoid, items: p.items)) {
    (by[e.primary.first.replaceAll('_', ' ')] ??= []).add(e.id);
  }
  return [for (final m in by.entries) '${m.key}: ${m.value.join(', ')}'].join('\n');
}

/// The on-phone model's answer for "Ask AI": a SAY line, then only real tools with real values.
/// Exercises: only this gym's, never ones that load a sore joint.
/// [mustAct]: the person asked for a change, so the answer starts with at least one tool call
/// (a small model otherwise just talks about it).
String toolGrammar(Library lib, Profile p, int planDays, {bool mustAct = false}) {
  final ids = _alt(lib.available(p.have, p.avoid, items: p.items).toList());
  final cap = capFor(p.minutes);
  final dayN = planDays < 1 ? '"1"' : [for (var i = 1; i <= planDays && i <= 9; i++) '"$i"'].join(' | ');
  return '''
root ::= ${mustAct ? 'act{1,6} ' : ''}"SAY: " say "\\n"
say ::= [^\\n]{1,250}
act ::= "DO: " (today | swap | add | remove | change | style | pick | skip | start | setting | profile) "\\n"
today ::= "today\\nDAY: " name "\\n" item{2,$cap}
item ::= ex " | " sets " | " reps " | " rest "\\n"
swap ::= "swap " ex " -> " ex " " scope
add ::= "add " ex " " sets " " reps " " rest " " scope
remove ::= "remove " ex " " scope
change ::= "change " ex (" sets=" sets)? (" reps=" reps)? (" rest=" rest)? " " scope
style ::= "style " ex " " ("drop" | "amrap" | "failure" | "restpause" | "normal") " " scope
pick ::= "pick day " ($dayN)
skip ::= "skip day"
start ::= "start workout"
setting ::= "setting " ("rest " (rest | "plan") | "smart_rest " onoff | "sound " ("cute" | "simple" | "off") | "keep_awake " onoff | "reminders " ("off" | wd ("," wd){0,6}) | "reminder_time " [0-2] [0-9] ":" [0-5] [0-9])
profile ::= "profile " ("goal " ("strength" | "size" | "both") | "days " [1-7] | "unit " ("kg" | "lb"))
wd ::= "mon" | "tue" | "wed" | "thu" | "fri" | "sat" | "sun"
onoff ::= "on" | "off"
scope ::= "today" | "always"
ex ::= $ids
$_common''';
}
