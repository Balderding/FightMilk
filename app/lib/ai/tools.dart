import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/exercise.dart';
import '../domain/gym.dart';
import '../domain/library.dart';
import '../domain/plan.dart';
import '../domain/plan_maker.dart';
import '../domain/superset.dart';
import '../domain/units.dart';
import '../ui/app_state.dart';
import 'plan_json.dart';

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
  const AppAction(this.says, this.run);
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
DO: body <weight> kg|lb            log a weigh-in
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
DO: setting reminders <mon,tue,...|off>
DO: setting reminder_time <HH:MM>
DO: setting preview on|off
DO: setting auto_update on|off
DO: setting auto_icons on|off
DO: setting warmups on|off           (warm-up help: general warm-up, warm-up sets, cool-down)
DO: setting hide_in_recents on|off  (blank card in recent apps, no screenshots)
DO: profile goal strength|size|both
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
      if (n == null || n < 20 || n > 700) throw _Bad('say a body weight, like "body 82.5 kg".');
      final kg = fromUnit(n, unit);
      return AppAction('Weigh-in: ${fmtWeight(kg, s.unit)} ${unitLabel(s.unit)}', (s) => s.repo.logBody(kg));
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
      return AppAction('Today: day $n, ${pl.days[n - 1].name}', (s) async => s.pickDay(n - 1));
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
    case 'setting':
      return _setting(a(1), w.length > 2 ? w.sublist(2).join(' ').toLowerCase() : '', s);
    case 'profile':
      return _profile(a(1), a(2), a(3), s);
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
      await s.savePlanEdits(Plan(id: s.plan!.id, name: s.plan!.name, source: s.plan!.source, days: days, userEdited: true, created: s.plan!.created));
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
    case 'keep_awake':
      final b = _onOff(v);
      return AppAction('Screen stays on in workouts: ${b ? 'yes' : 'no'}', (s) => s.saveSettings(s.settings.copyWith(keepAwake: b)));
    case 'reminders':
      final days = v == 'off' || v == 'none' ? <int>[] : [for (final d in v.split(RegExp(r'[,\s]+'))) if (d.isNotEmpty) _days[d.substring(0, d.length.clamp(0, 3))] ?? (throw _Bad('"$d" is not a weekday (mon, tue, ...).'))];
      return AppAction(days.isEmpty ? 'Reminders off' : 'Reminders on ${days.map((d) => _days.keys.elementAt(d - 1)).join(', ')}', (s) => s.saveSettings(s.settings.copyWith(remindDays: days.toSet().toList()..sort())));
    case 'reminder_time':
      final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v);
      if (m == null) throw _Bad('time looks like 17:30.');
      final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
      if (h > 23 || mi > 59) throw _Bad('time looks like 17:30.');
      return AppAction('Reminder time ${m.group(1)!.padLeft(2, '0')}:${m.group(2)}', (s) => s.saveSettings(s.settings.copyWith(remindAt: h * 60 + mi)));
    case 'preview':
      final b = _onOff(v);
      return AppAction('Show what is sent before AI requests: ${b ? 'yes' : 'no'}', (s) => s.saveSettings(s.settings.copyWith(preview: b)));
    case 'auto_update':
      final b = _onOff(v);
      return AppAction('Check for app updates on start: ${b ? 'yes' : 'no'}', (s) => s.saveSettings(s.settings.copyWith(autoUpdate: b)));
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
    case 'hide_in_recents':
      final b = _onOff(v);
      return AppAction('Hide the app in recent apps: ${b ? 'yes' : 'no'}', (s) async {
        await s.saveSettings(s.settings.copyWith(hideRecents: b));
        s.applyPrefs();
      });
    case 'auto_icons':
      final b = _onOff(v);
      return AppAction('Check for icon packs on start: ${b ? 'yes' : 'no'}', (s) => s.saveSettings(s.settings.copyWith(autoPacks: b)));
    case 'ai' || 'ai_on' || 'auto' || 'ai_auto' || 'key' || 'api_key' || 'model' || 'server':
      throw _Bad('the AI cannot change its own setup. Do that in Settings → AI coach.');
  }
  if (st.aiOn && k.isEmpty) throw _Bad('say which setting.');
  throw _Bad('the app has no setting called "$k".');
}

AppAction _profile(String k, String a1, String a2, AppState s) {
  final p = s.profile;
  if (p == null) throw _Bad('finish the setup first.');
  switch (k) {
    case 'goal':
      final g = Goal.values.where((x) => x.name == a1).firstOrNull ?? (throw _Bad('goal is strength, size or both.'));
      return AppAction('Goal: ${goalLabel[g]}', (s) => s.saveProfile(s.profile!.copyWith(goal: g)));
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
    case 'go_easy':
      final j = Joint.values.where((x) => x.name.toLowerCase() == a2.toLowerCase()).firstOrNull ?? (throw _Bad('joint is ${Joint.values.map((j) => j.name).join(', ')}.'));
      final add = a1 == 'add' ? true : a1 == 'remove' ? false : throw _Bad('say add or remove.');
      return AppAction('${add ? 'Go easy on' : 'No longer going easy on'} ${jointLabel[j]!.toLowerCase()}', (s) {
        final h = {...s.profile!.avoid};
        add ? h.add(j) : h.remove(j);
        return s.saveProfile(s.profile!.copyWith(avoid: h));
      });
  }
  throw _Bad('the profile has no "$k" (goal, days, minutes, unit, split, equipment, go_easy).');
}

// ---------- undo ----------

/// The parts of the app the tools can change: settings, profile, plans, today, the rotation and
/// an open workout's exercise list. Saved before every AI batch so one tap puts it all back.
Future<Map<String, dynamic>> snapshot(Database db) async => {
      'kv': [for (final r in await db.query('kv')) if (_undoable(r['k'] as String)) r],
      'plan': await db.query('plan'),
      'open': await db.query('session', columns: ['id', 'day'], where: 'finished IS NULL'),
    };

bool _undoable(String k) => k == 'settings' || k == 'profile' || k == 'deload_until' || k == 'feeling' || k == 'custom_ex' || k == 'ex_prefs' || k == 'gyms' || k == 'gym_active' || k == 'taken' || k == 'override' || k == 'picked' || k.startsWith('last_day:');

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
  const AiChange(this.at, this.asked, this.did, this.before, {this.undone = false});

  Map<String, dynamic> toJson() => {'at': at.millisecondsSinceEpoch, 'asked': asked, 'did': did, 'before': before, 'undone': undone};
  factory AiChange.fromJson(Map<String, dynamic> j) => AiChange(DateTime.fromMillisecondsSinceEpoch(j['at'] as int), j['asked'] as String,
      [for (final d in j['did'] as List) d as String], j['before'] as Map<String, dynamic>,
      undone: (j['undone'] ?? false) as bool);
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
