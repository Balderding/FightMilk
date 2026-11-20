import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/ai.dart';
import 'package:workout/data/backup.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/net/guarded_client.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  test('fixing a mistyped set in history corrects next time\'s weight', () async {
    final dir = Directory.systemTemp.createTempSync('rf');
    final r = await Repo.open('${dir.path}/r.db', factory: databaseFactoryFfi);
    final plan = makePlan(profile, lib);
    await r.savePlan(plan);
    final it = plan.days[0].items.first;
    final s = await r.startSession(plan, 0, plan.days[0]);
    final bad = await r.logSet(s.id, it.exerciseId, 1000, it.repHigh); // typo: 1000 instead of 100
    for (var i = 1; i < it.sets; i++) {
      await r.logSet(s.id, it.exerciseId, 100, it.repHigh);
    }
    await r.finishSession(s.id, lib, Unit.kg);
    expect((await r.lift(it.exerciseId))!.workKg, greaterThan(900));
    await r.updateSet(bad.id, 100, it.repHigh);
    await r.rebuildLifts([it.exerciseId], lib, Unit.kg);
    expect((await r.lift(it.exerciseId))!.workKg, 102.5);
    // deleting the whole workout forgets the lift
    await r.deleteSession(s.id);
    await r.rebuildLifts([it.exerciseId], lib, Unit.kg);
    expect(await r.lift(it.exerciseId), isNull);
    await r.close();
    dir.deleteSync(recursive: true);
  });

  test('day map follows moved and deleted days', () {
    final plan = makePlan(profile, lib); // A0 B1 C2 D3
    expect(dayMap(plan, plan.moveDay(3, 0)), [1, 2, 3, 0]);
    expect(dayMap(plan, plan.removeDay(1)), [0, null, 1, 2]);
    expect(dayMap(plan, plan.renameDay(2, 'x')), [0, 1, 2, 3]);
    expect(dayMap(plan, plan.addDay('E')), [0, 1, 2, 3]);
    expect(dayMap(plan, plan.addItem(1, const PlanItem(exerciseId: 'db_curl', sets: 3, repLow: 8, repHigh: 12, restSec: 60))), [0, 1, 2, 3]);
  });

  test('odd AI reply shapes become plain AiError, not crashes', () async {
    Future<void> expectAiError(AiKind k, String host, Object body) async {
      final c = GuardedClient(NetGuard(aiHost: host), MockClient((_) async => http.Response(jsonEncode(body), 200)));
      await expectLater(providerFor(AiConfig(kind: k, model: 'm', baseUrl: 'http://192.168.1.2:1'), 'k', c).complete('s', 'u'), throwsA(isA<AiError>()));
    }

    await expectAiError(AiKind.claude, 'api.anthropic.com', {'content': [{'type': 'text', 'text': 5}]});
    await expectAiError(AiKind.claude, 'api.anthropic.com', {'content': 'nope'});
    await expectAiError(AiKind.openai, 'api.openai.com', {'choices': ['x']});
    await expectAiError(AiKind.gemini, 'generativelanguage.googleapis.com', {'candidates': [{'content': 'x'}]});
    await expectAiError(AiKind.local, '192.168.1.2', [1, 2]);
  });

  test('a backup with broken rows is refused cleanly and changes nothing', () async {
    final dir = Directory.systemTemp.createTempSync('rf');
    final r = await Repo.open('${dir.path}/r.db', factory: databaseFactoryFfi);
    await r.savePlan(makePlan(profile, lib));
    final bad = jsonEncode({'format': 1, 'app': 'workout', 'kv': [], 'plan': [{'id': 'x'}], 'lift_state': [], 'session': [], 'set_log': []});
    await expectLater(importBackup(r, bad, replace: true), throwsA(isA<BackupError>()));
    expect(await r.activePlan(), isNotNull);
    await r.close();
    dir.deleteSync(recursive: true);
  });

  test('icon check never throws: junk or network failure gives a sentence', () async {
    final dir = Directory.systemTemp.createTempSync('rf');
    final store = PackStore(dir.path);
    final junk = GuardedClient(const NetGuard(), MockClient((_) async => http.Response('<html>', 200)));
    expect(await checkForPack(junk, store), isA<String>());
    final down = GuardedClient(const NetGuard(), MockClient((r) async {
      if (r.url.host == 'api.github.com') {
        return http.Response(jsonEncode({'assets': [{'name': 'pack.zip', 'browser_download_url': 'https://objects.githubusercontent.com/p'}]}), 200);
      }
      throw http.ClientException('offline');
    }));
    expect(await checkForPack(down, store), contains('Download failed'));
    dir.deleteSync(recursive: true);
  });

  test('moving or deleting days keeps the rotation on the same day', () async {
    final dir = Directory.systemTemp.createTempSync('rf');
    final repo = await Repo.open('${dir.path}/r.db', factory: databaseFactoryFfi);
    final st = await AppState.forTest(repo, PackStore(dir.path), lib);
    await st.saveProfile(profile);
    await st.makeBuiltInPlan(); // Upper A, Lower A, Upper B, Lower B
    await repo.setLastDayIndex(st.plan!.id, 1); // Lower A done -> Upper B next
    await st.reload();
    expect(st.today!.name, 'Upper B');
    await st.savePlanEdits(st.plan!.moveDay(3, 0)); // Lower B to the front
    expect(st.today!.name, 'Upper B');
    await st.savePlanEdits(st.plan!.removeDay(st.plan!.days.indexWhere((d) => d.name == 'Lower A')));
    expect(st.today!.name, 'Upper B');
    await repo.close();
    dir.deleteSync(recursive: true);
  });
}
