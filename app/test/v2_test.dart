import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/plan_json.dart';
import 'package:workout/data/backup.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/progression.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final kgProfile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('v2'));
  tearDown(() => stepOverrides.clear());

  Future<Repo> open([String n = 'r']) => Repo.open('${dir.path}/$n.db', factory: databaseFactoryFfi);

  test('library: big, every exercise explained, bands present', () {
    expect(lib.all.length, greaterThanOrEqualTo(250));
    for (final e in lib.all) {
      expect(e.about.length, greaterThanOrEqualTo(40), reason: e.id);
    }
    expect(lib.all.where((e) => e.equipment == Equipment.band), isNotEmpty);
    expect(lib.byId('plank')!.timed, isTrue);
    expect(lib.byId('dead_bug')!.timed, isFalse);
  });

  test('bodyweight added weight is rounded to a step', () {
    final pu = lib.byId('pull_up')!;
    final st = LiftState(exerciseId: pu.id, workKg: 2.7, workReps: pu.repHigh);
    final n = nextLift(st, pu, [SetLog(exerciseId: pu.id, kg: 2.7, reps: pu.repHigh)], Unit.kg);
    expect(n.workKg, 5.0);
  });

  test('custom plate steps are used', () {
    expect(stepIn(StepKind.barbell, Unit.lb), 5);
    stepOverrides[(StepKind.barbell, Unit.lb)] = 2.5;
    expect(stepIn(StepKind.barbell, Unit.lb), 2.5);
  });

  test('AI plan: duplicates in a day and exercises the gym lacks are refused', () {
    String p(List<String> ids) => jsonEncode({
          'name': 'x',
          'days': [
            {'name': 'A', 'items': [for (final i in ids) {'exercise': i, 'sets': 3, 'repLow': 8, 'repHigh': 12, 'rest': 90}]}
          ]
        });
    expect(parsePlan(p(['bench_press', 'bench_press']), lib).plan, isNull);
    final dbOnly = kgProfile.copyWith(have: {Equipment.dumbbell}, avoid: {Joint.knees});
    expect(parsePlan(p(['bench_press']), lib, profile: dbOnly).errors.join(), contains('Bench press'));
    expect(parsePlan(p(['goblet_squat']), lib, profile: dbOnly).errors.join(), contains('knees'));
    expect(parsePlan(p(['db_bench_press']), lib, profile: dbOnly).plan, isNotNull);
  });

  test('set order stays unique after deleting a set', () async {
    final r = await open();
    final plan = makePlan(kgProfile, lib);
    await r.savePlan(plan);
    final s = await r.startSession(plan, 0, plan.days[0]);
    final a = await r.logSet(s.id, 'bench_press', 100, 5);
    await r.logSet(s.id, 'bench_press', 100, 5);
    await r.deleteSet(a.id);
    final c = await r.logSet(s.id, 'bench_press', 110, 3);
    final ords = (await r.setsFor(s.id)).map((x) => x.ord).toList();
    expect(ords.toSet().length, ords.length);
    expect((await r.setsFor(s.id)).last.id, c.id);
    await r.close();
  });

  test('merging a backup made mid-workout does not add a second open workout', () async {
    final a = await open('a');
    final plan = makePlan(kgProfile, lib);
    await a.savePlan(plan);
    await a.startSession(plan, 0, plan.days[0]);
    final text = await exportBackup(a);
    final b = await open('b');
    await b.savePlan(makePlan(kgProfile, lib));
    final mine = await b.startSession((await b.activePlan())!, 0, (await b.activePlan())!.days[0]);
    await importBackup(b, text, replace: false);
    final open2 = await b.db.query('session', where: 'finished IS NULL');
    expect(open2.length, 1);
    expect(open2.first['id'], mine.id);
    await a.close();
    await b.close();
  });

  test('first-time target snaps to the plate grid; picked day survives a restart', () async {
    final r = await open();
    final st = await AppState.forTest(r, PackStore(dir.path), lib);
    await st.saveProfile(kgProfile.copyWith(unit: Unit.lb));
    await st.makeBuiltInPlan();
    final day = st.today!;
    final it = day.items.first;
    // a set logged in kg long ago: 61.2 kg, no lift state yet
    final s = await r.startSession(st.plan!, 0, day);
    await r.logSet(s.id, it.exerciseId, 61.2, 5);
    await r.db.update('session', {'finished': 1});
    final t = await st.targetFor(it);
    final lb = kgToLb(t.kg!);
    expect((lb / 5).roundToDouble() * 5, closeTo(lb, 0.01));

    st.pickDay(2);
    final again = await AppState.forTest(r, PackStore(dir.path), lib);
    expect(again.todayIndex, 2);
    await r.close();
  });

  test('finishing twice does not progress twice', () async {
    final r = await open();
    final plan = makePlan(kgProfile, lib);
    await r.savePlan(plan);
    final it = plan.days[0].items.first;
    final s = await r.startSession(plan, 0, plan.days[0]);
    for (var i = 0; i < it.sets; i++) {
      await r.logSet(s.id, it.exerciseId, 100, it.repHigh);
    }
    await r.finishSession(s.id, lib, Unit.kg);
    final once = (await r.lift(it.exerciseId))!.workKg;
    await r.finishSession(s.id, lib, Unit.kg);
    expect((await r.lift(it.exerciseId))!.workKg, once);
    await r.close();
  });
}
