import 'coach.dart';
import 'exercise.dart';
import 'library.dart';
import 'plan.dart';
import 'program.dart';
import 'progression.dart';
import 'programs.dart';
import 'units.dart';
import 'volume.dart';

/// Plain-words explanations (batch 16, F238-F251): why this exercise, why this rest, the rules,
/// tips, ranked swaps, stalls, and reading a plan from text. No AI needed for any of it.

// ---------- why this exercise (F239) ----------

String exerciseWhy(Exercise e, int index, Profile? p, {Set<Joint> sore = const {}}) {
  // "main lift" only for a big lift; a curl that happens to be first is just first up (review 2, P2-4)
  final role = index == 0 ? (e.compound ? 'The main lift of the day' : 'First up') : (e.compound ? 'A second big lift' : 'An extra for one muscle');
  final share = setShare(e);
  final main = [for (final m in share.entries) if (m.value == 1) muscleName(m.key).toLowerCase()];
  final help = [for (final m in share.entries) if (m.value < 1) muscleName(m.key).toLowerCase()];
  final b = StringBuffer('$role: works ${main.join(' and ')}${help.isEmpty ? '' : ', with help from ${help.join(', ')}'}.');
  if (e.equipment == Equipment.bodyweight || e.equipment == Equipment.band) {
    b.write(' Needs no machine.');
  } else {
    b.write(' Uses ${equipmentLabel[e.equipment]!.toLowerCase()}${p == null || p.have.contains(e.equipment) ? ', which your gym has' : ''}.');
  }
  final avoid = {...?p?.avoid, ...sore};
  if (avoid.isNotEmpty) {
    final ok = avoid.where((j) => !e.joints.contains(j)).map((j) => jointLabel[j]!.toLowerCase()).toList();
    if (ok.isNotEmpty) b.write(' Easy on your ${ok.join(' and ')}.');
  }
  if (e.compound && index == 0) b.write(' Big lifts go first, while you are fresh.');
  return b.toString();
}

// ---------- why this rest (F240) ----------

/// [setReps]: the reps of the set coming up (a program's own), when known.
String restWhy(Exercise e, PlanItem it, {required bool smart, required int planRest, int? setReps}) {
  String t(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  if (!smart) return 'Rest ${t(planRest)}: the time set in your plan (Settings → Rest).';
  if (e.timed) return 'Rest ${t(60)}: holds and carries rest a minute.';
  final base = smartRest(e, it, it.repLow, lastSet: false);
  final r = setReps ?? it.repLow;
  final range = setReps != null || it.repLow == it.repHigh ? repsWord(r) : '${it.repLow}-${it.repHigh} reps';
  final heavy = r <= 5 ? 'Heavy ($range)' : (r <= 8 ? 'Medium ($range)' : 'Light ($range)');
  return 'Rest ${t(base)}: $heavy${e.compound ? ' and a big lift' : ', one muscle'}. A set short of the range adds 0:45, beating the top by 2 takes 0:15 off, and an effort tap moves it. After the last set: 1:30 to set up the next exercise.';
}

// ---------- the rules, in plain words (F241) ----------

List<(String, String)> rulesText(ProgressRules r, {required int deloadEvery, required bool climb, required Unit u}) => [
      (
        'When the weight goes up',
        'When every set reaches the top of the rep range (say 12 of 8-12), next time adds one weight step${r.speed == 'fast' ? ' (two on the fast setting)' : ''}${r.speed == 'slow' ? ', after doing it in two workouts in a row (the slow setting)' : ''}. '
            '${r.effort ? 'If you tapped Easy on every set, it adds one more step; an all-out set means one step only. ' : ''}A + set that beats the top by 3 or more adds a step too.'
      ),
      ('Reps first', 'Until then the weight stays and you add reps. Lifts set to "add weight every session" (linear) go up whenever every set reaches the bottom of the range.'),
      (
        'When you miss',
        'A set below the bottom of the range is a miss. After ${r.missesToDrop} workout${r.missesToDrop == 1 ? '' : 's'} in a row with a miss, the weight drops ${(r.dropPct * 100).round()}%. "Bad day" on the Finish screen keeps the weights where they were.'
      ),
      ('Bodyweight lifts', 'Pull-ups, dips and push-ups add a rep at a time. At the top of the range they add a little weight and go back to the bottom.'),
      ('Time away', 'Back after 2 weeks: 10% lighter to start. After 4 weeks: 20% lighter.'),
      ('Deloads', deloadEvery == 0 ? 'A lighter week only when you ask or the app suggests one (3 or more lifts stuck). Fewer sets at about 90%; nothing moves during it.' : 'Every $deloadEvery weeks a lighter week: fewer sets at about 90%. Nothing moves during it.'),
      if (climb) ('Volume climb', 'The extra exercises start each block one set lighter and gain a set a week until the deload.'),
      ('Programs', 'Programs from the library follow their own rules: % of a training max, stages when a lift stalls, ladders to harder exercises. Plan → Lift rules shows each one.'),
      ('Lighter on purpose', 'After "That hurt" a lift starts 20% and then 10% lighter. A rough-day check-in takes a bit off, and a sport day takes a leg set off.'),
      ('Weight steps', 'One step is ${fmtWeight(stepKg(StepKind.barbell, u), u)} ${unitLabel(u)} on a barbell and the smallest change the equipment allows elsewhere; set your own under Settings → Weight steps.'),
    ];

// ---------- tips (F246) ----------

const tips = [
  'Sleep is when muscle is built: 7 to 9 hours makes more difference than any supplement.',
  'Protein: about 1.6 g per kg of body weight a day (0.7 g per lb) covers almost everyone.',
  'Leave one or two reps in the tank on most sets. Going all-out every set mostly adds tiredness.',
  'Rest long enough on big lifts: 2-3 minutes lets you lift more next set, which is what grows muscle.',
  'Control the way down. Lowering in about 2 seconds keeps tension where you want it.',
  'Log every set, even the bad ones. The app moves your weights from what you really did.',
  'A missed workout is not lost progress. Pick up where you left off.',
  'Warm up with lighter sets of your first lift: they prepare the exact movement better than cardio.',
  'Same exercise, same setup: note seat heights and grips (tap the pin in a workout).',
  'Progress is not a straight line. A flat week is normal; a flat month is worth a change.',
  'Full range is the safe default for growing muscle.',
  'Drink water during the workout: even a little dehydration costs strength.',
  'Creatine (3-5 g a day) is the one supplement with strong evidence for strength. Check with your doctor if unsure.',
  'Stuck on a lift? A variation for a few weeks (pause, close-grip, incline) often gets it moving again.',
  'Your back and legs can take more weight than your arms: progress shows up there first.',
  'Breathe in and brace before a heavy rep, then breathe out at the top.',
  'If a lift hurts (not just burns), stop. Tap the set and "That hurt" to swap it or go lighter.',
  'Walking on rest days helps recovery and costs nothing.',
  'Twice a week makes it easier to fit enough sets in; with the same sets, once or twice a week grows about the same.',
  'Four steady months beat one perfect week. Pick a plan you can keep.',
  'A deload week now and then lets tired joints catch up. Nothing is lost.',
  'Eating a bit more than you burn makes growing muscle much easier; eating less makes keeping it the goal.',
  'Slow progress at the start of a session? A third warm-up set can help on heavy days.',
  'Unilateral work (one arm, one leg) evens out a weaker side.',
  'Rate your sets now and then: Easy and Hard taps tune how fast the weights move.',
  'Big muscles take about 3 days to recover from a hard session, small ones about 2.',
  'If you have only 20 minutes, do the main lift and one extra. That still counts.',
  'Stretch after training, not before heavy sets: long holds right before can sap strength.',
  'Chalk or a firm grip on the bar makes everything feel lighter.',
  'Cardio and lifting mix fine. Keep hard runs away from leg day when you can.',
];

String tipOfDay(DateTime d) => tips[DateTime(d.year, d.month, d.day).difference(DateTime(2026)).inDays.abs() % tips.length];

// ---------- ranked swaps with a reason (F245) ----------

/// Swaps closest first, each with a short reason ("same movement · easier on knees").
List<(Exercise, String)> rankSwaps(Exercise from, Iterable<Exercise> cands, {Set<Joint> avoid = const {}, Set<String> favs = const {}}) {
  final out = <(Exercise, String, int)>[];
  for (final e in cands) {
    var score = 0;
    final why = <String>[];
    if (e.pattern == from.pattern) {
      score += 3;
      why.add('same movement');
    }
    if (e.equipment == from.equipment) {
      score += 2;
      why.add('same equipment');
    } else {
      why.add(equipmentLabel[e.equipment]!.toLowerCase());
    }
    if (e.compound == from.compound) score += 2;
    final helpers = e.secondary.toSet().intersection(from.secondary.toSet()).length;
    score += helpers;
    final spared = from.joints.difference(e.joints);
    if (spared.isNotEmpty) {
      final hurts = spared.intersection(avoid);
      score += hurts.isEmpty ? 1 : 4;
      why.add('easier on ${(hurts.isEmpty ? spared : hurts).map((j) => jointLabel[j]!.toLowerCase()).join(' and ')}');
    }
    if (e.joints.intersection(avoid).isNotEmpty) score -= 5;
    if (favs.contains(e.id)) {
      score += 2;
      why.add('a favourite');
    }
    out.add((e, why.take(3).join(' · '), score));
  }
  out.sort((a, b) => b.$3.compareTo(a.$3));
  return [for (final x in out) (x.$1, x.$2)];
}

// ---------- stalls (F243) ----------

class Stall {
  final int weeks; // since the last new best
  final int sessions; // workouts of it since then
  const Stall(this.weeks, this.sessions);
}

/// No new best (estimated 1-rep max, or reps for bodyweight) in [minWeeks] weeks with at least
/// three workouts of it since: a stall. Null when it is moving or too new to tell.
Stall? stallOf(List<SetLog> sets, bool bodyweight, DateTime now, {int minWeeks = 4}) {
  final per = <String, (DateTime, double)>{};
  for (final x in sets) {
    if (!x.counts || x.at == null) continue;
    final v = bodyweight ? x.reps.toDouble() + x.kg / 10 : e1rm(x.kg, x.reps);
    final c = per[x.sessionId];
    if (c == null || v > c.$2) per[x.sessionId] = (x.at!, v);
  }
  final pts = per.values.toList()..sort((a, b) => a.$1.compareTo(b.$1));
  if (pts.length < 4) return null;
  var best = pts.first.$2;
  var at = pts.first.$1;
  for (final p in pts.skip(1)) {
    if (p.$2 > best + 0.05) {
      best = p.$2;
      at = p.$1;
    }
  }
  final weeks = now.difference(at).inDays ~/ 7;
  final since = pts.where((p) => p.$1.isAfter(at)).length;
  if (weeks < minWeeks || since < 3) return null;
  if (now.difference(pts.last.$1).inDays > 28) return null; // not trained lately: not a stall
  return Stall(weeks, since);
}

String stallAdvice(Exercise e, Stall st) =>
    'No new best on ${e.name} in ${st.weeks} weeks (${st.sessions} workouts). Try a variation for 4 weeks, a deload week, or more sleep and food. Rest a little longer between sets too.';

// ---------- a program from a description (F250) ----------

/// "531 bbb 4 days", "stronglifts", "nsuns 5 day": the closest program in the library, or null.
ProgramTemplate? matchProgram(String text) {
  String norm(String x) => x.toLowerCase().replaceAll('5/3/1', '531').replaceAll('5x5', '5x5').replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  final t = norm(text);
  if (t.isEmpty) return null;
  final words = t.split(' ').where((w) => w.length > 1 && !const {'days', 'day', 'a', 'the', 'program', 'start', 'run', 'me', 'my', 'do', 'want', 'set', 'up', 'for', 'week', 'per', 'give', 'please', 'i', 'to', 'like'}.contains(w)).toSet();
  final days = int.tryParse(RegExp(r'\b([1-7])\s*days?\b').firstMatch(t)?.group(1) ?? '');
  ProgramTemplate? best;
  var bestScore = 0.0;
  for (final p in programTemplates) {
    final name = norm('${p.name} ${p.id.replaceAll('_', ' ')}').split(' ').toSet();
    final hit = words.where((w) => name.contains(w) || name.any((n) => n.length > 3 && (n.startsWith(w) || w.startsWith(n)))).length;
    if (hit == 0) continue;
    var score = hit / words.length + hit * 0.1;
    if (days != null && p.days == days) score += 0.3;
    if (words.length == 1 && words.first == '531' && p.id == '531_base') score += 0.2;
    if (score > bestScore) {
      bestScore = score;
      best = p;
    }
  }
  return bestScore >= 0.5 ? best : null;
}

// ---------- a plan from text (F251) ----------

class TextPlan {
  final Plan? plan;
  final List<String> unknown; // lines the app could not read (listed, never quietly dropped)
  final int matched;
  final int days; // days found; the plan keeps at most 14 ("N days kept of M")
  const TextPlan(this.plan, this.unknown, this.matched, {this.days = 0});
}

const _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
final _noteWords = RegExp(r'^(notes?|rest|warm|cool|tips?|comments?|optional|superset|then)\b', caseSensitive: false);
final _setRx = RegExp(r'(\d{1,2})\s*(?:x|×|\*|sets? of|sets? x)\s*(\d{1,3}|amrap|max)\s*(?:(?:-|–|to)\s*(\d{1,3}))?\s*(\+)?\s*(s(?:ec(?:onds?)?)?\b)?', caseSensitive: false);

/// One exercise line read: what, sets, reps (or seconds), rest, and an as-many-as-possible last set.
class _Line {
  final Exercise e;
  final int sets, lo, hi, rest;
  final bool amrap;
  const _Line(this.e, this.sets, this.lo, this.hi, this.rest, this.amrap);
}

/// Reads a plan written as text (review 2, P2-3). Headings are only lines that look like one
/// ("Day 12", "Monday", "Push:", or a short line right before an exercise); exercise lines can be
/// "Bench press 3x8-10", "5x5 Squat", "Pull-ups 3xAMRAP", "Plank 3x60s", "Bench press,3,8,90" or
/// "Squat - 5 sets of 5, 2 min rest". Anything else is listed as not understood.
TextPlan parseTextPlan(String text, Library lib, {String name = 'Imported plan', Profile? profile}) {
  final lines = [
    for (final raw in text.split(RegExp(r'\r?\n')))
      if (raw.trim().isNotEmpty) raw.replaceAll(RegExp(r'^[\s\-*•]*(\d{1,2}[.)]\s+)?'), '').trim()
  ];
  final read = [for (final l in lines) _readLine(l, lib, profile)];
  bool isHeading(int i) {
    final l = lines[i];
    if (read[i] != null || l.length > 40 || _noteWords.hasMatch(l)) return false;
    if (RegExp(r'^(day|week|workout|session)\s*[a-z0-9]{1,3}\b', caseSensitive: false).hasMatch(l)) return true;
    final first = l.toLowerCase().split(RegExp(r'[\s:,-]+')).first;
    if (_weekdays.contains(first)) return true;
    if (l.contains(':') && !l.trimRight().endsWith(':')) return false; // "Notes: go heavy"
    if (l.trimRight().endsWith(':')) return true;
    // a short word line right before an exercise line ("Push", "Upper A", "Core")
    return l.length <= 30 && !RegExp(r'\d{2,}').hasMatch(l) && i + 1 < lines.length && read[i + 1] != null;
  }

  final days = <PlanDay>[];
  var cur = <PlanItem>[];
  String? dayName;
  final unknown = <String>[];
  var matched = 0;
  void close() {
    if (cur.isNotEmpty) days.add(PlanDay(name: dayName ?? 'Day ${days.length + 1}', items: cur));
    cur = [];
  }

  for (var i = 0; i < lines.length; i++) {
    final r = read[i];
    if (r != null) {
      matched++;
      cur.add(PlanItem(exerciseId: r.e.id, sets: r.sets, repLow: r.lo, repHigh: r.hi, restSec: r.rest, style: r.amrap ? 'amrap' : ''));
    } else if (isHeading(i)) {
      close();
      dayName = lines[i].replaceAll(RegExp(r'[:#=*_]+'), '').trim();
    } else {
      unknown.add(lines[i]);
    }
  }
  close();
  if (days.isEmpty) return TextPlan(null, unknown, matched);
  return TextPlan(Plan(name: name, source: 'mine', days: days.take(14).toList(), userEdited: true), unknown, matched, days: days.length);
}

_Line? _readLine(String line, Library lib, Profile? p) {
  String exName;
  int sets, lo, hi;
  var amrap = false;
  String after;
  // comma-separated: name, sets, reps[, rest]
  final csv = line.split(',').map((x) => x.trim()).toList();
  if (csv.length >= 3 && int.tryParse(csv[1]) != null && RegExp(r'^\d{1,3}(\s*-\s*\d{1,3})?$').hasMatch(csv[2])) {
    exName = csv[0];
    sets = int.parse(csv[1]);
    final rr = csv[2].split('-');
    lo = int.parse(rr.first.trim());
    hi = rr.length > 1 ? int.parse(rr.last.trim()) : lo;
    after = csv.length > 3 ? '${csv[3]}s' : '';
  } else {
    final m = _setRx.firstMatch(line);
    if (m == null) return null;
    final atStart = line.substring(0, m.start).trim().isEmpty;
    exName = atStart ? line.substring(m.end) : line.substring(0, m.start);
    exName = exName.replaceAll(RegExp(r'[\-:–,]+\s*$|^\s*[\-:–,]+'), '').replaceAll(RegExp(r'[@(].*$'), '').trim();
    sets = int.parse(m.group(1)!);
    final rep = m.group(2)!.toLowerCase();
    amrap = rep == 'amrap' || rep == 'max' || m.group(4) != null;
    final e0 = _findLoose(exName, lib, p);
    lo = int.tryParse(rep) ?? (e0?.repLow ?? 8);
    hi = (int.tryParse(m.group(3) ?? '') ?? (amrap && int.tryParse(rep) == null ? (e0?.repHigh ?? lo) : lo));
    after = atStart ? '' : line.substring(m.end);
  }
  final e = _findLoose(exName, lib, p);
  if (e == null || sets < 1) return null;
  final rest = int.tryParse(RegExp(r'(\d{2,3})\s*s(?:ec(?:onds?)?)?\b').firstMatch(after)?.group(1) ?? '') ?? ((int.tryParse(RegExp(r'(\d)\s*min').firstMatch(after)?.group(1) ?? '') ?? 0) * 60);
  return _Line(e, sets.clamp(1, 10), lo.clamp(1, 300), hi.clamp(lo.clamp(1, 300), 300), rest > 0 ? rest.clamp(15, 600) : (e.compound ? 150 : 75), amrap);
}

/// The muscle a word usually means, to break ties ("curl" is a biceps curl unless it says leg).
String? _hint(List<String> w) {
  if (w.contains('curl') && !w.any((x) => const {'leg', 'hamstring', 'nordic', 'ham', 'wrist'}.contains(x))) return 'biceps';
  if (w.length == 1 && w.single == 'press') return 'shoulders'; // a lone "press" is the overhead press
  return null;
}

/// What lifters usually mean by the short names (review 2, P2-3): "squat" is a back squat, a lone
/// "press" the overhead press, "curl" a barbell curl.
const _usual = {
  'squat': 'back_squat', 'bench': 'bench_press', 'bench press': 'bench_press', 'deadlift': 'deadlift', 'dl': 'deadlift',
  'press': 'overhead_press', 'ohp': 'overhead_press', 'overhead press': 'overhead_press', 'military press': 'overhead_press',
  'row': 'barbell_row', 'barbell row': 'barbell_row', 'curl': 'barbell_curl', 'bicep curl': 'barbell_curl', 'biceps curl': 'barbell_curl',
  'leg curl': 'lying_leg_curl', 'pull up': 'pull_up', 'pullup': 'pull_up', 'chin up': 'chin_up', 'chinup': 'chin_up', 'dip': 'dips',
  'push up': 'push_up', 'pushup': 'push_up', 'lat pulldown': 'lat_pulldown', 'pulldown': 'lat_pulldown', 'rdl': 'romanian_deadlift',
  'lunge': 'walking_lunge', 'leg press': 'leg_press', 'calf raise': 'standing_calf_raise', 'plank': 'plank', 'side plank': 'side_plank',
};

Exercise? _findLoose(String n, Library lib, Profile? p) {
  final exact = lib.find(n);
  if (exact != null) return exact;
  final key = n.toLowerCase().replaceAll(RegExp(r'[^a-z ]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final id = _usual[key] ?? _usual[key.replaceFirst(RegExp(r's$'), '')]; // "press" as it is, "rows" -> "row"
  final usual = id == null ? null : lib.byId(id);
  if (usual != null) return usual;
  String norm(String x) => x.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ').replaceAll(RegExp(r'\b(db|dumbell)\b'), 'dumbbell').replaceAll(RegExp(r'\bbb\b'), 'barbell').replaceAll(RegExp(r'\s+'), ' ').trim();
  final w = norm(n).split(' ').where((x) => x.length > 1).map((x) => x.replaceFirst(RegExp(r's$'), '')).toList();
  if (w.isEmpty) return null;
  final hint = _hint(w);
  Exercise? best;
  (double, int, int, int, int)? bestKey;
  for (final e in lib.all) {
    final en = norm(e.name).split(' ').map((x) => x.replaceFirst(RegExp(r's$'), '')).toSet();
    final hit = w.where(en.contains).length;
    final score = hit / w.length - (en.length - hit) * 0.05;
    if (hit == 0 || score < 0.6) continue;
    // ties: the muscle the words mean, the gym has it, a favourite, free weights, then the short name
    final key = (
      double.parse(score.toStringAsFixed(3)),
      hint != null && e.primary.first == hint ? 1 : 0,
      p == null || p.have.contains(e.equipment) || e.bodyweight ? 1 : 0,
      lib.favs.contains(e.id) ? 1 : 0,
      e.equipment == Equipment.barbell || e.equipment == Equipment.dumbbell ? 1 : 0,
    );
    bool better((double, int, int, int, int) a, (double, int, int, int, int) b) {
      if (a.$1 != b.$1) return a.$1 > b.$1;
      if (a.$2 != b.$2) return a.$2 > b.$2;
      if (a.$3 != b.$3) return a.$3 > b.$3;
      if (a.$4 != b.$4) return a.$4 > b.$4;
      if (a.$5 != b.$5) return a.$5 > b.$5;
      return false;
    }

    if (bestKey == null || better(key, bestKey) || (!better(bestKey, key) && e.name.length < best!.name.length)) {
      best = e;
      bestKey = key;
    }
  }
  return best;
}
