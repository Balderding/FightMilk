// Live check of the on-phone engine, on the PC: the real LFM model through our C bridge (Windows DLL).
// Run: LFM_DLL=... LFM_MODEL=... flutter test test_live/lfm_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/ai/plan_json.dart';
import 'package:workout/ai/prompt.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/llm/native.dart';

void main() {
  final dll = Platform.environment['LFM_DLL'] ?? '';
  final model = Platform.environment['LFM_MODEL'] ?? '';
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: {Equipment.barbell, Equipment.dumbbell, Equipment.machine, Equipment.cable}, avoid: {Joint.knees}, unit: Unit.lb);
  final out = StringBuffer();
  tearDownAll(() => File('../work/lfm_live.txt').writeAsStringSync(out.toString()));

  test('plan with the grammar lock', () async {
    final r = await runLocal(library: dll, modelPath: model, system: localSystemPrompt(lib, profile, wholePlan: true),
        user: buildRequest(profile, makePlan(profile, lib), const [], lib, 'Improve this starting plan for my goal, equipment and session length. Keep the day names.'),
        grammar: planGrammar(lib, profile), maxTokens: 700, threads: 4);
    final p = parsePlan(r.text, lib, profile: profile);
    out.writeln('PLAN ${r.millis} ms status=${r.status} ${r.error}\n${r.text}\nerrors=${p.errors}\n');
    expect(r.status, anyOf(0, 4));
    expect(p.errors, isEmpty);
    expect(p.plan!.days.length, 4);
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('adjust today with the grammar lock', () async {
    final day = makePlan(profile, lib).days.first;
    final r = await runLocal(library: dll, modelPath: model, system: localSystemPrompt(lib, profile, wholePlan: false),
        user: buildRequest(profile, day, [SetLog(exerciseId: day.items.first.exerciseId, kg: lbToKg(225), reps: 8, at: DateTime(2026, 11, 17))], lib, "Adjust today's workout (${day.name})."),
        grammar: dayGrammar(lib, profile, day.name), maxTokens: 300, threads: 4);
    final d = parseDay(r.text, lib, profile: profile);
    out.writeln('TODAY ${r.millis} ms status=${r.status}\n${r.text}\nerrors=${d.errors}\n');
    expect(d.errors, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('coach question, free text', () async {
    final r = await runLocal(library: dll, modelPath: model, system: coachPrompt(),
        user: buildRequest(profile, null, const [], lib, 'My bench has been stuck at 225 for 3 weeks. What should I change?'), maxTokens: 400, temperature: 0.7, threads: 4);
    out.writeln('ASK ${r.millis} ms status=${r.status}\n${r.text}\n');
    expect(r.text.length, greaterThan(40));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
