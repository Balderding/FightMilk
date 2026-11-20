import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/domain/coach.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/ui/anim/pose.dart';
import 'package:workout/ui/anim/pose_data.dart';
import 'package:workout/ui/coach_screen.dart';

void main() {
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final bench = lib.byId('bench_press')!; // compound
  final curl = lib.byId('db_curl')!; // isolation
  final plank = lib.byId('plank')!;
  PlanItem it(String id, int lo, int hi) => PlanItem(exerciseId: id, sets: 4, repLow: lo, repHigh: hi, restSec: 120);

  group('smart rest', () {
    test('heavier and bigger lifts rest longer', () {
      final heavy = smartRest(bench, it('bench_press', 3, 5), 5, lastSet: false);
      final mid = smartRest(bench, it('bench_press', 8, 12), 10, lastSet: false);
      final small = smartRest(curl, it('db_curl', 10, 15), 12, lastSet: false);
      expect(heavy, greaterThan(mid));
      expect(mid, greaterThan(small));
      expect(heavy, 210);
      expect(small, 75);
    });
    test('missing reps adds time, crushing it takes a bit off', () {
      final normal = smartRest(bench, it('bench_press', 5, 8), 6, lastSet: false);
      expect(smartRest(bench, it('bench_press', 5, 8), 3, lastSet: false), normal + 45);
      expect(smartRest(bench, it('bench_press', 5, 8), 11, lastSet: false), normal - 15);
    });
    test('effort tap overrides the guess', () {
      final normal = smartRest(bench, it('bench_press', 5, 8), 6, lastSet: false);
      expect(smartRest(bench, it('bench_press', 5, 8), 6, lastSet: false, effort: Effort.easy), normal - 30);
      expect(smartRest(bench, it('bench_press', 5, 8), 6, lastSet: false, effort: Effort.hard), normal + 30);
      expect(smartRest(bench, it('bench_press', 5, 8), 6, lastSet: false, effort: Effort.max), normal + 60);
      expect(smartRest(bench, it('bench_press', 5, 8), 3, lastSet: false, effort: Effort.good), normal);
    });
    test('after the last set: time to set up the next exercise; holds rest a minute; always 30-300 in 15 s steps', () {
      expect(smartRest(bench, it('bench_press', 3, 5), 5, lastSet: true), 90);
      expect(smartRest(plank, it('plank', 30, 60), 45, lastSet: false), 60);
      for (final lo in [1, 3, 5, 8, 12, 20]) {
        for (final e in Effort.values) {
          final r = smartRest(bench, it('bench_press', lo, lo + 2), 0, lastSet: false, effort: e);
          expect(r, inInclusiveRange(30, 300));
          expect(r % 15, 0);
        }
      }
    });
  });

  group('guide', () {
    String g({int setNo = 1, int sets = 4, bool resting = false, bool restOver = false, bool exDone = false, String? next, bool allDone = false, bool first = false}) =>
        guideLine(name: 'Bench press', setNo: setNo, sets: sets, weight: '225 lb', reps: '5-8', resting: resting, restOver: restOver, exerciseDone: exDone, nextName: next, workoutDone: allDone, firstOfWorkout: first);
    test('says the right thing at each moment', () {
      expect(g(first: true), allOf(contains('Hey'), contains('Bench press'), contains('warm')));
      expect(g(setNo: 2), allOf(contains('Set 2 of 4'), contains('225 lb')));
      expect(g(setNo: 4), contains('Last set'));
      expect(g(setNo: 3, resting: true), allOf(contains('Rest'), contains('set 3 of 4')));
      expect(g(setNo: 3, restOver: true), allOf(contains("Rest's over"), contains('go')));
      expect(g(exDone: true, next: 'Barbell row'), allOf(contains('Bench press done'), contains('Barbell row')));
      expect(g(allDone: true), contains('Finish'));
    });
  });

  group('animation data', () {
    test('every exercise has an animation, and both poses match in shape', () {
      for (final e in lib.all) {
        final p = poseData[e.pattern];
        expect(p, isNotNull, reason: e.pattern);
        expect(p!.a.body.length, p.b.body.length);
        expect(p.a.hands.length, p.b.hands.length);
      }
    });
    test('one rep: lift, squeeze, lower slowly (lowering takes longer)', () {
      expect(repAt(0).$1, 0);
      expect(repAt(1.0).$2, Phase.top);
      expect(repAt(1.0).$1, 1);
      expect(repAt(2.0).$2, Phase.lower);
      expect(repAt(2.9).$2, Phase.bottom);
      expect(repAt(0.45).$2, Phase.lift);
      final midLift = repAt(0.45).$1, midLower = repAt(1.15 + 0.75).$1;
      expect(midLift, closeTo(0.5, 0.01));
      expect(midLower, closeTo(0.5, 0.01));
    });
  });

  test('coach answers lose markdown', () {
    expect(plainText('**Primary lifts:**\n- **Bench** press\n## Rest\n* two minutes'), 'Primary lifts:\n• Bench press\nRest\n• two minutes');
  });
}
