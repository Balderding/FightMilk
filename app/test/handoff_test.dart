import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/ai.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 3, minutes: 60, have: Equipment.values.toSet(), avoid: {Joint.knees}, unit: Unit.lb);

  Future<(AppState, Repo, Directory)> make() async {
    final dir = Directory.systemTemp.createTempSync('ho');
    final repo = await Repo.open('${dir.path}/r.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(repo, PackStore(dir.path), lib);
    await s.saveProfile(profile);
    await s.makeBuiltInPlan();
    await s.saveSettings(s.settings.copyWith(aiOn: true, ai: const AiConfig(kind: AiKind.chatApp, model: 'com.anthropic.claude')));
    return (s, repo, dir);
  }

  test('chat-app mode needs no key and talks to no server', () async {
    final (s, repo, dir) = await make();
    expect(s.settings.ai.host, isNull);
    expect(s.settings.ai.needsKey, isFalse);
    expect(await s.aiReady(), isTrue);
    await repo.close();
    dir.deleteSync(recursive: true);
  });

  test('handed-off text carries instructions, exercise list, setup and the reply format', () async {
    final (s, repo, dir) = await make();
    final r = await s.aiPlanRequest(profile);
    final t = handoffText(r);
    expect(t, contains('Use ONLY exercises from this list'));
    expect(t, contains('bench_press | Bench press'));
    expect(t, contains('Goal: both'));
    expect(t, contains('DAY: '));
    expect(t, contains('exercise_id | sets | reps | rest seconds'));
    final ask = handoffText(await s.aiAskRequest('How long should I rest?', const []));
    expect(ask, contains('How long should I rest?'));
    expect(ask, isNot(contains('PLAN: ')));
    await repo.close();
    dir.deleteSync(recursive: true);
  });

  test('pasting a good answer installs the plan; junk changes nothing', () async {
    final (s, repo, dir) = await make();
    final before = s.plan!.id;
    final r = await s.aiPlanRequest(profile);
    expect(await s.aiApplyText(r, 'Sorry, I can\'t help with that.'), isNotEmpty);
    expect(s.plan!.id, before);
    final good = 'Here is your plan:\n```json\n${jsonEncode({
          'name': 'Claude plan',
          'days': [
            {'name': 'Push', 'items': [{'exercise': 'bench_press', 'sets': 4, 'repLow': 5, 'repHigh': 8, 'rest': 150}]},
            {'name': 'Pull', 'items': [{'exercise': 'lat_pulldown', 'sets': 3, 'repLow': 8, 'repHigh': 12, 'rest': 90}]},
          ]
        })}\n```';
    expect(await s.aiApplyText(r, good), isNull);
    expect(s.plan!.name, 'Claude plan');
    expect(s.plan!.source, 'ai');
    // goblet squat is hard on the knees -> refused
    final bad = good.replaceAll('lat_pulldown', 'goblet_squat');
    expect((await s.aiApplyText(r, bad))!.join(), contains('knees'));
    expect(s.plan!.name, 'Claude plan');
    await repo.close();
    dir.deleteSync(recursive: true);
  });
}
