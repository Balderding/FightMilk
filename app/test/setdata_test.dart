import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/quick.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/backup.dart';
import 'package:workout/data/csv_export.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sd'));
  tearDown(() => stepOverrides.clear());

  test('a phone with the old database keeps its workouts after the upgrade', () async {
    final path = '${dir.path}/old.db';
    final old = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
      await db.execute('CREATE TABLE plan (id TEXT PRIMARY KEY, json TEXT NOT NULL, active INTEGER NOT NULL, created INTEGER NOT NULL)');
      await db.execute('CREATE TABLE lift_state (exercise_id TEXT PRIMARY KEY, json TEXT NOT NULL)');
      await db.execute('CREATE TABLE session (id TEXT PRIMARY KEY, plan_id TEXT NOT NULL, day_index INTEGER NOT NULL, day TEXT NOT NULL, started INTEGER NOT NULL, finished INTEGER, note TEXT NOT NULL DEFAULT "")');
      await db.execute('CREATE TABLE set_log (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, exercise_id TEXT NOT NULL, kg REAL NOT NULL, reps INTEGER NOT NULL, ord INTEGER NOT NULL, at INTEGER NOT NULL)');
    }));
    await old.insert('session', {'id': 's1', 'plan_id': 'p', 'day_index': 0, 'day': jsonEncode({'name': 'A', 'items': []}), 'started': 1, 'finished': 2});
    await old.insert('set_log', {'id': 'x1', 'session_id': 's1', 'exercise_id': 'bench_press', 'kg': 100.0, 'reps': 5, 'ord': 0, 'at': 1});
    await old.close();

    final r = await Repo.open(path, factory: databaseFactoryFfi);
    final sets = await r.setsFor('s1');
    expect(sets.single.kg, 100);
    expect(sets.single.type, SetType.work);
    expect(sets.single.counts, isTrue);
    await r.logBody(80);
    expect((await r.bodyLog()).single.$3, 80);
    await r.close();
  });

  test('warm-ups and drop sets do not move next time\'s weight; effort, notes, body weight saved', () async {
    final r = await Repo.open('${dir.path}/a.db', factory: databaseFactoryFfi);
    final plan = makePlan(profile, lib);
    await r.savePlan(plan);
    final it = plan.days[0].items.first;
    final s = await r.startSession(plan, 0, plan.days[0]);
    await r.logSet(s.id, it.exerciseId, 40, 10, type: SetType.warmup);
    for (var i = 0; i < it.sets; i++) {
      final x = await r.logSet(s.id, it.exerciseId, 100, it.repHigh, rest: 150);
      await r.updateSetInfo(x.id, effort: 2);
    }
    final d = await r.logSet(s.id, it.exerciseId, 80, 12, type: SetType.drop);
    await r.updateSetInfo(d.id, note: 'burned', rpe: 10);
    await r.finishSession(s.id, lib, Unit.kg);
    final st = await r.lift(it.exerciseId);
    expect(st!.workKg, greaterThan(100), reason: 'all planned sets hit the top: weight goes up from 100, the 40 and 80 are ignored');
    final all = await r.setsFor(s.id);
    expect(all.where((x) => x.counts).length, it.sets);
    expect(all.firstWhere((x) => x.type == SetType.drop).note, 'burned');
    expect(all.where((x) => x.effort == 2).length, it.sets);
    expect(all[1].rest, 150);

    await r.setExNote(it.exerciseId, 'seat 4');
    expect(await r.exNote(it.exerciseId), 'seat 4');

    // backup carries the new parts; an old backup without them still imports
    final text = await exportBackup(r);
    expect(jsonDecode(text)['ex_note'], isNotEmpty);
    final b = await Repo.open('${dir.path}/b.db', factory: databaseFactoryFfi);
    await importBackup(b, text, replace: true);
    expect(await b.exNote(it.exerciseId), 'seat 4');
    expect((await b.setsFor(s.id)).firstWhere((x) => x.type == SetType.drop).rpe, 10);
    // a backup from before 0.8 (no body, no notes) was format 1, with no check (batch 22)
    final oldStyle = (jsonDecode(text) as Map<String, dynamic>)
      ..remove('body')
      ..remove('ex_note')
      ..remove('sha256')
      ..remove('schema')
      ..['format'] = 1;
    final c = await Repo.open('${dir.path}/c.db', factory: databaseFactoryFfi);
    await importBackup(c, jsonEncode(oldStyle), replace: true);
    expect((await c.setsFor(s.id)).length, all.length);

    // CSV: W / D marks, RPE from the effort tap, the set note
    final csv = await exportCsv(r, lib, Unit.kg);
    final name = lib.byId(it.exerciseId)!.name;
    expect(csv, contains('"$name","W","40"'));
    expect(csv, contains('"$name","1","100"'));
    expect(csv, contains('"$name","D","80","12","0","0","burned"'));
    expect(csv, contains('"7.5"'));
    for (final x in [r, b, c]) {
      await x.close();
    }
  });

  test('"with drop sets" and the style tool set the last-set style; "I weigh 82 kg" logs it', () async {
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(profile);
    await s.makeBuiltInPlan();
    final q = quickCommand('chest and arms workout with drop sets', s)!;
    await s.runActions('q', q.actions);
    expect(s.today!.items.first.style, '');
    expect(s.today!.items.skip(1).every((i) => i.style == 'drop'), isTrue);
    final first = s.today!.items.first.exerciseId;
    final t = parseToolReply('DO: style $first amrap today', s);
    expect(t.errors, isEmpty);
    await s.runActions('t', t.actions);
    expect(s.today!.items.first.style, 'amrap');
    final w = quickCommand('I weigh 82 kg', s)!;
    await s.runActions('w', w.actions);
    expect((await r.bodyLog()).single.$3, closeTo(82, 0.01));
    // plan JSON keeps the style
    expect(PlanItem.fromJson(s.today!.items.first.toJson()).style, 'amrap');
    await r.close();
  });
}
