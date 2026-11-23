import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/auto_backup.dart';
import 'package:workout/data/backup.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

/// A folder in memory: what Android's document access would hold, as MainActivity.kt answers
/// since review 7: only our exact names, never a folder; a failed write leaves nothing; a clash
/// gets " (1)". [loose] answers like the old Kotlin did (every fightmilk-auto- name, folders
/// too), to show the Dart rule alone keeps the person's files safe.
class FakeFolder implements BackupFolder {
  final files = <String, (String name, Uint8List bytes, int at)>{};
  final dirs = <String>{}; // ids that are folders
  final deleted = <String>[];
  bool reachable = true, loose = false;
  Object? writeError;
  var n = 0, writes = 0;
  @override
  Future<String?> pick() async => 'content://tree/Backups';
  @override
  Future<bool> ok(String tree) async => reachable;
  @override
  Future<List<(String, String, int, int)>?> list(String tree) async => reachable
      ? [
          for (final e in files.entries)
            if (loose ? e.value.$1.startsWith('fightmilk-auto-') : (!dirs.contains(e.key) && autoNamePattern.hasMatch(e.value.$1))) (e.key, e.value.$1, e.value.$3, noSize.contains(e.key) ? -1 : e.value.$2.length),
        ]
      : null;
  @override
  Future<String> write(String tree, String name, Uint8List bytes) async {
    writes++;
    if (!reachable) throw BackupError('gone');
    if (writeError != null) throw writeError!; // the part file is removed again: nothing left
    var nm = name;
    var k = 1;
    while (files.values.any((v) => v.$1 == nm)) {
      nm = name.replaceFirst('.json', ' (${k++}).json');
    }
    files['doc${n++}'] = (nm, bytes, n);
    return nm;
  }

  final noSize = <String>{}; // ids whose size the folder does not say (-1), like some cloud folders
  final released = <String>[];
  @override
  Future<void> release(String tree) async => released.add(tree);
  @override
  Future<Uint8List?> head(String tree, String id, int n) async {
    final b = files[id]?.$2;
    return b == null ? null : Uint8List.sublistView(b, 0, b.length < n ? b.length : n);
  }

  @override
  Future<void> delete(String tree, String id, String name) async {
    // Kotlin asks the folder what it is: only our own file, never a folder
    // (loose: like the old Kotlin, which deleted any fightmilk-auto- id it was given, folders too)
    if (!loose && (dirs.contains(id) || files[id]?.$1 != name || !autoNamePattern.hasMatch(name))) return;
    deleted.add(name);
    files.remove(id);
  }
}

/// Batch 22b: automatic folder backups (F339) and the status (F340).
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
      case 'delete':
        store.remove(a['key']);
      case 'deleteAll':
        store.clear();
    }
    return null;
  });
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  Future<(AppState, FakeFolder)> app() async {
    final dir = Directory.systemTemp.createTempSync('auto22');
    final s = await AppState.forTest(await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi), PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    final f = FakeFolder();
    AppState.backupFolder = f;
    return (s, f);
  }

  Future<void> workout(AppState s) async {
    await s.startWorkout();
    await s.repo.logSet(s.session!.id, s.session!.day.items.first.exerciseId, 60, 8);
    await s.finishWorkout();
  }

  test('after each workout: one backup in the folder that restores; the newest N kept, others never touched', () async {
    final (s, f) = await app();
    f.files['theirs'] = ('holiday-photos.zip', Uint8List(3), 0); // not ours: never touched
    await s.saveAutoBackupChoice(AutoBackup(when: 'workout', tree: (await f.pick())!, folderName: 'Backups', keep: 2));
    for (var i = 0; i < 4; i++) {
      await workout(s);
      await Future<void>.delayed(const Duration(milliseconds: 1100)); // names carry the second
      await s.backupNow(); // the finish already started one; this one waits its turn or adds the newest
    }
    final ours = [for (final v in f.files.values) if (v.$1.startsWith('fightmilk-auto-')) v];
    expect(ours.length, 2, reason: 'keep the newest 2');
    expect(f.files['theirs'], isNotNull, reason: 'a file that is not ours is never touched');
    final newest = ours.reduce((a, b) => a.$1.compareTo(b.$1) > 0 ? a : b);
    final dir = Directory.systemTemp.createTempSync('auto22r');
    final t = await AppState.forTest(await Repo.open('${dir.path}/r.db', factory: databaseFactoryFfi), PackStore(dir.path), lib);
    await importBackup(t.repo, utf8.decode(newest.$2), replace: true);
    expect((await t.repo.history()).length, 4);
    expect(s.backupStatus.line(DateTime.now(), hasWorkouts: true), startsWith('Last backup today, your backup folder (Backups).'));
  });

  test('locked automatic backups use the password in secure storage; a missing one is said', () async {
    final (s, f) = await app();
    await s.saveAutoBackupChoice(AutoBackup(when: 'workout', tree: (await f.pick())!, locked: true));
    expect(await s.backupNow(), isFalse);
    expect(s.backupStatus.problem, contains('password is missing'));
    await s.secrets.setBackupPassword('a long password');
    expect(await s.backupNow(), isTrue);
    final file = utf8.decode(f.files.values.single.$2);
    expect(isLockedBackup(file), isTrue);
    expect(f.files.values.single.$1, endsWith('.locked.json'));
    expect(file, isNot(contains('a long password')));
    expect(await unlockBackup(file, 'a long password'), contains('"format": 2'));
  });

  test('an unreachable folder is said in the status line, and never throws', () async {
    final (s, f) = await app();
    await s.saveAutoBackupChoice(AutoBackup(when: 'day', tree: (await f.pick())!));
    f.reachable = false;
    expect(await s.backupNow(), isFalse);
    expect(s.backupStatus.line(DateTime.now(), hasWorkouts: true), contains('can no longer be reached'));
    f.reachable = true;
    expect(await s.backupNow(), isTrue);
    expect(s.backupStatus.problem, isNull, reason: 'a backup that works clears the problem');
  });

  test('once a day: only when the last backup is a day old', () async {
    final (s, f) = await app();
    await s.saveAutoBackupChoice(AutoBackup(when: 'day', tree: (await f.pick())!));
    await s.dailyBackup();
    expect(f.files.length, 1);
    await s.dailyBackup();
    expect(f.files.length, 1, reason: 'not again the same day');
    await noteBackup(s.repo, 'your backup folder', at: DateTime.now().subtract(const Duration(hours: 25)));
    await s.reload();
    await s.dailyBackup();
    expect(f.files.length, 2);
  });

  test('the status line: never, today, old, a nudge only with workouts', () {
    final now = DateTime(2026, 11, 22, 20);
    expect(const BackupStatus().line(now, hasWorkouts: false), 'No backup yet.');
    expect(const BackupStatus().line(now, hasWorkouts: true), contains('keeps your history safe'));
    expect(BackupStatus(last: now.subtract(const Duration(days: 20)), where: 'a file you saved').line(now, hasWorkouts: true), 'Last backup 20 days ago, a file you saved. Time for a new one.');
    expect(BackupStatus(last: now.subtract(const Duration(hours: 3))).line(now, hasWorkouts: true), 'Last backup today.');
    expect(BackupStatus(last: now.subtract(const Duration(days: 20))).old(now), isTrue);
  });

  test('a lock made with fewer rounds (older app) still opens', () async {
    final locked = await lockBackup('{"x":1}', 'password1', iterations: 200000);
    expect(await unlockBackup(locked, 'password1'), '{"x":1}');
    expect((jsonDecode(await lockBackup('{}', 'password1')) as Map)['iter'], 600000);
  });

  test('the backup choice and status stay on the phone: never in a backup', () async {
    final (s, f) = await app();
    await s.saveAutoBackupChoice(AutoBackup(when: 'day', tree: (await f.pick())!));
    await s.backupNow();
    final file = await exportBackup(s.repo);
    expect(file, isNot(contains('auto_backup')));
    expect(file, isNot(contains('backup_status')));
    expect(file, isNot(contains('content://tree')));
  });

  group('review 7 (fix 22b)', () {
    final decoys = ['fightmilk-auto.json.txt', 'fightmilk-auto-notes.txt', 'fightmilk-auto-my-plan.json', 'my-fightmilk-auto-2026-01-01-000000.json', 'FightMilk-auto-2026-01-01-000000.json', 'fightmilk-auto-2020-01-01-000000.json.bak'];

    for (final loose in [false, true]) {
      test('P1-1 (checks9 C1): keep 3 of 6 deletes only the three oldest real backups; every decoy stays${loose ? ' (even with the old, loose Kotlin list)' : ''}', () async {
        final (s, f) = await app();
        f.loose = loose;
        for (final d in decoys) {
          f.files['user-$d'] = (d, Uint8List.fromList(utf8.encode('mine')), 0);
        }
        f.files['user-dir'] = ('fightmilk-auto-old', Uint8List(0), 0);
        f.dirs.add('user-dir'); // a folder the person made
        await s.saveAutoBackupChoice(AutoBackup(when: 'day', tree: (await f.pick())!, keep: 3));
        for (var i = 0; i < 6; i++) {
          expect(await runAutoBackup(s.repo, f, s.autoBackup, now: DateTime(2026, 11, 10 + i, 9)), isTrue);
        }
        expect(f.deleted, unorderedEquals(['fightmilk-auto-2026-11-10-090000.json', 'fightmilk-auto-2026-11-11-090000.json', 'fightmilk-auto-2026-11-12-090000.json']));
        final left = {for (final v in f.files.values) v.$1};
        expect(left, containsAll([...decoys, 'fightmilk-auto-old', 'fightmilk-auto-2026-11-13-090000.json', 'fightmilk-auto-2026-11-14-090000.json', 'fightmilk-auto-2026-11-15-090000.json']));
      });
    }

    test('P1-1: the name rule is exact, and dates are read from it, not sorted as text', () {
      for (final n in ['fightmilk-auto-2026-11-22-101500.json', 'fightmilk-auto-2026-11-22-101500.locked.json', 'fightmilk-auto-2026-11-22-101500 (2).json', 'fightmilk-auto-2026-11-22-101500.locked (1).json']) {
        expect(autoNameTime(n), isNotNull, reason: n);
      }
      for (final n in [...decoys, 'fightmilk-auto-old', 'fightmilk-auto-2026-13-40-256199.json', 'fightmilk-auto-2026-11-22-101500.json.part', 'fightmilk-auto-٢٠٢٦-11-22-101500.json']) {
        expect(autoNameTime(n), isNull, reason: n);
      }
      expect(autoNameTime(autoName(DateTime(2026, 1, 2, 3, 4, 5), locked: true))!.$1, DateTime(2026, 1, 2, 3, 4, 5));
    });

    test('checks9 C2: three in the same second with keep 2 keeps the two newest, never the one just written', () async {
      final (s, f) = await app();
      await s.saveAutoBackupChoice(AutoBackup(when: 'workout', tree: (await f.pick())!, keep: 2));
      final t = DateTime(2026, 11, 22, 10, 15);
      for (var i = 0; i < 3; i++) {
        await runAutoBackup(s.repo, f, s.autoBackup, now: t);
      }
      expect({for (final v in f.files.values) v.$1}, {'fightmilk-auto-2026-11-22-101500 (1).json', 'fightmilk-auto-2026-11-22-101500 (2).json'});
    });

    test('P1-2 (checks9 C3): a full folder leaves no empty file, says so plainly, tries once an hour, and the good backup survives', () async {
      final (s, f) = await app();
      await s.saveAutoBackupChoice(AutoBackup(when: 'day', tree: (await f.pick())!, keep: 3));
      final day = DateTime(2026, 11, 1, 9);
      expect(await runAutoBackup(s.repo, f, s.autoBackup, now: day), isTrue);
      final good = f.files.values.single.$1;
      f.writeError = PlatformException(code: 'full', message: 'ENOSPC (No space left on device)');
      await s.reload();
      final later = day.add(const Duration(days: 2));
      for (var i = 0; i < 4; i++) {
        await s.dailyBackup(now: later.add(Duration(minutes: i * 5))); // start and every return to the app
      }
      expect(f.writes - 1, 1, reason: 'one try, not one per return');
      final line = s.backupStatus.line(later, hasWorkouts: true);
      expect(line, contains('The backup folder is full'));
      expect(line, isNot(contains('PlatformException')));
      expect(line, isNot(contains('ENOSPC')));
      expect([for (final v in f.files.values) v.$2.length], everyElement(greaterThan(0)));
      await s.dailyBackup(now: later.add(const Duration(minutes: 61)));
      expect(f.writes - 1, 2, reason: 'again after an hour');
      f.writeError = null;
      await s.dailyBackup(now: later.add(const Duration(minutes: 125)));
      expect(s.backupStatus.problem, isNull);
      expect({for (final v in f.files.values) v.$1}, contains(good), reason: 'the only good older backup stays');
      expect(f.deleted, isEmpty);
    });

    test('P1-2: an empty or cut-short file of ours never counts as a backup and never pushes a good one out', () async {
      final (s, f) = await app();
      await s.saveAutoBackupChoice(AutoBackup(when: 'day', tree: (await f.pick())!, keep: 2));
      expect(await runAutoBackup(s.repo, f, s.autoBackup, now: DateTime(2026, 11, 1, 9)), isTrue);
      for (var i = 0; i < 3; i++) {
        f.files['empty$i'] = ('fightmilk-auto-2026-11-0${2 + i}-090000.json', Uint8List(i * 10), 0); // left by an older app
      }
      expect(await runAutoBackup(s.repo, f, s.autoBackup, now: DateTime(2026, 11, 9, 9)), isTrue);
      expect(f.deleted, isEmpty, reason: 'two real ones, keep 2: nothing goes');
      expect({for (final v in f.files.values) v.$1}, containsAll(['fightmilk-auto-2026-11-01-090000.json', 'fightmilk-auto-2026-11-09-090000.json']));
    });

    test('P1-2: where the folder does not say the size, only a file that starts like ours counts (and others are never deleted)', () async {
      final (s, f) = await app();
      await s.saveAutoBackupChoice(AutoBackup(when: 'day', tree: (await f.pick())!, keep: 2));
      for (var d = 1; d <= 2; d++) {
        expect(await runAutoBackup(s.repo, f, s.autoBackup, now: DateTime(2026, 11, d, 9)), isTrue);
      }
      f.noSize.addAll(f.files.keys); // the two real ones: size not said
      f.files['empty'] = ('fightmilk-auto-2026-11-05-090000.json', Uint8List(0), 0);
      f.files['junk'] = ('fightmilk-auto-2026-11-06-090000.json', Uint8List.fromList(utf8.encode('{"notes": "mine, not a backup" ${'x' * 2000}}')), 0);
      f.files['locked'] = ('fightmilk-auto-2026-11-04-090000.locked.json', Uint8List.fromList(utf8.encode(await lockBackup('{}', 'password1', iterations: 100000))), 0);
      f.noSize.addAll(['empty', 'junk', 'locked']);
      expect(await runAutoBackup(s.repo, f, s.autoBackup, now: DateTime(2026, 11, 9, 9)), isTrue);
      // real: 11-01, 11-02, 11-04 (locked), 11-09 (just written); keep 2 -> 11-01 and 11-02 go
      expect(f.deleted, unorderedEquals(['fightmilk-auto-2026-11-01-090000.json', 'fightmilk-auto-2026-11-02-090000.json']));
      expect({for (final v in f.files.values) v.$1}, containsAll(['fightmilk-auto-2026-11-05-090000.json', 'fightmilk-auto-2026-11-06-090000.json']), reason: 'not proven ours: never deleted');
    });

    test('P3-8: another folder, or Delete all data, gives the folder back to Android; its files stay', () async {
      final (s, f) = await app();
      await s.saveAutoBackupChoice(AutoBackup(when: 'day', tree: 'content://tree/A', keep: 2));
      expect(await runAutoBackup(s.repo, f, s.autoBackup, now: DateTime(2026, 11, 1, 9)), isTrue);
      await s.saveAutoBackupChoice(s.autoBackup.copyWith(keep: 3)); // the same folder: kept
      expect(f.released, isEmpty);
      await s.saveAutoBackupChoice(s.autoBackup.copyWith(tree: 'content://tree/B'));
      expect(f.released, ['content://tree/A']);
      await s.wipeEverything();
      expect(f.released, ['content://tree/A', 'content://tree/B']);
      expect(f.files, isNotEmpty, reason: 'the backups in the folder are not deleted');
    });

    test('P1-2: a folder that did not keep the whole file is a failure, and nothing older is deleted', () async {
      final (s, f) = await app();
      await s.saveAutoBackupChoice(AutoBackup(when: 'day', tree: (await f.pick())!, keep: 1));
      expect(await runAutoBackup(s.repo, f, s.autoBackup, now: DateTime(2026, 11, 1, 9)), isTrue);
      final cut = _CutFolder(f);
      expect(await runAutoBackup(s.repo, cut, s.autoBackup, now: DateTime(2026, 11, 2, 9)), isFalse);
      expect(f.deleted, isEmpty);
      expect((await loadBackupStatus(s.repo)).problem, contains('would not take the file'));
    });
  });
}

/// A folder that keeps only half of what is written (a provider that lies about success).
class _CutFolder implements BackupFolder {
  final FakeFolder f;
  _CutFolder(this.f);
  @override
  Future<String?> pick() => f.pick();
  @override
  Future<bool> ok(String tree) => f.ok(tree);
  @override
  Future<List<(String, String, int, int)>?> list(String tree) => f.list(tree);
  @override
  Future<String> write(String tree, String name, Uint8List bytes) => f.write(tree, name, Uint8List.sublistView(bytes, 0, bytes.length ~/ 2));
  @override
  Future<void> delete(String tree, String id, String name) => f.delete(tree, id, name);
  @override
  Future<Uint8List?> head(String tree, String id, int n) => f.head(tree, id, n);
  @override
  Future<void> release(String tree) => f.release(tree);
}
