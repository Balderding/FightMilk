import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/program.dart';
import 'package:workout/domain/programs.dart';
import 'package:workout/domain/progression.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/domain/volume.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

/// Fixes from the review of batches 14-15 (PROGRESS.md "Fix batch 15b").
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fix15b'));
  tearDown(() => progressRules = const ProgressRules());

  Future<AppState> app() async {
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    return s;
  }

  /// Logs [sets] for plan item [i] of the workout going, into that item's own slot.
  Future<void> log(AppState s, int i, List<(double, int)> sets, {bool lastPlus = false}) async {
    final it = s.session!.day.items[i];
    for (var k = 0; k < sets.length; k++) {
      await s.repo.logSet(s.session!.id, it.exerciseId, sets[k].$1, sets[k].$2, slot: liftKey(it), type: lastPlus && k == sets.length - 1 ? SetType.amrap : SetType.work);
    }
  }

  group('P1-1 the same exercise twice in a day', () {
    test('a v2 database upgrades to v3 and keeps its sets (old rows have no slot)', () async {
      final path = '${dir.path}/old.db';
      final db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
              version: 2,
              onCreate: (db, v) async {
                await db.execute('CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
                await db.execute('CREATE TABLE plan (id TEXT PRIMARY KEY, json TEXT NOT NULL, active INTEGER NOT NULL, created INTEGER NOT NULL)');
                await db.execute('CREATE TABLE lift_state (exercise_id TEXT PRIMARY KEY, json TEXT NOT NULL)');
                await db.execute('CREATE TABLE session (id TEXT PRIMARY KEY, plan_id TEXT NOT NULL, day_index INTEGER NOT NULL, day TEXT NOT NULL, '
                    'started INTEGER NOT NULL, finished INTEGER, note TEXT NOT NULL DEFAULT "")');
                await db.execute('CREATE TABLE set_log (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, exercise_id TEXT NOT NULL, kg REAL NOT NULL, '
                    'reps INTEGER NOT NULL, ord INTEGER NOT NULL, at INTEGER NOT NULL)');
                for (final c in ["type TEXT NOT NULL DEFAULT 'work'", 'effort INTEGER', 'rpe REAL', "note TEXT NOT NULL DEFAULT ''", 'rest INTEGER', "side TEXT NOT NULL DEFAULT ''", 'secs INTEGER', 'meters REAL']) {
                  await db.execute('ALTER TABLE set_log ADD COLUMN $c');
                }
                await db.execute("CREATE TABLE body (id TEXT PRIMARY KEY, at INTEGER NOT NULL, kg REAL, fat REAL, json TEXT NOT NULL DEFAULT '{}')");
                await db.execute('CREATE TABLE ex_note (exercise_id TEXT PRIMARY KEY, note TEXT NOT NULL)');
                await db.insert('session', {'id': 's1', 'plan_id': 'p', 'day_index': 0, 'day': '{"name":"A","items":[]}', 'started': 1, 'finished': 2});
                await db.insert('set_log', {'id': 'x1', 'session_id': 's1', 'exercise_id': 'bench_press', 'kg': 100.0, 'reps': 5, 'ord': 0, 'at': 2});
              }));
      await db.close();
      final r = await Repo.open(path, factory: databaseFactoryFfi);
      final old = await r.setsFor('s1');
      expect(old.single.kg, 100);
      expect(old.single.slot, isNull);
      expect(old.single.key, 'bench_press');
      final n = await r.logSet('s1', 'bench_press', 50, 10, slot: 'bench_press#B');
      expect((await r.setsFor('s1')).firstWhere((x) => x.id == n.id).key, 'bench_press#B');
      await r.close();
    });

    test('5/3/1 FSL logged first and a 0-rep 1+ set: the training max does not rise; a hit raises it once', () async {
      final s = await app();
      await s.startProgram(buildProgram(templateById('531_fsl')!, full, lib), {'overhead_press': 100, 'deadlift': 200, 'bench_press': 120, 'back_squat': 150});
      await s.pickDay(8); // W3 · Press
      expect(s.today!.name, 'W3 · Press');
      await s.startWorkout();
      expect(liftKey(s.session!.day.items[1]), 'overhead_press#F');
      await log(s, 1, [for (var i = 0; i < 5; i++) (75.0, 5)]); // FSL first
      await log(s, 0, [(75, 5), (85, 3), (95, 0)], lastPlus: true);
      await s.finishWorkout();
      expect((await s.repo.lift('overhead_press'))!.tm, 100);
      // again with the 1+ hit
      await s.pickDay(8);
      await s.startWorkout();
      await log(s, 1, [for (var i = 0; i < 5; i++) (75.0, 5)]);
      await log(s, 0, [(75, 5), (85, 3), (95, 2)], lastPlus: true);
      await s.finishWorkout();
      expect((await s.repo.lift('overhead_press'))!.tm, 102.5);
      expect(await s.repo.lift('overhead_press#F'), isNull); // the supplement has no weights of its own
    });
  });

  test('P1-8 a weighted lift logged at 0 kg does not get a weight to start from', () async {
    final s = await app();
    await s.startWorkout();
    final it = s.session!.day.items.first;
    expect(lib.byId(it.exerciseId)!.bodyweight, isFalse);
    await log(s, 0, [(0, 8), (0, 8)]);
    await s.finishWorkout();
    expect(await s.repo.lift(it.exerciseId), isNull);
  });

  test('P1-9 "that hurt" lightens program % sets too: 80%, then 90%, then back', () async {
    final s = await app();
    await s.startProgram(buildProgram(templateById('531_base')!, full, lib), {'overhead_press': 100, 'deadlift': 200, 'bench_press': 120, 'back_squat': 150});
    final it = s.today!.items.first;
    expect((await s.targetFor(it)).perSet, [65, 75, 85]);
    await s.flagPain('overhead_press', Joint.shoulders);
    final t1 = await s.targetFor(it);
    expect(t1.perSet, [52.5, 60, 67.5]); // 80% of 65/75/85, to the step
    expect(t1.why, contains('after it hurt'));
    await s.startWorkout();
    await log(s, 0, [(52.5, 5), (60, 5), (67.5, 8)], lastPlus: true);
    await s.finishWorkout();
    await s.pickDay(0);
    final t2 = await s.targetFor(s.today!.items.first);
    expect(t2.perSet, [57.5, 67.5, 77.5]); // 90%
    await s.startWorkout();
    await log(s, 0, [(57.5, 5), (67.5, 5), (77.5, 8)], lastPlus: true);
    await s.finishWorkout();
    await s.pickDay(0);
    expect((await s.targetFor(s.today!.items.first)).perSet, [65, 75, 85]);
  });

  test('P1-4 Madcow: a missed Friday triple keeps the training max and counts a miss; a hit raises it', () {
    final sq = lib.byId('back_squat')!;
    final fri = parseSets('1x5@50 1x5@62.5 1x5@75 1x5@87.5 1x3@102.5 1x8@75');
    final r = templateById('madcow')!.rules['back_squat']!;
    const st = LiftState(exerciseId: 'back_squat', workKg: 100, tm: 100);
    List<SetLog> day(int tripleReps) => [for (var i = 0; i < fri.length; i++) SetLog(exerciseId: 'back_squat', kg: 100 * fri[i].pct!, reps: i == 4 ? tripleReps : fri[i].reps)];
    final miss = programNext(st, r, sq, day(1), fri, Unit.kg, bump: 'tm');
    expect(miss.state.tm, 100);
    expect(miss.state.misses, 1);
    expect(miss.note, contains('a set was short'));
    expect(programNext(st, r, sq, day(3), fri, Unit.kg, bump: 'tm').state.tm, 102.5);
  });

  test('P1-6 Leader and Anchor: week 1 has 3 main sets, each Leader cycle steps up, the 7th week only lowers a max that was too heavy', () {
    final pl = buildProgram(templateById('531_leader_anchor')!, full, lib);
    final w1 = pl.days.first.items.first;
    expect([w1.exerciseId, w1.perSet!.length], ['overhead_press', 3]);
    final w3 = pl.days[8].items.first; // week 3 of the first Leader cycle
    expect(w3.bump, 'tm');
    final press = lib.byId('overhead_press')!;
    final r = templateById('531_leader_anchor')!.rules['overhead_press']!;
    const st = LiftState(exerciseId: 'overhead_press', workKg: 70, tm: 100);
    final up = programNext(st, r, press, [for (final x in w3.perSet!) SetLog(exerciseId: 'overhead_press', kg: 100 * x.pct!, reps: x.reps)], w3.perSet!, Unit.kg, bump: w3.bump).state;
    expect(up.tm, 102.5);
    final seventh = pl.days.firstWhere((d) => d.name.contains('7th week')).items.first;
    expect(seventh.bump, 'check');
    List<SetLog> test(int reps) => [for (var i = 0; i < 4; i++) SetLog(exerciseId: 'overhead_press', kg: 100 * seventh.perSet![i].pct!, reps: i == 3 ? reps : seventh.perSet![i].reps)];
    expect(programNext(st, r, press, test(4), seventh.perSet!, Unit.kg, bump: 'check').state.tm, 100);
    expect(programNext(st, r, press, test(1), seventh.perSet!, Unit.kg, bump: 'check').state.tm, 90);
  });

  test('P1-7 lb: every weight from 45 to 315 moves on Greyskull, never stuck twice (half steps carried)', () {
    final bench = lib.byId('bench_press')!;
    final r = templateById('greyskull')!.rules['bench_press']!;
    final plan = parseSets('2x5 1x5+');
    for (var lb = 45.0; lb <= 315; lb += 5) {
      var st = LiftState(exerciseId: 'bench_press', workKg: lbToKg(lb));
      final seen = <double>[];
      for (var k = 0; k < 4; k++) {
        final kg = st.workKg;
        st = programNext(st, r, bench, [for (final x in plan) SetLog(exerciseId: 'bench_press', kg: kg, reps: x.reps)], plan, Unit.lb).state;
        seen.add(double.parse(fmtWeight(st.workKg, Unit.lb)));
      }
      expect(seen, [lb, lb + 5, lb + 5, lb + 10], reason: 'from $lb lb');
    }
    // whole steps still go up every time, kg too
    final sq = lib.byId('back_squat')!;
    final st = programNext(const LiftState(exerciseId: 'back_squat', workKg: 100), templateById('greyskull')!.rules['back_squat']!, sq,
        [for (final x in plan) SetLog(exerciseId: 'back_squat', kg: 100, reps: x.reps)], plan, Unit.kg).state;
    expect([st.workKg, st.carry], [102.5, 0]);
  });

  test('P1-5 a training max means what the program means: 1RM, best 5, or about 90%; a test can lower it', () {
    expect(templateById('smolov_jr')!.tmBasis, '1rm');
    expect(templateById('madcow')!.tmBasis, '5rm');
    expect(templateById('531_base')!.tmBasis, 'tm90');
    expect(buildProgram(templateById('smolov_jr')!, full, lib).program!.basis, '1rm');
    final sq = lib.byId('back_squat')!;
    const r = LiftRule(kind: 'tm', inc: 1);
    const st = LiftState(exerciseId: 'back_squat', workKg: 90, tm: 100);
    // Smolov Jr, 1RM 100, a test single at 105: the new max is 105
    expect(programNext(st, r, sq, [const SetLog(exerciseId: 'back_squat', kg: 105, reps: 1)], parseSets('1x1+@100'), Unit.kg, bump: 'test', basis: '1rm').state.tm, 105);
    // Madcow, a first workout of 100 x 5: the max (best 5) is 100
    expect(programNext(const LiftState(exerciseId: 'back_squat', workKg: 100), r, sq, [const SetLog(exerciseId: 'back_squat', kg: 100, reps: 5)], parseSets('1x5@100'), Unit.kg, basis: '5rm').state.tm, 100);
    // a bad test on a 90% max goes down
    final down = programNext(st, r, sq, [const SetLog(exerciseId: 'back_squat', kg: 100, reps: 1)], parseSets('1x1+@100'), Unit.kg, bump: 'test').state;
    expect(down.tm, 90);
    expect(tmBasisText['5rm'], contains('5 good reps'));
  });

  test('P1-10 careful mode while pregnant leaves out every exercise lying on the back or front (from the data)', () {
    final c = cautionIds('pregnant', lib);
    for (final e in lib.all.where((e) => e.position == 'supine' || e.position == 'prone')) {
      expect(c, contains(e.id), reason: '${e.id} is done lying ${e.position == 'supine' ? 'on the back' : 'on the front'}');
    }
    expect(c, containsAll(['close_grip_bench', 'glute_bridge', 'barbell_glute_bridge', 'jm_press', 'lying_leg_curl']));
    expect(c, isNot(contains('deficit_deadlift'))); // done standing
    expect(c, isNot(contains('hip_thrust')));
    expect(cautionIds('postpartum', lib), isNot(contains('bench_press')));
    expect(lib.byId('bench_press')!.position, 'supine');
  });

  test('P2-8 careful mode says what it changed; a day where nothing fits is empty, never a left-out exercise', () async {
    final s = await app();
    await s.saveProfile(s.profile!.copyWith(pregnancy: 'pregnant', have: {Equipment.barbell, Equipment.dumbbell}));
    await s.usePlan(Plan(name: 'old', days: [
      PlanDay(name: 'A', items: [PlanItem(exerciseId: 'bench_press', sets: 3, repLow: 5, repHigh: 8, restSec: 120), PlanItem(exerciseId: 'skull_crusher', sets: 3, repLow: 8, repHigh: 12, restSec: 90)]),
      PlanDay(name: 'B', items: [PlanItem(exerciseId: 'crunch', sets: 3, repLow: 10, repHigh: 15, restSec: 60)]),
    ]));
    final d = s.today!;
    expect(d.items.map((i) => i.exerciseId).toSet().intersection(cautionIds('pregnant', lib)), isEmpty);
    expect(s.carefulNote, startsWith('Careful mode:'));
    // day B: only crunches; with no machines, cables or bands the swaps are all left out too
    await s.pickDay(1);
    final b = s.today!;
    expect(b.items.where((i) => lib.caution.contains(i.exerciseId)), isEmpty);
    if (b.items.isEmpty) expect(s.carefulNote, contains('left out'));
  });

  test('P2-5 a training-max box takes a recent set; an empty one needs only the first weight of the day', () async {
    expect(parseMaxInput('100', Unit.kg, 'tm90'), 100);
    expect(parseMaxInput('100 x 5', Unit.kg, 'tm90'), closeTo(0.9 * 100 * (1 + 5 / 30), 0.01));
    expect(parseMaxInput('100x5', Unit.kg, '1rm'), closeTo(100 * (1 + 5 / 30), 0.01));
    expect(parseMaxInput('225×3', Unit.lb, '5rm'), isNotNull);
    expect(parseMaxInput('lots', Unit.kg, 'tm90'), isNull);
    final s = await app();
    await s.startProgram(buildProgram(templateById('nsuns_4')!, full, lib), {'bench_press': null, 'overhead_press': 50, 'back_squat': 100, 'deadlift': 140});
    final it = s.today!.items.first;
    expect(it.exerciseId, 'bench_press');
    await s.startWorkout();
    expect((await s.targetFor(it)).perSet!.every((x) => x == null), isTrue);
    await log(s, 0, [(75, 5)]); // first set: 75% of the max
    final t = await s.targetFor(it);
    expect(t.perSet![1], 85); // 85% of 100
    expect(t.perSet![2], 95);
    expect(t.why, contains('first set'));
  });

  test('P2-7 ramp sets under 65% do not count as hard sets in the weekly volume', () {
    final ns = buildProgram(templateById('nsuns_4')!, full, lib);
    final w = planWeekSets(ns, lib);
    // the review counted 33 shoulder sets with the ramps; what is left is the program's real work
    expect(w['shoulders']!, lessThanOrEqualTo(28), reason: 'shoulders ${w['shoulders']}');
    expect(statusOf('core', w['core'] ?? 0, full), isNot(VolumeStatus.tooMuch), reason: 'core ${w['core']}');
    expect(statusOf('chest', w['chest']!, full), isNot(VolumeStatus.tooMuch), reason: 'chest ${w['chest']}');
    final base = buildProgram(templateById('531_base')!, full, lib);
    expect(hardSets(base.days.first.items.first), 3); // 65/75/85
    final madcow = buildProgram(templateById('madcow')!, full, lib);
    expect(hardSets(madcow.days.first.items.first), 3); // 75, 87.5, 100 count; 50 and 62.5 do not
  });

  test('P2-9 a program week does not leak its light or heavy sets into another plan', () async {
    final s = await app();
    final old = s.plan!;
    await s.repo.saveLift(const LiftState(exerciseId: 'bench_press', workKg: 80));
    await s.startProgram(buildProgram(templateById('531_base')!, full, lib), {'overhead_press': 60, 'deadlift': 160, 'bench_press': 100, 'back_squat': 140});
    await s.pickDay(10); // W3 · Bench: 75/85/95
    expect(s.today!.name, 'W3 · Bench');
    await s.startWorkout();
    await log(s, 0, [(75, 5), (85, 3), (95, 3)], lastPlus: true);
    await s.finishWorkout();
    final st = (await s.repo.lift('bench_press'))!;
    expect(st.tm, 102.5);
    expect(st.workKg, 80, reason: 'the 95% single is not the working weight of the other plan');
    await s.restorePlan(old.id);
    final it = s.plan!.days.expand((d) => d.items).firstWhere((x) => x.exerciseId == 'bench_press');
    expect((await s.targetFor(it)).kg, 80);
  });
}
