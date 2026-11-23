import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/stats.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/lift_chart.dart';

/// Charts and records (batch 17, F252-F274).
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final bench = lib.byId('bench_press')!;
  final t0 = DateTime(2026, 6, 1, 18);

  /// Workout [w] (a week apart) of bench: [sets] as (kg, reps).
  List<SetLog> day(int w, List<(double, int)> sets, {int? effort, int? rest}) => [
        for (var i = 0; i < sets.length; i++)
          SetLog(id: 'w$w-$i', sessionId: 's$w', exerciseId: 'bench_press', kg: sets[i].$1, reps: sets[i].$2, at: t0.add(Duration(days: 7 * w, minutes: i)), effort: effort, rest: rest)
      ];

  final log = [
    ...day(0, [(100, 5), (100, 5), (100, 4)], effort: 2, rest: 120),
    ...day(1, [(102.5, 5), (102.5, 5), (102.5, 5)], effort: 3, rest: 150),
    ...day(2, [(105, 3), (95, 8)], effort: 4),
  ];

  group('chart series', () {
    test('one point per workout for every kind', () {
      expect(seriesOf(log, ChartKind.heaviest).map((p) => p.v), [100, 102.5, 105]);
      expect(seriesOf(log, ChartKind.workoutVolume).map((p) => p.v), [1400, 1537.5, 1075]);
      expect(seriesOf(log, ChartKind.bestSetVolume).map((p) => p.v), [500, 512.5, 760]);
      expect(seriesOf(log, ChartKind.totalReps).map((p) => p.v), [14, 15, 11]);
      expect(seriesOf(log, ChartKind.sets).map((p) => p.v), [3, 3, 2]);
      expect(seriesOf(log, ChartKind.weightAt, reps: 5).map((p) => p.v), [100, 102.5, 95]);
      expect(seriesOf(log, ChartKind.weightAt, reps: 10), isEmpty);
      expect(seriesOf(log, ChartKind.e1rm).last.v, closeTo(95 * (1 + 8 / 30), 0.01));
      expect(seriesOf(log, ChartKind.length, minutes: {'s0': 50, 's2': 40}).map((p) => p.v), [50, 40]);
      expect(seriesOf(log, ChartKind.effort).map((p) => p.v), [7.5, 9.0, 10.0]);
      expect(seriesOf(log, ChartKind.rest).map((p) => p.v), [120, 150]);
      final perBody = seriesOf(log, ChartKind.perBody, body: [(t0.subtract(const Duration(days: 3)), 80.0)]);
      expect(perBody.first.v, closeTo(100 * (1 + 5 / 30) / 80, 0.001));
      // warm-ups never count
      expect(seriesOf([...log, SetLog(sessionId: 's0', exerciseId: 'bench_press', kg: 200, reps: 1, at: t0, type: SetType.warmup)], ChartKind.heaviest).first.v, 100);
    });

    test('ranges, a moving average and where the line is heading', () {
      final p = seriesOf(log, ChartKind.heaviest);
      expect(inRange(p, 1, t0.add(const Duration(days: 20))).length, 3);
      expect(inRange(p, 1, t0.add(const Duration(days: 60))).length, 0);
      expect(inRange(p, 0, DateTime(2030)).length, 3);
      expect(movingAverage(p, n: 2), [100, 101.25, 103.75]);
      final pr = projection(p)!;
      expect(pr.$1, closeTo(2.5, 0.01)); // +2.5 kg a week
      expect(pr.$3, closeTo(105 + 2.5 * 4, 0.1));
      expect(projection(p.take(2).toList()), isNull);
    });

    test('a tap picks the nearest workout', () {
      final p = seriesOf(log, ChartKind.heaviest);
      final size = const Size(336, 200);
      expect(ChartPainter.nearest(p, const Offset(48, 50), size, 0, 1, null)!.session, 's0'); // just right of the side values (44 since B1)
      expect(ChartPainter.nearest(p, const Offset(330, 50), size, 0, 1, null)!.session, 's2');
      expect(ChartPainter.nearest(p, const Offset(10, 50), size, 0, 1, null), isNull, reason: 'the side values are not a workout');
      // zoomed into the second half: the left edge is the middle workout
      expect(ChartPainter.nearest(p, const Offset(45, 50), size, 0.5, 1, null)!.session, 's1');
    });
  });

  group('tables', () {
    test('% of max and the rep-max grid', () {
      final t = percentTable(100);
      expect(t.first, (100, 100.0));
      expect(t.last, (50, 50.0));
      expect(t.length, 11);
      final g = repMaxGrid(log);
      expect(g.length, 12);
      expect(g[0].$2, 105); // 1 rep: the heaviest set
      expect(g[4].$2, 102.5); // 5 reps: the best 5
      expect(g[7].$2, 95); // 8 reps
      expect(g[11].$2, isNull); // never did 12
      expect(g[0].$3, closeTo(95 * (1 + 8 / 30), 0.01));
      expect(g[9].$3, closeTo(g[0].$3 / (1 + 10 / 30), 0.01));
    });
  });

  group('records', () {
    test('what each record is, when it was set and what it beat; medals only on beaten records', () {
      final h = recordHistory(log, bench);
      final cur = currentRecords(h);
      expect(cur[RecordKind.heaviest]!.value, 105);
      expect(cur[RecordKind.heaviest]!.before, 102.5);
      expect(cur[RecordKind.mostReps]!.value, 8);
      expect(cur[RecordKind.bestWorkoutVolume]!.value, 1537.5);
      expect(cur[RecordKind.bestWorkoutVolume]!.session, 's1');
      expect(h.where((r) => r.kind == RecordKind.heaviest).map((r) => r.value), [100, 102.5, 105]);
      final medals = medalSets(h);
      expect(medals, isNot(contains('w0-0')), reason: 'the very first workout beats nothing');
      expect(medals, containsAll(['w1-0', 'w2-0', 'w2-1']));
      expect(recordText(cur[RecordKind.heaviest]!, Unit.kg), '105 kg × 3');
    });

    test('best this week, month and year', () {
      final now = t0.add(const Duration(days: 15)); // a Tuesday in the week of workout 2
      expect(windowStart('week', now).weekday, DateTime.monday);
      final wk = bestSince(log, bench, windowStart('week', now));
      expect(wk[RecordKind.heaviest]!.value, 105);
      expect(wk[RecordKind.bestWorkoutVolume]!.value, 1075);
      expect(bestSince(log, bench, DateTime(2027)).isEmpty, isTrue);
    });

    test('pull-ups with a belt and timed holds have their own records (F273, F274)', () {
      final pu = lib.byId('pull_up')!;
      final sets = [
        SetLog(id: 'a', sessionId: 'x', exerciseId: 'pull_up', kg: 0, reps: 12, at: t0),
        SetLog(id: 'b', sessionId: 'y', exerciseId: 'pull_up', kg: 10, reps: 6, at: t0.add(const Duration(days: 3))),
      ];
      expect(recordKinds(pu, sets), [RecordKind.mostReps, RecordKind.addedWeight]);
      final cur = currentRecords(recordHistory(sets, pu));
      expect(cur[RecordKind.mostReps]!.value, 12);
      expect(recordText(cur[RecordKind.addedWeight]!, Unit.kg), '+10 kg × 6');
      final carry = lib.byId('farmer_carry')!;
      final c = [SetLog(id: 'c', sessionId: 'z', exerciseId: 'farmer_carry', kg: 30, reps: 45, secs: 45, meters: 40, at: t0)];
      expect(recordKinds(carry, c), containsAll([RecordKind.longestHold, RecordKind.farthest]));
      expect(recordText(currentRecords(recordHistory(c, carry))[RecordKind.longestHold]!, Unit.kg), '0:45');
      expect(recordText(currentRecords(recordHistory(c, carry))[RecordKind.farthest]!, Unit.kg), '40 m');
    });

    test('all bench press kinds on one chart (F266)', () {
      final v = variantsOf(bench, lib).map((e) => e.id).toSet();
      expect(v, containsAll(['bench_press', 'db_bench_press', 'smith_bench_press', 'incline_bench_press', 'close_grip_bench']));
      expect(v, isNot(contains('back_squat')));
      expect(variantsOf(lib.byId('back_squat')!, lib).map((e) => e.id), containsAll(['front_squat', 'box_squat']));
    });
  });

  test('every new part has an AI tool; the AI sees records', () async {
    final dir = Directory.systemTemp.createTempSync('stats');
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg));
    await s.makeBuiltInPlan();
    for (final cmd in ['dashboard add streak', 'dashboard remove week_volume', 'setting chart_smooth on', 'setting chart_dots off']) {
      final rep = parseToolReply('SAY: ok\nDO: $cmd', s);
      expect(rep.errors, isEmpty, reason: cmd);
      for (final a in rep.actions) {
        await a.run(s);
      }
    }
    expect(s.dash, contains('streak'));
    expect(s.dash, isNot(contains('week_volume')));
    expect(s.settings.chartSmooth, isTrue);
    expect(s.settings.chartDots, isFalse);
    expect(parseToolReply('SAY: x\nDO: dashboard add nonsense', s).errors, isNotEmpty);
    await s.startWorkout();
    final it = s.session!.day.items.first;
    await s.repo.logSet(s.session!.id, it.exerciseId, 60, 8);
    await s.finishWorkout();
    expect(await s.recordsLine(), startsWith('Records: '));
    expect(await s.medalsFor([it.exerciseId]), isEmpty); // a first workout beats nothing
    await s.repo.close();
  });

  test('chart side values are round steps (review 2, P3-N7)', () {
    expect(niceStep(65.6), 50);
    expect(niceStep(23), 20);
    expect(niceStep(1.2), 1);
    expect(niceStep(0.04), closeTo(0.05, 1e-9));
  });
}
