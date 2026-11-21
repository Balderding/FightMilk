// Live check: the on-phone model (on the PC through our C bridge) using the app tools.
// Run: LFM_DLL=... LFM_MODEL=... flutter test test_live/tools_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/ai.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/llm/native.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final dll = Platform.environment['LFM_DLL'] ?? '';
  final model = Platform.environment['LFM_MODEL'] ?? '';
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: {Equipment.dumbbell, Equipment.machine, Equipment.cable, Equipment.smith, Equipment.bodyweight}, avoid: {}, unit: Unit.lb);
  final out = StringBuffer();
  tearDownAll(() => File('../work/tools_live.txt').writeAsStringSync(out.toString()));

  const asks = [
    'Set me up a chest, shoulders and arms workout for today.',
    'Remind me to train Monday, Wednesday and Friday at 18:00.',
    'Give me 2 minutes rest between sets.',
    'How long should I rest between heavy sets?',
  ];

  for (final ask in asks) {
    test(ask, () async {
      final dir = Directory.systemTemp.createTempSync('tl');
      final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
      final s = await AppState.forTest(r, PackStore(dir.path), lib);
      await s.saveProfile(profile);
      await s.makeBuiltInPlan();
      await s.saveSettings(s.settings.copyWith(ai: const AiConfig(kind: AiKind.onDevice, model: 'lfm2.5-1.2b-instruct')));
      final req = await s.aiToolRequest(ask, const []);
      final res = await runLocal(library: dll, modelPath: model, system: req.system, user: req.user,
          grammar: toolGrammar(lib, profile, s.plan!.days.length, mustAct: looksLikeChange(ask)), maxTokens: 700, temperature: 0.5, threads: 4);
      final p = parseToolReply(res.text, s);
      out.writeln('ASK: $ask\n${res.millis} ms status=${res.status} ${res.error}\n${res.text}\nerrors=${p.errors}\nactions=${p.actions.map((a) => a.says).toList()}\n');
      expect(res.status, anyOf(0, 4));
      expect(p.errors, isEmpty);
      if (looksLikeChange(ask)) expect(p.actions, isNotEmpty);
      await r.close();
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
