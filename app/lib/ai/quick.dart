import '../domain/gym.dart';
import '../domain/plan.dart';
import '../domain/plan_maker.dart';
import '../domain/superset.dart';
import '../domain/units.dart';
import '../ui/app_state.dart';
import 'tools.dart';

/// Quick commands: everyday requests the app understands by itself, with no AI at all
/// ("set me up a chest and arms workout", "remind me Mon Wed Fri at 6 pm", "2 minutes rest",
/// "I only have 30 minutes", "the bench is taken"). Instant, works offline and with the AI off,
/// and gives the small on-phone model's weak spot (tool use) to plain rules.
/// Returns null when the message is not one of them; then the AI (if on) answers it.
ToolReply? quickCommand(String text, AppState s) {
  final t = ' ${text.toLowerCase().replaceAll(RegExp(r"[^a-z0-9:.' ]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  if (s.profile == null) return null;
  final acts = <AppAction>[];
  final say = <String>[];

  // ---- log a set by typing: "log 100x8", "185 x 5", "8 reps at 60 kg" ----
  final lg = RegExp(r'^\s*(?:log\s+|did\s+)?(\d+(?:\.\d+)?)\s*(kg|kilos?|lb|lbs|pounds?)?\s*(?:x|×|for)\s*(\d{1,3})\s*(?:reps?)?\s*$').firstMatch(t.trim()) ??
      RegExp(r'^\s*(?:log\s+|did\s+)?(\d{1,3})\s*reps?\s*(?:at|with|@)\s*(\d+(?:\.\d+)?)\s*(kg|kilos?|lb|lbs|pounds?)?\s*$').firstMatch(t.trim());
  if (lg != null && s.session != null) {
    final byReps = lg.pattern.toString().contains('reps?\\s*(?:at');
    final w = double.parse(byReps ? lg.group(2)! : lg.group(1)!);
    final ut = byReps ? lg.group(3) : lg.group(2);
    final r = int.parse(byReps ? lg.group(1)! : lg.group(3)!);
    final unit = (ut ?? '').startsWith('k') ? Unit.kg : (ut ?? '').isEmpty ? s.unit : Unit.lb;
    final day = s.session!.day;
    return ToolReply('', [
      AppAction('Log ${fmtNum(w)} ${unit.name} × $r', (s) async {
        final sets = await s.repo.setsFor(s.session!.id);
        final it = day.items.firstWhere((i) => sets.where((x) => x.exerciseId == i.exerciseId && x.counts).length < i.sets, orElse: () => day.items.last);
        await s.repo.logSet(s.session!.id, it.exerciseId, fromUnit(w, unit), r);
      }),
    ], const []);
  }

  // ---- deload, how I feel ----
  if (RegExp(r'\bdeload\b').hasMatch(t)) {
    final off = RegExp(r'\b(end|stop|no|off|cancel|finish)\b').hasMatch(t);
    acts.add(AppAction(off ? 'Deload week ended' : 'Deload this week', (s) => s.setDeload(!off)));
    say.add(off ? 'Back to normal training.' : 'Deload week: fewer sets at about 90%. Your progress stays where it is.');
  }
  final feel = RegExp(r"\b(?:i(?:'m| am)?|feel(?:ing)?)\b.*\b(rough|tired|exhausted|wrecked|sore|sick|bad|beat|great|amazing|strong|fresh|good|fine|ok)\b").firstMatch(t);
  if (feel != null && !RegExp(r'\b(hurts?|pain|injur)').hasMatch(t) && _areas(t).isEmpty) {
    final w = feel.group(1)!;
    final f = {'great', 'amazing', 'strong', 'fresh'}.contains(w) ? 3 : {'good', 'fine', 'ok'}.contains(w) ? 2 : 1;
    acts.add(AppAction('Today: feeling ${['rough', 'ok', 'great'][f - 1]}', (s) => s.setFeeling(f)));
    say.add(f == 1 ? 'Taking it a bit easier today: one set fewer and slightly lighter.' : f == 3 ? 'Good stuff. Normal targets, push the last sets.' : 'Normal targets today.');
  }

  // ---- which gym ----
  final at = RegExp(r"\b(?:i'm|i am|im|we're|at)\s+(?:at\s+|in\s+)?(?:the\s+)?([a-z0-9' ]{3,40}?)(?:\s+(?:today|now|this time|gym))*\s*$").firstMatch(t.trim());
  if (at != null && RegExp(r"\b(i'm|i am|im)\b").hasMatch(t)) {
    final want = at.group(1)!.trim();
    final g = s.gyms.where((g) => g.name.toLowerCase() == want || want.contains(g.name.toLowerCase()) || g.name.toLowerCase().contains(want)).firstOrNull;
    if (g != null) {
      acts.add(AppAction('At: ${g.name}', (s) => s.useGym(g.id)));
      say.add("Switched to ${g.name}. Plans and swaps use what's there.");
    } else {
      final tp = gymTemplates.where((x) => x.label.toLowerCase() == want || (x.id == 'planet_fitness' && RegExp(r'planet|\bpf\b').hasMatch(want)) || (x.id == 'hotel' && want.contains('hotel')) || (x.id == 'home_garage' && RegExp(r'home|garage').hasMatch(want))).firstOrNull;
      if (tp != null) {
        acts.add(AppAction('New gym: ${tp.label}, now the one you are at', (s) => s.saveGym(Gym.create(tp.label, {...tp.items}, maxDumbbellKg: tp.maxDumbbellKg), use: true)));
        say.add('Made a ${tp.label} gym with the usual equipment. Check it once in Settings → Your gyms and tick anything extra your club has.');
      }
    }
  }

  // ---- body weight ----
  final bw = RegExp(r'\b(?:i weigh|i weighed|weighed in at|weigh in|weighed|my weight is|body ?weight(?: is)?)\s+(\d{2,3}(?:\.\d)?)\s*(kg|kilos?|lb|lbs|pounds?)?\b').firstMatch(t);
  if (bw != null) {
    final n = double.parse(bw.group(1)!);
    final unit = (bw.group(2) ?? '').startsWith('k') ? Unit.kg : (bw.group(2) ?? '').isEmpty ? s.unit : Unit.lb;
    final kg = fromUnit(n, unit);
    acts.add(AppAction('Weigh-in: ${fmtWeight(kg, s.unit)} ${unitLabel(s.unit)}', (s) => s.repo.logBody(kg)));
    say.add('Saved your weigh-in (Progress → Body weight).');
  }

  // ---- reminders ----
  if (t.contains('remind')) {
    if (RegExp(r'\b(stop|no|off|cancel|turn off)\b').hasMatch(t)) {
      acts.add(AppAction('Reminders off', (s) => s.saveSettings(s.settings.copyWith(remindDays: const []))));
      say.add('Reminders are off.');
    } else {
      final days = _weekdays(t);
      final at = _time(t);
      if (days.isEmpty && at == null) return null;
      if (days.isNotEmpty) {
        final d = days.toList()..sort();
        acts.add(AppAction('Reminders on ${d.map((x) => _dayName[x - 1]).join(', ')}', (s) => s.saveSettings(s.settings.copyWith(remindDays: d))));
      }
      if (at != null) {
        acts.add(AppAction('Reminder time ${_hm(at)}', (s) => s.saveSettings(s.settings.copyWith(remindAt: at))));
      }
      say.add('Reminders set.');
    }
  }

  // ---- rest ----
  final rest = RegExp(r'\b(\d+(?:\.\d+)?)\s*(m|min|mins|minute|minutes|s|sec|secs|second|seconds)\b(?:\s+\w+){0,2}\s+rest\b|\brest\b(?:\s+\w+){0,3}?\s+(\d+(?:\.\d+)?)\s*(m|min|mins|minute|minutes|s|sec|secs|second|seconds)\b').firstMatch(t);
  if (rest != null) {
    final n = double.parse(rest.group(1) ?? rest.group(3)!);
    final unit = rest.group(2) ?? rest.group(4)!;
    final sec = (unit.startsWith('m') ? n * 60 : n).round();
    if (sec >= 30 && sec <= 600) {
      acts.add(AppAction('Rest between sets: ${sec}s', (s) => s.saveSettings(s.settings.copyWith(rest: sec, restOff: false))));
      say.add('Rest is now ${sec >= 60 && sec % 60 == 0 ? '${sec ~/ 60} min' : '$sec s'} between sets.');
    }
  } else if (RegExp(r'\bsmart rest\b').hasMatch(t)) {
    final on = !RegExp(r'\b(off|no|stop|disable)\b').hasMatch(t);
    acts.add(AppAction('Smart rest ${on ? 'on' : 'off'}', (s) => s.saveSettings(s.settings.copyWith(smartRest: on, planRest: true))));
    say.add('Smart rest is ${on ? 'on' : 'off'}.');
  }

  // ---- units, sounds ----
  final wantsKg = RegExp(r'\b(use|switch to|change to|in|set)\s+(kg|kilos?|kilograms?)\b').hasMatch(t);
  final wantsLb = RegExp(r'\b(use|switch to|change to|in|set)\s+(lb|lbs|pounds?)\b').hasMatch(t);
  if (wantsKg != wantsLb && !t.contains(' rest ')) {
    final u = wantsKg ? Unit.kg : Unit.lb;
    acts.add(AppAction('Weights in ${u.name}', (s) => s.saveProfile(s.profile!.copyWith(unit: u))));
    say.add('Weights are in ${u.name} now.');
  }
  final snd = RegExp(r'\b(sounds?|noises?)\b.*\b(off|mute|simple|cute|on)\b|\b(mute|turn off)\b.*\bsounds?\b').firstMatch(t);
  if (snd != null) {
    final m = t.contains('simple') ? 'simple' : (t.contains('cute') || (snd.group(2) == 'on')) ? 'cute' : 'off';
    acts.add(AppAction('Sounds: $m', (s) => s.saveSettings(s.settings.copyWith(sound: m))));
    say.add('Sounds: $m.');
  }

  // ---- today's workout ----
  final areas = _areas(t);
  final minutes = RegExp(r'\b(\d{2,3})\s*(?:min|mins|minutes)\b').firstMatch(t);
  final mins = minutes == null ? null : int.parse(minutes.group(1)!).clamp(15, 180);
  final wantsWorkout = RegExp(r'\b(workout|day|session|routine|set me up|set up|give me|make me|build|train|hit|do)\b').hasMatch(t);
  if (areas.isNotEmpty && wantsWorkout && s.plan != null) {
    if (s.session != null) return ToolReply('A workout is already going. Finish it (or throw it away) first, then ask again.', const [], const []);
    final name = _title(areas);
    final d = makeDayFor(areas, s.profile!, s.lib, minutes: mins, name: name);
    if (d.items.isEmpty) return ToolReply("Your gym's equipment has nothing for $name. Add equipment in your setup.", const [], const []);
    final style = RegExp(r'\bdrop ?sets?\b').hasMatch(t)
        ? 'drop'
        : RegExp(r'\b(amrap|as many (reps )?as possible)\b').hasMatch(t)
            ? 'amrap'
            : RegExp(r'\b(to failure|failure sets?)\b').hasMatch(t)
                ? 'failure'
                : RegExp(r'\brest ?pause\b').hasMatch(t)
                    ? 'restpause'
                    : '';
    // the big first lift stays normal; the rest get the style asked for
    var styled = style.isEmpty ? d : d.copyWith(items: [for (var i = 0; i < d.items.length; i++) i == 0 && d.items.length > 1 ? d.items[i] : d.items[i].copyWith(style: style)]);
    if (RegExp(r'\b(super ?sets?|circuit)\b').hasMatch(t)) styled = styled.copyWith(items: autoSupersets(styled.items, s.lib));
    acts.add(AppAction('Today: ${d.name} (${d.items.length} exercises${style.isEmpty ? '' : ', last set ${lastSetStyles[style]!.toLowerCase()}'})', (s) => s.setToday(styled)));
    say.add('$name is set for today: ${d.items.map((i) => s.lib.byId(i.exerciseId)?.name ?? i.exerciseId).join(', ')}.');
    if (style.isNotEmpty) say.add('The last set of each exercise after the first is a ${lastSetStyles[style]!.toLowerCase()}; the workout screen walks you through it.');
    if (RegExp(r'\b(super ?sets?|circuit)\b').hasMatch(t)) say.add('Accessories are paired into supersets: one set of each, then rest.');
  } else if (mins != null && rest == null && RegExp(r'\b(only|just|short|quick|have|got)\b').hasMatch(t) && s.today != null) {
    final cap = capFor(mins);
    final d = s.today!;
    if (d.items.length > cap) {
      final nd = d.copyWith(items: d.items.take(cap).toList());
      acts.add(AppAction('Today: ${d.name} trimmed to $cap exercises for $mins minutes', (s) => s.setToday(nd)));
      say.add('Trimmed today to the first $cap exercises so it fits $mins minutes.');
    } else {
      say.add('Today already fits $mins minutes (${d.items.length} exercises).');
    }
  }

  // ---- supersets for today's workout ----
  if (areas.isEmpty && RegExp(r'\b(super ?sets?|pair (them|exercises))\b').hasMatch(t) && s.today != null && !t.contains('->')) {
    final off = RegExp(r'\b(no|remove|without|stop|off)\b').hasMatch(t);
    final d = s.today!;
    final nd = d.copyWith(items: off ? [for (final x in d.items) x.copyWith(clearGroup: true)] : autoSupersets(d.items, s.lib));
    acts.add(AppAction(off ? 'No supersets today' : 'Supersets today (opposite muscles paired)', (s) => s.setToday(nd)));
    say.add(off ? 'Supersets removed for today.' : 'Paired the accessories into supersets: one set of each, then rest.');
  }

  // ---- taken / broken / swap ----
  final taken = RegExp(r'\b(?:the )?([a-z ]{3,40}?)\s+(?:is|are)\s+(?:taken|busy|broken|in use|occupied|out of order)\b').firstMatch(t);
  final swapReq = RegExp(r'\b(?:swap|replace|switch)\s+(?:out\s+)?(?:the\s+)?([a-z ]{3,40}?)(?:\s+for\s+something.*|\s+today.*|\s*$)').firstMatch(t.trim());
  final what = taken?.group(1) ?? (t.contains('->') ? null : swapReq?.group(1));
  if (what != null && s.today != null && areas.isEmpty) {
    final d = s.today!;
    final words = what.trim().split(' ').where((w) => w.length > 2 && w != 'the').toList();
    final i = d.items.indexWhere((it) {
      final n = (s.lib.byId(it.exerciseId)?.name ?? it.exerciseId).toLowerCase();
      return words.isNotEmpty && words.every((w) => n.contains(w.replaceFirst(RegExp(r'es$|s$'), '')));
    });
    if (i >= 0) {
      final from = s.lib.byId(d.items[i].exerciseId)!;
      final busy = RegExp(r'\b(barbell|bench|rack|machine|cable|smith)\b').firstMatch(what)?.group(1);
      final alts = [
        for (final e in s.lib.swapsFor(from, s.profile!.have, s.profile!.avoid, items: s.profile!.items))
          if (!d.items.any((x) => x.exerciseId == e.id) && (busy == null || !e.name.toLowerCase().contains(busy))) e
      ];
      if (alts.isNotEmpty) {
        final to = alts.first;
        acts.add(AppAction('Swap ${from.name} → ${to.name} (today)', (s) async {
          final j = s.today!.items.indexWhere((x) => x.exerciseId == from.id);
          if (j >= 0) await s.swap(j, to, forever: false);
        }));
        say.add('Swapped ${from.name} for ${to.name} today.');
      } else {
        say.add('Nothing in your gym works the same muscles instead of ${from.name}.');
      }
    }
  }

  // ---- skip / start ----
  if (RegExp(r'\bskip (today|this day|the day|it)\b').hasMatch(t) && s.plan != null && s.session == null) {
    acts.add(AppAction('Skip ${s.today?.name ?? 'today'} and move on', (s) => s.skipToday()));
    say.add('Skipped. The next day in your rotation is up.');
  } else if (RegExp(r'\b(start|begin) (the |my )?(workout|session|training)\b').hasMatch(t) && s.today != null && s.session == null) {
    acts.add(AppAction('Start the workout', (s) async {
      await s.startWorkout();
    }));
    say.add('Workout started.');
  }

  if (acts.isEmpty && say.isEmpty) return null;
  return ToolReply(say.join(' '), acts, const []);
}

const _dayName = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

Set<int> _weekdays(String t) {
  final out = <int>{};
  if (RegExp(r'\b(every ?day|daily)\b').hasMatch(t)) return {1, 2, 3, 4, 5, 6, 7};
  if (RegExp(r'\bweekdays\b').hasMatch(t)) out.addAll([1, 2, 3, 4, 5]);
  if (RegExp(r'\bweekends?\b').hasMatch(t)) out.addAll([6, 7]);
  const full = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  for (var i = 0; i < 7; i++) {
    if (RegExp('\\b(${full[i]}s?|${_dayName[i]}|${full[i].substring(0, 3)}s)\\b').hasMatch(t) || (i == 1 && RegExp(r'\btues\b').hasMatch(t)) || (i == 3 && RegExp(r'\bthurs?\b').hasMatch(t))) {
      out.add(i + 1);
    }
  }
  return out;
}

/// Minutes after midnight from "6 pm", "6:30pm", "18:00", "at 7".
int? _time(String t) {
  final m = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a m|p m)\b').firstMatch(t) ?? RegExp(r'\b(\d{1,2}):(\d{2})\b()').firstMatch(t) ?? RegExp(r'\bat (\d{1,2})\b()()').firstMatch(t);
  if (m == null) return null;
  var h = int.parse(m.group(1)!);
  final mi = int.tryParse(m.group(2) ?? '') ?? 0;
  final ap = (m.group(3) ?? '').replaceAll(' ', '');
  if (ap == 'pm' && h < 12) h += 12;
  if (ap == 'am' && h == 12) h = 0;
  if (ap.isEmpty && m.group(2) == null && h >= 1 && h <= 9) h += 12; // "at 6" means evening at a gym
  if (h > 23 || mi > 59) return null;
  return h * 60 + mi;
}

String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

const _areaWords = <String, String>{
  'chest': 'chest', 'pecs': 'chest', 'pec': 'chest',
  'back': 'back', 'lats': 'back',
  'shoulders': 'shoulders', 'shoulder': 'shoulders', 'delts': 'shoulders',
  'arms': 'arms', 'arm': 'arms',
  'biceps': 'biceps', 'bicep': 'biceps', 'bis': 'biceps',
  'triceps': 'triceps', 'tricep': 'triceps', 'tris': 'triceps',
  'legs': 'legs', 'leg': 'legs',
  'quads': 'quads', 'quad': 'quads',
  'hamstrings': 'hamstrings', 'hamstring': 'hamstrings', 'hams': 'hamstrings',
  'glutes': 'glutes', 'glute': 'glutes', 'butt': 'glutes',
  'calves': 'calves', 'calf': 'calves',
  'core': 'core', 'abs': 'core',
  'upper body': 'upper', 'upper': 'upper',
  'lower body': 'lower', 'lower': 'lower',
  'push': 'push', 'pull': 'pull',
  'full body': 'full', 'whole body': 'full',
};

List<String> _areas(String t) {
  final hits = <int, String>{};
  for (final e in _areaWords.entries) {
    final m = RegExp('\\b${e.key}\\b').firstMatch(t);
    if (m != null && !hits.containsValue(e.value)) hits[m.start] = e.value;
  }
  final keys = hits.keys.toList()..sort();
  final l = [for (final k in keys) hits[k]!];
  // "arms" already covers biceps and triceps
  if (l.contains('arms')) l.removeWhere((x) => x == 'biceps' || x == 'triceps');
  if (l.contains('legs')) l.removeWhere((x) => {'quads', 'hamstrings', 'glutes', 'calves'}.contains(x));
  // a back that is sore is not a request for a back workout
  if (RegExp(r'\b(sore|hurts?|pain|injured|tweaked)\b').hasMatch(t)) return const [];
  return l;
}

String _title(List<String> a) {
  String c(String x) => switch (x) { 'full' => 'Full body', 'upper' => 'Upper body', 'lower' => 'Lower body', _ => x[0].toUpperCase() + x.substring(1) };
  final n = a.map(c).toList();
  if (n.length == 1) return n.first;
  return '${n.sublist(0, n.length - 1).join(', ')} & ${n.last}';
}

/// The small on-phone model repeats itself: keep one action per thing changed (the last), and
/// no "start workout" unless the person asked for it.
List<AppAction> tidyActions(List<AppAction> acts, String asked) {
  final startAsked = RegExp(r'\b(start|begin)\b', caseSensitive: false).hasMatch(asked);
  final out = <String, AppAction>{};
  for (final a in acts) {
    if (a.says == 'Start the workout' && !startAsked) continue;
    final key = a.says.contains(':') ? a.says.substring(0, a.says.indexOf(':')) : a.says;
    out.remove(key);
    out[key] = a;
  }
  return out.values.toList();
}
