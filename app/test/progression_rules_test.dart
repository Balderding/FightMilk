import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/quick.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/progression.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final bench = lib.byId('bench_press')!;
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  tearDown(() {
    progressRules = const ProgressRules();
    e1rmFormula = 'epley';
    stepOverrides.clear();
  });
  List<SetLog> sets(int n, double kg, int reps, {int? effort, SetType type = SetType.work}) =>
      [for (var i = 0; i < n; i++) SetLog(exerciseId: 'bench_press', kg: kg, reps: reps, effort: effort, type: type)];
  final st = LiftState(exerciseId: 'bench_press', workKg: 100);

  test('speeds, effort and AMRAP jumps', () {
    expect(nextLift(st, bench, sets(3, 100, 8), Unit.kg, repLow: 5, repHigh: 8).workKg, 102.5);
    progressRules = const ProgressRules(speed: 'fast');
    expect(nextLift(st, bench, sets(3, 100, 8), Unit.kg, repLow: 5, repHigh: 8).workKg, 105);
    progressRules = const ProgressRules(speed: 'slow');
    final once = nextLift(st, bench, sets(3, 100, 8), Unit.kg, repLow: 5, repHigh: 8);
    expect(once.workKg, 100, reason: 'slow waits for a second session at the top');
    expect(nextLift(once, bench, sets(3, 100, 8), Unit.kg, repLow: 5, repHigh: 8).workKg, 102.5);
    progressRules = const ProgressRules();
    expect(nextLift(st, bench, sets(3, 100, 8, effort: 1), Unit.kg, repLow: 5, repHigh: 8).workKg, 105, reason: 'all easy: two steps');
    expect(nextLift(st, bench, [...sets(2, 100, 8), ...sets(1, 100, 8, effort: 4)], Unit.kg, repLow: 5, repHigh: 8).workKg, 102.5, reason: 'a grind: one step');
    expect(nextLift(st, bench, [...sets(2, 100, 8), ...sets(1, 100, 12, type: SetType.amrap)], Unit.kg, repLow: 5, repHigh: 8).workKg, 105, reason: 'AMRAP 4 over: bigger jump');
    progressRules = const ProgressRules(effort: false);
    expect(nextLift(st, bench, sets(3, 100, 8, effort: 1), Unit.kg, repLow: 5, repHigh: 8).workKg, 102.5);
  });

  test('linear, per-lift step, miss settings', () {
    progressRules = const ProgressRules(scheme: {'bench_press': 'linear'}, stepKg: {'bench_press': 1.0});
    expect(nextLift(st, bench, sets(3, 100, 5), Unit.kg, repLow: 5, repHigh: 8).workKg, 101);
    progressRules = const ProgressRules(missesToDrop: 1, dropPct: 0.05);
    expect(nextLift(st, bench, sets(3, 100, 3), Unit.kg, repLow: 5, repHigh: 8).workKg, 95);
    progressRules = const ProgressRules(missesToDrop: 3);
    var s = nextLift(st, bench, sets(3, 100, 3), Unit.kg, repLow: 5, repHigh: 8);
    s = nextLift(s, bench, sets(3, 100, 3), Unit.kg, repLow: 5, repHigh: 8);
    expect(s.workKg, 100);
    expect(nextLift(s, bench, sets(3, 100, 3), Unit.kg, repLow: 5, repHigh: 8).workKg, 90);
  });

  test('Brzycki', () {
    e1rmFormula = 'brzycki';
    expect(e1rm(100, 5), closeTo(112.5, 0.01));
    e1rmFormula = 'epley';
    expect(e1rm(100, 5), closeTo(116.67, 0.01));
  });

  test('deload week: fewer sets, lighter, progress does not move; bad day keeps weights; time off; rough day', () async {
    final dir = Directory.systemTemp.createTempSync('pr');
    final r = await Repo.open('${dir.path}/p.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(profile);
    await s.makeBuiltInPlan();
    final it0 = s.plan!.days[s.todayIndex].items.first;
    await r.saveLift(LiftState(exerciseId: it0.exerciseId, workKg: 100, updated: DateTime.now()));
    final normalSets = s.today!.items[1].sets;

    await s.setDeload(true);
    expect(s.inDeload, isTrue);
    expect(s.today!.items[1].sets, (normalSets * 0.6).ceil());
    expect((await s.targetFor(s.today!.items.first)).kg, closeTo(90, 1.3));
    var ses = await s.startWorkout();
    for (var i = 0; i < s.today!.items.first.sets; i++) {
      await r.logSet(ses.id, it0.exerciseId, 90, it0.repHigh);
    }
    await s.finishWorkout();
    expect((await r.lift(it0.exerciseId))!.workKg, 100, reason: 'deload does not move the weight');
    await s.setDeload(false);

    // a bad day: misses do not count
    ses = await s.startWorkout();
    for (var i = 0; i < 3; i++) {
      await r.logSet(ses.id, it0.exerciseId, 100, 1);
    }
    await s.finishWorkout(excuse: true, rating: 2);
    final l = await r.lift(it0.exerciseId);
    expect(l!.workKg, 100);
    expect(l.misses, 0);
    // history rebuild keeps both rules
    await s.historyChanged([it0.exerciseId]);
    expect((await r.lift(it0.exerciseId))!.workKg, 100);

    // back after a month: 20 % lighter
    await r.saveLift(LiftState(exerciseId: it0.exerciseId, workKg: 100, updated: DateTime.now().subtract(const Duration(days: 30))));
    final t = await s.targetFor(it0);
    expect(t.kg, closeTo(80, 1.3));
    expect(t.why, contains('Back after'));

    // rough day: one set fewer on accessories, a bit lighter
    final q = quickCommand("I'm exhausted today", s)!;
    await s.runActions('q', q.actions);
    expect(s.feeling, 1);
    expect(s.today!.items[1].sets, normalSets - 1);
    await r.close();
  });
}
