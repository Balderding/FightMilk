import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/backup.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.size, days: 3, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.lb);

  group('backup', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('bk'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Repo> filled(String name) async {
      final r = await Repo.open('${dir.path}/$name.db', factory: databaseFactoryFfi);
      await r.saveProfile(profile);
      final plan = makePlan(profile, lib);
      await r.savePlan(plan);
      final s = await r.startSession(plan, 0, plan.days[0]);
      await r.logSet(s.id, 'bench_press', 100, 10);
      await r.logSet(s.id, 'bench_press', 100, 9);
      await r.finishSession(s.id, lib, Unit.lb);
      await r.kvSet('ai_key', 'sk-secret'); // must never be exported
      return r;
    }

    Future<Map<String, int>> counts(Repo r) async => {
          for (final t in ['plan', 'lift_state', 'session', 'set_log']) t: (await r.db.rawQuery('SELECT COUNT(*) c FROM $t')).first['c'] as int
        };

    test('round trip into an empty phone', () async {
      final a = await filled('a');
      final text = await exportBackup(a);
      expect(text, isNot(contains('sk-secret')));
      expect((jsonDecode(text) as Map)['format'], 1);
      final b = await Repo.open('${dir.path}/b.db', factory: databaseFactoryFfi);
      await importBackup(b, text, replace: true);
      expect(await counts(b), await counts(a));
      expect((await b.profile())!.toJson(), profile.toJson());
      expect((await b.activePlan())!.toJson(), (await a.activePlan())!.toJson());
      expect(await b.lastDayIndex((await b.activePlan())!.id), 0);
      await a.close();
      await b.close();
    });

    test('merging the same backup twice does not duplicate', () async {
      final a = await filled('a');
      final text = await exportBackup(a);
      final before = await counts(a);
      await importBackup(a, text, replace: false);
      await importBackup(a, text, replace: false);
      expect(await counts(a), before);
      await a.close();
    });

    test('junk is refused and nothing changes', () async {
      final a = await filled('a');
      final before = await counts(a);
      await expectLater(importBackup(a, 'not json', replace: true), throwsA(isA<BackupError>()));
      await expectLater(importBackup(a, '{"format": 99}', replace: true), throwsA(isA<BackupError>()));
      expect(await counts(a), before);
      await a.close();
    });
  });

  group('signed packs', () {
    Future<(SimpleKeyPair, List<int>)> keys() async {
      final kp = await Ed25519().newKeyPairFromSeed(List.filled(32, 7));
      final pub = (await kp.extractPublicKey()).bytes;
      return (kp, pub);
    }

    Future<List<int>> makeZip(SimpleKeyPair kp, int version, Map<String, List<int>> files, {bool tamper = false}) async {
      final manifest = utf8.encode(jsonEncode({
        'version': version,
        'files': {for (final e in files.entries) e.key: sha256.convert(e.value).toString()},
      }));
      final sig = await Ed25519().sign(manifest, keyPair: kp);
      final ar = Archive()
        ..addFile(ArchiveFile.bytes('manifest.json', manifest))
        ..addFile(ArchiveFile.bytes('manifest.sig', utf8.encode(base64Encode(sig.bytes))));
      files.forEach((k, v) => ar.addFile(ArchiveFile.bytes(k, tamper ? [...v, 1] : v)));
      return ZipEncoder().encodeBytes(ar);
    }

    final icon = utf8.encode('<svg/>');
    final exJson = utf8.encode(jsonEncode({
      'exercises': [
        {'id': 'new_thing', 'name': 'New thing', 'equipment': 'machine', 'primary': ['chest'], 'pattern': 'press', 'swap': 'chest_press', 'repLow': 8, 'repHigh': 12, 'step': 'machine', 'icon': 'press_machine'}
      ]
    }));

    test('a good pack verifies, with its icons and exercises', () async {
      final (kp, pub) = await keys();
      final z = await makeZip(kp, 3, {'icons/press_machine.svg': icon, 'exercises.json': exJson});
      final p = await verifyPack(z, pub);
      expect(p.version, 3);
      expect(p.files.keys, containsAll(['icons/press_machine.svg', 'exercises.json']));
      expect(p.exercises.single.id, 'new_thing');
    });
    test('a changed file is refused', () async {
      final (kp, pub) = await keys();
      final z = await makeZip(kp, 3, {'icons/a.svg': icon}, tamper: true);
      await expectLater(verifyPack(z, pub), throwsA(isA<PackError>()));
    });
    test('a pack signed with another key is refused', () async {
      final (kp, _) = await keys();
      final other = await Ed25519().newKeyPairFromSeed(List.filled(32, 9));
      final z = await makeZip(kp, 3, {'icons/a.svg': icon});
      await expectLater(verifyPack(z, (await other.extractPublicKey()).bytes), throwsA(isA<PackError>()));
    });
    test('files outside the manifest, or path tricks, are refused', () async {
      final (kp, pub) = await keys();
      final z = await makeZip(kp, 3, {'../evil.svg': icon});
      await expectLater(verifyPack(z, pub), throwsA(isA<PackError>()));
    });
    test('install writes files; older or same version is ignored', () async {
      final (kp, pub) = await keys();
      final dir = Directory.systemTemp.createTempSync('pk');
      final store = PackStore(dir.path);
      expect(store.installedVersion(), 0);
      expect(await store.install(await verifyPack(await makeZip(kp, 2, {'icons/press_machine.svg': icon}), pub)), isTrue);
      expect(store.installedVersion(), 2);
      expect(File(store.iconPath('press_machine')!).readAsStringSync(), '<svg/>');
      expect(await store.install(await verifyPack(await makeZip(kp, 2, {'icons/x.svg': icon}), pub)), isFalse);
      expect(store.iconPath('x'), isNull);
      dir.deleteSync(recursive: true);
    });
  });
}
