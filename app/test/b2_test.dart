import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/export.dart';
import 'package:workout/data/recovery.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/main.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/services/crash_log.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/recovery_screen.dart';
import 'package:workout/ui/shortcuts.dart';

/// Batch B2 (PLAN-next with the evaluation's changes): a safe start, the recovery screen, the
/// local crash log, the AI's network switches, the database copy, and the link reader.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg, bodyKg: 82.5);

  Future<AppState> app(String path) async {
    final s = await AppState.forTest(await Repo.open(path, factory: databaseFactoryFfi), PackStore(File(path).parent.path), lib);
    await s.saveProfile(profile);
    await s.makeBuiltInPlan();
    return s;
  }

  group('F430 crash log: only the kind of error and where, never its words', () {
    test('a database error with a note and a FormatException with a profile row leave no words', () async {
      final dir = Directory.systemTemp.createTempSync('b2log');
      final log = CrashLog(File('${dir.path}/crash_log.json'));
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      Object? dbErr;
      StackTrace? dbSt;
      try {
        await db.rawQuery('SELECT * FROM no_such_table WHERE note = ?', ['knee pain on the left']);
      } catch (e, st) {
        dbErr = e;
        dbSt = st;
      }
      expect(dbErr.toString(), contains('knee pain'), reason: 'the raw error does carry the note');
      await log.record(dbErr!, dbSt);
      await log.record(const FormatException('bad', '{"bodyKg": 82.5, "notes": "sore shoulder"}'), StackTrace.fromString('#0 readProfile (package:workout/x.dart:12:3)\n#1 load (/data/user/0/org.balderding.workout/files/photos/IMG_2026.jpg:1:1)'));
      final text = await log.text();
      for (final word in ['knee pain', 'no_such_table', 'SELECT', '82.5', 'bodyKg', 'sore shoulder', 'IMG_2026']) {
        expect(text, isNot(contains(word)), reason: word);
      }
      expect(text, contains('FormatException'));
      expect(text, contains('readProfile'), reason: 'where it happened stays');
      final raw = await log.file.readAsString();
      expect(raw, isNot(contains('knee pain')));
      await db.close();
    });

    test('only the newest five are kept; a broken file reads as empty', () async {
      final dir = Directory.systemTemp.createTempSync('b2log2');
      final log = CrashLog(File('${dir.path}/crash_log.json'));
      for (var i = 0; i < 8; i++) {
        await log.record(StateError('$i'), StackTrace.current);
      }
      expect((await log.entries()).length, CrashLog.keep);
      await log.file.writeAsString('{not json');
      expect(await log.entries(), isEmpty);
      await log.record(StateError('x'), null);
      expect((await log.entries()).length, 1);
    });
  });

  group('F431 recovery: a copy, never the original; a normal backup out of it', () {
    test('the newest workout in the WAL comes along; the photo list, the server and body data stay out', () async {
      final dir = Directory.systemTemp.createTempSync('b2rec');
      final path = '${dir.path}/workout.db';
      final s = await app(path);
      // WAL on, no automatic checkpoint: the newest writes stay in workout.db-wal (PLAN-next change 12)
      await s.repo.db.rawQuery('PRAGMA journal_mode=WAL');
      await s.repo.db.rawQuery('PRAGMA wal_autocheckpoint=0');
      await s.startWorkout();
      await s.repo.logSet(s.session!.id, s.session!.day.items.first.exerciseId, 61.5, 7);
      await s.finishWorkout();
      await s.repo.kvSet('photos', jsonEncode([{'file': 'IMG_1.jpg', 'at': 1}]));
      await s.repo.kvSet('webdav', jsonEncode({'url': 'https://cloud.example.org/dav', 'user': 'me'}));
      await s.repo.logBody(81.0);
      expect(File('$path-wal').lengthSync(), greaterThan(0), reason: 'the test really has a WAL');
      // the main file alone does not hold the workout: a copy of it alone would lose it
      final alone = '${dir.path}/alone.db';
      File(path).copySync(alone);
      final a = await databaseFactoryFfi.openDatabase(alone);
      final aloneSets = (await a.rawQuery('SELECT COUNT(*) c FROM set_log')).first['c'];
      await a.close();
      final before = File(path).readAsBytesSync();
      final work = Directory('${dir.path}/support')..createSync();
      final out = await recoveryBackup(path, work, body: false, factory: databaseFactoryFfi);
      final j = jsonDecode(out) as Map<String, dynamic>;
      expect((j['set_log'] as List).length, greaterThan(aloneSets as int), reason: 'the WAL rows reached the backup');
      expect(out, contains('61.5'));
      expect(out, isNot(contains('IMG_1.jpg')));
      expect(out, isNot(contains('"photos"')));
      expect(out, isNot(contains('cloud.example.org')));
      expect(j['body'], isEmpty, reason: 'no body data unless the person says yes');
      expect(out, isNot(contains('82.5')), reason: "the profile's body weight is out too");
      expect(File(path).readAsBytesSync(), before, reason: 'the original file is unchanged');
      expect(recoveryDir(work).existsSync(), isFalse, reason: 'the private copy is cleared');
      final withBody = jsonDecode(await recoveryBackup(path, work, body: true, factory: databaseFactoryFfi)) as Map<String, dynamic>;
      expect(withBody['body'], isNotEmpty);
      await s.repo.close();
    });

    test('a file even the copy cannot open: a plain reason, nothing changed, no copy left', () async {
      final dir = Directory.systemTemp.createTempSync('b2bad');
      final path = '${dir.path}/workout.db';
      File(path).writeAsStringSync('this is not a database ' * 200);
      final before = File(path).readAsBytesSync();
      final work = Directory('${dir.path}/support')..createSync();
      await expectLater(() => recoveryBackup(path, work, body: false, factory: databaseFactoryFfi), throwsA(isA<StartFailure>().having((e) => e.reason, 'reason', 'The data file is damaged.')));
      expect(File(path).readAsBytesSync(), before);
      expect(recoveryDir(work).existsSync(), isFalse);
    });

    test('plain reasons, never the database text; a leftover copy is cleaned at start', () {
      expect(plainReason(Exception('SqliteException(13): database or disk is full')), contains('storage is full'));
      expect(plainReason(Exception('file is not a database')), 'The data file is damaged.');
      expect(plainReason(Exception('database is locked')), contains('in use'));
      expect(plainReason(Exception('whatever SELECT * FROM x')), 'The data file could not be read.');
      final dir = Directory.systemTemp.createTempSync('b2left');
      recoveryDir(dir).createSync();
      File('${recoveryDir(dir).path}/workout.db').writeAsStringSync('x');
      cleanRecoveryLeftovers(dir);
      expect(recoveryDir(dir).existsSync(), isFalse);
    });

    testWidgets('the first start fails: the recovery screen says why and where; Try again starts the app', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('b2retry');
      late AppState s;
      await tester.runAsync(() async {
        s = await AppState.forTest(await Repo.open('${dir.path}/r.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
        await s.saveProfile(profile);
        await s.makeBuiltInPlan();
      });
      var calls = 0;
      Future<AppState> loader() async {
        calls++;
        if (calls == 1) throw StartFailure('/data/user/0/org.balderding.workout/databases/workout.db', Exception('database or disk is full'));
        return s;
      }

      await tester.pumpWidget(WorkoutApp(loader: loader));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(RecoveryScreen), findsOneWidget);
      expect(find.textContaining('storage is full'), findsOneWidget);
      expect(find.textContaining('Where: /data/user/0/org.balderding.workout/databases/workout.db'), findsOneWidget);
      expect(find.text('Save a copy of my data'), findsOneWidget);
      expect(find.textContaining('Reset'), findsNothing, reason: 'no reset in recovery');
      await tester.tap(find.text('Try again'));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(calls, 2);
      expect(find.byType(RecoveryScreen), findsNothing);
      expect(find.text('Today'), findsWidgets, reason: 'the app started');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('PLAN-next change 12: a database copy takes its WAL along', () {
    test('without VACUUM INTO (older phones) the copy still holds the newest rows', () async {
      final dir = Directory.systemTemp.createTempSync('b2copy');
      final db = await databaseFactoryFfi.openDatabase('${dir.path}/x.db');
      await db.rawQuery('PRAGMA journal_mode=WAL');
      await db.rawQuery('PRAGMA wal_autocheckpoint=0');
      await db.execute('CREATE TABLE t (v TEXT)');
      await db.insert('t', {'v': 'newest'});
      expect(File('${dir.path}/x.db-wal').lengthSync(), greaterThan(0));
      await copyDatabase(db, '${dir.path}/copy.db', vacuumInto: false);
      final c = await databaseFactoryFfi.openDatabase('${dir.path}/copy.db');
      expect(await c.query('t'), [{'v': 'newest'}]);
      await c.close();
      await db.close();
    });
  });

  group('PLAN-next change 8: the AI may not change its own oversight; network on always asks', () {
    test('the preview switch is not the AI\'s; turning on update or icon checks always asks', () async {
      final dir = Directory.systemTemp.createTempSync('b2ai');
      final s = await app('${dir.path}/a.db');
      final r = parseToolReply('SAY: ok\nDO: setting preview off', s);
      expect(r.errors, isNotEmpty);
      expect(r.errors.join(' '), contains('cannot change its own setup'));
      for (final k in ['auto_update', 'auto_icons']) {
        expect(parseToolReply('SAY: ok\nDO: setting $k on', s).actions.single.alwaysAsk, isTrue, reason: '$k on');
        expect(parseToolReply('SAY: ok\nDO: setting $k off', s).actions.single.alwaysAsk, isFalse, reason: '$k off');
      }
      expect(toolHelp(s.lib), isNot(contains('setting preview')));
      expect(toolHelpShort(), isNot(contains('setting preview')));
      await s.repo.close();
    });
  });

  test('121eda3 review: the link reader never throws and never fills in an odd number', () {
    final rnd = Random(7);
    const parts = ['fightmilk://', 'weight', 'start', 'last', '?kg=', '?lb=', '&kg=', '1e9', '-0', 'NaN', 'Infinity', ' 80 ', '80', '%20', '#', '/', '..', 'KG=', '٨٠', '0x50', '80.5.5', ''];
    for (var i = 0; i < 3000; i++) {
      final link = [for (var k = 0; k < 1 + rnd.nextInt(6); k++) parts[rnd.nextInt(parts.length)]].join();
      final l = readLink(link);
      if (l?.kg != null) expect(l!.kg!, inInclusiveRange(20, 400), reason: link);
    }
    for (final odd in ['fightmilk://weight?kg=1e9', 'fightmilk://weight?kg=Infinity', 'fightmilk://weight?lb=1e3', 'fightmilk://weight?kg=0x50']) {
      expect(readLink(odd)!.kg, isNull, reason: odd);
    }
    expect(readLink('fightmilk://weight?kg=80&kg=90')!.kg, anyOf(80, 90));
    expect(readLink('fightmilk://weight?kg=%2080%20')?.kg, anyOf(isNull, 80.0));
  });
}
