import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/ai/plan_json.dart';
import 'package:workout/ai/prompt.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {Joint.knees}, unit: Unit.lb);

  const plain = '''
Sure! Here's your plan:

PLAN: Upper/Lower 4-day
DAY: Upper A
bench_press | 4 | 5-8 | 150
barbell_row | 4 | 6-8 | 120
DAY: Lower A
romanian_deadlift | 4 | 6-8 | 150
lying_leg_curl | 3 | 10-15 | 75

Let me know if you want changes.
''';

  test('plain workout list is accepted', () {
    final r = parsePlan(plain, lib, profile: profile);
    expect(r.errors, isEmpty);
    expect(r.plan!.name, 'Upper/Lower 4-day');
    expect(r.plan!.days.map((d) => d.name), ['Upper A', 'Lower A']);
    final b = r.plan!.days.first.items.first;
    expect((b.exerciseId, b.sets, b.repLow, b.repHigh, b.restSec), ('bench_press', 4, 5, 8, 150));
  });

  test('chat-style noise is tolerated: code fence, bullets, names, "8 reps", "90s", one rep number', () {
    const messy = '''
```
PLAN: Mine
DAY: Push
- Bench press | 4 | 5-8 | 150s
* incline_db_press | 3 | 8 - 12 reps | 90 sec
3. Rope pushdown | 3 | 12 | 60
```''';
    final r = parsePlan(messy, lib, profile: profile);
    expect(r.errors, isEmpty);
    final it = r.plan!.days.single.items;
    expect(it.map((i) => i.exerciseId), ['bench_press', 'incline_db_press', 'rope_pushdown']);
    expect((it[1].repLow, it[1].repHigh, it[1].restSec), (8, 12, 90));
    expect((it[2].repLow, it[2].repHigh), (12, 12));
  });

  test('same checks as JSON: unknown, sore joints, silly numbers', () {
    expect(parsePlan('PLAN: x\nDAY: A\nlaser_press | 3 | 8-12 | 90', lib).errors.join(), contains('laser_press'));
    expect(parsePlan('PLAN: x\nDAY: A\ngoblet_squat | 3 | 8-12 | 90', lib, profile: profile).errors.join(), contains('knees'));
    expect(parsePlan('PLAN: x\nDAY: A\nbench_press | 30 | 8-12 | 90', lib).plan, isNull);
    expect(parsePlan('I can not do that.', lib).plan, isNull);
  });

  test('a single day (adjust today)', () {
    final r = parseDay('DAY: Upper A\nbench_press | 4 | 5-8 | 150\nlat_pulldown | 3 | 8-12 | 90', lib, profile: profile);
    expect(r.errors, isEmpty);
    expect(r.day!.name, 'Upper A');
    expect(r.day!.items.length, 2);
  });

  test('JSON still works', () {
    expect(parsePlan('{"name":"j","days":[{"name":"A","items":[{"exercise":"bench_press","sets":3,"repLow":8,"repHigh":12,"rest":90}]}]}', lib).errors, isEmpty);
  });

  test('chat prompts ask for the plain format; project instructions carry rules, format and list', () {
    final sys = systemPrompt(lib, profile, wholePlan: true, plainText: true);
    expect(sys, contains('PLAN: '));
    expect(sys, contains('exercise_id | sets | reps | rest seconds'));
    expect(sys, isNot(contains('"days"')));
    final pi = projectInstructions(lib, profile);
    expect(pi, contains('Use ONLY exercises from this list'));
    expect(pi, contains('bench_press | Bench press'));
    expect(pi, contains('DAY: '));
    expect(pi, isNot(contains('goblet_squat |'))); // knees
  });

  test('with a Project, the hand-off message is short', () {
    const r = AiRequest('x', 'SYSTEM TEXT', 'Goal: both\nRequest: make a plan', AiTask.plan);
    final full = handoffText(r);
    final short = handoffText(r, project: true);
    expect(full, contains('SYSTEM TEXT'));
    expect(short, isNot(contains('SYSTEM TEXT')));
    expect(short, contains('Request: make a plan'));
    expect(short, contains('workout list format'));
  });
}
