import 'dart:convert';

import '../domain/exercise.dart';
import '../domain/library.dart';
import '../domain/plan.dart';

class PlanParse {
  final Plan? plan;
  final List<String> errors;
  const PlanParse(this.plan, this.errors);
}

class DayParse {
  final PlanDay? day;
  final List<String> errors;
  const DayParse(this.day, this.errors);
}

/// Pulls the JSON object out of an AI reply (bare, or inside a ``` fence, or with chatter around it).
Object? extractJson(String text) {
  var t = text.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
  if (fence != null) t = fence.group(1)!.trim();
  final a = t.indexOf('{'), z = t.lastIndexOf('}');
  if (a < 0 || z <= a) return null;
  try {
    return jsonDecode(t.substring(a, z + 1));
  } catch (_) {
    return null;
  }
}

/// Reads the plain workout list format:
///   `PLAN: name`
///   `DAY: name`
///   `exercise_id | sets | reps | rest seconds`
/// Tolerates chat noise: code fences, bullets/numbers, exercise names instead of ids, "8-12 reps",
/// "90s", "2 min", a single rep number. Returns the same shape as the JSON answer, or null.
Map<String, dynamic>? parseListText(String text, Library lib) {
  String? planName;
  final days = <Map<String, dynamic>>[];
  Map<String, dynamic>? cur;
  final head = RegExp(r'^\s*[#*_]*\s*(PLAN|DAY)\s*[:\-]\s*(.+?)\s*[*_]*\s*$', caseSensitive: false);
  for (var line in text.split(RegExp(r'\r?\n'))) {
    if (line.trim().startsWith('```')) continue;
    final h = head.firstMatch(line);
    if (h != null) {
      if (h.group(1)!.toUpperCase() == 'PLAN') {
        planName = h.group(2);
      } else {
        cur = {'name': h.group(2), 'items': <Map<String, dynamic>>[]};
        days.add(cur);
      }
      continue;
    }
    if (cur == null || !line.contains('|')) continue;
    line = line.replaceFirst(RegExp(r'^\s*(?:[-*\u2022]|\d+[.)])\s*'), '');
    final f = line.split('|').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    if (f.length < 4) continue;
    final ex = lib.find(f[0]);
    final sets = int.tryParse(RegExp(r'\d+').firstMatch(f[1])?.group(0) ?? '');
    final range = RegExp(r'(\d+)\s*(?:-|\u2013|to)\s*(\d+)').firstMatch(f[2]);
    final one = RegExp(r'\d+').firstMatch(f[2]);
    final lo = range != null ? int.parse(range.group(1)!) : (one == null ? null : int.parse(one.group(0)!));
    final hi = range != null ? int.parse(range.group(2)!) : lo;
    var rest = int.tryParse(RegExp(r'\d+').firstMatch(f[3])?.group(0) ?? '');
    if (rest != null && f[3].toLowerCase().contains('min')) rest *= 60;
    (cur['items'] as List).add({'exercise': ex?.id ?? f[0], 'sets': sets, 'repLow': lo, 'repHigh': hi, 'rest': rest});
  }
  if (days.isEmpty) return null;
  return {'name': planName ?? 'AI plan', 'days': days};
}

PlanDay? _day(Object? d, Library lib, List<String> err, String where, Profile? p) {
  if (d is! Map) {
    err.add('$where is not a day.');
    return null;
  }
  final name = d['name'];
  final items = d['items'];
  if (name is! String || name.trim().isEmpty) err.add('$where has no name.');
  if (items is! List || items.isEmpty) {
    err.add('$where has no exercises.');
    return null;
  }
  if (items.length > 12) err.add('$where has ${items.length} exercises (12 at most).');
  final out = <PlanItem>[];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final w = '$where, exercise ${i + 1}';
    if (it is! Map) {
      err.add('$w is not an exercise.');
      continue;
    }
    final id = it['exercise'];
    final ex = id is String ? lib.byId(id) : null;
    if (ex == null) {
      err.add('$w: unknown exercise "$id".');
      continue;
    }
    if (out.any((x) => x.exerciseId == ex.id)) {
      err.add('$where has ${ex.name} twice.');
      continue;
    }
    if (p != null) {
      if (ex.equipment != Equipment.bodyweight && !p.have.contains(ex.equipment)) {
        err.add('$w: ${ex.name} needs ${equipmentLabel[ex.equipment]!.toLowerCase()}, which your gym does not have.');
        continue;
      }
      final sore = ex.joints.intersection(p.avoid);
      if (sore.isNotEmpty) {
        err.add('$w: ${ex.name} is hard on your ${sore.map((j) => jointLabel[j]!.toLowerCase()).join(' and ')}.');
        continue;
      }
    }
    int? n(String k) => it[k] is num ? (it[k] as num).round() : null;
    final sets = n('sets'), lo = n('repLow'), hi = n('repHigh'), rest = n('rest');
    final maxReps = ex.timed ? 120 : 30;
    if (sets == null || sets < 1 || sets > 10) err.add('$w (${ex.name}): sets must be 1-10.');
    if (lo == null || hi == null || lo < 1 || hi > maxReps || lo > hi) err.add('$w (${ex.name}): reps must be 1-$maxReps, low <= high.');
    if (rest == null || rest < 30 || rest > 600) err.add('$w (${ex.name}): rest must be 30-600 seconds.');
    if (sets != null && lo != null && hi != null && rest != null) {
      out.add(PlanItem(exerciseId: ex.id, sets: sets, repLow: lo, repHigh: hi, restSec: rest));
    }
  }
  return PlanDay(name: (name is String ? name.trim() : 'Day'), items: out);
}

/// Checks an AI plan. Anything wrong = no plan, and a list of reasons in plain words.
PlanParse parsePlan(String text, Library lib, {Profile? profile}) {
  var j = extractJson(text);
  if (j is! Map || j['days'] == null) j = parseListText(text, lib) ?? j;
  if (j is! Map) return const PlanParse(null, ['The AI did not send a plan the app can read.']);
  final days = j['days'];
  if (days is! List || days.isEmpty) return const PlanParse(null, ['The AI plan has no days.']);
  if (days.length > 7) return PlanParse(null, ['The AI plan has ${days.length} days (7 at most).']);
  final err = <String>[];
  final out = <PlanDay>[];
  for (var i = 0; i < days.length; i++) {
    final d = _day(days[i], lib, err, 'Day ${i + 1}', profile);
    if (d != null) out.add(d);
  }
  if (err.isNotEmpty) return PlanParse(null, err);
  final name = j['name'] is String && (j['name'] as String).trim().isNotEmpty ? (j['name'] as String).trim() : 'AI plan';
  return PlanParse(Plan(name: name, source: 'ai', days: out), const []);
}

/// Checks an AI "adjust today" answer.
DayParse parseDay(String text, Library lib, {Profile? profile}) {
  var j = extractJson(text);
  if (j is! Map || j['items'] == null) {
    final t = parseListText(text, lib);
    if (t != null) j = (t['days'] as List).first;
  }
  if (j is! Map) return const DayParse(null, ['The AI did not send a workout the app can read.']);
  final err = <String>[];
  final d = _day(j, lib, err, 'Today', profile);
  if (err.isNotEmpty || d == null) return DayParse(null, err);
  return DayParse(d, const []);
}
