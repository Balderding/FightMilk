// Live check against the real Claude API, using the app's own code. Not part of the normal suite.
// Run: CLAUDE_KEY=... flutter test test_live/live_claude_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/ai/ai.dart';
import 'package:workout/ai/plan_json.dart';
import 'package:workout/ai/prompt.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/net/guarded_client.dart';

void main() {
  HttpOverrides.global = null; // real network for this file only
  final key = Platform.environment['CLAUDE_KEY'] ?? '';
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: {Equipment.barbell, Equipment.dumbbell, Equipment.machine, Equipment.cable}, avoid: {Joint.knees}, unit: Unit.lb);
  const cfg = AiConfig(kind: AiKind.claude, model: 'claude-opus-5-5');
  AiProvider p() => providerFor(cfg, key, GuardedClient(NetGuard(aiHost: cfg.host)));
  final out = StringBuffer();

  tearDownAll(() => File('../work/live_claude.txt').writeAsStringSync(out.toString()));

  test('plan', () async {
    expect(key, isNotEmpty, reason: 'no key');
    final sw = Stopwatch()..start();
    final text = await p().complete(systemPrompt(lib, profile, wholePlan: true), buildRequest(profile, null, const [], lib, 'Make me a 4-day rotation for my goal, equipment and session length.'),
        schema: planSchema(lib, profile));
    final r = parsePlan(text, lib, profile: profile);
    out.writeln('PLAN (${sw.elapsed.inSeconds}s) errors=${r.errors}');
    for (final d in r.plan?.days ?? <PlanDay>[]) {
      out.writeln('  ${d.name}: ${d.items.map((i) => '${lib.byId(i.exerciseId)!.name} ${i.sets}x${i.repLow}-${i.repHigh} r${i.restSec}').join('; ')}');
    }
    expect(r.errors, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('adjust today', () async {
    final day = makePlan(profile, lib).days.first;
    final sw = Stopwatch()..start();
    final text = await p().complete(systemPrompt(lib, profile, wholePlan: false),
        buildRequest(profile, day, [SetLog(exerciseId: day.items.first.exerciseId, kg: lbToKg(225), reps: 8, at: DateTime(2026, 11, 17))], lib, "Adjust today's workout (${day.name}). Keep it the same kind of day."),
        schema: daySchema(lib, profile));
    final r = parseDay(text, lib, profile: profile);
    out.writeln('TODAY (${sw.elapsed.inSeconds}s) errors=${r.errors}');
    out.writeln('  ${r.day?.name}: ${r.day?.items.map((i) => '${lib.byId(i.exerciseId)!.name} ${i.sets}x${i.repLow}-${i.repHigh}').join('; ')}');
    expect(r.errors, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('ask the coach', () async {
    final sw = Stopwatch()..start();
    final a = await p().complete(coachPrompt(), buildRequest(profile, null, const [], lib, 'My bench has been stuck at 225 for 3 weeks. What should I change?'));
    out.writeln('ASK (${sw.elapsed.inSeconds}s):\n$a');
    expect(a.length, greaterThan(40));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
