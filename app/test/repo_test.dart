import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/units.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('repo');
    path = '${dir.path}/t.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Repo> open() => Repo.open(path, factory: databaseFactoryFfi);

  test('profile and plan persist', () async {
    final r = await open();
    await r.saveProfile(profile);
    final plan = makePlan(profile, lib);
    await r.savePlan(plan);
    await r.close();
    final r2 = await open();
    expect((await r2.profile())!.toJson(), profile.toJson());
    expect((await r2.activePlan())!.toJson(), plan.toJson());
    await r2.close();
  });

  test('logged sets survive the app being killed; open session resumes', () async {
    final r = await open();
    final plan = makePlan(profile, lib);
    await r.savePlan(plan);
    final s = await r.startSession(plan, 0, plan.days[0]);
    await r.logSet(s.id, 'bench_press', 100, 8);
    await r.logSet(s.id, 'bench_press', 100, 7);
    await r.close(); // "killed"
    final r2 = await open();
    final again = await r2.openSession();
    expect(again!.id, s.id);
    expect(again.day.name, plan.days[0].name);
    final sets = await r2.setsFor(s.id);
    expect(sets.map((x) => x.reps), [8, 7]);
    expect(sets.map((x) => x.ord), [0, 1]);
    await r2.close();
  });

  test('finishing applies progression and advances rotation', () async {
    final r = await open();
    final plan = makePlan(profile, lib);
    await r.savePlan(plan);
    final day = plan.days[0];
    final first = day.items.first; // main lift, 5-8 reps
    final s = await r.startSession(plan, 0, day);
    for (var i = 0; i < first.sets; i++) {
      await r.logSet(s.id, first.exerciseId, 100, first.repHigh);
    }
    await r.finishSession(s.id, lib, Unit.kg);
    expect(await r.openSession(), isNull);
    expect((await r.lift(first.exerciseId))!.workKg, greaterThan(100));
    expect(await r.lastDayIndex(plan.id), 0);
    expect(nextDayIndex(plan, await r.lastDayIndex(plan.id)), 1);
    await r.close();
  });

  test('finishing with no sets discards the session and does not advance', () async {
    final r = await open();
    final plan = makePlan(profile, lib);
    await r.savePlan(plan);
    final s = await r.startSession(plan, 0, plan.days[0]);
    await r.finishSession(s.id, lib, Unit.kg);
    expect(await r.history(), isEmpty);
    expect(await r.lastDayIndex(plan.id), isNull);
    await r.close();
  });

  test('history newest first; old plans kept and restorable', () async {
    final r = await open();
    final p1 = makePlan(profile, lib, name: 'one');
    await r.savePlan(p1);
    for (var d = 0; d < 2; d++) {
      final s = await r.startSession(p1, d, p1.days[d]);
      await r.logSet(s.id, p1.days[d].items.first.exerciseId, 50, 5);
      await r.finishSession(s.id, lib, Unit.kg);
    }
    final h = await r.history();
    expect(h.map((s) => s.dayIndex), [1, 0]);
    final p2 = makePlan(profile.copyWith(days: 3), lib, name: 'two');
    await r.savePlan(p2);
    expect((await r.activePlan())!.name, 'two');
    expect((await r.oldPlans()).map((p) => p.name), ['one']);
    await r.restorePlan(p1.id);
    expect((await r.activePlan())!.name, 'one');
    await r.close();
  });

  test('edit and delete sets; wipe clears everything', () async {
    final r = await open();
    final plan = makePlan(profile, lib);
    await r.savePlan(plan);
    final s = await r.startSession(plan, 0, plan.days[0]);
    final a = await r.logSet(s.id, 'bench_press', 100, 8);
    await r.logSet(s.id, 'bench_press', 100, 8);
    await r.updateSet(a.id, 102.5, 6);
    expect((await r.setsFor(s.id)).first.kg, 102.5);
    await r.deleteSet(a.id);
    expect((await r.setsFor(s.id)).length, 1);
    await r.wipe();
    expect(await r.activePlan(), isNull);
    expect(await r.openSession(), isNull);
    await r.close();
  });
}
