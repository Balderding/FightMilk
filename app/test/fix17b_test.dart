import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/explain.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plates.dart';
import 'package:workout/domain/program.dart';
import 'package:workout/domain/programs.dart';
import 'package:workout/domain/progression.dart';
import 'package:workout/domain/stats.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/domain/volume.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

/// Fixes from the second review (REVIEW-2026-11-22-0953), fix batch 17b.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final t0 = DateTime(2026, 6, 1, 18);
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  Future<AppState> app() async {
    final dir = Directory.systemTemp.createTempSync('fix17b');
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    return s;
  }

  Future<void> workout(AppState s) async {
    await s.startWorkout();
    final it = s.session!.day.items.first;
    await s.repo.logSet(s.session!.id, it.exerciseId, 50, 8, slot: liftKey(it));
    await s.finishWorkout();
  }

  group('P1-1 the % table plates', () {
    const lbPlates = <double>[45, 35, 25, 10, 5, 2.5];
    final bar = lbToKg(45);
    test('lb plates are shown as they are, not converted twice', () {
      expect(plateLine(lbToKg(225), bar, lbPlates, Unit.lb), 'per side 45 + 45');
      expect(plateLine(lbToKg(235), bar, lbPlates, Unit.lb), 'per side 45 + 45 + 5');
      expect(plateLine(bar, bar, lbPlates, Unit.lb), 'the bar');
    });

    test('below the bar, and "≈" when the plates make another weight', () {
      expect(plateLine(lbToKg(30), bar, lbPlates, Unit.lb), 'below the bar');
      expect(plateLine(15, 20, const <double>[25, 20, 15, 10, 5, 2.5], Unit.kg), 'below the bar');
      // 62.5 kg with no 1.25 kg plates: 21.25 a side cannot be made, 20 a side makes 60
      expect(plateLine(62.5, 20, const <double>[25, 20, 15, 10, 5, 2.5], Unit.kg), 'per side 20 ≈ 60');
      expect(plateLine(62.5, 20, const <double>[25, 20, 15, 10, 5, 2.5, 1.25], Unit.kg), 'per side 20 + 1.25');
    });
  });

  group('P1-2 a missed rep (0 reps) is not a lift', () {
    test('e1RM, records and the chart skip it', () {
      expect(e1rm(140, 0), 0);
      expect(e1rm(140, 1), 140);
      final sq = lib.byId('back_squat')!;
      final sets = [
        SetLog(id: 'a', sessionId: 's1', exerciseId: 'back_squat', kg: 120, reps: 5, at: t0),
        SetLog(id: 'b', sessionId: 's2', exerciseId: 'back_squat', kg: 140, reps: 0, at: t0.add(const Duration(days: 7))),
      ];
      final cur = currentRecords(recordHistory(sets, sq));
      expect(cur[RecordKind.heaviest]!.value, 120);
      expect(cur[RecordKind.e1rm]!.value, closeTo(140, 0.01)); // 120 x 5, not the missed 140
      expect(cur[RecordKind.e1rm]!.session, 's1');
      expect(seriesOf(sets, ChartKind.heaviest).map((p) => p.session), ['s1']);
      expect(seriesOf(sets, ChartKind.e1rm).map((p) => p.session), ['s1'], reason: 'a missed-only workout is no point (review 3, P2-9)');
      expect(seriesOf(sets, ChartKind.bestSetVolume).map((p) => p.session), ['s1']);
    });

    test('a missed test single on a 1RM-basis program falls to the best real set', () {
      final sq = lib.byId('back_squat')!;
      const r = LiftRule(kind: 'tm', inc: 1);
      const st = LiftState(exerciseId: 'back_squat', workKg: 90, tm: 100);
      final day = [const SetLog(exerciseId: 'back_squat', kg: 90, reps: 1), const SetLog(exerciseId: 'back_squat', kg: 100, reps: 0)];
      expect(programNext(st, r, sq, day, parseSets('1x1@90 1x1+@100'), Unit.kg, bump: 'test', basis: '1rm').state.tm, 90);
    });
  });

  group('P1-3 a swap for a block belongs to its plan and ends by date', () {
    test('another plan is never rewritten; the first plan gets its lift back when it is in use again', () async {
      final s = await app();
      final a = s.plan!;
      final id = a.days.first.items.first.exerciseId;
      final v = await s.swapForBlock(id);
      expect(v, isNotNull);
      expect(s.plan!.days.first.items.first.exerciseId, v!.id);
      // plan B uses the variation on purpose
      await s.usePlan(Plan(name: 'B', days: [PlanDay(name: 'B1', items: [PlanItem(exerciseId: v.id, sets: 3, repLow: 8, repHigh: 12, restSec: 90)])]));
      for (var k = 0; k < 6; k++) {
        await workout(s);
      }
      expect(s.plan!.days.first.items.first.exerciseId, v.id, reason: 'plan B keeps its own exercise');
      expect(s.blockSwaps, isNotEmpty, reason: 'the swap waits for its own plan');
      // four weeks later, back on plan A: the lift comes back at its own place
      final key = s.blockSwaps.keys.single;
      s.blockSwaps[key]!['until'] = DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch;
      await s.repo.kvSet('block_swaps', jsonEncode(s.blockSwaps));
      await s.restorePlan(a.id);
      expect(s.plan!.days.first.items.first.exerciseId, id);
      expect(s.blockSwaps, isEmpty);
      expect(s.programNotes.join(), contains('Block done'));
      await workout(s);
      expect(s.programNotes.join(), isNot(contains('Block done')), reason: 'shown once (review 4, P3-N11)');
    });

    test('a program keeps its own lifts: no swap of % sets, and the AI tool says so', () async {
      final s = await app();
      await s.startProgram(buildProgram(templateById('531_base')!, full, lib), {'overhead_press': 60, 'deadlift': 160, 'bench_press': 100, 'back_squat': 140});
      expect(s.blockSwapPlaces('overhead_press'), isEmpty);
      expect(await s.swapForBlock('overhead_press'), isNull);
      expect(parseToolReply('SAY: x\nDO: stall swap overhead_press', s).errors.join(), contains('program keeps its own lifts'));
    });
  });

  test('P2-1 records: one per kind per workout, against the workouts before; the first workout breaks nothing', () {
    final sq = lib.byId('back_squat')!;
    SetLog x(String id, String ses, int day, double kg, int reps, int k) => SetLog(id: id, sessionId: ses, exerciseId: 'back_squat', kg: kg, reps: reps, at: t0.add(Duration(days: day, minutes: k)));
    final first = [x('a', 's1', 0, 60, 5, 0), x('b', 's1', 0, 80, 5, 1), x('c', 's1', 0, 100, 5, 2)];
    final h1 = recordHistory(first, sq);
    expect(h1.where((r) => r.before != null), isEmpty, reason: 'nothing was broken on the first workout');
    expect(medalSets(h1), isEmpty);
    expect(currentRecords(h1)[RecordKind.heaviest]!.value, 100);
    final second = [...first, x('d', 's2', 7, 102.5, 3, 0), x('e', 's2', 7, 105, 3, 1)];
    final h2 = recordHistory(second, sq);
    final heavy = h2.where((r) => r.kind == RecordKind.heaviest && r.before != null).toList();
    expect(heavy.length, 1, reason: 'one heaviest record for the workout, not one per rising set');
    expect([heavy.single.value, heavy.single.before], [105, 100]);
    expect(medalSets(h2), contains('e'));
    expect(medalSets(h2), isNot(contains('d')));
  });

  group('P2-4 the Why sheet', () {
    test('a program lift says the program set it, not the last weight', () async {
      final s = await app();
      await s.startProgram(buildProgram(templateById('531_base')!, full, lib), {'overhead_press': 60, 'deadlift': 160, 'bench_press': 100, 'back_squat': 140});
      await s.pickDay(8); // W3 Press, a bump day
      final it = s.today!.items.first;
      await s.startWorkout();
      for (final (kg, r) in [(45.0, 5), (51.0, 3), (57.0, 3)]) {
        await s.repo.logSet(s.session!.id, it.exerciseId, kg, r, slot: liftKey(it), type: r == 3 && kg == 57 ? SetType.amrap : SetType.work);
      }
      await s.finishWorkout();
      await s.pickDay(0);
      final t = await s.targetFor(s.today!.items.first);
      expect(t.tm, isNotNull);
      expect(t.reason, contains('training max'));
    });

    test('exercise and rest lines say only what is true', () {
      final bodyweightGym = Profile(goal: Goal.both, days: 3, minutes: 45, have: {Equipment.bodyweight, Equipment.dumbbell}, avoid: {}, unit: Unit.kg);
      expect(exerciseWhy(lib.byId('bench_press')!, 1, bodyweightGym), isNot(contains('which your gym has')));
      expect(exerciseWhy(lib.byId('db_bench_press')!, 1, bodyweightGym), contains('which your gym has'));
      expect(exerciseWhy(lib.byId('db_curl')!, 0, full), startsWith('First up'));
      expect(exerciseWhy(lib.byId('back_squat')!, 0, full), startsWith('The main lift of the day'));
      final it = PlanItem.of('overhead_press', parseSets('1x5@75 1x3@85 1x1+@95'));
      expect(restWhy(lib.byId('overhead_press')!, it, smart: true, planRest: 90, setReps: 1), contains('Heavy (1 rep)'));
    });
  });

  test('P2-5 in a deload week the finish sheet says weights stay, not +2.5 kg', () async {
    final s = await app();
    await s.setDeload(true);
    await s.startWorkout();
    expect(s.sessionDeload, isTrue);
    final it = s.session!.day.items.first;
    for (var i = 0; i < it.sets; i++) {
      await s.repo.logSet(s.session!.id, it.exerciseId, 50, it.repHigh, slot: liftKey(it));
    }
    final p = await s.previewNext();
    expect(p.single.text, 'Deload week: weights stay where they are.');
    expect(nextSummary([const NextLine('a', 1), const NextLine('b', 0), const NextLine('c', 0)]), '1 up, 2 the same');
  });

  test('P2-7 every tool in the AI help is in the on-phone grammar (whole plans have their own task)', () async {
    final s = await app();
    final help = toolHelp(s.lib);
    final verbs = {for (final m in RegExp(r'^DO: ([a-z_]+)', multiLine: true).allMatches(help)) m[1]!};
    expect(verbs, containsAll(['changes', 'dashboard', 'sore', 'stall']));
    final g = toolGrammar(s.lib, s.profile!, s.plan!.days.length);
    for (final v in verbs.difference({'plan'})) {
      expect(g.contains('"$v'), isTrue, reason: 'the on-phone model cannot call "$v"');
    }
    expect(g, contains('"changes undo "'));
    expect(g, contains('"week_workouts"'));
  });

  test('P2-2 the rep-max grid runs the chosen formula backwards: a 100 x 5 set says 100 at 5 reps', () {
    final sets = [const SetLog(exerciseId: 'bench_press', kg: 100, reps: 5)];
    for (final f in ['epley', 'brzycki']) {
      e1rmFormula = f;
      expect(repMaxGrid(sets)[4].$3, closeTo(100, 0.01), reason: f);
      expect(repsAt(e1rm(80, 8), 8), closeTo(80, 0.01), reason: f);
    }
    e1rmFormula = 'epley';
  });

  group('P2-3 plan import reads what lifters write, and lists what it cannot', () {
    List<String> ids(TextPlan r, [int d = 0]) => [for (final i in r.plan!.days[d].items) i.exerciseId];

    test('note lines never start a day; they are listed', () {
      final r = parseTextPlan('Day 1\nBench press 3x8\nNotes: go heavy\nSquat 3x5', lib);
      expect(r.plan!.days.length, 1);
      expect(ids(r), ['bench_press', 'back_squat']);
      expect(r.unknown, ['Notes: go heavy']);
      final r2 = parseTextPlan('Legs\nSquat 3x5\nRest 2 min between sets\nLeg curl 3x12', lib);
      expect(r2.plan!.days.single.name, 'Legs');
      expect(ids(r2), ['back_squat', 'lying_leg_curl']);
      expect(r2.unknown.single, startsWith('Rest 2 min'));
    });

    test('Day 10 and on are days; more than 14 says how many were kept', () {
      final r = parseTextPlan([for (var i = 1; i <= 12; i++) 'Day $i\nSquat 3x5'].join('\n'), lib);
      expect(r.plan!.days.length, 12);
      expect(r.plan!.days.last.name, 'Day 12');
      final many = parseTextPlan([for (var i = 1; i <= 20; i++) 'Day $i\nSquat 3x5'].join('\n'), lib);
      expect([many.plan!.days.length, many.days], [14, 20]);
    });

    test('AMRAP, max, sets first, CSV, seconds and rest wording', () {
      final pull = parseTextPlan('Pull\nPull-ups 3xAMRAP\nChin-ups 3 x max\nBarbell row 4x6-8', lib);
      expect(ids(pull), ['pull_up', 'chin_up', 'barbell_row']);
      expect(pull.plan!.days.single.items.first.style, 'amrap');
      expect(pull.unknown, isEmpty);
      expect(ids(parseTextPlan('Day A\n5x5 Squat\n5x5 Bench press', lib)), ['back_squat', 'bench_press']);
      final csv = parseTextPlan('Bench press,3,8\nSquat,3,5', lib);
      expect(ids(csv), ['bench_press', 'back_squat']);
      expect(csv.plan!.days.single.items.last.repLow, 5);
      final core = parseTextPlan('Core\nPlank 3x60s\nSide plank 3 x 30 sec', lib);
      expect(core.plan!.days.single.items.first.repLow, 60);
      final up = parseTextPlan('Upper\nBench press 3 x 8-12, 90 sec rest\nLat pulldown 3x10 2 min', lib);
      expect([up.plan!.days.single.items[0].restSec, up.plan!.days.single.items[1].restSec], [90, 120]);
      expect(parseTextPlan('Monday\n1. Squat 5x5\n2. Bench 5x5\nWednesday\nDeadlift 1x5', lib).plan!.days.map((d) => d.name), ['Monday', 'Wednesday']);
    });

    test('short names mean what lifters mean: curl is a biceps curl, a lone press the overhead press', () {
      final a = parseTextPlan('A\nCurl 3x8 to 12\nDips 3x8-12', lib);
      expect(lib.byId(ids(a).first)!.primary.first, 'biceps');
      expect([a.plan!.days.single.items.first.repLow, a.plan!.days.single.items.first.repHigh], [8, 12]);
      expect(ids(parseTextPlan('Push\nPress 3x8\nRows 3x10', lib)), ['overhead_press', 'barbell_row']);
    });
  });

  test('P3-N1 BBB 5x10 at 50% counts as hard work; nSuns ramps still do not', () {
    final bbb = planWeekSets(buildProgram(templateById('531_bbb')!, full, lib), lib);
    expect(bbb['chest']!, greaterThanOrEqualTo(8));
    final ns = planWeekSets(buildProgram(templateById('nsuns_4')!, full, lib), lib);
    expect(ns['shoulders']!, lessThanOrEqualTo(28));
  });

  test('P3-N5 a record says what it beat in the same words', () {
    final b = lib.byId('bench_press')!;
    final sets = [
      SetLog(id: 'a', sessionId: 's1', exerciseId: 'bench_press', kg: 100, reps: 5, at: t0),
      SetLog(id: 'b', sessionId: 's2', exerciseId: 'bench_press', kg: 100, reps: 8, at: t0.add(const Duration(days: 7))),
    ];
    final r = recordHistory(sets, b).firstWhere((x) => x.kind == RecordKind.bestSetVolume && x.before != null);
    expect(recordText(Rec(r.kind, r.before!, r.at, '', set: r.beforeSet), Unit.kg), '100 kg × 5');
  });

  test('P3-N4 a max box takes a unit, and says when it cannot read the text', () {
    expect(parseMaxInput('100kg', Unit.lb, 'tm90'), 100);
    expect(parseMaxInput('225 lb x 5', Unit.kg, '1rm'), closeTo(lbToKg(225) * (1 + 5 / 30), 0.01));
    expect(parseMaxInput('a lot', Unit.kg, 'tm90'), isNull);
  });
}
