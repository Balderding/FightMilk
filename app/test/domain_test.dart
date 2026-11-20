import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/progression.dart';
import 'package:workout/domain/units.dart';

Library loadLib() => Library.fromJsonString(File('assets/exercises.json').readAsStringSync());

void main() {
  final lib = loadLib();

  group('library', () {
    test('every exercise has an icon file', () {
      for (final e in lib.all) {
        expect(File('assets/icons/${e.icon}.svg').existsSync(), isTrue, reason: e.id);
      }
    });
    test('ids unique', () {
      expect(lib.all.map((e) => e.id).toSet().length, lib.all.length);
    });
    test('every swap group has at least 2 members', () {
      final groups = <String, int>{};
      for (final e in lib.all) {
        groups[e.swap] = (groups[e.swap] ?? 0) + 1;
      }
      groups.forEach((g, n) => expect(n, greaterThanOrEqualTo(2), reason: g));
    });
    test('swapsFor bench with machine+dumbbell', () {
      final s = lib.swapsFor(lib.byId('bench_press')!, {Equipment.machine, Equipment.dumbbell}, {}).map((e) => e.id);
      expect(s, contains('machine_chest_press'));
      expect(s, contains('db_bench_press'));
      expect(s, isNot(contains('bench_press')));
    });
  });

  group('units + progression', () {
    final bench = lib.byId('bench_press')!; // 6-10
    final pullUp = lib.byId('pull_up')!; // bodyweight
    SetLog s(double kg, int reps) => SetLog(exerciseId: bench.id, kg: kg, reps: reps);

    test('all sets at top of range -> add one step', () {
      final st = LiftState(exerciseId: bench.id, workKg: 100, misses: 0);
      final t = nextLift(st, bench, [s(100, 10), s(100, 10), s(100, 10)], Unit.kg);
      expect(t.workKg, 102.5);
      expect(t.misses, 0);
    });
    test('lb step is 5 lb', () {
      final st = LiftState(exerciseId: bench.id, workKg: lbToKg(225), misses: 0);
      final t = nextLift(st, bench, [s(lbToKg(225), 10), s(lbToKg(225), 10)], Unit.lb);
      expect(kgToLb(t.workKg), closeTo(230, 0.01));
    });
    test('a set below the range -> miss; two misses -> drop 10% to step', () {
      var st = LiftState(exerciseId: bench.id, workKg: 100, misses: 0);
      st = nextLift(st, bench, [s(100, 8), s(100, 5)], Unit.kg);
      expect(st.workKg, 100);
      expect(st.misses, 1);
      st = nextLift(st, bench, [s(100, 5)], Unit.kg);
      expect(st.workKg, 90);
      expect(st.misses, 0);
    });
    test('in between -> same weight, misses reset', () {
      final st = LiftState(exerciseId: bench.id, workKg: 100, misses: 1);
      final t = nextLift(st, bench, [s(100, 8), s(100, 7)], Unit.kg);
      expect(t.workKg, 100);
      expect(t.misses, 0);
    });
    test('bodyweight: progresses on reps first, then added weight', () {
      final st = LiftState(exerciseId: pullUp.id, workKg: 0, misses: 0, workReps: pullUp.repLow);
      final t1 = nextLift(st, pullUp, [SetLog(exerciseId: pullUp.id, kg: 0, reps: pullUp.repLow)], Unit.kg);
      expect(t1.workReps, pullUp.repLow + 1);
      expect(t1.workKg, 0);
      final top = LiftState(exerciseId: pullUp.id, workKg: 0, misses: 0, workReps: pullUp.repHigh);
      final t2 = nextLift(top, pullUp, [SetLog(exerciseId: pullUp.id, kg: 0, reps: pullUp.repHigh)], Unit.kg);
      expect(t2.workKg, 2.5);
      expect(t2.workReps, pullUp.repLow);
    });
    test('display', () {
      expect(fmtWeight(100, Unit.lb), '220.5');
      expect(fmtWeight(102.5, Unit.kg), '102.5');
      expect(fmtWeight(100, Unit.kg), '100');
      expect(roundToStep(lbToKg(223), StepKind.barbell, Unit.lb), closeTo(lbToKg(225), 0.001));
    });
    test('e1rm Epley', () {
      expect(e1rm(100, 5), closeTo(116.67, 0.01));
      expect(e1rm(100, 1), 100);
    });
  });

  group('plan maker', () {
    Profile p({Goal goal = Goal.both, int days = 4, int minutes = 60, Set<Equipment>? have, Set<Joint> avoid = const {}, String? split}) =>
        Profile(goal: goal, days: days, minutes: minutes, have: have ?? Equipment.values.toSet(), avoid: avoid, unit: Unit.lb, split: split);

    test('day counts and default splits', () {
      expect(makePlan(p(days: 2), lib).days.map((d) => d.name), ['Full body A', 'Full body B']);
      expect(makePlan(p(days: 3), lib).days.map((d) => d.name), ['Full body A', 'Full body B', 'Full body C']);
      expect(makePlan(p(days: 4), lib).days.map((d) => d.name), ['Upper A', 'Lower A', 'Upper B', 'Lower B']);
      expect(makePlan(p(days: 5), lib).days.map((d) => d.name), ['Upper', 'Lower', 'Push', 'Pull', 'Legs']);
      expect(makePlan(p(days: 6), lib).days.map((d) => d.name), ['Push A', 'Pull A', 'Legs A', 'Push B', 'Pull B', 'Legs B']);
    });
    test('chosen split overrides', () {
      expect(makePlan(p(days: 3, split: 'ppl'), lib).days.map((d) => d.name), ['Push', 'Pull', 'Legs']);
      expect(makePlan(p(days: 5, split: 'bro'), lib).days.map((d) => d.name), ['Chest', 'Back', 'Shoulders', 'Legs', 'Arms']);
      expect(makePlan(p(days: 2, split: 'upper_lower'), lib).days.map((d) => d.name), ['Upper', 'Lower']);
    });
    test('session length caps exercise count', () {
      for (final (mins, cap) in [(45, 5), (60, 6), (90, 8)]) {
        for (final d in makePlan(p(minutes: mins), lib).days) {
          expect(d.items.length, lessThanOrEqualTo(cap));
          expect(d.items.length, greaterThanOrEqualTo(3));
        }
      }
    });
    test('first item each day is a compound', () {
      for (final days in [2, 3, 4, 5, 6]) {
        for (final d in makePlan(p(days: days), lib).days) {
          expect(lib.byId(d.items.first.exerciseId)!.compound, isTrue, reason: d.name);
        }
      }
    });
    test('dumbbells only + sore joints: never empty, never an avoided joint', () {
      final avoid = {Joint.shoulders, Joint.lowerBack, Joint.knees};
      for (final days in [2, 3, 4, 5, 6]) {
        final plan = makePlan(p(days: days, have: {Equipment.dumbbell}, avoid: avoid), lib);
        for (final d in plan.days) {
          expect(d.items, isNotEmpty, reason: d.name);
          for (final it in d.items) {
            final e = lib.byId(it.exerciseId)!;
            expect(e.joints.intersection(avoid), isEmpty, reason: e.id);
            expect({Equipment.dumbbell, Equipment.bodyweight}, contains(e.equipment));
          }
        }
      }
    });
    test('rep ranges by goal', () {
      final s = makePlan(p(goal: Goal.strength), lib).days.first.items;
      expect((s.first.repLow, s.first.repHigh), (3, 6));
      final z = makePlan(p(goal: Goal.size), lib).days.first.items;
      expect((z.first.repLow, z.first.repHigh), (8, 12));
      final b = makePlan(p(goal: Goal.both), lib).days.first.items;
      expect((b.first.repLow, b.first.repHigh), (5, 8));
      final acc = b.where((i) => !lib.byId(i.exerciseId)!.compound);
      for (final a in acc) {
        expect(a.repLow, greaterThanOrEqualTo(8));
      }
    });
    test('no duplicate exercises in a day', () {
      for (final d in makePlan(p(days: 6, minutes: 90), lib).days) {
        expect(d.items.map((i) => i.exerciseId).toSet().length, d.items.length);
      }
    });
    test('rotation wraps', () {
      final plan = makePlan(p(days: 4), lib);
      expect(nextDayIndex(plan, null), 0);
      expect(nextDayIndex(plan, 2), 3);
      expect(nextDayIndex(plan, 3), 0);
      expect(nextDayIndex(plan, 9), 0); // stale index after days removed
    });
    test('plan json round trip', () {
      final plan = makePlan(p(days: 3), lib);
      final back = Plan.fromJson(plan.toJson());
      expect(back.toJson(), plan.toJson());
    });
  });

  group('plan editing', () {
    test('move, add, remove keep things valid', () {
      final plan = makePlan(Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg), lib);
      final first = plan.days[0].items[0].exerciseId;
      final p2 = plan.moveItem(0, 0, 2);
      expect(p2.days[0].items[2].exerciseId, first);
      expect(p2.userEdited, isTrue);
      final p3 = p2.addDay('Arms');
      expect(p3.days.last.name, 'Arms');
      final p4 = p3.removeDay(0);
      expect(p4.days.length, 4);
      expect(p4.days.first.name, 'Lower A');
      final p5 = p4.addItem(3, PlanItem(exerciseId: 'db_curl', sets: 3, repLow: 10, repHigh: 12, restSec: 60));
      expect(p5.days[3].items.single.exerciseId, 'db_curl');
      final p6 = p5.removeItem(3, 0).moveDay(3, 0);
      expect(p6.days.first.name, 'Arms');
      expect(p6.days.first.items, isEmpty);
      // original untouched (immutable)
      expect(plan.days.length, 4);
      expect(plan.userEdited, isFalse);
    });
  });
}
