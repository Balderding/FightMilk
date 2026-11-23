import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/auto_backup.dart';
import 'package:workout/data/backup.dart';
import 'package:workout/data/import_store.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/data/webdav.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/import.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/export_screen.dart' show askLock;
import 'package:workout/ui/widgets.dart';

/// Fix 22b: the seventh review's P2s (work/reviews/REVIEW-2026-11-22-1945.md), each from its
/// checks9 line.
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

  Future<AppState> blank() async {
    final dir = Directory.systemTemp.createTempSync('f22b');
    return AppState.forTest(await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi), PackStore(dir.path), lib);
  }

  Future<AppState> filled() async {
    final s = await blank();
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    await s.startWorkout();
    await s.repo.logSet(s.session!.id, s.session!.day.items.first.exerciseId, 60, 8);
    await s.finishWorkout();
    return s;
  }

  test('P2-1 (checks9 B9): "Replace everything" keeps this phone\'s automatic backup, server and status', () async {
    final s = await filled();
    final file = await exportBackup(s.repo);
    await saveAutoBackup(s.repo, const AutoBackup(when: 'day', tree: 'content://tree/x', folderName: 'Backups', locked: true));
    await s.secrets.setBackupPassword('auto-pass-123');
    const c = ServerConfig('https://cloud.example.org/dav', 'me');
    await saveServer(s.repo, c);
    await s.secrets.setServerPassword('server-pass-XYZ', forServer: serverKey(c));
    await noteBackup(s.repo, 'your backup folder');
    await s.repo.kvSet('photos', '[]');
    await importBackup(s.repo, file, replace: true);
    await s.reload();
    expect(s.autoBackup.when, 'day');
    expect(s.autoBackup.tree, 'content://tree/x');
    expect(s.autoBackup.locked, isTrue);
    expect(s.server?.url, c.url);
    expect(s.backupStatus.last, isNotNull);
    expect(await s.secrets.serverPassword(serverKey(c)), 'server-pass-XYZ');
    expect(await s.secrets.backupPassword(), 'auto-pass-123');
    expect(await s.repo.kvGet('photos'), '[]');
    // and a backup still never carries them
    final again = await exportBackup(s.repo);
    for (final k in deviceOnlyKeys) {
      expect(again, isNot(contains('"$k"')), reason: k);
    }
  });

  group('P2-3 (checks9 B8): import records in a merge', () {
    const strongCsv = 'Date,Exercise,Weight,Reps\n2025-06-01 18:00,Squat,100,5\n';
    const hevyCsv = 'Date,Exercise,Weight,Reps\n2025-07-01 18:00,Bench Press,70,5\n';
    Future<AppState> withImport(String label, String csv, String name, String id) async {
      final s = await filled();
      await saveImport(s.repo, readImport(csv, appUnit: Unit.kg), {name: id}, label: label);
      return s;
    }

    bool june(List<Session> h) => h.any((w) => w.started.year == 2025 && w.started.month == 6);

    test("a merge brings the file's import record, for what came in, so it can be undone here", () async {
      final other = await withImport('Strong', strongCsv, 'Squat', 'back_squat');
      final file = await exportBackup(other.repo);
      final s = await withImport('Hevy', hevyCsv, 'Bench Press', 'bench_press');
      await importBackup(s.repo, file, replace: false);
      final recs = await importRecords(s.repo);
      expect([for (final x in recs) x.label], ['Hevy', 'Strong']);
      final strong = recs.last;
      expect(strong.sessions, hasLength(1));
      expect(strong.lifts, isEmpty, reason: "the other phone's lift states are not put back here");
      expect(june(await s.repo.history()), isTrue);
      await undoImport(s.repo, strong.id);
      expect(june(await s.repo.history()), isFalse);
      expect([for (final x in await importRecords(s.repo)) x.label], ['Hevy']);
    });

    test('an undone import never comes back with a merge of the same backup', () async {
      final other = await withImport('Strong', strongCsv, 'Squat', 'back_squat');
      final file = await exportBackup(other.repo);
      final t = await blank();
      await importBackup(t.repo, file, replace: true);
      final rec = (await importRecords(t.repo)).single;
      final n0 = (await t.repo.history()).length;
      await undoImport(t.repo, rec.id);
      final n1 = (await t.repo.history()).length;
      expect(n1, n0 - 1);
      await importBackup(t.repo, file, replace: false);
      expect((await t.repo.history()).length, n1, reason: 'the undone workout stays out');
      expect(await importRecords(t.repo), isEmpty);
      // the undone list travels in a backup: a phone that merges both files does not get it back
      final again = await exportBackup(t.repo);
      final u = await blank();
      await importBackup(u.repo, again, replace: true);
      await importBackup(u.repo, file, replace: false);
      expect(june(await u.repo.history()), isFalse);
    });

    test('a merge that brought nothing new of an import adds no second record', () async {
      final other = await withImport('Strong', strongCsv, 'Squat', 'back_squat');
      final file = await exportBackup(other.repo);
      final t = await blank();
      await importBackup(t.repo, file, replace: true);
      await importBackup(t.repo, file, replace: false);
      expect(await importRecords(t.repo), hasLength(1));
    });
  });

  group('P2-5 (checks9 B2, B4, B5): a file whose contents are wrong is refused before anything changes', () {
    // the app's own hash rule, so a hand-edited file passes the check (like checks9)
    Future<String> rehash(Map<String, dynamic> j) async {
      j.remove('sha256');
      final h = await Sha256().hash(utf8.encode(jsonEncode(j)));
      j['sha256'] = h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      return const JsonEncoder.withIndent(' ').convert(j);
    }

    Future<String> raw(Repo r) async {
      final o = <String>[];
      for (final t in ['kv', 'plan', 'lift_state', 'session', 'set_log', 'body', 'ex_note']) {
        final rows = [for (final row in await r.db.query(t)) jsonEncode(row)]..sort();
        o.add('$t:${rows.join('|')}');
      }
      return o.join('\n');
    }

    Future<Map<String, dynamic>> fileOf(AppState s) async => jsonDecode(await exportBackup(s.repo)) as Map<String, dynamic>;

    Future<void> refused(Map<String, dynamic> j, String want, {String? reason}) async {
      for (final replace in [true, false]) {
        final t = await filled();
        final before = await raw(t.repo);
        await expectLater(() async => importBackup(t.repo, await rehash(Map.of(j)), replace: replace),
            throwsA(predicate((e) => e is BackupError && e.message.contains(want) && !e.message.contains('Exception'), 'BackupError with "$want"')),
            reason: reason ?? want);
        expect(await raw(t.repo), before, reason: 'nothing changed (${reason ?? want})');
        await t.reload(); // and the app still works
      }
    }

    test('B4: broken plan, lift and profile JSON; impossible numbers', () async {
      final s = await filled();
      var j = await fileOf(s);
      (j['plan'] as List).first['json'] = '{"broken":';
      await refused(j, 'plan row 1 is damaged');
      j = await fileOf(s);
      (j['lift_state'] as List).first['json'] = 'not json';
      await refused(j, 'lift_state row 1 is damaged');
      j = await fileOf(s);
      (j['kv'] as List).firstWhere((x) => x['k'] == 'profile')['v'] = '[1,2]';
      await refused(j, 'the profile setting is damaged');
      j = await fileOf(s);
      (j['kv'] as List).add({'k': 'settings', 'v': '"x"'});
      await refused(j, 'the settings setting is damaged');
      j = await fileOf(s);
      (j['session'] as List).first['day'] = '{}';
      await refused(j, 'session row 1 is damaged');
      for (final (f, v) in [('kg', -500), ('kg', 5000.0), ('reps', -3), ('reps', 100000), ('at', 5), ('at', DateTime(2100).millisecondsSinceEpoch)]) {
        j = await fileOf(s);
        (j['set_log'] as List).first[f] = v;
        await refused(j, 'set_log row 1', reason: '$f $v');
      }
    });

    test('B2: an unknown field is refused in plain words, without database text', () async {
      final s = await filled();
      final j = await fileOf(s);
      (j['ex_note'] as List).add({'exercise_id': 'deadlift', 'note': 'x', 'evil': 1});
      await refused(j, 'has a field this app does not know ("evil")');
    });

    test('B5: two rows with one id are refused; two plans in use become one (the newest)', () async {
      final s = await filled();
      var j = await fileOf(s);
      final ses = Map<String, dynamic>.from((j['session'] as List).first as Map)..['started'] = DateTime(2025).millisecondsSinceEpoch;
      (j['session'] as List).add(ses);
      await refused(j, 'two session rows share one id');
      j = await fileOf(s);
      final p = Map<String, dynamic>.from((j['plan'] as List).first as Map)
        ..['id'] = 'second-plan'
        ..['created'] = ((j['plan'] as List).first['created'] as int) + 1000;
      (j['plan'] as List).add(p);
      final t = await blank();
      await importBackup(t.repo, await rehash(j), replace: true);
      final act = await t.repo.db.query('plan', where: 'active = 1');
      expect(act.map((x) => x['id']), ['second-plan']);
      await t.reload();
      expect(t.plan, isNotNull);
    });

    test('a real backup of every kind still restores (nothing over-strict)', () async {
      final s = await filled();
      await s.repo.db.insert('body', {'id': 'b1', 'at': DateTime(2026, 11, 1).millisecondsSinceEpoch, 'kg': 80.5, 'fat': 18.0});
      await s.repo.db.insert('ex_note', {'exercise_id': 'back_squat', 'note': 'knees out'});
      await s.addAim('lift', 100, exercise: 'bench_press');
      final t = await blank();
      await importBackup(t.repo, await exportBackup(s.repo), replace: true);
      await t.reload();
      expect(t.aims, hasLength(1));
      expect((await t.repo.history()).length, 1);
    });
  });

  group('P2-4 (checks9 B10): restore size, speed and a spinner', () {
    test('a 70 MB file is refused before it is read whole', () async {
      var read = 0;
      Stream<List<int>> big() async* {
        for (var i = 0; i < 70; i++) {
          read++;
          yield Uint8List(1 << 20);
        }
      }

      expect(await readCapped(big()), isNull);
      expect(read, lessThanOrEqualTo(65), reason: 'stops at 64 MB');
      expect(await readCapped(Stream.value(utf8.encode('{"x":1}'))), utf8.encode('{"x":1}'));
    });

    test('a large backup (over 256 KB: checked on a worker isolate, rows in one batch) restores whole', () async {
      final s = await filled();
      final ses = s.repo.db.batch();
      final w = (await s.repo.history()).first;
      for (var i = 0; i < 6000; i++) {
        ses.insert('set_log', {'id': 'x$i', 'session_id': w.id, 'exercise_id': 'back_squat', 'kg': 100.0, 'reps': 5, 'ord': i + 10, 'at': DateTime(2026, 11, 1).millisecondsSinceEpoch + i});
      }
      await ses.commit(noResult: true);
      final file = await exportBackup(s.repo);
      expect(file.length, greaterThan(256 * 1024));
      final t = await blank();
      await importBackup(t.repo, file, replace: true);
      expect((await t.repo.db.rawQuery('SELECT COUNT(*) c FROM set_log')).first['c'], 6001);
      // a damaged large file is refused from the isolate in plain words, and changes nothing
      final bad = file.replaceFirst('"reps": 5', '"reps": 6');
      final before = (await t.repo.db.rawQuery('SELECT COUNT(*) c FROM set_log')).first['c'];
      await expectLater(() => importBackup(t.repo, bad, replace: true), throwsA(predicate((e) => e is BackupError && e.message.contains('check does not match'))));
      expect((await t.repo.db.rawQuery('SELECT COUNT(*) c FROM set_log')).first['c'], before);
    });

    test('"no body data" is seen from the top of the file, without a second decode', () async {
      final s = await filled();
      expect(backupHasBody(await exportBackup(s.repo)), isTrue);
      expect(backupHasBody(await exportBackup(s.repo, body: false)), isFalse);
      expect(backupHasBody('not json'), isTrue);
    });

    testWidgets('busyWhile shows a spinner with its words while the work runs, and always goes away', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      })));
      final done = Completer<int>();
      final f = busyWhile(ctx, 'Restoring…', () => done.future);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Restoring…'), findsOneWidget);
      done.complete(7);
      expect(await f, 7);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // a failing work: the spinner goes, the error comes through
      final g = expectLater(busyWhile<int>(ctx, 'Locking…', () async => throw BackupError('no')), throwsA(isA<BackupError>()));
      await tester.pump();
      await g;
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('P2-2 (checks9 A3, A4): the lock', () {
    test('stated round counts outside 100 000 to 2 000 000 are refused at once', () async {
      final ok = jsonDecode(await lockBackup('{"x":1}', 'password1', iterations: lockMinIterations)) as Map<String, dynamic>;
      for (final bad in [0, 1, -5, 9999, 99999, 2000001, 5000000, 1000000000000, 600000.0, '600000']) {
        final f = jsonEncode({...ok, 'iter': bad});
        final sw = Stopwatch()..start();
        await expectLater(() => unlockBackup(f, 'password1'), throwsA(predicate((e) => e is BackupError && e.message.contains('damaged'))), reason: '$bad');
        expect(sw.elapsedMilliseconds, lessThan(200), reason: '$bad: refused before any rounds');
      }
      expect(await unlockBackup(jsonEncode(ok), 'password1'), '{"x":1}');
      expect(() => lockBackup('{}', 'password1', iterations: 5000000), throwsArgumentError);
    });

    test('the rounds run on a worker isolate: the main isolate keeps ticking', () async {
      var ticks = 0, longest = 0;
      var last = DateTime.now();
      final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        final now = DateTime.now();
        longest = now.difference(last).inMilliseconds > longest ? now.difference(last).inMilliseconds : longest;
        last = now;
        ticks++;
      });
      final locked = await lockBackup('{"x":1}', 'a long password');
      expect(await unlockBackup(locked, 'a long password'), '{"x":1}');
      timer.cancel();
      expect(ticks, greaterThan(20));
      expect(longest, lessThan(250), reason: 'no long stall while 2 x 600 000 rounds ran');
    });
  });

  group('review 7 P3s', () {
    test('P3-9: a non-number schema is refused; the check is checked whenever it is there', () async {
      final s = await filled();
      final j = jsonDecode(await exportBackup(s.repo)) as Map<String, dynamic>;
      final t = await blank();
      final a = Map<String, dynamic>.from(j)..['schema'] = '9';
      await expectLater(() => importBackup(t.repo, jsonEncode(a), replace: true), throwsA(isA<BackupError>()));
      // a damaged file relabelled format 1 still carries its check: refused
      final b = Map<String, dynamic>.from(j)
        ..['format'] = 1
        ..['kv'] = [...(j['kv'] as List), {'k': 'aims', 'v': '[]'}];
      await expectLater(() => importBackup(t.repo, jsonEncode(b), replace: true), throwsA(predicate((e) => e is BackupError && e.message.contains('check does not match'))));
      // a real format-1 file (no check at all) still restores
      final c = Map<String, dynamic>.from(j)
        ..['format'] = 1
        ..remove('sha256')
        ..remove('schema');
      await importBackup(t.repo, jsonEncode(c), replace: true);
    });

    test('P3-11: a problem is said with when the last good backup was', () {
      final now = DateTime(2026, 11, 22, 20);
      final st = BackupStatus(last: now.subtract(const Duration(days: 20)), problem: 'The backup folder can no longer be reached. Pick it again in Settings → Backup.');
      expect(st.line(now, hasWorkouts: true), 'The backup folder can no longer be reached. Pick it again in Settings → Backup. Last good backup 20 days ago.');
      expect(const BackupStatus(problem: 'x.').line(now, hasWorkouts: true), 'x.');
    });
  });

  testWidgets('P3-7: a password of only spaces is refused; a short one gets a hint, not a block', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox());
    })));
    String? got = 'not yet';
    askLock(ctx).then((v) => got = v);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pw1')), '        ');
    await tester.enterText(find.byKey(const Key('pw2')), '        ');
    await tester.tap(find.byKey(const Key('lockYes')));
    await tester.pumpAndSettle();
    expect(find.text('Use letters, numbers or signs, not only spaces.'), findsOneWidget);
    expect(got, 'not yet', reason: 'the sheet stays open');
    await tester.enterText(find.byKey(const Key('pw1')), 'tenletters');
    await tester.pumpAndSettle();
    expect(find.text('Longer is stronger: 12 or more characters is a good length.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pw2')), 'tenletters');
    await tester.tap(find.byKey(const Key('lockYes')));
    await tester.pumpAndSettle();
    expect(got, 'tenletters');
  });
}
