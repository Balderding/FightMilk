// Training-example prompts for the on-phone coach, built with the app's OWN prompt code so the
// training inputs are exactly what the phone sends. Made-up lifters only - nothing personal.
// Run: FM_OUT=.../prompts.jsonl [FM_QUESTIONS=.../questions.txt] flutter test test_live/gen_training_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/ai/prompt.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/units.dart';

final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());

T pick<T>(Random r, List<T> l) => l[r.nextInt(l.length)];

Profile randomProfile(Random r) {
  final gyms = <Set<Equipment>>[
    Equipment.values.where((e) => e != Equipment.bodyweight).toSet(), // full gym
    {Equipment.barbell, Equipment.dumbbell, Equipment.machine, Equipment.cable},
    {Equipment.barbell, Equipment.dumbbell, Equipment.machine, Equipment.cable, Equipment.smith},
    {Equipment.dumbbell, Equipment.band}, // home
    {Equipment.dumbbell, Equipment.kettlebell, Equipment.band},
    {Equipment.machine, Equipment.cable}, // machines only
    {Equipment.barbell, Equipment.dumbbell}, // garage gym
    {Equipment.dumbbell, Equipment.machine, Equipment.cable},
  ];
  final w = [30, 25, 10, 8, 5, 8, 9, 5];
  var x = r.nextInt(w.reduce((a, b) => a + b));
  var gi = 0;
  while (x >= w[gi]) {
    x -= w[gi];
    gi++;
  }
  final avoid = <Joint>{};
  final a = r.nextDouble();
  if (a > .65) avoid.add(pick(r, Joint.values));
  if (a > .9) avoid.add(pick(r, Joint.values));
  final days = pick(r, [2, 3, 3, 4, 4, 4, 5, 5, 6]);
  String? split;
  if (r.nextDouble() < .45) {
    split = pick(r, ['full_body', 'upper_lower', 'ppl', 'bro']);
    if (split == 'bro' && days < 4) split = 'full_body';
  }
  return Profile(goal: pick(r, Goal.values), days: days, minutes: pick(r, [45, 60, 60, 90]), have: gyms[gi], avoid: avoid, unit: r.nextDouble() < .72 ? Unit.lb : Unit.kg, split: split);
}

/// Working weight in lb for a lifter of [level] 0 (new) .. 2 (strong).
double baseLb(Exercise e, int level, Random r) {
  if (e.bodyweight) return r.nextDouble() < .25 && level > 0 ? 10.0 * level : 0;
  final lower = const {'quads', 'hamstrings', 'glutes'}.contains(e.primary.first);
  double b = switch (e.equipment) {
    Equipment.barbell || Equipment.smith => lower ? [135, 225, 315][level] : [95, 165, 225][level],
    Equipment.dumbbell || Equipment.kettlebell => lower ? [30, 50, 80][level] : [20, 40, 65][level],
    Equipment.machine => lower ? [140, 260, 400][level] : [70, 140, 210][level],
    Equipment.cable => [40, 80, 120][level],
    _ => 0,
  }.toDouble();
  if (!e.compound) b *= .45;
  if (e.primary.first == 'shoulders' && e.compound) b *= .65;
  return max(5, (b * (0.85 + r.nextDouble() * .3) / 5).round() * 5.0);
}

/// Two weeks of sets for the plan's days, with a story per lift: progressing, stalled, missing, skipped.
List<SetLog> history(Plan plan, Profile p, Random r, {required int todayIndex}) {
  final level = r.nextInt(3);
  final sessions = r.nextInt(7); // 0..6 workouts in the last 14 days
  final out = <SetLog>[];
  final story = <String, String>{};
  final now = DateTime(2026, 11, 20, 18);
  for (var k = sessions; k >= 1; k--) {
    final di = (todayIndex - k) % plan.days.length;
    final day = plan.days[di < 0 ? di + plan.days.length : di];
    final when = now.subtract(Duration(days: (k * 14 / max(1, sessions)).round()));
    for (final it in day.items) {
      final e = lib.byId(it.exerciseId)!;
      final s = story.putIfAbsent(e.id, () => pick(r, ['progress', 'progress', 'stall', 'stall', 'miss', 'skip', 'easy']));
      if (s == 'skip' && r.nextDouble() < .7) continue;
      final kg = lbToKg(baseLb(e, level, r) + (s == 'progress' ? (sessions - k) * 5 : 0));
      for (var n = 0; n < it.sets; n++) {
        final reps = switch (s) {
          'miss' => max(1, it.repLow - 1 - r.nextInt(2)),
          'easy' => it.repHigh + 1 + r.nextInt(2),
          'stall' => it.repLow + r.nextInt(max(1, it.repHigh - it.repLow)),
          _ => n < it.sets - 1 ? it.repHigh : it.repHigh - r.nextInt(2),
        };
        out.add(SetLog(exerciseId: e.id, kg: e.bodyweight ? 0 : kg, reps: e.timed ? 30 + r.nextInt(30) : reps, at: when));
      }
    }
  }
  return out;
}

const freeNotes = [
  'no bench today, the benches are all taken',
  'my left shoulder is a bit sore',
  'I want to focus a little more on arms today',
  'I have 90 minutes today',
  'the cable machines are all busy',
  'my lower back feels tight',
  'I did a long run yesterday so my legs are tired',
  'I want to try a heavier top set on the main lift',
  'I am coming back after a week off',
  'only dumbbells are free right now',
];

Map<String, dynamic> dayInfo(Profile p, String name) {
  final all = [for (final e in lib.available(p.have, p.avoid)) if ((musclesFor(name) == null || musclesFor(name)!.contains(e.primary.first) || e.primary.first == 'core')) e];
  var first = [for (final e in all) if (e.compound && e.primary.first != 'core') e.id];
  if (first.isEmpty) first = [for (final e in all) e.id];
  return {'name': name, 'allowed': [for (final e in all) e.id], 'first': first};
}

void main() {
  test('generate', () {
    final out = Platform.environment['FM_OUT'] ?? '';
    expect(out, isNotEmpty);
    final qFile = Platform.environment['FM_QUESTIONS'];
    final questions = qFile == null ? <String>[] : File(qFile).readAsLinesSync().map((l) => l.trim()).where((l) => l.length > 8).toList();
    // FM_ONLY=ask: only coach questions, as round 2 ("ask2" ids, new lifters)
    final askOnly = Platform.environment['FM_ONLY'] == 'ask';
    final r = Random(askOnly ? 20261121 : 20261120);
    final rows = <Map<String, dynamic>>[];
    void add(String task, int i, Profile p, String system, String user, {List<Map<String, dynamic>>? days, String? grammar}) {
      rows.add({
        'id': '$task-${i.toString().padLeft(4, '0')}',
        'task': task == 'ask2' ? 'ask' : task,
        'system': system,
        'user': user,
        'profile': p.toJson(),
        'cap': capFor(p.minutes),
        if (days != null) 'days': days,
        if (grammar != null) 'grammar': grammar,
      });
    }

    for (var i = 0; i < (askOnly ? 0 : 1000); i++) {
      final p = randomProfile(r);
      final plan = makePlan(p, lib);
      final recent = r.nextDouble() < .5 ? history(plan, p, r, todayIndex: r.nextInt(plan.days.length)) : <SetLog>[];
      add('plan', i, p, localSystemPrompt(lib, p, wholePlan: true),
          buildRequest(p, plan, recent, lib, 'Improve this starting plan for my goal, equipment and session length. Keep the day names.'),
          days: [for (final n in dayNames(p.days, p.split)) dayInfo(p, n)], grammar: planGrammar(lib, p));
    }
    for (var i = 0; i < (askOnly ? 0 : 1000); i++) {
      final p = randomProfile(r);
      final plan = makePlan(p, lib);
      final di = r.nextInt(plan.days.length);
      final day = plan.days[di];
      final recent = history(plan, p, r, todayIndex: di);
      final notes = <String>[];
      final n = r.nextDouble();
      if (n > .4) notes.add(pick(r, todayNotes.values.toList()));
      if (n > .9) notes.add(pick(r, todayNotes.values.toList()));
      if (r.nextDouble() < .15) notes.add(pick(r, freeNotes));
      final extra = notes.isEmpty ? '' : ' ${notes.toSet().join(' ')}';
      add('today', i, p, localSystemPrompt(lib, p, wholePlan: false),
          buildRequest(p, day, recent, lib, "Adjust today's workout (${day.name}) based on my recent training.$extra"),
          days: [dayInfo(p, day.name)], grammar: dayGrammar(lib, p, day.name));
    }
    for (var i = 0; i < (askOnly ? 0 : 500); i++) {
      final p = randomProfile(r);
      final plan = makePlan(p, lib);
      final di = r.nextInt(plan.days.length);
      add('guide', i, p, guidePrompt(), buildRequest(p, plan.days[di], history(plan, p, r, todayIndex: di), lib, guideAsk(plan.days[di].name)));
    }
    for (var i = 0; i < questions.length; i++) {
      final p = randomProfile(r);
      final plan = makePlan(p, lib);
      final recent = r.nextDouble() < .7 ? history(plan, p, r, todayIndex: r.nextInt(plan.days.length)) : <SetLog>[];
      add(askOnly ? 'ask2' : 'ask', i, p, coachPrompt(), buildRequest(p, plan, recent, lib, questions[i]));
    }
    File(out).writeAsStringSync(rows.map(jsonEncode).join('\n') + '\n');
    print('${rows.length} prompts -> $out');
  });
}
