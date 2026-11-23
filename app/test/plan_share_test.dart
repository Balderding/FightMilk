import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_share.dart';
import 'package:workout/domain/program.dart';
import 'package:workout/domain/programs.dart';
import 'package:workout/domain/units.dart';

/// Batch 20 plan sharing (F323-F327, F329) and the guardrails for a plan from a stranger.
void main() {
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  PlanItem item(String id, {int sets = 3, int lo = 8, int hi = 10, int rest = 90, String style = ''}) => PlanItem(exerciseId: id, sets: sets, repLow: lo, repHigh: hi, restSec: rest, style: style);
  final plan = Plan(name: 'Push Pull', source: 'mine', days: [
    PlanDay(name: 'Push', items: [item('bench_press', sets: 4, lo: 6, hi: 8, rest: 150), item('overhead_press'), item('plank', sets: 3, lo: 45, hi: 60, rest: 60)]),
    PlanDay(name: 'Pull', items: [item('deadlift', sets: 3, lo: 5, hi: 5, rest: 180, style: 'amrap'), item('barbell_row')]),
  ]);

  List<(String, int, int, int)> shape(Plan p) => [for (final d in p.days) for (final i in d.items) (i.exerciseId, i.sets, i.repLow, i.repHigh)];

  test('the share JSON, the link and the text all come back as the same plan, with a new id', () {
    for (final input in [sharePlanJson(plan), sharePlanLink(plan)]) {
      final r = readSharedPlan(input, lib);
      expect(r.ok, isTrue, reason: r.problems.join());
      expect(r.plan!.name, 'Push Pull');
      expect(shape(r.plan!), shape(plan));
      expect(r.plan!.days.map((d) => d.name), ['Push', 'Pull']);
      expect(r.plan!.id, isNot(plan.id), reason: 'never replaces a plan');
      expect(r.plan!.days[1].items.first.style, 'amrap');
    }
    final text = sharePlanText(plan, lib);
    expect(text, contains('Bench press 4x6-8, 150s rest'));
    final t = readSharedPlan(text, lib);
    expect(t.ok, isTrue);
    expect([for (final d in t.plan!.days) for (final i in d.items) i.exerciseId], ['bench_press', 'overhead_press', 'plank', 'deadlift', 'barbell_row']);
    expect(t.plan!.days.first.items.first.restSec, 150);
  });

  test('F329 one day travels alone', () {
    final r = readSharedPlan(sharePlanLink(plan, onlyDay: 1), lib);
    expect(r.plan!.days.single.name, 'Pull');
    expect(r.plan!.name, 'Push Pull: Pull');
  });

  test('a program keeps its rules; an own-script rule stays out until the person says yes', () {
    final p = buildProgram(templateById('531_bbb')!, full, lib);
    final withRule = p.copyWith(program: ProgramInfo(id: p.program!.id, basis: p.program!.basis, rules: {...p.program!.rules, 'bench_press': const LiftRule(kind: 'script', script: 'if top: add 1\nelse: same')}));
    final r = readSharedPlan(sharePlanJson(withRule), lib);
    expect(r.ok, isTrue, reason: r.problems.join());
    expect(r.scripts, {'bench_press': 'if top: add 1\nelse: same'});
    expect(r.plan!.program!.rules['bench_press'], isNull, reason: 'off by default');
    expect(r.plan!.program!.rules.length, p.program!.rules.length - (p.program!.rules.containsKey('bench_press') ? 1 : 0));
    expect(withScripts(r.plan!, r.scripts).program!.rules['bench_press']!.script, 'if top: add 1\nelse: same');
    expect(r.plan!.weeksPerCycle, p.weeksPerCycle);
    // a script that is not a rule, or too long, is refused with a plain line
    Map<String, dynamic> m(String script) => sharePlanMap(withRule.copyWith(program: ProgramInfo(id: 'x', rules: {'bench_press': LiftRule(kind: 'script', script: script)})));
    expect(readSharedPlan(jsonEncode(m('rm -rf /')), lib).problems.join(), contains('is not a rule'));
    expect(readSharedPlan(jsonEncode(m(List.filled(60, 'if top: add 1').join('\n'))), lib).problems.join(), contains('too long'));
  });

  test('unknown exercises are listed plainly; a day with none left is left out', () {
    final m = sharePlanMap(plan);
    ((m['days'] as List)[0]['items'] as List).add({'exercise': 'moon_press', 'sets': 3, 'repLow': 5, 'repHigh': 5, 'rest': 90});
    (m['days'] as List).add({
      'name': 'Alien',
      'items': [
        {'exercise': 'zero_g_row', 'sets': 3, 'repLow': 5, 'repHigh': 5, 'rest': 90}
      ]
    });
    final r = readSharedPlan(jsonEncode(m), lib);
    expect(r.ok, isTrue);
    expect(r.unknown, containsAll(['moon_press', 'zero_g_row']));
    expect(r.plan!.days.length, 2);
    expect(r.notes.single, contains('Alien was left out'));
  });

  test('fuzz: random, cut short, wrong types, huge and bomb inputs are refused with a plain line, never a crash', () {
    final rnd = Random(20);
    void refused(String input, String what) {
      late Received r;
      expect(() => r = readSharedPlan(input, lib), returnsNormally, reason: what);
      if (!r.ok) {
        expect(r.problems, isNotEmpty, reason: what);
        expect(r.problems.join().length, lessThan(200), reason: '$what: a plain line');
      }
    }

    // random strings and bytes
    for (var i = 0; i < 300; i++) {
      final s = String.fromCharCodes([for (var k = 0; k < rnd.nextInt(400); k++) rnd.nextInt(0x2FF)]);
      refused(s, 'random $i');
      refused('{$s', 'random json $i');
      refused('$linkPrefix$s', 'random link $i');
    }
    // the share JSON cut short at every length
    final good = jsonEncode(sharePlanMap(plan));
    for (var n = 0; n < good.length; n++) {
      final r = readSharedPlan(good.substring(0, n), lib);
      if (n > 0 && good.substring(0, n).trim().startsWith('{')) expect(r.ok, isFalse, reason: 'cut at $n');
    }
    // the link cut short
    final link = sharePlanLink(plan);
    for (var n = linkPrefix.length; n < link.length; n += 3) {
      refused(link.substring(0, n), 'link cut at $n');
    }
    // every field swapped for a wrong type or a crazy number
    const wrong = [null, 'x', -1, 0, 1e300, 99999999999, true, <dynamic>[], <String, dynamic>{}, 1.5];
    final keys = ['sets', 'repLow', 'repHigh', 'rest', 'style', 'group', 'exercise', 'perSet', 'tier', 'tmOf', 'bump'];
    for (final k in keys) {
      for (final v in wrong) {
        final m = jsonDecode(good) as Map<String, dynamic>;
        ((m['days'] as List)[0]['items'] as List)[0][k] = v;
        refused(jsonEncode(m), '$k = $v');
      }
    }
    for (final top in ['days', 'name', 'v', 'weeks', 'program']) {
      for (final v in wrong) {
        final m = jsonDecode(good) as Map<String, dynamic>;
        m[top] = v;
        refused(jsonEncode(m), '$top = $v');
      }
    }
    // sane ranges: a % over 150, 30 sets, a negative rest
    final m = jsonDecode(good) as Map<String, dynamic>;
    ((m['days'] as List)[0]['items'] as List)[0]['perSet'] = [
      {'r': 5, 'p': 2.0}
    ];
    expect(readSharedPlan(jsonEncode(m), lib).problems.join(), contains('0-150'));
    final m2 = jsonDecode(good) as Map<String, dynamic>;
    ((m2['days'] as List)[0]['items'] as List)[0]['sets'] = 30;
    expect(readSharedPlan(jsonEncode(m2), lib).problems.join(), contains('sets must be 1-20'));
    // over 1 MB
    expect(readSharedPlan('{"fightmilk":"plan","x":"${'a' * (shareMaxBytes + 10)}"}', lib).problems.join(), contains('too big'));
    // a small link that would unpack to megabytes
    final bomb = ZLibCodec(level: 9).encode(utf8.encode('{"fightmilk":"plan","pad":"${' ' * (8 * 1024 * 1024)}"}'));
    expect(readSharedPlan('$linkPrefix${base64Url.encode(bomb).replaceAll('=', '')}', lib).ok, isFalse);
    // a link the app doesn't know opens nothing
    expect(readSharedPlan('fightmilk://settings#wipe', lib).ok, isFalse);
    expect(readSharedPlan('https://example.com/plan.json', lib).ok, isFalse);
    // a newer format is refused kindly
    final m3 = jsonDecode(good) as Map<String, dynamic>..['v'] = 7;
    expect(readSharedPlan(jsonEncode(m3), lib).problems.join(), contains('newer FightMilk'));
  });

  test('F327 exercises the gym lacks or that load a sore joint get a swap offered', () {
    final home = Profile(goal: Goal.both, days: 3, minutes: 45, have: {Equipment.dumbbell, Equipment.bodyweight}, avoid: {}, unit: Unit.kg);
    final fixes = gymFixes(plan, home, lib);
    expect(fixes.map((f) => f.from.id), containsAll(['bench_press', 'deadlift', 'barbell_row']));
    expect(fixes.firstWhere((f) => f.from.id == 'bench_press').to, isNotNull);
    expect(fixes.firstWhere((f) => f.from.id == 'bench_press').why, contains('your gym does not have'));
    final fixed = applyFixes(plan, fixes);
    expect(gymFixes(fixed, home, lib).where((f) => f.to != null), isEmpty);
    expect(fixed.days.length, plan.days.length);
  });
}
