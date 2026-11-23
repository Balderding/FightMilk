import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/quick.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/explain.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/progression.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('coach'));
  tearDown(() => progressRules = const ProgressRules());

  Future<AppState> app() async {
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    return s;
  }

  SetLog set(double kg, int reps, {String ses = 's', DateTime? at}) => SetLog(exerciseId: 'bench_press', sessionId: ses, kg: kg, reps: reps, at: at);

  /// A workout of today's first exercise: every planned set at [kg] x [reps].
  Future<PlanItem> workout(AppState s, double kg, int reps) async {
    await s.startWorkout();
    final it = s.session!.day.items.first;
    for (var i = 0; i < it.sets; i++) {
      await s.repo.logSet(s.session!.id, it.exerciseId, kg, reps);
    }
    await s.finishWorkout();
    return it;
  }

  group('why lines', () {
    test('every progression step says why in plain words', () {
      final e = lib.byId('bench_press')!;
      const st = LiftState(exerciseId: 'bench_press', workKg: 100);
      expect(nextLift(st, e, [set(100, 10), set(100, 10)], Unit.kg, repLow: 6, repHigh: 10).why, '+2.5 kg: every set hit 10');
      expect(nextLift(st, e, [set(100, 8), set(100, 7)], Unit.kg, repLow: 6, repHigh: 10).why, contains('get every set to 10'));
      final miss = nextLift(st, e, [set(100, 4)], Unit.kg, repLow: 6, repHigh: 10);
      expect(miss.why, contains('1 of 2 before it drops'));
      expect(nextLift(miss, e, [set(100, 4)], Unit.kg, repLow: 6, repHigh: 10).why, '-10%: 2 workouts in a row short of 6 reps');
      final pu = lib.byId('pull_up')!;
      expect(nextLift(const LiftState(exerciseId: 'pull_up', workKg: 0, workReps: 6), pu, [SetLog(exerciseId: 'pull_up', kg: 0, reps: 6)], Unit.kg, repLow: 6, repHigh: 10).why, 'One more rep: every set hit 6');
      // the reason survives a save
      expect(LiftState.fromJson(miss.toJson()).why, miss.why);
    });

    test('the target carries the reason; the exercise and the rest are explained', () async {
      final s = await app();
      final it = await workout(s, 60, s.today!.items.first.repHigh);
      final t = await s.targetFor(s.plan!.days.expand((d) => d.items).firstWhere((x) => x.exerciseId == it.exerciseId));
      expect(t.reason, startsWith('+'));
      final e = lib.byId(it.exerciseId)!;
      expect(exerciseWhy(e, 0, full), startsWith('The main lift of the day'));
      expect(exerciseWhy(lib.byId('cable_fly')!, 3, full.copyWith(avoid: {Joint.knees})), contains('Easy on your knees'));
      expect(restWhy(lib.byId('back_squat')!, PlanItem(exerciseId: 'back_squat', sets: 3, repLow: 5, repHigh: 5, restSec: 180), smart: true, planRest: 90), startsWith('Rest 3:30: Heavy'));
      expect(restWhy(e, it, smart: false, planRest: 90), startsWith('Rest 1:30'));
      progressRules = const ProgressRules(missesToDrop: 3, dropPct: 0.15);
      final rules = rulesText(progressRules, deloadEvery: 4, climb: false, u: Unit.kg);
      expect(rules.firstWhere((r) => r.$1 == 'When you miss').$2, contains('After 3 workouts in a row with a miss, the weight drops 15%'));
      expect(rules.any((r) => r.$1 == 'Volume climb'), isFalse);
    });
  });

  group('change log', () {
    test('each moved weight is listed with its reason and can be put back once', () async {
      final s = await app();
      final it = await workout(s, 60, s.today!.items.first.repHigh);
      expect(s.autoChanges, isNotEmpty);
      final c = s.autoChanges.firstWhere((x) => x['key'] == it.exerciseId);
      expect(s.autoChangeText(c), contains('every set hit'));
      final i = s.autoChanges.indexOf(c);
      expect(await s.bodyContext(), contains('Weights the app moved lately'));
      expect(await s.undoAutoChange(i), isTrue);
      expect((await s.repo.lift(it.exerciseId))!.workKg, 60);
      expect(await s.undoAutoChange(i), isFalse); // only once
    });
  });

  group('stalls and swaps', () {
    test('no new best in 4+ weeks with 3 workouts since is a stall; a rising lift is not', () {
      final now = DateTime(2026, 11, 22);
      final flat = [for (var w = 0; w < 6; w++) set(100, 5, ses: 'w$w', at: now.subtract(Duration(days: 42 - w * 7)))];
      final st = stallOf(flat, false, now);
      expect(st?.weeks, 6);
      expect(st?.sessions, 5);
      final rising = [for (var w = 0; w < 6; w++) set(100 + w * 2.5, 5, ses: 'w$w', at: now.subtract(Duration(days: 42 - w * 7)))];
      expect(stallOf(rising, false, now), isNull);
      expect(stallOf(flat.take(3).toList(), false, now), isNull); // too new to tell
      expect(stallAdvice(lib.byId('bench_press')!, st!), contains('Try a variation for 4 weeks'));
    });

    test('swaps come closest first with a reason; a sore joint moves easier options up', () {
      final bench = lib.byId('bench_press')!;
      final c = lib.swapsFor(bench, Equipment.values.toSet(), {});
      final r = rankSwaps(bench, c);
      expect(r.first.$2, contains('same movement'));
      final sore = rankSwaps(bench, c, avoid: {Joint.shoulders});
      expect(sore.first.$1.joints.contains(Joint.shoulders), isFalse);
      expect(sore.first.$2, contains('easier on shoulders'));
      expect(rankSwaps(bench, c, favs: {'floor_press'}).take(3).map((x) => x.$1.id), contains('floor_press'));
    });

    test('a stuck lift is swapped for a block and comes back after it', () async {
      final s = await app();
      final id = s.today!.items.first.exerciseId;
      final v = await s.swapForBlock(id, weeks: 0);
      expect(v, isNotNull);
      expect(s.plan!.days.expand((d) => d.items).any((i) => i.exerciseId == id), isFalse);
      expect(s.blockSwapOf(id)?['var'], v!.id);
      await s.startWorkout();
      await s.repo.logSet(s.session!.id, s.session!.day.items.first.exerciseId, 50, 8);
      await s.finishWorkout();
      expect(s.plan!.days.expand((d) => d.items).any((i) => i.exerciseId == id), isTrue);
      expect(s.blockSwaps, isEmpty);
      expect(s.programNotes.join(), contains('Block done'));
    });

    test('finish preview and the weekly suggestion', () async {
      final s = await app();
      await s.startWorkout();
      final it = s.session!.day.items.first;
      for (var i = 0; i < it.sets; i++) {
        await s.repo.logSet(s.session!.id, it.exerciseId, 60, it.repHigh);
      }
      final p = await s.previewNext();
      expect(p.single.text, contains('every set hit ${it.repHigh}'));
      expect(await s.repo.lift(it.exerciseId), isNull); // nothing saved by the preview
      await s.finishWorkout();
      // one workout this week: some muscles far under their range
      expect(await s.weeklySuggestion(), anyOf(isNull, contains('sets')));
    });
  });

  group('programs and plans from words', () {
    test('a description finds the program', () {
      expect(matchProgram('531 bbb 4 days')?.id, '531_bbb');
      expect(matchProgram('5/3/1 boring but big')?.id, '531_bbb');
      expect(matchProgram('stronglifts')?.id, 'stronglifts');
      expect(matchProgram('nsuns 5 days')?.id, 'nsuns_5');
      expect(matchProgram('gzclp please')?.id, 'gzclp');
      expect(matchProgram('pizza tonight'), isNull);
    });

    test('a plan written as text is read: days, sets, reps, rest; unknown lines are listed', () {
      const text = '''
Push day:
1. Bench press 4x6-8 120s
- DB shoulder press 3 x 10
Triceps pushdown - 3 sets of 12

Pull
Deadlift 3x5 3 min
Lat pulldowns 3x10-12
Unicorn curls 3x12
''';
      final r = parseTextPlan(text, lib);
      expect(r.plan!.days.map((d) => d.name), ['Push day', 'Pull']);
      final push = r.plan!.days.first.items;
      expect(push.map((i) => i.exerciseId), ['bench_press', 'seated_db_press', 'triceps_pushdown']);
      expect([push.first.sets, push.first.repLow, push.first.repHigh, push.first.restSec], [4, 6, 8, 120]);
      expect(r.plan!.days[1].items.first.restSec, 180);
      expect(r.plan!.days[1].items[1].exerciseId, 'lat_pulldown');
      expect(r.unknown.single, contains('Unicorn'));
      expect(parseTextPlan('hello there\nhow are you', lib).plan, isNull);
    });

    test('tips: one a day, the same all day', () {
      final a = tipOfDay(DateTime(2026, 11, 22, 8)), b = tipOfDay(DateTime(2026, 11, 22, 21));
      expect(a, b);
      expect(tipOfDay(DateTime(2026, 11, 23)), isNot(a));
      expect(tips.length, greaterThanOrEqualTo(30));
    });
  });

  test('every new part has an AI tool, and quick words start a program', () async {
    final s = await app();
    final ex = s.today!.items.first.exerciseId;
    await workout(s, 60, s.today!.items.first.repHigh);
    for (final cmd in ['changes undo 1', 'setting tips off', 'stall swap $ex', 'program start 531 bbb 4 days']) {
      final r = parseToolReply('SAY: ok\nDO: $cmd', s);
      expect(r.errors, isEmpty, reason: cmd);
      for (final a in r.actions) {
        await a.run(s);
      }
    }
    expect(s.settings.tips, isFalse);
    expect(s.plan!.program?.id, '531_bbb');
    final q = quickCommand('start stronglifts', s);
    expect(q?.actions, hasLength(1));
    await q!.actions.single.run(s);
    expect(s.plan!.program?.id, 'stronglifts');
    expect(quickCommand('start the workout', s)?.say, isNot(contains('Starting')));
    expect(toolHelp(s.lib), contains('DO: stall swap'));
  });
}
