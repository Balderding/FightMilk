import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/backup.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

/// F432 (PLAN-next change 3): the data that FightMilk 0.8.0's own code wrote (test/fixtures,
/// made by work/old080/app/test/zz_make_fixture_test.dart from git 85bbb86) opens in today's app:
/// database v2 -> v3, the settings, profile, gym, plan, lifts, workouts, weigh-in and note all
/// read back as 0.8.0 wrote them, logging still works, and 0.8.0's format-1 backup restores.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final expectJ = jsonDecode(File('test/fixtures/v080_expect.json').readAsStringSync()) as Map<String, dynamic>;

  Future<AppState> open080() async {
    final dir = Directory.systemTemp.createTempSync('m080');
    final path = '${dir.path}/workout.db';
    File('test/fixtures/v080.db').copySync(path);
    final s = await AppState.forTest(await Repo.open(path, factory: databaseFactoryFfi), PackStore(dir.path), lib);
    await s.reload();
    return s;
  }

  test('the fixture is really 0.8.0\'s (database v2)', () {
    expect(expectJ['user_version'], 2);
    expect(expectJ['made_by'], contains('0.8.0'));
  });

  test('0.8.0\'s database opens as v3, and every value reads back as 0.8.0 wrote it', () async {
    final s = await open080();
    expect((await s.repo.db.rawQuery('PRAGMA user_version')).first['user_version'], 3);
    // profile
    final p = s.profile!;
    expect(p.goal, Goal.strength);
    expect(p.days, 3);
    expect(p.minutes, 60);
    expect(p.unit, Unit.kg);
    expect(p.split, 'full_body');
    // settings
    final st = s.settings;
    expect(st.remindDays, [1, 3, 5]);
    expect(st.remindAt, 18 * 60 + 15);
    expect(st.rest, 150);
    expect(st.sound, 'simple');
    expect(st.progSpeed, 'slow');
    expect(st.autoUpdate, isTrue);
    expect(st.warmups, isFalse);
    expect(st.missesToDrop, 3);
    expect(s.loadProblems, isEmpty, reason: 'nothing 0.8.0 wrote fails to read');
    // gym
    expect(s.activeGym?.name, 'Home garage');
    expect(s.activeGym?.maxDumbbellKg, 32);
    // plan, lifts, history, body, note
    expect([for (final d in s.plan!.days) d.name], expectJ['plan_days']);
    for (final e in (expectJ['lift_state'] as Map).entries) {
      final was = jsonDecode(e.value as String) as Map;
      final now = await s.repo.lift(e.key as String);
      expect(now?.workKg, (was['work_kg'] as num).toDouble(), reason: e.key as String);
      expect(now?.misses, was['misses'], reason: e.key as String);
    }
    final counts = expectJ['counts'] as Map;
    for (final t in counts.keys) {
      expect((await s.repo.db.rawQuery('SELECT COUNT(*) c FROM $t')).first['c'], counts[t], reason: t as String);
    }
    expect((await s.repo.db.rawQuery('SELECT COUNT(*) c FROM set_log WHERE slot IS NOT NULL')).first['c'], 0, reason: 'old sets have no slot');
    expect(await s.repo.exNote(expectJ['first_exercise'] as String), 'knees out, brace');
    final body = await s.repo.db.query('body');
    expect(body.single['kg'], 81.4);
    expect(body.single['fat'], 17.5);
    expect((await s.repo.history()).length, 2);
    await s.repo.close();
  });

  test('after the update, logging works and the weights move on from 0.8.0\'s', () async {
    final s = await open080();
    await s.startWorkout();
    final it = s.session!.day.items.first;
    await s.repo.logSet(s.session!.id, it.exerciseId, 62.5, 5, slot: liftKey(it));
    await s.finishWorkout();
    expect((await s.repo.history()).length, 3);
    expect(await s.repo.lift(it.exerciseId), isNotNull);
    await s.repo.close();
  });

  test('0.8.0\'s backup (format 1) restores into today\'s app', () async {
    final text = File('test/fixtures/v080_backup.json').readAsStringSync();
    expect((jsonDecode(text) as Map)['format'], 1);
    final dir = Directory.systemTemp.createTempSync('m080b');
    final s = await AppState.forTest(await Repo.open('${dir.path}/n.db', factory: databaseFactoryFfi), PackStore(dir.path), lib);
    await importBackup(s.repo, text, replace: true);
    await s.reload();
    expect((await s.repo.history()).length, 2);
    expect(s.profile?.goal, Goal.strength);
    expect(s.settings.remindDays, [1, 3, 5]);
    expect(s.activeGym?.name, 'Home garage');
    await s.repo.close();
  });
}
