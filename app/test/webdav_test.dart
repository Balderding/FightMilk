import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/backup.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/data/webdav.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/net/guarded_client.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/settings_screen.dart';

/// Batch 22c, F343: "Send a backup to my server": only on a tap, https only, the password in
/// secure storage, the destination shown first.
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

  Future<AppState> app() async {
    final dir = Directory.systemTemp.createTempSync('dav22');
    final s = await AppState.forTest(await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi), PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    const c = ServerConfig('https://cloud.example.org/remote.php/dav/files/me/Backups', 'me');
    await saveServer(s.repo, c);
    await s.secrets.setServerPassword('server-pass-XYZ', forServer: serverKey(c));
    await s.reload();
    return s;
  }

  test('addresses: https only, with plain reasons', () {
    expect(checkServerUrl('https://cloud.example.org/dav/'), isNull);
    expect(checkServerUrl('http://cloud.example.org/dav/'), contains('Only https://'));
    expect(checkServerUrl('ftp://x'), contains('https://'));
    expect(checkServerUrl('not an address'), isNotNull);
    expect(checkServerUrl('https://me:pw@cloud.example.org/'), contains('user name in its own box'));
    expect(serverTarget(const ServerConfig('https://h.org/dav/files/me/Backups', 'me'), 'a b.json').toString(), 'https://h.org/dav/files/me/Backups/a%20b.json');
  });

  test('a send goes to the folder shown, as the user, locked when chosen; the status says so', () async {
    final s = await app();
    final seen = <http.Request>[];
    final mock = MockClient((r) async {
      seen.add(r);
      return http.Response('', 201);
    });
    final to = await s.sendBackupToServer(body: false, lockPassword: 'a long password', via: mock);
    final r = seen.single;
    expect(r.method, 'PUT');
    expect(r.url, to);
    expect(r.url.host, 'cloud.example.org');
    expect(r.url.path, startsWith('/remote.php/dav/files/me/Backups/fightmilk-backup-'));
    expect(r.url.path, endsWith('.locked.json'));
    expect(r.headers['Authorization'], 'Basic ${base64.encode(utf8.encode('me:server-pass-XYZ'))}');
    expect(isLockedBackup(r.body), isTrue);
    expect(r.body, isNot(contains('back_squat')));
    expect(s.backupStatus.line(DateTime.now(), hasWorkouts: true), contains('your server'));
  });

  test('the server says no: plain words, nothing marked as backed up', () async {
    final s = await app();
    for (final (code, want) in [(401, 'user name or password is wrong'), (404, 'no folder at that address'), (507, 'full'), (500, 'answered 500')]) {
      await expectLater(() => s.sendBackupToServer(body: true, via: MockClient((r) async => http.Response('', code))), throwsA(predicate((e) => e is BackupError && e.message.contains(want))), reason: '$code');
    }
    expect(s.backupStatus.last, isNull);
  });

  test('the guard lets the backup through only to that host, only over https', () {
    const g = NetGuard(backupHost: 'cloud.example.org');
    expect(g.allows(Uri.parse('https://cloud.example.org/x')), isTrue);
    expect(g.allows(Uri.parse('http://cloud.example.org/x')), isFalse);
    expect(g.allows(Uri.parse('https://evil.example.org/x')), isFalse);
    expect(const NetGuard().allows(Uri.parse('https://cloud.example.org/x')), isFalse, reason: 'not outside a send');
  });

  test('never in a backup: the server, its user or its password; and no send by itself', () async {
    final s = await app();
    var calls = 0;
    final mock = MockClient((r) async {
      calls++;
      return http.Response('', 201);
    });
    final file = await exportBackup(s.repo);
    expect(file, isNot(contains('server-pass-XYZ')));
    expect(file, isNot(contains('cloud.example.org')));
    expect(file, isNot(contains('"webdav"')));
    // a workout finished and a day passed: nothing goes to the server
    await s.startWorkout();
    await s.repo.logSet(s.session!.id, s.session!.day.items.first.exerciseId, 60, 8);
    await s.finishWorkout();
    await s.dailyBackup();
    expect(calls, 0);
    await s.sendBackupToServer(body: true, via: mock);
    expect(calls, 1, reason: 'only when asked');
  });

  group('review 7, P1-3 (checks9 D3): a password belongs to one server', () {
    test('a changed host, port or user never gets the old password; nothing is sent', () async {
      for (final other in [
        const ServerConfig('https://other-host.example.net/remote.php/dav/files/me/Backups', 'me'),
        const ServerConfig('https://cloud.exmaple.org/remote.php/dav/files/me/Backups', 'me'),
        const ServerConfig('https://cloud.example.org:8443/remote.php/dav/files/me/Backups', 'me'),
        const ServerConfig('https://cloud.example.org/remote.php/dav/files/me/Backups', 'someone'),
      ]) {
        final s = await app();
        await saveServer(s.repo, other); // changed without a new password
        await s.reload();
        var calls = 0;
        await expectLater(() => s.sendBackupToServer(body: true, via: MockClient((r) async {
              calls++;
              return http.Response('', 201);
            })), throwsA(predicate((e) => e is BackupError && e.message.contains('password is missing'))), reason: other.url);
        expect(calls, 0, reason: other.url);
      }
    });

    test('the same server written another way (case, a path change) keeps its password', () async {
      final s = await app();
      await saveServer(s.repo, const ServerConfig('https://CLOUD.example.org:443/remote.php/dav/files/me/Other', 'me'));
      await s.reload();
      var calls = 0;
      await s.sendBackupToServer(body: true, via: MockClient((r) async {
        calls++;
        return http.Response('', 201);
      }));
      expect(calls, 1);
    });

    testWidgets('Change: a new address with the password left blank asks for its password', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final s = (await tester.runAsync(app))!;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsScreen(s: s))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'automatic backup');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Backup').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Change'), 200, scrollable: find.byType(Scrollable).last);
      await tester.ensureVisible(find.text('Change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Folder address (https://...)'), 'https://other-host.example.net/dav/');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('The server or user changed: type its password.'), findsOneWidget);
      expect(s.server!.url, startsWith('https://cloud.example.org/'), reason: 'nothing saved');
      await tester.enterText(find.widgetWithText(TextField, 'Password (an app password is best)'), 'new-host-pass');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 20 && !s.server!.url.contains('other-host'); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // the database writes
        await tester.pump();
      }
      await tester.runAsync(() async {
        expect(await s.secrets.serverPassword(serverKey(s.server!)), 'new-host-pass');
      });
      expect(s.server!.url, 'https://other-host.example.net/dav/');
    });
  });

  group('review 7 P3s', () {
    test('P3-4: an address with ? or # is refused (it would push the folder out)', () {
      expect(checkServerUrl('https://h.org/dav?token=abc'), contains('Leave out the part after ? or #'));
      expect(checkServerUrl('https://h.org/dav#x'), contains('Leave out'));
      expect(checkServerUrl('https://h.org/dav/files/me/Backups'), isNull);
    });

    test('P3-5: a send the guard blocks says so, not "could not be reached"', () async {
      final s = await app();
      await expectLater(
          () => s.sendBackupToServer(body: true, via: MockClient((r) async => throw NetBlocked(r.url))),
          throwsA(predicate((e) => e is BackupError && e.message.contains('did not send it') && !e.message.contains('could not be reached'))));
    });

    test('P3-6: the name shown before sending is the name used', () async {
      final s = await app();
      final seen = <Uri>[];
      final name = serverFileName(DateTime(2026, 11, 22, 10, 15, 30), locked: false);
      expect(name, 'fightmilk-backup-2026-11-22T101530.json');
      final to = await s.sendBackupToServer(body: true, name: name, via: MockClient((r) async {
        seen.add(r.url);
        return http.Response('', 201);
      }));
      expect(seen.single.path, endsWith('/$name'));
      expect(to.path, endsWith('/$name'));
      // a name that does not fit the lock is not used
      final locked = await s.sendBackupToServer(body: true, lockPassword: 'a long password', name: name, via: MockClient((r) async => http.Response('', 201)));
      expect(locked.path, endsWith('.locked.json'));
    });
  });
}
