import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/program.dart';
import 'package:workout/domain/programs.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/domain/volume.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vol'));

  Future<AppState> app({Profile? p}) async {
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(p ?? full);
    await s.makeBuiltInPlan();
    return s;
  }

  SetLog at(String ex, DateTime t, {int effort = 2, SetType type = SetType.work}) => SetLog(exerciseId: ex, kg: 50, reps: 10, at: t, effort: effort, type: type);

  /// A finished workout of [sets] sets of [ex], [daysAgo] days back.
  Future<void> past(AppState s, String ex, int sets, int daysAgo) async {
    final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
    final t = DateTime.now().subtract(Duration(days: daysAgo, minutes: 5));
    for (var i = 0; i < sets; i++) {
      final x = await s.repo.logSet(ses.id, ex, 60, 8);
      await s.repo.db.update('set_log', {'at': t.millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [x.id]);
    }
    await s.repo.db.update('session', {'finished': t.millisecondsSinceEpoch, 'started': t.millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [ses.id]);
  }

  group('weekly sets per muscle', () {
    test('helpers count half; finer muscles fold in; a 3-day rotation trained twice counts two thirds', () {
      final bench = setShare(lib.byId('bench_press')!);
      expect(bench, {'chest': 1.0, 'triceps': 0.5, 'shoulders': 0.5});
      expect(setShare(lib.byId('lat_pulldown')!)['back'], 1.0); // lats → back
      final plan = Plan(name: 'p', days: [
        PlanDay(name: 'A', items: [PlanItem(exerciseId: 'bench_press', sets: 3, repLow: 5, repHigh: 8, restSec: 120)]),
        PlanDay(name: 'B', items: [PlanItem(exerciseId: 'bench_press', sets: 3, repLow: 5, repHigh: 8, restSec: 120)]),
        PlanDay(name: 'C', items: [PlanItem(exerciseId: 'back_squat', sets: 3, repLow: 5, repHigh: 8, restSec: 120)]),
      ]);
      expect(planWeekSets(plan, lib)['chest'], 6);
      expect(planWeekSets(plan, lib, perWeek: 2)['chest'], 4);
      expect(planWeekSets(plan, lib)['triceps'], 3);
    });

    test('ranges follow the goal, experience, priority and "less work"; status words', () {
      expect(muscleTarget('chest', full).lo, 10);
      expect(muscleTarget('chest', full).hi, 20);
      expect(volumeText(8, muscleTarget('chest', full)), '8 of 10-20');
      final str = full.copyWith(goal: Goal.strength);
      expect(muscleTarget('chest', str).hi, lessThan(20));
      expect(muscleTarget('chest', full.copyWith(experience: 'new')).hi, lessThan(20));
      expect(muscleTarget('chest', full.copyWith(priority: {'chest'})).lo, 15);
      expect(muscleTarget('chest', full.copyWith(low: {'chest'})).hi, 10);
      expect(statusOf('chest', 8, full), VolumeStatus.under);
      expect(statusOf('chest', 14, full), VolumeStatus.on);
      expect(statusOf('chest', 21, full), VolumeStatus.over);
      expect(statusOf('chest', 30, full), VolumeStatus.tooMuch);
    });

    test('the plan maker lands the big muscles in range and stays inside the time', () {
      for (final days in [2, 3, 4, 5]) {
        final p = full.copyWith(days: days);
        final plan = makePlan(p, lib);
        final w = planWeekSets(plan, lib, perWeek: days);
        for (final m in const ['chest', 'back', 'quads']) {
          expect(statusOf(m, w[m] ?? 0, p), isNot(VolumeStatus.tooMuch), reason: '$days days $m ${w[m]}');
        }
        for (final d in plan.days) {
          expect(dayMinutes(d, lib), lessThanOrEqualTo((p.minutes * 1.15).round() + 15), reason: '$days days ${d.name}');
        }
      }
    });

    test('fit: sets are added where a muscle is under, taken off where it is far over; programs keep theirs', () {
      final thin = Plan(name: 'p', days: [
        PlanDay(name: 'A', items: [PlanItem(exerciseId: 'bench_press', sets: 2, repLow: 5, repHigh: 8, restSec: 90), PlanItem(exerciseId: 'barbell_row', sets: 2, repLow: 5, repHigh: 8, restSec: 90)]),
        PlanDay(name: 'B', items: [PlanItem(exerciseId: 'db_bench_press', sets: 2, repLow: 8, repHigh: 12, restSec: 90), PlanItem(exerciseId: 'lat_pulldown', sets: 2, repLow: 8, repHigh: 12, restSec: 90)]),
      ]);
      final p = full.copyWith(days: 2);
      expect(statusOf('chest', planWeekSets(thin, lib, perWeek: 2)['chest']!, p), VolumeStatus.under);
      final fit = fitVolume(thin, p, lib);
      expect(planWeekSets(fit, lib, perWeek: 2)['chest'], greaterThan(4));
      expect(fit.days.expand((d) => d.items).every((it) => it.sets <= 5), isTrue);
      final heavy = Plan(name: 'p', days: [
        PlanDay(name: 'A', items: [for (final id in ['bench_press', 'db_bench_press', 'incline_bench_press', 'cable_fly', 'pec_deck']) PlanItem(exerciseId: id, sets: 5, repLow: 8, repHigh: 12, restSec: 60)]),
      ]);
      final cut = fitVolume(heavy, full.copyWith(days: 2), lib);
      expect(planWeekSets(cut, lib, perWeek: 2)['chest']!, lessThanOrEqualTo(22));
      for (final id in ['531_bbb', 'stronglifts']) {
        final prog = buildProgram(templateById(id)!, full, lib);
        expect(identical(fitVolume(prog, full, lib), prog), isTrue, reason: id);
      }
    });

    test('lopsided plans are named: no legs, light legs', () {
      final upper = Plan(name: 'p', days: [
        PlanDay(name: 'A', items: [PlanItem(exerciseId: 'bench_press', sets: 4, repLow: 5, repHigh: 8, restSec: 90)]),
        PlanDay(name: 'B', items: [PlanItem(exerciseId: 'barbell_row', sets: 4, repLow: 5, repHigh: 8, restSec: 90)]),
      ]);
      expect(planWarnings(upper, lib), contains('No leg work in this plan.'));
      final light = Plan(name: 'p', days: [
        upper.days[0].copyWith(items: [...upper.days[0].items, PlanItem(exerciseId: 'overhead_press', sets: 4, repLow: 5, repHigh: 8, restSec: 90)]),
        upper.days[1].copyWith(items: [...upper.days[1].items, PlanItem(exerciseId: 'standing_calf_raise', sets: 2, repLow: 10, repHigh: 15, restSec: 60)]),
      ]);
      expect(planWarnings(light, lib).any((w) => w.startsWith('Light on legs')), isTrue);
      expect(dayMinutes(upper.days[0], lib), inInclusiveRange(5, 12));
    });

    test('weekly trend buckets the log by week; warm-ups do not count', () {
      final now = DateTime(2026, 11, 22, 18);
      final log = [
        at('bench_press', now.subtract(const Duration(days: 1))),
        at('bench_press', now.subtract(const Duration(days: 2))),
        at('bench_press', now.subtract(const Duration(days: 9))),
        at('bench_press', now.subtract(const Duration(days: 1)), type: SetType.warmup),
      ];
      final w = weeklyMuscles(log, lib, now, 2);
      expect(w.sets['chest'], [1, 2]);
      expect(w.sets['triceps'], [0.5, 1]);
      expect(w.kg['chest']!.last, 1000);
    });
  });

  group('recovery', () {
    test('tiredness fades over 72 h for big muscles, 48 h for small; hard sets count more', () {
      final now = DateTime(2026, 11, 22, 18);
      final six = [for (var i = 0; i < 6; i++) at('bench_press', now.subtract(const Duration(hours: 1)))];
      final r = recovery(six, lib, now);
      expect(r['chest']!.pct, inInclusiveRange(38, 45));
      expect(r['triceps']!.pct, greaterThan(r['chest']!.pct));
      expect(recovery(six, lib, now.add(const Duration(hours: 36)))['chest']!.pct, inInclusiveRange(65, 75));
      expect(recovery(six, lib, now.add(const Duration(hours: 80)))['chest']!.pct, 100);
      final hard = [for (var i = 0; i < 6; i++) at('bench_press', now.subtract(const Duration(hours: 1)), effort: 4)];
      expect(recovery(hard, lib, now)['chest']!.pct, lessThan(r['chest']!.pct));
      expect(recovery(const [], lib, now)['quads']!.pct, 100);
      expect(agoText(now.subtract(const Duration(days: 1)), now), 'yesterday');
    });

    test('days in a row; extra sets earlier in a workout make the next weight lighter', () {
      final now = DateTime(2026, 11, 22, 18);
      expect(trainingStreak([for (var d = 1; d <= 4; d++) now.subtract(Duration(days: d))], now), 4);
      expect(trainingStreak([now.subtract(const Duration(days: 2))], now), 0);
      final incline = lib.byId('incline_bench_press')!;
      final planned = [PlanItem(exerciseId: 'incline_bench_press', sets: 3, repLow: 8, repHigh: 12, restSec: 90), PlanItem(exerciseId: 'bench_press', sets: 3, repLow: 5, repHigh: 8, restSec: 90)];
      final done = [for (var i = 0; i < 6; i++) at('bench_press', now)];
      final extra = extraSetsBefore(incline, done, planned, lib);
      expect(extra, 6);
      expect(fatigueFactor(extra), closeTo(0.95, 0.001));
      expect(fatigueFactor(2), 1);
      expect(fatigueFactor(30), 0.9);
      // done in the planned order: nothing extra
      expect(extraSetsBefore(lib.byId('bench_press')!, [for (var i = 0; i < 3; i++) at('incline_bench_press', now)], planned, lib), lessThanOrEqualTo(0));
    });

    test('Today: a muscle trained yesterday is flagged (not one trained today); more days in a row than the plan trains suggests a day off', () async {
      final s = await app(); // a 4-day plan
      expect(await s.recoveryHint(), isNull);
      final first = s.lib.byId(s.today!.items.first.exerciseId)!;
      await past(s, first.id, 8, 0);
      expect((await s.recoveryHint())?.warn, isNull, reason: 'trained today: you know');
      await past(s, first.id, 8, 1);
      final h = await s.recoveryHint();
      expect(h?.warn, contains('still recovering'));
      for (var d = 2; d <= 3; d++) {
        await past(s, 'standing_calf_raise', 1, d);
      }
      expect((await s.recoveryHint())?.rest, isNull, reason: '4 days running is what a 4-day plan does');
      await past(s, 'standing_calf_raise', 1, 4);
      final h2 = await s.recoveryHint();
      expect(h2?.rest, contains('5 days in a row'));
      await s.hideRestHint();
      expect((await s.recoveryHint())?.rest, isNull);
      expect(await s.bodyContext(), contains('Still recovering'));
      // a 6-day plan (PPL twice): 5 days running is the plan, no card
      await s.saveProfile(s.profile!.copyWith(days: 6));
      await s.repo.kvSet('rest_hint_off', '');
      await s.reload();
      expect((await s.recoveryHint())?.rest, isNull);
    });

    test('Simple mode: no "still recovering" card, the day-off card at most once a week (P2-1)', () async {
      final s = await app();
      await s.saveSettings(s.settings.copyWith(simple: true));
      final first = s.lib.byId(s.today!.items.first.exerciseId)!;
      for (var d = 1; d <= 5; d++) {
        await past(s, first.id, 8, d);
      }
      final h = await s.recoveryHint();
      expect(h?.warn, isNull);
      expect(h?.betterDay, isNull);
      expect(h?.rest, contains('days in a row'));
      // seen yesterday: not again today
      await s.repo.kvSet('rest_hint_seen', '${DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch}');
      expect((await s.recoveryHint())?.rest, isNull);
    });
  });

  group('pain and sore joints', () {
    test('"that hurt" eases the next two workouts back in; the same workout does not count down', () async {
      final s = await app();
      final it = s.today!.items.first;
      final e = s.lib.byId(it.exerciseId)!;
      await s.startWorkout();
      await s.repo.logSet(s.session!.id, e.id, 100, 8);
      await s.finishWorkout();
      final normal = (await s.targetFor(it)).kg!;
      await s.flagPain(e.id, Joint.shoulders);
      expect(s.soreToday, {Joint.shoulders});
      expect((await s.targetFor(it)).kg, closeTo(normal * 0.8, 2.6));
      expect((await s.targetFor(it)).why, contains('after it hurt'));
      expect(await s.bodyContext(), contains('that hurt'));
      // a workout of it: one step down the ramp
      await s.pickDay(s.plan!.days.indexWhere((d) => d.items.any((x) => x.exerciseId == e.id)));
      await s.startWorkout();
      await s.repo.logSet(s.session!.id, e.id, 80, 8);
      await s.finishWorkout();
      expect(s.ramp[e.id]?['n'], 1);
      await s.clearRamp(e.id);
      expect(s.ramp, isEmpty);
    });

    test('sore today: exercises hard on it are flagged and swapped for today only; new joints are tagged', () async {
      expect(lib.byId('skull_crusher')!.joints, contains(Joint.elbows));
      expect(lib.byId('box_jump')!.joints, contains(Joint.ankles));
      expect(lib.usable(lib.byId('skull_crusher')!, Equipment.values.toSet(), {Joint.elbows}), isFalse);
      final s = await app();
      final today = s.today!;
      final i = today.items.indexWhere((it) => s.lib.byId(it.exerciseId)!.joints.isNotEmpty);
      expect(i, greaterThanOrEqualTo(0));
      final sore = s.lib.byId(today.items[i].exerciseId)!.joints;
      await s.setSore(sore);
      expect(s.soreItems, contains(i));
      final n = await s.swapSore();
      expect(n, greaterThan(0));
      expect(s.soreItems.length, lessThan(today.items.where((it) => s.lib.byId(it.exerciseId)!.joints.intersection(sore).isNotEmpty).length));
      expect(s.plan!.days[s.todayIndex].items[i].exerciseId, today.items[i].exerciseId); // plan unchanged
    });
  });

  group('careful modes', () {
    test('pregnant: risky moves left out of plans and today, no + or all-out sets', () async {
      final s = await app();
      await s.saveProfile(s.profile!.copyWith(pregnancy: 'pregnant'));
      expect(s.lib.caution, contains('bench_press'));
      expect(s.lib.available(Equipment.values.toSet(), {}).any((e) => e.id == 'crunch'), isFalse);
      await s.makeBuiltInPlan();
      final ids = s.plan!.days.expand((d) => d.items).map((i) => i.exerciseId).toSet();
      expect(ids.intersection(cautionIds('pregnant', lib)), isEmpty);
      // an old plan with a risky lift and a + set: swapped today, + taken off
      final old = Plan(name: 'old', days: [
        PlanDay(name: 'A', items: [PlanItem.of('bench_press', parseSets('3x5+')), PlanItem(exerciseId: 'box_jump', sets: 3, repLow: 5, repHigh: 5, restSec: 90, style: 'failure')])
      ]);
      await s.usePlan(old);
      final d = s.today!;
      expect(d.items.map((i) => i.exerciseId), isNot(contains('bench_press')));
      expect(d.items.every((i) => i.style.isEmpty && !(i.perSet?.any((x) => x.amrap) ?? false)), isTrue);
      expect(await s.bodyContext(), isNot(contains('pregnan')));
      await s.saveProfile(s.profile!.copyWith(clearPregnancy: true));
      expect(s.lib.caution, isEmpty);
    });

    test('volume climb: extras one set lighter in the first week of a block', () async {
      final s = await app();
      final base = s.today!.items;
      await s.saveSettings(s.settings.copyWith(climb: true, deloadEvery: 4));
      expect(s.climbStep, -1);
      final d = s.today!.items;
      expect(d.first.sets, base.first.sets);
      expect(d[1].sets, (base[1].sets - 1).clamp(2, 99));
    });
  });

  test('every new part has an AI tool', () async {
    final s = await app();
    final ex = s.today!.items.first.exerciseId;
    for (final cmd in ['sore knees,lower_back', 'sore none', 'pain $ex shoulders', 'pain $ex', 'pain $ex clear', 'volume fit', 'setting climb on', 'profile pregnancy postpartum', 'profile pregnancy none', 'rest_hint off']) {
      final r = parseToolReply('SAY: ok\nDO: $cmd', s);
      expect(r.errors, isEmpty, reason: cmd);
      for (final a in r.actions) {
        await a.run(s);
      }
    }
    expect(s.settings.climb, isTrue);
    expect(s.profile!.pregnancy, isNull);
    expect(parseToolReply('SAY: x\nDO: sore elbow', s).errors, isNotEmpty);
    await s.setSore({Joint.knees});
    expect(parseToolReply('SAY: x\nDO: sore swap', s).errors, isEmpty);
    expect(toolHelp(s.lib), contains('DO: sore'));
    final g = toolGrammar(s.lib, s.profile!, s.plan!.days.length);
    expect(g, contains('"sore "'));
    expect(g, contains('"climb "'));
    expect(g, contains('"lowerback"'));
  });
}
