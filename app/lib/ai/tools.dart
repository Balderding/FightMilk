import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/body.dart';
import '../domain/exercise.dart';
import '../domain/explain.dart';
import '../domain/gym.dart';
import '../domain/library.dart';
import '../domain/plan.dart';
import '../domain/programs.dart';
import '../domain/program.dart';
import '../domain/plan_maker.dart';
import '../domain/superset.dart';
import '../domain/units.dart';
import '../domain/volume.dart';
import '../ui/app_state.dart';
import 'plan_json.dart';
import '../data/export.dart' show ExportKind, exportLabel;

/// The app's tools for the AI: everything you can do by tapping, the AI can do by asking.
/// It works like an MCP server, but inside the app: no network port, nothing to connect to.
///
/// The AI answers in plain lines:
///   SAY: what it tells you (one or more lines)
///   `DO: tool arguments`        (zero or more)
/// `DO: today` and `DO: plan` are followed by a workout in the usual list format.
/// Every DO line is checked before anything changes; one bad line stops the whole batch.
///
/// The AI can never touch its own setup (which AI, keys, server, Auto mode) and cannot make the
/// app send anything anywhere.

/// One checked change, ready to run.
class AppAction {
  final String says; // plain words for the person
  final Future<void> Function(AppState s) run;
  /// Asked first even with Auto on (review 6 / self7: the AI's import undo).
  final bool alwaysAsk;
  /// False: the AI change list's Undo cannot bring this one back, and says so.
  final bool undoable;
  const AppAction(this.says, this.run, {this.alwaysAsk = false, this.undoable = true});
}

class ToolReply {
  final String say;
  final List<AppAction> actions;
  final List<String> errors; // non-empty = nothing may run
  const ToolReply(this.say, this.actions, this.errors);
}

/// The tool list, as the AI reads it.
String toolHelp(Library lib) => '''
You can change the app for the person. Answer in this format, exactly:
SAY: <your answer in plain words, short>
DO: <tool> <arguments>
(zero or more DO lines; only use DO when they asked for a change)

Tools:
DO: today                         then a DAY block: replace today's workout
  DAY: <day name>
  exercise_id | sets | reps | rest seconds
DO: plan                          then PLAN: + DAY blocks: a whole new plan
DO: swap <exercise_id> -> <exercise_id> today|always
DO: add <exercise_id> <sets> <low>-<high> <rest> today|always
DO: remove <exercise_id> today|always
DO: change <exercise_id> sets=<n> reps=<low>-<high> rest=<seconds> today|always   (any of sets/reps/rest)
DO: style <exercise_id> drop|amrap|failure|restpause|normal today|always   (how the last set is done)
DO: import undo                    take the last import out again (its workouts and weigh-ins)
DO: export ${ExportKind.values.map((k) => k.name).join('|')}   open Export on that format (the person saves or shares it; you cannot)
DO: body <weight> kg|lb [fat <percent>]   log a weigh-in, optionally with body fat
DO: tape <part> <size> [cm|in] [left|right]  a tape measurement (neck, shoulders, chest, waist, hips, arm, forearm, thigh, calf, or own words); no unit = the person's (cm for kg users, in for lb users)
DO: superset <exercise_id> <exercise_id> today|always   do them together, one set of each in turn
DO: superset auto today|always       pair opposite muscles to save time
DO: unsuperset <exercise_id> today|always
DO: exercise favourite|unfavourite|hide|unhide <exercise_id>   favourites come first; hidden ones are never used
DO: exercise rename <exercise_id> <new name>
DO: deload on|off                    a lighter week (fewer sets, ~90%), progress does not move
DO: feeling rough|ok|great          today's check-in (rough = one set fewer, a bit lighter)
DO: setting progression slow|steady|fast
DO: setting drop_after 1|2|3        missed sessions before the weight drops
DO: setting deload_every 0|4|5|6    weeks (0 = only when asked)
DO: progression <exercise_id> linear|double   add weight every session, or reps first
DO: pick day <number>             do that day of the plan today (1 = first)
DO: skip day                      move on to the next day without training
DO: start workout
DO: log <exercise_id> <weight> <reps>   log a set in the workout that is going (weight in the person's unit)
DO: setting rest <seconds|plan|off>
DO: setting smart_rest on|off
DO: setting sound cute|simple|off
DO: setting keep_awake on|off
DO: setting left_handed on|off     (mirror the workout buttons)
DO: setting dim_rest on|off        (dark screen while resting; a touch only wakes it)
DO: setting reminders <mon,tue,...|off>
DO: setting reminder_time <HH:MM>
DO: setting weigh_reminder <HH:MM>|off   a morning weigh-in reminder
DO: setting auto_update on|off
DO: setting auto_icons on|off
DO: setting warmups on|off           (warm-up help: general warm-up, warm-up sets, cool-down)
DO: setting hide_in_recents on|off  (blank card in recent apps, no screenshots)
DO: setting checkin on|off           (ask "how do you feel?" before a workout)
DO: setting effort_chips on|off      (ask "how was that set?" while resting)
DO: setting effort_drives on|off     (easy/hard taps change the next jump)
DO: setting simple on|off            (Simple mode hides the extra tools)
DO: setting formula epley|brzycki    (one-rep max estimate)
DO: setting drop_pct 5|10|15         (how much the weight drops after misses)
DO: setting steps barbell|dumbbell|machine|cable <weight>   smallest weight step, in the person's unit
DO: step <exercise_id> <weight>|usual   this lift's own weight step
DO: note <exercise_id> <text>|clear     pinned note for that exercise (seat height, grip)
DO: fill <exercise_id> <weight> <reps>  log the rest of its planned sets in the workout that is going
DO: profile goal ${Goal.values.map(_goalWord).join('|')}
DO: profile experience new|some|years
DO: profile weekdays mon,wed,fri|none   plan days tied to those weekdays (none = keep the loop)
DO: profile sport_days sat|none          a sport or long run on those days: legs lighter around them
DO: profile priority add|remove <muscle> more sets for it (muscles: ${priorityMuscles.join(', ')})
DO: profile low add|remove <muscle>      fewer sets for it
DO: profile focus <muscle>|none          a specialisation block: extra volume for one muscle, others held
DO: profile body_weight <weight>|none    only for start weights and standards
DO: profile age <years>|none
DO: profile sex m|f|none
DO: profile height <cm>|<ft>'<in>|<n> in|none   for BMI and FFMI
DO: program start <program_id>            start a program from the library (ids: ${programTemplates.map((t) => t.id).join(', ')})
DO: program tm <exercise_id> <weight>|clear   a lift's training max (programs take % of it)
DO: program rule <exercise_id> linear|double|tm|stage|ladder [inc=<steps>] [misses=<n>] [reset=<percent>] [amrap=<reps>]
DO: program rule <exercise_id> script <line; line>   my own progression, e.g. "if top: add 1; if miss 3: times 0.9; else: same"
DO: program rule <exercise_id> none       back to the usual progression
DO: program stage <exercise_id> <1-3>     which stage a stage-rule lift is on
DO: plans copy                    save a copy of the current plan (to edit, or to keep home and gym plans)
DO: plans use <plan name>         switch to a saved plan
DO: plans folder <folder name>|none   put the current plan in a folder
DO: plans variety 0|4|6|8         accessories change every N weeks (main lifts stay); 0 = off
DO: day copy <number>             duplicate that day of the plan (1 = first)
DO: weak <exercise_id> <point>    add an exercise for a weak point (${weakPoints.entries.map((e) => '${e.key}: ${e.value.keys.map(_slug).join('/')}').join('; ')})
DO: profile days <1-7>
DO: profile minutes <20-180>
DO: profile unit kg|lb
DO: profile split ${splitLabel.keys.join('|')}|auto
DO: profile equipment add|remove ${Equipment.values.map((e) => e.name).join('|')}
DO: gym use <gym name>            switch to that gym
DO: gym new <template> <name>     templates: ${gymTemplates.map((t) => t.id).join('|')}
DO: gym add <item_id>             the current gym has it (item ids: ${gymItems.map((i) => i.id).join(', ')})
DO: gym remove <item_id>
DO: gym taken <item_id>           taken or broken today (back tomorrow)
DO: profile go_easy add|remove ${Joint.values.map((j) => j.name).join('|')}
DO: profile pregnancy pregnant|postpartum|none   leaves out crunches, jumps, Olympic lifts (pregnant: lying flat too), no all-out sets
DO: sore <joint,joint>|none       sore today only (${Joint.values.map((j) => j.name).join(', ')}): those exercises are flagged and can be swapped
DO: sore swap                     swap today's exercises that are hard on a sore joint
DO: pain <exercise_id> [joint]    "that hurt": noted, the joint is sore today, the next two workouts of it 20% then 10% lighter
DO: pain <exercise_id> clear      back to its normal weights
DO: volume fit                    add or take off sets so each muscle lands in its weekly range (not for programs)
DO: setting climb on|off          extra exercises start a block one set lighter and gain a set each week
DO: rest_hint off                 put away today's "take a day off" suggestion
DO: stall swap <exercise_id>      a stuck lift: the closest variation for 4 weeks, then it comes back
DO: changes undo <n>              put back the nth newest weight the app moved (1 = newest), if nothing moved it since
DO: setting tips on|off           tip of the day on Today
DO: dashboard add|remove <tile>   tiles at the top of Progress (${dashTiles.keys.join(', ')})
DO: setting chart_smooth on|off   smooth curves on the charts
DO: setting chart_dots on|off     a dot on every workout in the charts
DO: setting badges on|off         badges and levels in Reports
DO: goal lift <exercise_id> <weight> [by YYYY-MM-DD]   a lift goal (est. 1-rep max)
DO: goal reps <exercise_id> <reps> [by YYYY-MM-DD]     reps in one set
DO: goal body <weight> [by YYYY-MM-DD]                 body weight
DO: goal volume <tonnes> [by YYYY-MM-DD]               tonnes lifted a month
DO: goal remove <n>               remove the nth goal (1 = first)
DO: program start <description>   also works with a description, e.g. "program start 531 bbb 4 days"

"today" changes only today's workout; "always" also changes the plan.
Use only exercise ids from the exercise list. Never invent ids.
''';

/// Does this message ask the app to change something (rather than ask a question)?
/// Used so the small on-phone model must answer with a tool call.
bool looksLikeChange(String q) {
  final t = q.toLowerCase().trim();
  if (RegExp(r'^(how|what|why|when|which|who|is|are|should|can i|do i|does)\b').hasMatch(t) && !t.contains('can you')) return false;
  return RegExp(r'\b(set (me )?up|make|give me|change|swap|replace|add|remove|drop|skip|start|remind|reminders?|turn (on|off)|switch|use|put|move|pick|i only have|i have \d+|is taken|are taken|is broken|shorter|longer|rest|sound|units?|kg|lbs?|minutes)\b')
      .hasMatch(t);
}

/// Short tool list with worked examples, for the small model on the phone (the grammar does the rest).
String toolHelpShort() => '''
You can change the app. First the changes, one per line starting with DO:, then one short SAY: line.
Examples:
Request: Set me up a back and biceps workout for today.
DO: today
DAY: Back and Biceps
lat_pulldown | 4 | 8-12 | 90
seated_cable_row | 3 | 8-12 | 90
db_curl | 3 | 10-12 | 60
SAY: Done: a back and biceps day is set for today.
Request: Remind me to train Tuesday and Thursday at 7 pm.
DO: setting reminders tue,thu
DO: setting reminder_time 19:00
SAY: Reminders are on for Tuesday and Thursday at 7 pm.
Request: Give me 90 seconds rest between sets.
DO: setting rest 90
SAY: Rest is now 90 seconds.
Request: The bench is taken, swap it.
DO: swap bench_press -> db_bench_press today
SAY: Swapped to dumbbell bench press for today.
''';

const _days = {'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7};

/// Reads and checks an AI answer. [s] gives the current plan, today and profile.
ToolReply parseToolReply(String text, AppState s) {
  final lib = s.lib;
  final lines = text.replaceAll('\r', '').split('\n');
  final say = <String>[];
  final acts = <AppAction>[];
  final err = <String>[];
  bool isDo(String l) => l.trimLeft().toUpperCase().startsWith('DO:');
  bool isSay(String l) => l.trimLeft().toUpperCase().startsWith('SAY:');
  var i = 0;
  var inSay = true; // text before any DO line is what it says
  while (i < lines.length) {
    final l = lines[i];
    if (!isDo(l)) {
      if (isSay(l)) inSay = true;
      final t = l.trim();
      if (inSay && !t.startsWith('```')) say.add(t.replaceFirst(RegExp(r'^SAY:\s*', caseSensitive: false), ''));
      i++;
      continue;
    }
    inSay = false;
    final cmd = l.trim().substring(3).trim();
    i++;
    final block = <String>[];
    while (i < lines.length && !isDo(lines[i]) && !isSay(lines[i])) {
      block.add(lines[i]);
      i++;
    }
    if (cmd.isEmpty) continue;
    try {
      acts.add(_action(cmd, block.join('\n'), s, lib));
    } on _Bad catch (e) {
      err.add('"DO: $cmd": ${e.why}');
    }
  }
  return ToolReply(say.join('\n').trim(), acts, err);
}

class _Bad implements Exception {
  final String why;
  _Bad(this.why);
}

Exercise _ex(Library lib, String id, AppState s) {
  final e = lib.find(id);
  if (e == null) throw _Bad('unknown exercise "$id".');
  final p = s.profile;
  if (p != null) {
    if (p.items != null ? !gymAllows(e, p.items!) : (e.equipment != Equipment.bodyweight && !p.have.contains(e.equipment))) {
      throw _Bad('${e.name} needs ${p.items != null ? missingFor(e, p.items!) : equipmentLabel[e.equipment]!.toLowerCase()}, which your gym does not have.');
    }
    final sore = e.joints.intersection(p.avoid);
    if (sore.isNotEmpty) throw _Bad('${e.name} is hard on your ${sore.map((j) => jointLabel[j]!.toLowerCase()).join(' and ')}.');
  }
  return e;
}

bool _always(String w) {
  if (w == 'always' || w == 'plan') return true;
  if (w == 'today' || w.isEmpty) return false;
  throw _Bad('say "today" or "always" at the end.');
}

(int, int) _reps(String r) {
  final m = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(r);
  if (m == null) throw _Bad('reps must look like 8-12.');
  final lo = int.parse(m.group(1)!), hi = int.parse(m.group(2) ?? m.group(1)!);
  if (lo < 1 || hi > 120 || lo > hi) throw _Bad('reps must be 1-120, low <= high.');
  return (lo, hi);
}

int _int(String v, int lo, int hi, String what) {
  final n = int.tryParse(v);
  if (n == null || n < lo || n > hi) throw _Bad('$what must be $lo-$hi.');
  return n;
}

String _goalWord(Goal g) => g.name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '_').replaceAll(RegExp(r'^_|_$'), '');

List<int> _weekdays(String v) {
  if (v == 'none' || v == 'off' || v.isEmpty) return const [];
  final out = <int>{};
  for (final d in v.split(',')) {
    final n = _days[d.trim().substring(0, d.trim().length.clamp(0, 3))];
    if (n == null) throw _Bad('days look like mon,wed,fri.');
    out.add(n);
  }
  return out.toList()..sort();
}

double _weight(String v, AppState s) {
  final n = double.tryParse(v.replaceAll(',', '.'));
  if (n == null || n <= 0 || n > 1500) throw _Bad('write a weight in ${unitLabel(s.unit)}.');
  return fromUnit(n, s.unit);
}

/// "goal lift bench_press 100 by 2027-03-01", "goal body 80", "goal remove 2" (F294-F296).
AppAction _goal(List<String> w, AppState s, Library lib) {
  String a(int k) => k < w.length ? w[k].toLowerCase() : '';
  if (a(1) == 'remove') {
    final n = _int(a(2), 1, s.aims.isEmpty ? 1 : s.aims.length, 'n');
    if (s.aims.isEmpty) throw _Bad('there are no goals yet.');
    final g = s.aims[n - 1];
    return AppAction('Goal removed', (s) => s.removeAim(g.id));
  }
  final kind = a(1);
  if (!const {'lift', 'reps', 'body', 'volume'}.contains(kind)) throw _Bad('goal kinds are lift, reps, body, volume.');
  final withEx = kind == 'lift' || kind == 'reps';
  final e = withEx ? (lib.find(a(2)) ?? (throw _Bad('unknown exercise "${a(2)}".'))) : null;
  final vi = withEx ? 3 : 2;
  final raw = double.tryParse(a(vi).replaceAll(',', '.'));
  if (raw == null || raw <= 0 || raw > 2000) throw _Bad('give the target number.');
  DateTime? by;
  if (a(vi + 1) == 'by') {
    // strict: 2027-13-45 would roll over to 2028; and no dates in the past (review 3, P2-10)
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(a(vi + 2));
    final d = m == null ? null : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    if (d == null || d.month != int.parse(m![2]!) || d.day != int.parse(m[3]!)) throw _Bad('write the date as YYYY-MM-DD.');
    if (d.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))) throw _Bad('the date is in the past.');
    by = d;
  }
  final target = kind == 'reps' || kind == 'volume' ? raw : fromUnit(raw, s.unit);
  final what = kind == 'reps' ? '${raw.round()} reps' : (kind == 'volume' ? '${fmtNum(raw)} t a month' : '${fmtNum(raw)} ${unitLabel(s.unit)}');
  return AppAction('Goal: ${e == null ? (kind == 'body' ? 'body weight' : 'volume') : e.name} $what${by == null ? '' : ' by ${by.year}-${by.month.toString().padLeft(2, '0')}-${by.day.toString().padLeft(2, '0')}'}', (s) => s.addAim(kind, target, exercise: e?.id ?? '', by: by));
}

Joint _jointWord(String v) =>
    Joint.values.where((j) => j.name.toLowerCase() == v.trim().toLowerCase().replaceAll('_', '')).firstOrNull ?? (throw _Bad('joint is ${Joint.values.map((j) => j.name).join(', ')}.'));

bool _onOff(String v) => switch (v) { 'on' || 'yes' || 'true' => true, 'off' || 'no' || 'false' => false, _ => throw _Bad('say on or off.') };

AppAction _action(String cmd, String block, AppState s, Library lib) {
  final w = cmd.split(RegExp(r'\s+'));
  final t = w.first.toLowerCase();
  String a(int k) => k < w.length ? w[k].toLowerCase() : '';
  final today = s.today;
  switch (t) {
    case 'today':
      final r = parseDay(block, lib, profile: s.profile);
      if (r.day == null) throw _Bad(r.errors.join(' '));
      final d = r.day!;
      if (s.plan == null) throw _Bad('there is no plan yet; make one first.');
      return AppAction("Today: ${d.name} (${d.items.length} exercises)", (s) => s.setToday(d));
    case 'plan':
      final r = parsePlan(block, lib, profile: s.profile);
      if (r.plan == null) throw _Bad(r.errors.join(' '));
      final p = r.plan!;
      return AppAction('New plan: ${p.name} (${p.days.length} days)', (s) => s.usePlan(p));
    case 'swap':
      final arrow = cmd.indexOf('->');
      if (arrow < 0) throw _Bad('write it as: swap old_id -> new_id today|always');
      final left = cmd.substring(4, arrow).trim();
      final right = cmd.substring(arrow + 2).trim().split(RegExp(r'\s+'));
      final from = lib.find(left);
      if (from == null) throw _Bad('unknown exercise "$left".');
      final to = _ex(lib, right.first, s);
      final always = _always(right.length > 1 ? right[1].toLowerCase() : '');
      final i = today?.items.indexWhere((x) => x.exerciseId == from.id) ?? -1;
      if (i < 0) throw _Bad("${from.name} is not in today's workout.");
      return AppAction('Swap ${from.name} → ${to.name}${always ? ' (also in the plan)' : ' (today)'}', (s) async {
        final j = s.today!.items.indexWhere((x) => x.exerciseId == from.id);
        if (j >= 0) await s.swap(j, to, forever: always);
      });
    case 'add':
      if (w.length < 5) throw _Bad('write it as: add id sets low-high rest today|always');
      final e = _ex(lib, w[1], s);
      final sets = _int(w[2], 1, 10, 'sets');
      final (lo, hi) = _reps(w[3]);
      final rest = _int(w[4].replaceAll(RegExp(r'[^0-9]'), ''), 30, 600, 'rest');
      final always = _always(a(5));
      if (today == null) throw _Bad('there is no workout today to add to.');
      if (today.items.any((x) => x.exerciseId == e.id)) throw _Bad('${e.name} is already in today\'s workout.');
      final it = PlanItem(exerciseId: e.id, sets: sets, repLow: lo, repHigh: hi, restSec: rest);
      return AppAction('Add ${e.name} $sets × $lo-$hi${always ? ' (also in the plan)' : ' (today)'}', (s) => _editToday(s, always, (l) => l..add(it), (l) => l.any((x) => x.exerciseId == e.id) ? l : (l..add(it))));
    case 'remove':
      final e = lib.find(a(1));
      if (e == null) throw _Bad('unknown exercise "${a(1)}".');
      final always = _always(a(2));
      if (today == null || !today.items.any((x) => x.exerciseId == e.id)) throw _Bad("${e.name} is not in today's workout.");
      if (today.items.length < 2) throw _Bad('a workout needs at least one exercise.');
      return AppAction('Remove ${e.name}${always ? ' (also from the plan)' : ' (today)'}', (s) => _editToday(s, always, (l) => l..removeWhere((x) => x.exerciseId == e.id), (l) => l..removeWhere((x) => x.exerciseId == e.id)));
    case 'change':
      final e = lib.find(a(1));
      if (e == null) throw _Bad('unknown exercise "${a(1)}".');
      if (today == null || !today.items.any((x) => x.exerciseId == e.id)) throw _Bad("${e.name} is not in today's workout.");
      int? sets, rest, lo, hi;
      var always = false;
      for (final kv in w.skip(2)) {
        final p = kv.toLowerCase().split('=');
        if (p.length == 1) {
          always = _always(p[0]);
        } else if (p[0] == 'sets') {
          sets = _int(p[1], 1, 10, 'sets');
        } else if (p[0] == 'reps') {
          (lo, hi) = _reps(p[1]);
        } else if (p[0] == 'rest') {
          rest = _int(p[1].replaceAll(RegExp(r'[^0-9]'), ''), 30, 600, 'rest');
        } else {
          throw _Bad('"${p[0]}" is not something you can change (sets, reps, rest).');
        }
      }
      if (sets == null && rest == null && lo == null) throw _Bad('say what to change: sets=, reps= or rest=.');
      PlanItem ch(PlanItem x) => x.exerciseId != e.id ? x : PlanItem(exerciseId: x.exerciseId, sets: sets ?? x.sets, repLow: lo ?? x.repLow, repHigh: hi ?? x.repHigh, restSec: rest ?? x.restSec);
      final bits = [if (sets != null) '$sets sets', if (lo != null) '$lo-$hi reps', if (rest != null) '${rest}s rest'].join(', ');
      return AppAction('${e.name}: $bits${always ? ' (also in the plan)' : ' (today)'}', (s) => _editToday(s, always, (l) => l.map(ch).toList(), (l) => l.map(ch).toList()));
    case 'style':
      final e = lib.find(a(1));
      if (e == null) throw _Bad('unknown exercise "${a(1)}".');
      final st = a(2) == 'normal' ? '' : a(2);
      if (!lastSetStyles.containsKey(st)) throw _Bad('style is drop, amrap, failure, restpause or normal.');
      final always = _always(a(3));
      if (today == null || !today.items.any((x) => x.exerciseId == e.id)) throw _Bad("${e.name} is not in today's workout.");
      PlanItem ch(PlanItem x) => x.exerciseId == e.id ? x.copyWith(style: st) : x;
      return AppAction('${e.name}: last set ${lastSetStyles[st]!.toLowerCase()}${always ? ' (also in the plan)' : ' (today)'}', (s) => _editToday(s, always, (l) => l.map(ch).toList(), (l) => l.map(ch).toList()));
    case 'body':
      final n = double.tryParse(a(1).replaceAll(',', '.'));
      final unit = a(2) == 'kg' ? Unit.kg : a(2) == 'lb' || a(2) == 'lbs' ? Unit.lb : s.unit;
      if (n == null || !validBodyKg(fromUnit(n, unit))) throw _Bad('say a body weight between ${fmtWeight(bodyKgMin, s.unit)} and ${fmtWeight(bodyKgMax, s.unit)} ${unitLabel(s.unit)}, like "body 82.5 kg".');
      final kg = fromUnit(n, unit);
      final fi = [for (var i = 0; i < 6; i++) a(i)].indexOf('fat');
      final fat = fi < 0 ? null : double.tryParse(a(fi + 1).replaceAll('%', '').replaceAll(',', '.'));
      if (fi >= 0 && (fat == null || !validFat(fat))) throw _Bad('body fat is a percent between ${fatMin.round()} and ${fatMax.round()}, like "fat 18".');
      return AppAction('Weigh-in: ${fmtWeight(kg, s.unit)} ${unitLabel(s.unit)}${fat == null ? '' : ', body fat ${fat.toStringAsFixed(1)}%'}', (s) => s.repo.logBody(kg, fat: fat));
    case 'import':
      if (a(1) != 'undo') throw _Bad('the import tool only undoes: "import undo".');
      final last = s.lastImport;
      if (last == null) throw _Bad('there is no import to undo.');
      final n = last.sessions.length, b = last.body.length;
      return AppAction(
          'Take out the last import (${last.label}): $n workout${n == 1 ? '' : 's'}${b == 0 ? '' : ' and $b weigh-in${b == 1 ? '' : 's'}'}. Undo in AI changes cannot bring them back; you can import the file again.',
          (s) => s.undoLastImport(),
          alwaysAsk: true,
          undoable: false);
    case 'export':
      // batch 20: only picks what the Export screen shows; saving and sending stay the person's
      final ek = ExportKind.values.where((k) => k.name == a(1)).firstOrNull;
      if (ek == null) throw _Bad('export is one of ${ExportKind.values.map((k) => k.name).join(', ')}.');
      return AppAction('Export ready: ${exportLabel[ek]} (Settings → Your data → Export…)', (s) async => s.exportPreset = ek);
    case 'tape':
      // F301: tape <part words...> <cm> [left|right]
      final w = [for (var i = 1; i < 12; i++) a(i)].where((x) => x.isNotEmpty).toList();
      var side = '';
      if (w.isNotEmpty && (w.last == 'left' || w.last == 'right')) side = w.removeLast() == 'left' ? 'L' : 'R';
      var lenU = lengthUnit(s.unit);
      if (w.isNotEmpty && (w.last == 'cm' || w.last == 'in')) lenU = w.removeLast();
      var num0 = w.isEmpty ? '' : w.removeLast();
      if (num0.endsWith('cm') || num0.endsWith('in')) {
        lenU = num0.substring(num0.length - 2);
        num0 = num0.substring(0, num0.length - 2);
      }
      final n = double.tryParse(num0.replaceAll(',', '.'));
      final cm = n == null ? null : (lenU == 'in' ? n * 2.54 : n);
      final part = w.join(' ').toLowerCase();
      if (cm == null || cm <= 0 || cm > 300 || part.isEmpty) throw _Bad(s.unit == Unit.kg ? 'say it like "tape waist 84" or "tape arm 38 left".' : 'say it like "tape waist 34" or "tape arm 15 left" (inches).');
      final sided = tapeParts[part] == true;
      if (sided && side.isEmpty) throw _Bad('say left or right for $part, like "tape $part 38 left".');
      final sd = sided ? side : '';
      return AppAction('Tape: ${Tape(DateTime.now(), part, sd, cm).label} ${fmtLen(cm, s.unit)}', (s) => s.addTape(part, cm, side: sd));
    case 'superset' || 'unsuperset':
      if (today == null) throw _Bad('there is no workout today.');
      if (t == 'superset' && a(1) == 'auto') {
        final always = _always(a(2));
        return AppAction('Supersets to save time${always ? ' (also in the plan)' : ' (today)'}', (s) => _editToday(s, always, (l) => autoSupersets(l, s.lib), (l) => autoSupersets(l, s.lib)));
      }
      final e1 = lib.find(a(1));
      if (e1 == null) throw _Bad('unknown exercise "${a(1)}".');
      if (!today.items.any((x) => x.exerciseId == e1.id)) throw _Bad("${e1.name} is not in today's workout.");
      if (t == 'unsuperset') {
        final always = _always(a(2));
        List<PlanItem> f(List<PlanItem> l) => ungroup(l, l.indexWhere((x) => x.exerciseId == e1.id));
        return AppAction('${e1.name} out of its superset${always ? ' (also in the plan)' : ' (today)'}', (s) => _editToday(s, always, f, f));
      }
      final e2 = lib.find(a(2));
      if (e2 == null) throw _Bad('unknown exercise "${a(2)}".');
      if (!today.items.any((x) => x.exerciseId == e2.id)) throw _Bad("${e2.name} is not in today's workout.");
      final always = _always(a(3));
      List<PlanItem> f(List<PlanItem> l) {
        // move the second right after the first, then group them
        final l2 = [...l];
        final j = l2.indexWhere((x) => x.exerciseId == e2.id);
        final b = l2.removeAt(j);
        final i = l2.indexWhere((x) => x.exerciseId == e1.id);
        l2.insert(i + 1, b);
        return supersetWithNext(l2, i);
      }
      return AppAction('Superset: ${e1.name} + ${e2.name}${always ? ' (also in the plan)' : ' (today)'}', (s) => _editToday(s, always, f, f));
    case 'exercise':
      final e = lib.find(a(2));
      if (e == null) throw _Bad('unknown exercise "${a(2)}".');
      switch (a(1)) {
        case 'favourite' || 'favorite':
          return AppAction('${e.name}: favourite', (s) => s.setFavourite(e.id, true));
        case 'unfavourite' || 'unfavorite':
          return AppAction('${e.name}: not a favourite', (s) => s.setFavourite(e.id, false));
        case 'hide':
          return AppAction('${e.name}: never used', (s) => s.setHidden(e.id, true));
        case 'unhide':
          return AppAction('${e.name}: used again', (s) => s.setHidden(e.id, false));
        case 'rename':
          final n = w.length > 3 ? w.sublist(3).join(' ') : '';
          if (n.trim().isEmpty || n.length > 60) throw _Bad('give the new name.');
          return AppAction('${e.name} is now called "$n"', (s) => s.renameExercise(e.id, n));
      }
      throw _Bad('exercise tools are favourite, unfavourite, hide, unhide, rename.');
    case 'deload':
      final on = _onOff(a(1));
      return AppAction(on ? 'Deload this week' : 'Deload week ended', (s) => s.setDeload(on));
    case 'feeling':
      final f = switch (a(1)) { 'rough' || 'tired' || 'bad' => 1, 'ok' || 'fine' => 2, 'great' || 'good' => 3, _ => throw _Bad('feeling is rough, ok or great.') };
      return AppAction('Today: feeling ${['rough', 'ok', 'great'][f - 1]}', (s) => s.setFeeling(f));
    case 'progression':
      final e = lib.find(a(1));
      if (e == null) throw _Bad('unknown exercise "${a(1)}".');
      if (a(2) != 'linear' && a(2) != 'double') throw _Bad('progression is linear or double.');
      return AppAction('${e.name}: ${a(2) == 'linear' ? 'add weight every session' : 'reps first, then weight'}', (s) => s.setScheme(e.id, a(2)));
    case 'pick':
      final pl = s.plan;
      if (pl == null) throw _Bad('there is no plan yet.');
      if (s.session != null) throw _Bad('a workout is already going; finish it first.');
      final n = _int(a(1) == 'day' ? a(2) : a(1), 1, pl.days.length, 'the day number');
      return AppAction('Today: day $n, ${pl.days[n - 1].name}', (s) => s.pickDay(n - 1));
    case 'skip':
      if (s.plan == null) throw _Bad('there is no plan yet.');
      if (s.session != null) throw _Bad('a workout is already going.');
      return AppAction('Skip ${today?.name ?? 'today'} and move on', (s) => s.skipToday());
    case 'start':
      if (today == null) throw _Bad('there is no workout to start.');
      return AppAction('Start the workout', (s) async {
        await s.startWorkout();
      });
    case 'gym':
      return _gym(a(1), w.length > 2 ? w.sublist(2).join(' ') : '', s);
    case 'log':
      if (s.session == null) throw _Bad('no workout is going; start one first.');
      final e = lib.find(a(1));
      if (e == null) throw _Bad('unknown exercise "${a(1)}".');
      final w = double.tryParse(a(2).replaceAll(',', '.'));
      final r = int.tryParse(a(3));
      if (w == null || w < 0 || w > 1000 || r == null || r < 0 || r > 500) throw _Bad('write it as: log exercise_id weight reps');
      final kg = fromUnit(w, s.unit);
      return AppAction('Log ${e.name}: ${fmtNum(w)} ${unitLabel(s.unit)} × $r', (s) async {
        await s.repo.logSet(s.session!.id, e.id, kg, r);
      });
    case 'fill':
      if (s.session == null) throw _Bad('no workout is going; start one first.');
      final e = lib.find(a(1));
      if (e == null) throw _Bad('unknown exercise "${a(1)}".');
      final it = s.session!.day.items.where((x) => x.exerciseId == e.id).firstOrNull ?? (throw _Bad('${e.name} is not in this workout.'));
      final fw = double.tryParse(a(2).replaceAll(',', '.'));
      final fr = int.tryParse(a(3));
      if (fw == null || fw < 0 || fw > 1000 || fr == null || fr < 0 || fr > 500) throw _Bad('write it as: fill exercise_id weight reps');
      final fkg = fromUnit(fw, s.unit);
      return AppAction('${e.name}: the rest of its ${it.sets} sets at ${fmtNum(fw)} ${unitLabel(s.unit)} × $fr', (s) async {
        final done = (await s.repo.setsFor(s.session!.id)).where((x) => x.key == liftKey(it) && x.counts).length;
        for (var i = done; i < it.sets; i++) {
          await s.repo.logSet(s.session!.id, e.id, fkg, fr, slot: liftKey(it));
        }
      });
    case 'note':
      final e = lib.find(a(1));
      if (e == null) throw _Bad('unknown exercise "${a(1)}".');
      final text = w.length > 2 ? w.sublist(2).join(' ').trim() : '';
      if (text.length > 200) throw _Bad('keep the note under 200 characters.');
      return AppAction(text.isEmpty ? '${e.name}: note removed' : '${e.name}: note "$text"', (s) => s.repo.setExNote(e.id, text == 'none' || text == 'clear' ? '' : text));
    case 'step':
      final e = lib.find(a(1));
      if (e == null) throw _Bad('unknown exercise "${a(1)}".');
      if (a(2) == 'usual' || a(2) == 'default') return AppAction('${e.name}: the usual weight step', (s) => s.setExStep(e.id, null));
      final sv = double.tryParse(a(2).replaceAll(',', '.'));
      if (sv == null || sv <= 0 || sv > 25) throw _Bad('write it as: step exercise_id <weight> (or usual)');
      return AppAction('${e.name}: weight step ${fmtNum(sv)} ${unitLabel(s.unit)}', (s) => s.setExStep(e.id, fromUnit(sv, s.unit)));
    case 'program':
      return _program(w, s, lib);
    case 'plans':
      return _plans(w, s);
    case 'weak':
      final e = lib.find(a(1)) ?? (throw _Bad('unknown exercise "${a(1)}".'));
      final pts = weakPoints[e.id] ?? (throw _Bad('weak points are known for ${weakPoints.keys.join(', ')}.'));
      final pt = pts.keys.where((k) => _slug(k) == _slug(w.length > 2 ? w.sublist(2).join(' ') : '')).firstOrNull ?? (throw _Bad('point is ${pts.keys.map(_slug).join(' or ')}.'));
      return AppAction('${e.name}: an exercise for "${pt.toLowerCase()}"', (s) async {
        final n = await s.addWeakPoint(e.id, pt);
        if (n == null) throw StateError('none of the exercises for that fit this gym or plan');
      });
    case 'day':
      if (a(1) != 'copy') throw _Bad('write it as: day copy <number>.');
      if (s.plan == null) throw _Bad('there is no plan yet.');
      final n = _int(a(2), 1, s.plan!.days.length, 'day');
      return AppAction('Copy of day $n (${s.plan!.days[n - 1].name})', (s) => s.savePlanEdits(s.plan!.duplicateDay(n - 1)));
    case 'sore':
      if (a(1) == 'swap') {
        if (s.soreToday.isEmpty) throw _Bad('nothing is marked sore today; use sore <joint> first.');
        if (s.session != null) throw _Bad('a workout is already going; swap in the workout instead.');
        return AppAction("Swap today's exercises that are hard on ${s.soreToday.map((j) => jointLabel[j]!.toLowerCase()).join(', ')}", (s) => s.swapSore());
      }
      final js = a(1) == 'none' || a(1) == 'off' ? <Joint>{} : {for (final n in a(1).split(',')) _jointWord(n)};
      return AppAction(js.isEmpty ? 'Nothing sore today' : 'Sore today: ${js.map((j) => jointLabel[j]!.toLowerCase()).join(', ')}', (s) => s.setSore(js));
    case 'pain':
      final e = lib.find(a(1)) ?? (throw _Bad('unknown exercise "${a(1)}".'));
      if (a(2) == 'clear' || a(2) == 'none') return AppAction('${e.name}: back to its normal weights', (s) => s.clearRamp(e.id));
      final j = a(2).isEmpty ? null : _jointWord(a(2));
      return AppAction('${e.name} hurt${j == null ? '' : ' (${jointLabel[j]!.toLowerCase()})'}: next two times lighter', (s) => s.flagPain(e.id, j));
    case 'volume':
      if (a(1) != 'fit') throw _Bad('write it as: volume fit');
      if (s.plan == null) throw _Bad('there is no plan yet.');
      if (s.plan!.program != null || s.plan!.weeksPerCycle > 1) throw _Bad('a program keeps its own sets.');
      return AppAction('Sets fitted to the weekly range per muscle', (s) => s.fitPlanVolume());
    case 'stall':
      if (a(1) != 'swap') throw _Bad('write it as: stall swap <exercise_id>');
      final e = lib.find(a(2)) ?? (throw _Bad('unknown exercise "${a(2)}".'));
      if (s.plan == null || !s.plan!.days.any((d) => d.items.any((i) => i.exerciseId == e.id))) throw _Bad('${e.name} is not in the plan.');
      if (s.blockSwapPlaces(e.id).isEmpty) throw _Bad('a program keeps its own lifts; change the program instead.');
      final v = s.variationFor(e) ?? (throw _Bad('no variation of ${e.name} fits this gym.'));
      return AppAction('${v.name} instead of ${e.name} for 4 weeks', (s) async {
        await s.swapForBlock(e.id);
      });
    case 'changes':
      if (a(1) != 'undo') throw _Bad('write it as: changes undo <n>');
      final n = _int(a(2), 1, s.autoChanges.isEmpty ? 1 : s.autoChanges.length, 'n');
      if (s.autoChanges.isEmpty) throw _Bad('the app has not moved any weights yet.');
      return AppAction('Put back: ${s.autoChangeText(s.autoChanges[n - 1])}', (s) async {
        if (!await s.undoAutoChange(n - 1)) throw StateError('it moved again since, so it cannot be put back');
      });
    case 'dashboard':
      final tile = a(2);
      if (!dashTiles.containsKey(tile)) throw _Bad('tiles are ${dashTiles.keys.join(', ')}.');
      final add = a(1) == 'add' ? true : a(1) == 'remove' ? false : throw _Bad('say add or remove.');
      return AppAction('${add ? 'Progress shows' : 'Progress no longer shows'} "${dashTiles[tile]}"', (s) => s.setDash(add ? [...s.dash.where((x) => x != tile), tile] : [...s.dash.where((x) => x != tile)]));
    case 'goal':
      return _goal(w, s, lib);
    case 'rest_hint':
      return AppAction('Rest-day suggestion put away for today', (s) => s.hideRestHint());
    case 'setting':
      return _setting(a(1), w.length > 2 ? w.sublist(2).join(' ').toLowerCase() : '', s);
    case 'profile':
      return _profile(a(1), a(2), a(3), s, more: w.length > 2 ? w.sublist(2).join(' ').toLowerCase() : '');
  }
  throw _Bad('the app has no tool called "$t".');
}

/// Today's list (and with [always] the plan's day for today) changed by [f].
Future<void> _editToday(AppState s, bool always, List<PlanItem> Function(List<PlanItem>) f, List<PlanItem> Function(List<PlanItem>) fPlan) async {
  final d = s.today!;
  final nd = d.copyWith(items: f([...d.items]));
  if (always && s.plan != null) {
    final di = s.session?.dayIndex ?? s.todayIndex;
    if (di >= 0 && di < s.plan!.days.length) {
      final pd = s.plan!.days[di];
      final days = [...s.plan!.days]..[di] = pd.copyWith(items: fPlan([...pd.items]));
      final keepSession = s.session != null;
      await s.savePlanEdits(s.plan!.copyWith(days: days, userEdited: true));
      if (keepSession) await s.setToday(nd);
      return;
    }
  }
  await s.setToday(nd);
}

AppAction _gym(String k, String v, AppState s) {
  final arg = v.trim();
  switch (k) {
    case 'use':
      final g = s.gyms.where((g) => g.name.toLowerCase() == arg.toLowerCase()).firstOrNull ?? s.gyms.where((g) => g.name.toLowerCase().contains(arg.toLowerCase())).firstOrNull;
      if (g == null) throw _Bad('there is no gym called "$arg" (${s.gyms.isEmpty ? 'no gyms yet' : s.gyms.map((g) => g.name).join(', ')}).');
      return AppAction('At: ${g.name}', (s) => s.useGym(g.id));
    case 'new':
      final p = arg.split(RegExp(r'\s+'));
      final t = gymTemplates.where((t) => t.id == p.first.toLowerCase()).firstOrNull ?? (throw _Bad('template is ${gymTemplates.map((t) => t.id).join(', ')}.'));
      final name = p.length > 1 ? p.sublist(1).join(' ') : t.label;
      return AppAction('New gym: $name (from ${t.label}), now the one you are at', (s) => s.saveGym(Gym.create(name, {...t.items}, maxDumbbellKg: t.maxDumbbellKg), use: true));
    case 'add' || 'remove' || 'taken':
      final it = gymItemById[arg.toLowerCase()] ?? (throw _Bad('unknown gym item "$arg".'));
      final g = s.activeGym ?? (throw _Bad('no gym is set up yet; make one first (gym new ...).'));
      if (k == 'taken') return AppAction('${it.label}: taken today', (s) => s.setTaken(it.id, true));
      final add = k == 'add';
      return AppAction('${g.name} ${add ? 'has' : 'has no'} ${it.label.toLowerCase()}', (s) {
        final items = {...s.activeGym!.items};
        add ? items.add(it.id) : items.remove(it.id);
        return s.saveGym(s.activeGym!.copyWith(items: items));
      });
  }
  throw _Bad('gym tools are use, new, add, remove, taken.');
}

AppAction _setting(String k, String v, AppState s) {
  final st = s.settings;
  switch (k) {
    case 'rest':
      if (v == 'plan') return AppAction('Rest: each exercise\'s own rest', (s) => s.saveSettings(s.settings.copyWith(planRest: true, restOff: false)));
      if (v == 'off') return AppAction('Rest timer off', (s) => s.saveSettings(s.settings.copyWith(restOff: true)));
      final n = _int(v.replaceAll(RegExp(r'[^0-9]'), ''), 30, 600, 'rest');
      return AppAction('Rest between sets: ${n}s', (s) => s.saveSettings(s.settings.copyWith(rest: n, restOff: false)));
    case 'smart_rest':
      final b = _onOff(v);
      return AppAction('Smart rest ${b ? 'on' : 'off'}', (s) => s.saveSettings(s.settings.copyWith(smartRest: b)));
    case 'sound':
      if (!{'cute', 'simple', 'off'}.contains(v)) throw _Bad('sound is cute, simple or off.');
      return AppAction('Sounds: $v', (s) => s.saveSettings(s.settings.copyWith(sound: v)));
    case 'dim_rest':
      final dr = _onOff(v);
      return AppAction('Dark screen while resting: ${dr ? 'on' : 'off'}', (s) => s.saveSettings(s.settings.copyWith(dimRest: dr)));
    case 'left_handed':
      final lh = _onOff(v);
      return AppAction('Left-handed layout: ${lh ? 'on' : 'off'}', (s) => s.saveSettings(s.settings.copyWith(leftHanded: lh)));
    case 'keep_awake':
      final b = _onOff(v);
      return AppAction('Screen stays on in workouts: ${b ? 'yes' : 'no'}', (s) => s.saveSettings(s.settings.copyWith(keepAwake: b)));
    case 'reminders':
      final days = v == 'off' || v == 'none' ? <int>[] : [for (final d in v.split(RegExp(r'[,\s]+'))) if (d.isNotEmpty) _days[d.substring(0, d.length.clamp(0, 3))] ?? (throw _Bad('"$d" is not a weekday (mon, tue, ...).'))];
      return AppAction(days.isEmpty ? 'Reminders off' : 'Reminders on ${days.map((d) => _days.keys.elementAt(d - 1)).join(', ')}', (s) => s.saveSettings(s.settings.copyWith(remindDays: days.toSet().toList()..sort())));
    case 'weigh_reminder':
      if (v == 'off' || v == 'none') return AppAction('Morning weigh-in reminder off', (s) => s.saveSettings(s.settings.copyWith(weighAt: -1)));
      final wm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v);
      if (wm == null || int.parse(wm.group(1)!) > 23 || int.parse(wm.group(2)!) > 59) throw _Bad('time looks like 07:00, or off.');
      final at = int.parse(wm.group(1)!) * 60 + int.parse(wm.group(2)!);
      return AppAction('Morning weigh-in reminder at ${wm.group(1)!.padLeft(2, '0')}:${wm.group(2)}', (s) => s.saveSettings(s.settings.copyWith(weighAt: at)));
    case 'reminder_time':
      final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v);
      if (m == null) throw _Bad('time looks like 17:30.');
      final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
      if (h > 23 || mi > 59) throw _Bad('time looks like 17:30.');
      return AppAction('Reminder time ${m.group(1)!.padLeft(2, '0')}:${m.group(2)}', (s) => s.saveSettings(s.settings.copyWith(remindAt: h * 60 + mi)));
    case 'auto_update':
      final b = _onOff(v);
      // turning a network feature ON always asks the person, even in Auto (PLAN-next change 8)
      return AppAction('Check for app updates on start: ${b ? 'yes' : 'no'}', (s) => s.saveSettings(s.settings.copyWith(autoUpdate: b)), alwaysAsk: b);
    case 'warmups':
      final b = _onOff(v);
      return AppAction('Warm-up help ${b ? 'on' : 'off'}', (s) => s.saveSettings(s.settings.copyWith(warmups: b)));
    case 'progression':
      if (!{'slow', 'steady', 'fast'}.contains(v)) throw _Bad('progression is slow, steady or fast.');
      return AppAction('Progression: $v', (s) => s.saveSettings(s.settings.copyWith(progSpeed: v)));
    case 'drop_after':
      final n = _int(v, 1, 3, 'drop_after');
      return AppAction('Weight drops after $n missed session${n == 1 ? '' : 's'}', (s) => s.saveSettings(s.settings.copyWith(missesToDrop: n)));
    case 'deload_every':
      final n = _int(v, 0, 12, 'deload_every');
      return AppAction(n == 0 ? 'Deload only when asked' : 'Deload every $n weeks', (s) => s.saveSettings(s.settings.copyWith(deloadEvery: n)));
    case 'badges':
      final bg = _onOff(v);
      return AppAction(bg ? 'Badges and levels on' : 'No badges or levels', (s) => s.saveSettings(s.settings.copyWith(badges: bg)));
    case 'chart_smooth':
      final sm = _onOff(v);
      return AppAction(sm ? 'Charts with smooth curves' : 'Charts with straight lines', (s) => s.saveSettings(s.settings.copyWith(chartSmooth: sm)));
    case 'chart_dots':
      final dt = _onOff(v);
      return AppAction(dt ? 'Charts show a dot per workout' : 'Charts without dots', (s) => s.saveSettings(s.settings.copyWith(chartDots: dt)));
    case 'tips':
      final on = _onOff(v);
      return AppAction(on ? 'Tips on Today' : 'No tips on Today', (s) => s.saveSettings(s.settings.copyWith(tips: on)));
    case 'climb':
      final on = _onOff(v);
      return AppAction(on ? 'Volume climb on: extras gain a set each week of a block' : 'Volume climb off', (s) => s.saveSettings(s.settings.copyWith(climb: on)));
    case 'hide_in_recents':
      final b = _onOff(v);
      return AppAction('Hide the app in recent apps: ${b ? 'yes' : 'no'}', (s) async {
        await s.saveSettings(s.settings.copyWith(hideRecents: b));
        s.applyPrefs();
      });
    case 'checkin':
      final b = _onOff(v);
      return AppAction('Ask how I feel before a workout: ${b ? 'yes' : 'no'}', (s) => s.saveSettings(s.settings.copyWith(checkin: b)));
    case 'effort_chips':
      final b = _onOff(v);
      return AppAction('Ask "how was that set?" while resting: ${b ? 'yes' : 'no'}', (s) => s.saveSettings(s.settings.copyWith(effortChips: b)));
    case 'effort_drives':
      final b = _onOff(v);
      return AppAction('Effort taps change the next jump: ${b ? 'yes' : 'no'}', (s) => s.saveSettings(s.settings.copyWith(effortDrives: b)));
    case 'simple':
      final b = _onOff(v);
      return AppAction(b ? 'Simple mode on (extras hidden)' : 'Simple mode off (all tools shown)', (s) => s.saveSettings(s.settings.copyWith(simple: b)));
    case 'formula':
      if (v != 'epley' && v != 'brzycki') throw _Bad('formula is epley or brzycki.');
      return AppAction('One-rep max formula: ${v == 'epley' ? 'Epley' : 'Brzycki'}', (s) => s.saveSettings(s.settings.copyWith(formula: v)));
    case 'drop_pct':
      final n = _int(v.replaceAll('%', ''), 5, 15, 'drop_pct');
      if (n != 5 && n != 10 && n != 15) throw _Bad('drop_pct is 5, 10 or 15.');
      return AppAction('After misses the weight drops by $n%', (s) => s.saveSettings(s.settings.copyWith(dropPct: n)));
    case 'steps':
      final parts = v.split(RegExp(r'\s+'));
      final kind = const [StepKind.barbell, StepKind.dumbbell, StepKind.machine, StepKind.cable].where((x) => x.name == parts.first).firstOrNull ?? (throw _Bad('steps is barbell, dumbbell, machine or cable, then the weight.'));
      final n = parts.length > 1 ? double.tryParse(parts[1].replaceAll(',', '.')) : null;
      if (n == null || n <= 0 || n > 20) throw _Bad('write it as: setting steps barbell 5');
      return AppAction('Smallest ${kind.name} step: ${fmtNum(n)} ${unitLabel(s.unit)}', (s) => s.saveSettings(s.settings.copyWith(steps: {...s.settings.steps, '${kind.name}_${s.unit.name}': n})));
    case 'auto_icons':
      final b = _onOff(v);
      return AppAction('Check for icon packs on start: ${b ? 'yes' : 'no'}', (s) => s.saveSettings(s.settings.copyWith(autoPacks: b)), alwaysAsk: b);
    // what the AI is shown and how it is overseen are the person's alone (PLAN-next change 8)
    case 'ai' || 'ai_on' || 'auto' || 'ai_auto' || 'key' || 'api_key' || 'model' || 'server' || 'preview':
      throw _Bad('the AI cannot change its own setup. Do that in Settings → Ask AI.');
  }
  if (st.aiOn && k.isEmpty) throw _Bad('say which setting.');
  throw _Bad('the app has no setting called "$k".');
}

AppAction _program(List<String> w, AppState s, Library lib) {
  String a(int k) => k < w.length ? w[k].toLowerCase() : '';
  switch (a(1)) {
    case 'start':
      final tp = templateById(a(2)) ?? matchProgram(w.skip(2).join(' ')) ?? (throw _Bad('no program "${a(2)}" (ids: ${programTemplates.map((t) => t.id).join(', ')}).'));
      if (s.profile == null) throw _Bad('finish the setup first.');
      return AppAction('Start ${tp.name} (training maxes from your history)', (s) async {
        final pl = buildProgram(tp, s.profile!, s.lib);
        await s.startProgram(pl, {for (final k in programMaxes(pl).keys) k: await s.guessMax(k, basis: pl.program?.basis ?? 'tm90')});
      });
    case 'tm':
      final e = lib.find(a(2).split('#').first) ?? (throw _Bad('unknown exercise "${a(2)}".'));
      final key = a(2).contains('#') ? '${e.id}#${a(2).split('#')[1].toUpperCase()}' : e.id;
      if (a(3) == 'clear' || a(3) == 'none') return AppAction('${e.name}: no training max (set from the next workout)', (s) => s.setTm(key, null));
      final kg = _weight(a(3), s);
      return AppAction('${e.name}: training max ${fmtWeight(kg, s.unit)} ${unitLabel(s.unit)}', (s) => s.setTm(key, kg));
    case 'stage':
      final e = lib.find(a(2).split('#').first) ?? (throw _Bad('unknown exercise "${a(2)}".'));
      final key = a(2).contains('#') ? '${e.id}#${a(2).split('#')[1].toUpperCase()}' : e.id;
      final r = s.plan?.program?.rules[key];
      if (r == null || r.kind != 'stage') throw _Bad('${e.name} has no stage rule in this plan.');
      final n = _int(a(3), 1, r.stages.length, 'stage');
      return AppAction('${e.name}: stage $n (${r.stages[n - 1]})', (s) => s.setStage(key, n - 1));
    case 'rule':
      final e = lib.find(a(2).split('#').first) ?? (throw _Bad('unknown exercise "${a(2)}".'));
      final key = a(2).contains('#') ? '${e.id}#${a(2).split('#')[1].toUpperCase()}' : e.id;
      if (s.plan == null) throw _Bad('there is no plan yet.');
      final kind = a(3);
      if (kind == 'none') return AppAction('${e.name}: the usual progression', (s) => s.setRule(key, null));
      final old = s.plan!.program?.rules[key] ?? const LiftRule();
      if (kind == 'script') {
        final text = w.sublist(4).join(' ').split(';').map((x) => x.trim()).where((x) => x.isNotEmpty).join('\n');
        final bad = checkScript(text);
        if (bad != null || text.isEmpty) throw _Bad(bad ?? 'write at least one line, like "if top: add 1".');
        return AppAction('${e.name}: my own rule (${text.split('\n').length} lines)', (s) => s.setRule(key, old.copyWith(kind: 'script', script: text)));
      }
      if (!ruleKinds.containsKey(kind)) throw _Bad('rule is ${ruleKinds.keys.join(', ')} or none.');
      if (kind == 'stage' && old.stages.isEmpty) throw _Bad('a stage rule needs stages; change them on the Lift rules page.');
      if (kind == 'ladder' && old.ladder.isEmpty) throw _Bad('a ladder needs its steps; use a bodyweight program for ladders.');
      var r = old.copyWith(kind: kind);
      for (final o in w.skip(4)) {
        final m = RegExp(r'^(inc|misses|reset|amrap)=(\d+(?:\.\d+)?)%?$').firstMatch(o.toLowerCase());
        if (m == null) throw _Bad('options look like inc=1 misses=3 reset=90 amrap=10.');
        final v = double.parse(m[2]!);
        r = switch (m[1]) {
          'inc' => v > 0 && v <= 10 ? r.copyWith(inc: v) : throw _Bad('inc is 0.5-10 steps.'),
          'misses' => v >= 1 && v <= 9 ? r.copyWith(misses: v.round()) : throw _Bad('misses is 1-9.'),
          'reset' => v >= 50 && v <= 100 ? r.copyWith(reset: v / 100) : throw _Bad('reset is 50-100 (percent).'),
          _ => v >= 0 && v <= 50 ? r.copyWith(amrapGoal: v.round()) : throw _Bad('amrap is 0-50 reps.'),
        };
      }
      return AppAction('${e.name}: ${r.describe(s.unit, e.step)}', (s) => s.setRule(key, r));
  }
  throw _Bad('program tools: start, tm, rule, stage.');
}

AppAction _plans(List<String> w, AppState s) {
  final k = w.length > 1 ? w[1].toLowerCase() : '';
  final rest = w.length > 2 ? w.sublist(2).join(' ').trim() : '';
  if (s.plan == null && k != 'use') throw _Bad('there is no plan yet.');
  switch (k) {
    case 'copy':
      return AppAction('Saved a copy of "${s.plan!.name}"', (s) => s.duplicatePlan());
    case 'use':
      return AppAction('Switch to the plan "$rest"', (s) async {
        final l = await s.savedPlans();
        final p = l.where((p) => p.name.toLowerCase() == rest.toLowerCase()).firstOrNull ?? l.where((p) => p.name.toLowerCase().contains(rest.toLowerCase())).firstOrNull;
        if (p == null) throw StateError('no saved plan called "$rest"');
        await s.restorePlan(p.id);
      });
    case 'folder':
      final f = rest.toLowerCase() == 'none' ? '' : rest;
      if (f.length > 40) throw _Bad('keep the folder name short.');
      return AppAction(f.isEmpty ? 'Plan out of its folder' : 'Plan in the folder "$f"', (s) => s.setPlanFolder(s.plan!.id, f));
    case 'variety':
      final n = _int(rest, 0, 12, 'variety');
      if (n != 0 && n != 4 && n != 6 && n != 8) throw _Bad('variety is 0, 4, 6 or 8 weeks.');
      return AppAction(n == 0 ? 'Accessories stay the same' : 'Accessories change every $n weeks', (s) => s.setRotation(n));
  }
  throw _Bad('plans tools: copy, use, folder, variety.');
}

AppAction _profile(String k, String a1, String a2, AppState s, {String more = ''}) {
  final p = s.profile;
  if (p == null) throw _Bad('finish the setup first.');
  switch (k) {
    case 'goal':
      final g = Goal.values.where((x) => _goalWord(x) == a1 || x.name.toLowerCase() == a1.replaceAll('_', '')).firstOrNull ?? (throw _Bad('goal is ${Goal.values.map(_goalWord).join(', ')}.'));
      return AppAction('Goal: ${goalLabel[g]}', (s) => s.saveProfile(s.profile!.copyWith(goal: g)));
    case 'experience':
      if (!experienceLabel.containsKey(a1)) throw _Bad('experience is new, some or years.');
      return AppAction('Experience: ${experienceLabel[a1]}', (s) => s.saveProfile(s.profile!.copyWith(experience: a1)));
    case 'weekdays':
      final d = _weekdays(a1);
      return AppAction(d.isEmpty ? 'Plan days: any day (the loop)' : 'Plan days on ${d.map((x) => weekdayShort[x - 1]).join(', ')}', (s) => s.saveProfile(s.profile!.copyWith(weekdays: d, days: d.isEmpty ? null : d.length)));
    case 'sport_days':
      final d = _weekdays(a1);
      return AppAction(d.isEmpty ? 'No sport days' : 'Sport days: ${d.map((x) => weekdayShort[x - 1]).join(', ')} (legs lighter around them)', (s) => s.saveProfile(s.profile!.copyWith(sportDays: d.toSet())));
    case 'priority' || 'low':
      if (!priorityMuscles.contains(a2)) throw _Bad('muscle is ${priorityMuscles.join(', ')}.');
      final add = a1 == 'add' ? true : a1 == 'remove' ? false : throw _Bad('say add or remove.');
      return AppAction('${add ? (k == 'low' ? 'Fewer sets for' : 'More sets for') : 'Usual sets for'} $a2 (from the next plan made)', (s) {
        final pr = {...s.profile!.priority}, lo = {...s.profile!.low};
        (k == 'low' ? lo : pr).remove(a2);
        if (add) {
          (k == 'low' ? lo : pr).add(a2);
          (k == 'low' ? pr : lo).remove(a2);
        }
        return s.saveProfile(s.profile!.copyWith(priority: pr, low: lo));
      });
    case 'focus':
      if (a1 == 'none' || a1 == 'off') return AppAction('No focus block (from the next plan made)', (s) => s.saveProfile(s.profile!.copyWith(clearSpecial: true)));
      if (!priorityMuscles.contains(a1)) throw _Bad('muscle is ${priorityMuscles.join(', ')}.');
      return AppAction('Focus block for $a1: extra sets for it, others held (from the next plan made)', (s) => s.saveProfile(s.profile!.copyWith(special: a1)));
    case 'body_weight':
      if (a1 == 'none') return AppAction('Body weight not used', (s) => s.saveProfile(Profile.fromJson({...s.profile!.toJson()..remove('bodyKg')})));
      final kg = _weight(a1, s);
      return AppAction('Body weight ${fmtWeight(kg, s.unit)} ${unitLabel(s.unit)} (only for first weights)', (s) => s.saveProfile(s.profile!.copyWith(bodyKg: kg)));
    case 'age':
      if (a1 == 'none') return AppAction('Age not used', (s) => s.saveProfile(Profile.fromJson({...s.profile!.toJson()..remove('age')})));
      final n = _int(a1, 12, 100, 'age');
      return AppAction('Age $n (only for first weights)', (s) => s.saveProfile(s.profile!.copyWith(age: n)));
    case 'height':
      if (a1 == 'none') return AppAction('Height not used', (s) => s.saveProfile(Profile.fromJson({...s.profile!.toJson()..remove('height')})));
      final cmH = parseHeight(more.isEmpty ? '$a1 $a2' : more); // every word: "5 ft 10" (review 5, P2-7)
      if (cmH == null) throw _Bad('height is like "profile height 178", "profile height 5\'10" or "profile height 70 in".');
      return AppAction('Height ${fmtHeight(cmH, s.unit)} (for BMI and FFMI)', (s) => s.saveProfile(s.profile!.copyWith(heightCm: cmH)));
    case 'sex':
      if (a1 == 'none') return AppAction('Sex not used', (s) => s.saveProfile(Profile.fromJson({...s.profile!.toJson()..remove('sex')})));
      if (a1 != 'm' && a1 != 'f') throw _Bad('sex is m, f or none.');
      return AppAction('Sex: ${a1 == 'm' ? 'male' : 'female'} (only for first weights)', (s) => s.saveProfile(s.profile!.copyWith(sex: a1)));
    case 'days':
      final n = _int(a1, 1, 7, 'days');
      return AppAction('Training days a week: $n', (s) => s.saveProfile(s.profile!.copyWith(days: n)));
    case 'minutes':
      final n = _int(a1, 20, 180, 'minutes');
      return AppAction('Session length: $n minutes', (s) => s.saveProfile(s.profile!.copyWith(minutes: n)));
    case 'unit':
      final u = switch (a1) { 'kg' => 'kg', 'lb' || 'lbs' => 'lb', _ => throw _Bad('unit is kg or lb.') };
      return AppAction('Weights in $u', (s) => s.saveProfile(s.profile!.copyWith(unit: u == 'kg' ? Unit.kg : Unit.lb)));
    case 'split':
      if (a1 == 'auto') return AppAction('Split: let the app choose', (s) => s.saveProfile(s.profile!.copyWith(clearSplit: true)));
      if (!splitLabel.containsKey(a1)) throw _Bad('split is ${splitLabel.keys.join(', ')} or auto.');
      return AppAction('Split: ${splitLabel[a1]}', (s) => s.saveProfile(s.profile!.copyWith(split: a1)));
    case 'equipment':
      final e = Equipment.values.where((x) => x.name == a2).firstOrNull ?? (throw _Bad('equipment is ${Equipment.values.map((e) => e.name).join(', ')}.'));
      final add = a1 == 'add' ? true : a1 == 'remove' ? false : throw _Bad('say add or remove.');
      return AppAction('${add ? 'Gym has' : 'Gym has no'} ${equipmentLabel[e]!.toLowerCase()}', (s) {
        final h = {...s.profile!.have};
        add ? h.add(e) : h.remove(e);
        return s.saveProfile(s.profile!.copyWith(have: h));
      });
    case 'pregnancy':
      final m = switch (a1) { 'pregnant' => 'pregnant', 'postpartum' || 'after_birth' => 'postpartum', 'none' || 'off' || 'no' => null, _ => throw _Bad('say pregnant, postpartum or none.') };
      return AppAction(m == null ? 'Pregnancy caution off' : 'Careful mode: ${pregnancyLabel[m]!.toLowerCase()}', (s) => s.saveProfile(m == null ? s.profile!.copyWith(clearPregnancy: true) : s.profile!.copyWith(pregnancy: m)));
    case 'go_easy':
      final j = Joint.values.where((x) => x.name.toLowerCase() == a2.toLowerCase()).firstOrNull ?? (throw _Bad('joint is ${Joint.values.map((j) => j.name).join(', ')}.'));
      final add = a1 == 'add' ? true : a1 == 'remove' ? false : throw _Bad('say add or remove.');
      return AppAction('${add ? 'Go easy on' : 'No longer going easy on'} ${jointLabel[j]!.toLowerCase()}', (s) {
        final h = {...s.profile!.avoid};
        add ? h.add(j) : h.remove(j);
        return s.saveProfile(s.profile!.copyWith(avoid: h));
      });
  }
  throw _Bad('the profile has no "$k" (goal, experience, days, minutes, unit, split, weekdays, sport_days, priority, low, focus, body_weight, age, sex, equipment, go_easy, pregnancy).');
}

// ---------- undo ----------

/// The parts of the app the tools can change: settings, profile, plans, today, the rotation and
/// an open workout's exercise list. Saved before every AI batch so one tap puts it all back.
Future<Map<String, dynamic>> snapshot(Database db) async => {
      'kv': [for (final r in await db.query('kv')) if (_undoable(r['k'] as String)) r],
      'plan': await db.query('plan'),
      'open': await db.query('session', columns: ['id', 'day'], where: 'finished IS NULL'),
    };

bool _undoable(String k) => k == 'settings' || k == 'profile' || k == 'deload_until' || k == 'feeling' || k == 'custom_ex' || k == 'ex_prefs' || k == 'gyms' || k == 'gym_active' || k == 'taken' || k == 'sore' || k == 'ramp' || k == 'pain' || k == 'rest_hint_off' || k == 'block_swaps' || k == 'tip_off' || k == 'dash' || k == 'auto_changes' || k == 'aims' || k == 'override' || k == 'picked' || k.startsWith('last_day:');

Future<void> restoreSnapshot(Database db, Map<String, dynamic> snap) async {
  await db.transaction((tx) async {
    for (final r in await tx.query('kv')) {
      if (_undoable(r['k'] as String)) await tx.delete('kv', where: 'k = ?', whereArgs: [r['k']]);
    }
    for (final r in (snap['kv'] as List).cast<Map<String, dynamic>>()) {
      await tx.insert('kv', r, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await tx.delete('plan');
    for (final r in (snap['plan'] as List).cast<Map<String, dynamic>>()) {
      await tx.insert('plan', r);
    }
    for (final r in (snap['open'] as List).cast<Map<String, dynamic>>()) {
      await tx.update('session', {'day': r['day']}, where: 'id = ? AND finished IS NULL', whereArgs: [r['id']]);
    }
    // a workout the AI started is removed again if nothing was logged in it yet
    final openIds = {for (final r in (snap['open'] as List).cast<Map<String, dynamic>>()) r['id']};
    for (final r in await tx.query('session', columns: ['id'], where: 'finished IS NULL')) {
      if (!openIds.contains(r['id'])) {
        final n = Sqflite.firstIntValue(await tx.rawQuery('SELECT COUNT(*) FROM set_log WHERE session_id = ?', [r['id']])) ?? 0;
        if (n == 0) {
          await tx.delete('session', where: 'id = ?', whereArgs: [r['id']]);
        }
      }
    }
  });
}

/// One entry in "AI changes": what it did and how to put it back.
class AiChange {
  final DateTime at;
  final String asked;
  final List<String> did;
  final Map<String, dynamic> before;
  final bool undone;
  final bool partial; // it held a step Undo cannot bring back (an import taken out)
  const AiChange(this.at, this.asked, this.did, this.before, {this.undone = false, this.partial = false});

  Map<String, dynamic> toJson() => {'at': at.millisecondsSinceEpoch, 'asked': asked, 'did': did, 'before': before, 'undone': undone, if (partial) 'partial': true};
  factory AiChange.fromJson(Map<String, dynamic> j) => AiChange(DateTime.fromMillisecondsSinceEpoch(j['at'] as int), j['asked'] as String,
      [for (final d in j['did'] as List) d as String], j['before'] as Map<String, dynamic>,
      undone: (j['undone'] ?? false) as bool, partial: (j['partial'] ?? false) as bool);
}

String encodeChanges(List<AiChange> l) => jsonEncode([for (final c in l) c.toJson()]);
List<AiChange> decodeChanges(String? s) {
  if (s == null) return [];
  try {
    return [for (final c in jsonDecode(s) as List) AiChange.fromJson(c as Map<String, dynamic>)];
  } catch (_) {
    return [];
  }
}
