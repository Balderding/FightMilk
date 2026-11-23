import 'dart:convert';
import 'dart:io' show ZLibCodec;

import 'exercise.dart';
import 'explain.dart';
import 'gym.dart';
import 'library.dart';
import 'plan.dart';
import 'program.dart';

/// Passing a plan on with no server (batch 20, F323-F327, F329). What travels is only the plan:
/// its name, days, exercises, sets, reps, rest and a program's rules. Nothing about the person
/// (no weights, training maxes, body data or photos).
///
/// A received plan is input from a stranger (MCP guardrails): [readSharedPlan] never throws, caps
/// the size, checks every field and range, lists unknown exercises plainly, gives a new plan id
/// (it never replaces a plan) and keeps any own-script progression rule out until the person has
/// read it and said yes.

const shareMaxBytes = 1024 * 1024; // the largest plan read, as text or unpacked from a link
const maxReceivedScripts = 10; // own-script rules a received plan may carry (review 5, P2-1)
const linkPrefix = 'fightmilk://plan#';

// ---------- sending ----------

Map<String, dynamic> _itemJson(PlanItem i) => {
      'exercise': i.exerciseId,
      'sets': i.sets,
      'repLow': i.repLow,
      'repHigh': i.repHigh,
      'rest': i.restSec,
      if (i.style.isNotEmpty) 'style': i.style,
      if (i.group != null) 'group': i.group,
      if (i.perSet != null) 'perSet': [for (final p in i.perSet!) p.toJson()],
      if (i.tier.isNotEmpty) 'tier': i.tier,
      if (i.tmOf.isNotEmpty) 'tmOf': i.tmOf,
      if (i.bump.isNotEmpty) 'bump': i.bump,
    };

/// The plan as the share JSON. [onlyDay]: just that day (F329).
Map<String, dynamic> sharePlanMap(Plan p, {int? onlyDay}) {
  final days = onlyDay == null ? p.days : [p.days[onlyDay]];
  return {
    'fightmilk': 'plan',
    'v': 1,
    'name': onlyDay == null ? p.name : '${p.name}: ${p.days[onlyDay].name}',
    'days': [
      for (final d in days) {'name': d.name, 'items': [for (final i in d.items) _itemJson(i)]}
    ],
    if (onlyDay == null && p.weeksPerCycle > 1) 'weeks': p.weeksPerCycle,
    if (onlyDay == null && p.program != null) 'program': p.program!.toJson(),
  };
}

String sharePlanJson(Plan p, {int? onlyDay}) => const JsonEncoder.withIndent(' ').convert(sharePlanMap(p, onlyDay: onlyDay));

/// `fightmilk://plan#<the plan, compressed, base64url>` (F326). The data is in the link itself.
String sharePlanLink(Plan p, {int? onlyDay}) {
  final z = ZLibCodec(level: 9).encode(utf8.encode(jsonEncode(sharePlanMap(p, onlyDay: onlyDay))));
  return '$linkPrefix${base64Url.encode(z).replaceAll('=', '')}';
}

/// The plan as text a person can read and FightMilk reads back (F324; [parseTextPlan]).
String sharePlanText(Plan p, Library lib, {int? onlyDay}) {
  final b = StringBuffer('${onlyDay == null ? p.name : '${p.name}: ${p.days[onlyDay].name}'}\n');
  for (final d in onlyDay == null ? p.days : [p.days[onlyDay]]) {
    b.write('\n${d.name}\n');
    for (final i in d.items) {
      final e = lib.byId(i.exerciseId);
      final reps = i.repHigh > i.repLow ? '${i.repLow}-${i.repHigh}' : '${i.repLow}';
      final plus = i.style == 'amrap' ? '+' : '';
      b.write('${e?.name ?? i.exerciseId} ${i.sets}x$reps$plus${e?.timed == true ? 's' : ''}, ${i.restSec}s rest\n');
    }
  }
  b.write('\n(Made with FightMilk. Paste it in Plan → Import a plan.)\n');
  return b.toString();
}

// ---------- receiving ----------

class Received {
  final Plan? plan; // null: refused, see [problems]
  final List<String> problems; // why it was refused, in plain words
  final List<String> unknown; // exercises this app doesn't have (left out)
  final Map<String, String> scripts; // own-script rules per lift, kept out until the person says yes
  final List<String> notes; // other things left out or changed
  const Received(this.plan, {this.problems = const [], this.unknown = const [], this.scripts = const {}, this.notes = const []});
  bool get ok => plan != null;
}

Received _no(String why) => Received(null, problems: [why]);

/// Reads a plan someone sent: the share JSON, a fightmilk:// link or plain text. Never throws.
Received readSharedPlan(String input, Library lib) {
  try {
    if (input.length > shareMaxBytes) return _no('That is too big to be a plan (over 1 MB).');
    final t = input.trim();
    if (t.isEmpty) return _no('There is nothing to read.');
    if (t.startsWith('fightmilk:')) {
      final data = _unlink(t);
      if (data == null) return _no('That link is not a FightMilk plan link, or it is broken.');
      return _fromJson(data, lib);
    }
    if (t.startsWith('{')) {
      Object? j;
      try {
        j = jsonDecode(t);
      } on FormatException {
        return _no('The file is broken or cut short: it is not whole JSON.');
      }
      if (j is Map && j['fightmilk'] == 'plan') return _fromJson(j, lib);
      return _no('That file is not a FightMilk plan.');
    }
    final r = parseTextPlan(t, lib);
    if (r.plan == null) return _no('No exercise lines with sets and reps were found.');
    return Received(r.plan!.copyWith(id: Plan(name: '', days: const []).id, source: 'mine'), unknown: r.unknown);
  } catch (e) {
    return _no('That could not be read as a plan.');
  }
}

/// The JSON inside a link, or null. Unpacks at most [shareMaxBytes].
Object? _unlink(String link) {
  if (!link.startsWith(linkPrefix)) return null;
  final d = link.substring(linkPrefix.length);
  if (d.isEmpty || d.length > 64 * 1024 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(d)) return null;
  final List<int> z;
  try {
    z = base64Url.decode(d.padRight((d.length + 3) ~/ 4 * 4, '='));
  } catch (_) {
    return null;
  }
  final out = <int>[];
  var tooBig = false;
  final sink = ByteConversionSink.withCallback((b) => out.addAll(b));
  final inflate = ZLibCodec().decoder.startChunkedConversion(_Capped(sink, () => tooBig = true));
  try {
    for (var i = 0; i < z.length && !tooBig; i += 4096) {
      inflate.add(z.sublist(i, (i + 4096).clamp(0, z.length)));
    }
    if (!tooBig) inflate.close();
  } catch (_) {
    return null;
  }
  if (tooBig) return null;
  try {
    return jsonDecode(utf8.decode(out));
  } catch (_) {
    return null;
  }
}

/// Stops unpacking at [shareMaxBytes] (a small link can unpack to a huge file).
class _Capped implements Sink<List<int>> {
  final Sink<List<int>> to;
  final void Function() over;
  var n = 0;
  _Capped(this.to, this.over);
  @override
  void add(List<int> b) {
    n += b.length;
    if (n > shareMaxBytes) {
      over();
      throw const FormatException('too big');
    }
    to.add(b);
  }

  @override
  void close() => to.close();
}

/// Bidi controls and zero-width marks: they can make a name read differently from what is stored
/// (review 5, P2-3). Removed from every received string, scripts included.
final _hidden = RegExp('[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');

bool _combining(int c) => (c >= 0x300 && c <= 0x36F) || (c >= 0x1AB0 && c <= 0x1AFF) || (c >= 0x1DC0 && c <= 0x1DFF) || (c >= 0x20D0 && c <= 0x20FF) || (c >= 0xFE20 && c <= 0xFE2F);

/// A received text made safe to show: no control or hidden marks, at most 2 combining marks after
/// a letter, cut at [max] letters (whole code points, never half an emoji).
String cleanReceived(String s, int max) {
  final t = s.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').replaceAll(_hidden, '');
  final out = <int>[];
  var marks = 0;
  for (final c in t.runes) {
    if (_combining(c)) {
      if (++marks > 2) continue;
    } else {
      marks = 0;
    }
    out.add(c);
    if (out.length >= max) break;
  }
  return String.fromCharCodes(out).trim();
}

String _clean(Object? s, int max) => s is String ? cleanReceived(s, max) : '';

int? _int(Object? v, int lo, int hi) => v is int && v >= lo && v <= hi ? v : (v is double && v == v.roundToDouble() && v >= lo && v <= hi ? v.toInt() : null);

Received _fromJson(Object? j, Library lib) {
  if (j is! Map || j['fightmilk'] != 'plan') return _no('That is not a FightMilk plan.');
  if (j['v'] is! int || (j['v'] as int) < 1) return _no('That is not a FightMilk plan.');
  if ((j['v'] as int) > 1) return _no('This plan was made by a newer FightMilk. Update the app to read it.');
  final days = j['days'];
  if (days is! List || days.isEmpty) return _no('The plan has no days.');
  if (days.length > 84) return _no('The plan has ${days.length} days (84 at most).'); // programs: a day per training day of each week
  final unknown = <String>{};
  final notes = <String>[];
  final out = <PlanDay>[];
  for (var di = 0; di < days.length; di++) {
    final d = days[di];
    if (d is! Map || d['items'] is! List) return _no('Day ${di + 1} is not a day.');
    final items = d['items'] as List;
    if (items.length > 20) return _no('Day ${di + 1} has ${items.length} exercises (20 at most).');
    final kept = <PlanItem>[];
    for (var ii = 0; ii < items.length; ii++) {
      final it = items[ii];
      final w = 'Day ${di + 1}, exercise ${ii + 1}';
      if (it is! Map) return _no('$w is not an exercise.');
      final id = it['exercise'];
      if (id is! String || id.length > 80) return _no('$w has no exercise.');
      final e = lib.byId(id);
      if (e == null) {
        unknown.add(id);
        continue;
      }
      final sets = _int(it['sets'], 1, 20), lo = _int(it['repLow'], 1, e.timed ? 600 : 100), hi = _int(it['repHigh'], 1, e.timed ? 600 : 100), rest = _int(it['rest'], 0, 900);
      if (sets == null) return _no('$w (${e.name}): sets must be 1-20.');
      if (lo == null || hi == null || lo > hi) return _no('$w (${e.name}): the reps are not a sane range.');
      if (rest == null) return _no('$w (${e.name}): rest must be 0-900 seconds.');
      final style = it['style'] ?? '';
      if (style is! String || !lastSetStyles.containsKey(style)) return _no('$w (${e.name}): unknown last-set style.');
      final group = it['group'] == null ? null : _int(it['group'], 0, 99);
      if (it['group'] != null && group == null) return _no('$w (${e.name}): bad superset group.');
      List<SetSpec>? per;
      if (it['perSet'] != null) {
        final ps = it['perSet'];
        if (ps is! List || ps.isEmpty || ps.length > 20) return _no('$w (${e.name}): bad per-set targets.');
        per = [];
        for (final x in ps) {
          if (x is! Map) return _no('$w (${e.name}): bad per-set targets.');
          final r = _int(x['r'], 1, e.timed ? 600 : 100);
          final h = x['h'] == null ? null : _int(x['h'], 1, e.timed ? 600 : 100);
          final pct = x['p'];
          if (r == null || (x['h'] != null && (h == null || h < r))) return _no('$w (${e.name}): per-set reps out of range.');
          if (pct != null && (pct is! num || pct < 0 || pct > 1.5)) return _no('$w (${e.name}): a % must be 0-150.');
          per.add(SetSpec(r, hi: h, pct: (pct as num?)?.toDouble(), amrap: x['a'] == 1));
        }
      }
      final tier = _clean(it['tier'], 8), tmOf = _clean(it['tmOf'], 80), bump = _clean(it['bump'], 20);
      if (tier.isNotEmpty && !RegExp(r'^[A-Z0-9]{1,8}$').hasMatch(tier)) return _no('$w (${e.name}): a bad slot name.');
      if (tmOf.isNotEmpty && lib.byId(tmOf) == null) return _no('$w (${e.name}): its training max is from an unknown lift.');
      if (bump.isNotEmpty && !bumpKinds.containsKey(bump)) return _no('$w (${e.name}): unknown training-max rule.');
      if (kept.any((x) => x.exerciseId == e.id && x.tier == tier)) return _no('Day ${di + 1} has ${e.name} twice.');
      kept.add(PlanItem(exerciseId: e.id, sets: per?.length ?? sets, repLow: lo, repHigh: hi, restSec: rest, style: style, group: group, perSet: per, tier: tier, tmOf: tmOf, bump: bump));
    }
    final name = _clean(d['name'], 40);
    if (kept.isEmpty) {
      notes.add('${name.isEmpty ? 'Day ${di + 1}' : name} was left out: none of its exercises are in this app.');
      continue;
    }
    out.add(PlanDay(name: name.isEmpty ? 'Day ${di + 1}' : name, items: kept));
  }
  if (out.isEmpty) return Received(null, problems: ['None of the plan\'s exercises are in this app.'], unknown: unknown.toList());
  final weeks = j['weeks'] == null ? 1 : _int(j['weeks'], 1, 52);
  if (weeks == null) return _no('The plan\'s weeks must be 1-52.');
  // a program's rules; own-script rules are set aside until the person reads them
  ProgramInfo? prog;
  final scripts = <String, String>{};
  if (j['program'] != null) {
    final pr = j['program'];
    if (pr is! Map || pr['rules'] is! Map) return _no('The plan\'s program rules are broken.');
    final rules = <String, LiftRule>{};
    // a rule must be for a lift (and slot) the plan's days use: at most one per lift and slot
    // (review 5, P2-1), so the count is bounded by the plan itself
    final inPlan = {for (final d in out) for (final it in d.items) liftKey(it)};
    final scriptCount = [for (final v in (pr['rules'] as Map).values) if (v is Map && v['kind'] == 'script') v].length;
    if (scriptCount > maxReceivedScripts) return _no('This plan has $scriptCount own rules; $maxReceivedScripts at most.');
    var dropped = 0;
    for (final e in (pr['rules'] as Map).entries) {
      final k = e.key, v = e.value;
      if (k is! String || v is! Map) return _no('The plan\'s program rules are broken.');
      if (!RegExp(r'^[a-z0-9_]{1,80}(#[A-Z0-9]{1,8})?$').hasMatch(k) || !inPlan.contains(k)) {
        dropped++;
        continue;
      }
      final lift = k.split('#').first;
      final kind = v['kind'] ?? 'double';
      if (kind is! String || !ruleKinds.containsKey(kind)) return _no('Unknown progression rule "$kind".');
      final inc = v['inc'] ?? 1, misses = v['misses'] ?? 2, reset = v['reset'] ?? 0.9, goal = v['amrapGoal'] ?? 0, up = v['resetUp'] ?? 0;
      if (inc is! num || inc < -10 || inc > 10 || misses is! int || misses < 1 || misses > 10 || reset is! num || reset < 0.3 || reset > 1.2 || goal is! int || goal < 0 || goal > 50 || up is! num || up < 0 || up > 20) {
        return _no('A progression rule has numbers out of range.');
      }
      final stages = v['stages'] ?? const [], ladder = v['ladder'] ?? const [];
      if (stages is! List || stages.length > 10 || stages.any((x) => x is! String || x.length > 30)) return _no('A stage rule is broken.');
      if (ladder is! List || ladder.length > 10 || ladder.any((x) => x is! String || lib.byId(x) == null)) return _no('A ladder rule names an unknown exercise.');
      for (final st in stages.cast<String>()) {
        try {
          parseSets(st);
        } on FormatException {
          return _no('A stage rule has a bad set text: "$st".');
        }
      }
      final script = v['script'] ?? '';
      if (script is! String) return _no('A progression rule is broken.');
      if (kind == 'script') {
        final bad = checkScript(script);
        if (bad != null) return _no('The plan\'s own rule for ${lib.byId(lift)!.name}: $bad');
        // kept out of the plan until the person says yes; the sender's comments are not shown
        // or kept (review 5, P2-2)
        scripts[k] = [for (final l in script.split('\n')) if (cleanReceived(l, 200).isNotEmpty && !cleanReceived(l, 200).startsWith('#')) cleanReceived(l, 200)].join('\n');
        continue;
      }
      rules[k] = LiftRule(kind: kind, inc: inc.toDouble(), misses: misses, reset: reset.toDouble(), stages: stages.cast<String>(), ladder: ladder.cast<String>(), amrapGoal: goal, resetUp: up.toDouble());
    }
    if (dropped > 0) notes.add('$dropped progression rule${dropped == 1 ? '' : 's'} for lifts not in the plan ${dropped == 1 ? 'was' : 'were'} left out.');
    final basis = pr['basis'] ?? 'tm90';
    if (basis is! String || !tmBases.containsKey(basis)) return _no('Unknown training-max basis.');
    prog = ProgramInfo(id: _clean(pr['id'], 40), rules: rules, basis: basis);
  }
  final name = _clean(j['name'], 60);
  return Received(
    Plan(name: name.isEmpty ? 'Shared plan' : name, source: 'mine', days: out, program: prog, weeksPerCycle: weeks), // always a new id
    unknown: unknown.toList(),
    scripts: scripts,
    notes: notes,
  );
}

/// Puts the own-script rules back in, after the person said "Use it".
Plan withScripts(Plan p, Map<String, String> scripts) {
  if (scripts.isEmpty) return p;
  final prog = p.program ?? const ProgramInfo(id: 'shared');
  return p.copyWith(program: ProgramInfo(id: prog.id, basis: prog.basis, rules: {...prog.rules, for (final e in scripts.entries) e.key: LiftRule(kind: 'script', script: e.value)}));
}

// ---------- fitting it to this gym (F327) ----------

class GymFix {
  final int day, item;
  final Exercise from;
  final String why;
  final Exercise? to; // the best swap, if any
  const GymFix(this.day, this.item, this.from, this.why, this.to);
}

/// Exercises in [p] this gym lacks or that load a sore joint, with the best swap for each.
List<GymFix> gymFixes(Plan p, Profile pr, Library lib) {
  final out = <GymFix>[];
  final cands = lib.available(pr.have, pr.avoid, items: pr.items);
  for (var d = 0; d < p.days.length; d++) {
    for (var i = 0; i < p.days[d].items.length; i++) {
      final e = lib.byId(p.days[d].items[i].exerciseId);
      if (e == null) continue;
      String? why;
      if (pr.items != null ? !gymAllows(e, pr.items!) : (e.equipment != Equipment.bodyweight && !pr.have.contains(e.equipment))) {
        why = 'needs ${pr.items != null ? missingFor(e, pr.items!) : equipmentLabel[e.equipment]!.toLowerCase()}, which your gym does not have';
      } else if (e.joints.intersection(pr.avoid).isNotEmpty) {
        why = 'is hard on your ${e.joints.intersection(pr.avoid).map((j) => jointLabel[j]!.toLowerCase()).join(' and ')}';
      }
      if (why == null) continue;
      final best = rankSwaps(e, cands.where((c) => c.id != e.id), avoid: pr.avoid).firstOrNull?.$1;
      out.add(GymFix(d, i, e, why, best));
    }
  }
  return out;
}

/// The plan with the chosen swaps made.
Plan applyFixes(Plan p, List<GymFix> fixes) {
  final days = [for (final d in p.days) [...d.items]];
  for (final f in fixes) {
    if (f.to != null) days[f.day][f.item] = days[f.day][f.item].copyWith(exerciseId: f.to!.id);
  }
  return p.copyWith(days: [for (var d = 0; d < p.days.length; d++) p.days[d].copyWith(items: days[d])]);
}
