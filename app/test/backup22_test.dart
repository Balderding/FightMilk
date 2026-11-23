import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/ai.dart';
import 'package:workout/data/backup.dart';
import 'package:workout/data/import_store.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/import.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/programs.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

/// Batch 22 backups (F338, F341, F344, F345) and the rules from the start: every backup restores
/// whole; old files restore; a bad file changes nothing; a merge never duplicates; no photo and
/// no key in it.
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
    final a = (c.arguments as Map?) ?? {};
    switch (c.method) {
      case 'write':
        store[a['key'] as String] = a['value'] as String;
      case 'read':
        return store[a['key']];
      case 'deleteAll':
        store.clear();
    }
    return null;
  });
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  Future<AppState> blank() async {
    final dir = Directory.systemTemp.createTempSync('bk22');
    return AppState.forTest(await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi), PackStore(dir.path), lib);
  }

  /// A phone with a bit of everything: a program, workouts, body data, tape, a goal, an import,
  /// a photo and an API key.
  Future<AppState> filled() async {
    final s = await blank();
    await s.saveProfile(full.copyWith(bodyKg: 82.4, heightCm: 181.5));
    await s.startProgram(buildProgram(templateById('531_bbb')!, full, lib), {'overhead_press': 50, 'deadlift': 140, 'bench_press': 90, 'back_squat': 120});
    for (var w = 0; w < 2; w++) {
      final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
      await s.repo.logSet(ses.id, 'back_squat', 100 + w * 2.5, 5);
      await s.repo.logSet(ses.id, 'plank', 0, 60);
      await s.repo.finishSession(ses.id, s.lib, s.unit);
    }
    await s.repo.logBody(81.7, fat: 17.3);
    await s.addTape('waist', 86.4);
    await s.addAim('body', 77.7);
    final r = readImport('Date,Exercise,Weight,Reps\n2025-06-01 18:00,Deadlift,150,5\n', appUnit: Unit.kg);
    await saveImport(s.repo, r, {'Deadlift': 'deadlift'}, label: 'Strong');
    AppState.clearPicked = () async {};
    await s.addPhoto([1, 2, 3, 4]);
    await s.secrets.setKey(AiKind.claude, 'sk-test-SECRET-KEY-123');
    await s.reload();
    return s;
  }

  /// Every exportable row of every table, sorted, for an exact compare.
  Future<Map<String, List<String>>> dump(Repo r, {bool body = true}) async {
    final out = <String, List<String>>{};
    for (final t in ['plan', 'lift_state', 'session', 'set_log', 'body', 'ex_note']) {
      out[t] = [for (final row in await r.db.query(t)) jsonEncode(row)]..sort();
    }
    out['kv'] = [for (final row in exportKvRows(await r.db.query('kv'), body: body)) jsonEncode(row)]..sort();
    return out;
  }

  group('round trip', () {
    test('backup -> a fresh app -> restore: every table and setting equal (with body data)', () async {
      final s = await filled();
      final file = await exportBackup(s.repo);
      final t = await blank();
      await importBackup(t.repo, file, replace: true);
      expect(await dump(t.repo), await dump(s.repo));
      await t.reload();
      expect(t.plan!.program, isNotNull, reason: 'the program comes back');
      expect((await importRecords(t.repo)).single.label, 'Strong', reason: 'the import list comes along');
    });

    test('without body data: everything else equal, no body data at all', () async {
      final s = await filled();
      final file = await exportBackup(s.repo, body: false);
      final t = await blank();
      await importBackup(t.repo, file, replace: true);
      final a = await dump(t.repo, body: false), b = await dump(s.repo, body: false);
      for (final k in a.keys) {
        if (k == 'body') continue;
        expect(a[k], b[k], reason: k);
      }
      expect(a['body'], isEmpty);
      for (final n in ['81.7', '17.3', '86.4', '82.4', '181.5', '77.7']) {
        expect(file, isNot(contains(n)), reason: n);
      }
    });

    test('Undo of an import still works after a restore', () async {
      final s = await filled();
      final t = await blank();
      await importBackup(t.repo, await exportBackup(s.repo), replace: true);
      final rec = (await importRecords(t.repo)).single;
      final before = (await t.repo.history()).length;
      await undoImport(t.repo, rec.id);
      expect((await t.repo.history()).length, before - 1);
    });

    test('no photo and no key in any backup', () async {
      final s = await filled();
      final id = s.photos.single['id'] as String;
      for (final body in [true, false]) {
        final f = await exportBackup(s.repo, body: body);
        expect(f, isNot(contains(id)));
        expect(f, isNot(contains('"photos"')));
        expect(f, isNot(contains('sk-test-SECRET')));
        expect(f, isNot(contains('ai_key')));
      }
      expect(store.values, contains('sk-test-SECRET-KEY-123'), reason: 'the key is in secure storage, not the database');
    });
  });

  test('an older backup (format 1, no check) still restores', () async {
    final s = await filled();
    final j = jsonDecode(await exportBackup(s.repo)) as Map<String, dynamic>
      ..['format'] = 1
      ..remove('schema')
      ..remove('sha256')
      ..remove('kv');
    j['kv'] = [for (final row in exportKvRows(await s.repo.db.query('kv'), body: true)) if (row['k'] != 'imports') row]; // format 1 had no import list
    final t = await blank();
    await importBackup(t.repo, jsonEncode(j), replace: true);
    expect((await t.repo.history()).length, (await s.repo.history()).length);
  });

  group('a bad file changes nothing', () {
    Future<void> refused(String text, String why) async {
      final s = await filled();
      final before = await dump(s.repo);
      await expectLater(() => importBackup(s.repo, text, replace: true), throwsA(isA<BackupError>()), reason: why);
      expect(await dump(s.repo), before, reason: '$why: nothing changed');
    }

    test('cut short, damaged, wrong kinds, newer, too big', () async {
      final s = await filled();
      final good = await exportBackup(s.repo);
      for (final n in [10, good.length ~/ 3, good.length ~/ 2, good.length - 5]) {
        await refused(good.substring(0, n), 'cut at $n');
      }
      await refused(good.replaceFirst('"reps": 5', '"reps": 6'), 'one number changed: the check does not match');
      final j = jsonDecode(good) as Map<String, dynamic>;
      (j['set_log'] as List).first['reps'] = 'five';
      j['sha256'] = 'x';
      await refused(jsonEncode(j), 'a wrong kind');
      final k = jsonDecode(good) as Map<String, dynamic>..['format'] = 9;
      await refused(jsonEncode(k), 'from a newer app');
      await refused('{"app":"workout","format":2}', 'no parts');
      await refused('not json at all', 'not a backup');
      expect(() => importBackup(s.repo, 'x' * (backupMaxBytes + 1), replace: true), throwsA(isA<BackupError>()));
    });

    test('a wrong row kind without a check (format 1) is still caught before writing', () async {
      final s = await filled();
      final j = jsonDecode(await exportBackup(s.repo)) as Map<String, dynamic>
        ..['format'] = 1
        ..remove('sha256');
      (j['session'] as List).first['started'] = 'yesterday';
      await refused(jsonEncode(j), 'format 1 with a bad row');
    });
  });

  group('merge', () {
    test('merging the same backup twice adds nothing twice', () async {
      final s = await filled();
      final file = await exportBackup(s.repo);
      final before = await dump(s.repo);
      await importBackup(s.repo, file, replace: false);
      await importBackup(s.repo, file, replace: false);
      final after = await dump(s.repo);
      for (final t in ['session', 'set_log', 'body', 'lift_state']) {
        expect(after[t]!.length, before[t]!.length, reason: t);
      }
    });

    test('the same workouts and weigh-ins under other ids (another phone) are not doubled', () async {
      final s = await filled();
      final j = jsonDecode(await exportBackup(s.repo)) as Map<String, dynamic>;
      for (final row in j['session'] as List) {
        final old = row['id'];
        row['id'] = 'other-$old';
        for (final x in j['set_log'] as List) {
          if (x['session_id'] == old) x['session_id'] = 'other-$old';
        }
      }
      for (final x in j['set_log'] as List) {
        x['id'] = 'other-${x['id']}';
      }
      for (final x in j['body'] as List) {
        x['id'] = 'other-${x['id']}';
      }
      j.remove('sha256');
      j['format'] = 1;
      final sessions = (await s.repo.db.query('session')).length, bodies = (await s.repo.db.query('body')).length;
      await importBackup(s.repo, jsonEncode(j), replace: false);
      expect((await s.repo.db.query('session')).length, sessions);
      expect((await s.repo.db.query('body')).length, bodies);
    });
  });

  group('F338 locked with a password', () {
    test('locked and opened again; a wrong password says so and changes nothing', () async {
      final s = await filled();
      final plain = await exportBackup(s.repo);
      final locked = await lockBackup(plain, 'correct horse battery');
      expect(locked, isNot(contains('back_squat')), reason: 'nothing readable inside');
      expect(isLockedBackup(locked), isTrue);
      expect(await unlockBackup(locked, 'correct horse battery'), plain);
      final t = await blank();
      await expectLater(() => importBackup(t.repo, locked, replace: true), throwsA(isA<BackupNeedsPassword>()));
      await expectLater(() => importBackup(t.repo, locked, replace: true, password: 'wrong one'), throwsA(predicate((e) => e is BackupError && e.message.startsWith('Wrong password'))));
      expect(await t.repo.history(), isEmpty);
      await importBackup(t.repo, locked, replace: true, password: 'correct horse battery');
      expect((await t.repo.history()).length, (await s.repo.history()).length);
      final j = jsonDecode(locked) as Map..['data'] = base64.encode(utf8.encode('x' * 40));
      await expectLater(() => unlockBackup(jsonEncode(j), 'correct horse battery'), throwsA(isA<BackupError>()));
    });
  });
}
