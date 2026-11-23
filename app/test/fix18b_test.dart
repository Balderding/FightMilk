import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/programs.dart';
import 'package:workout/domain/reports.dart';
import 'package:workout/domain/stats.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/llm/native.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/history_screen.dart';
import 'package:workout/ui/progress_screen.dart';
import 'package:workout/ui/theme.dart';

/// Fixes from the third review (REVIEW-2026-11-22-1105), fix batch 18b.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  final now = DateTime(2026, 11, 18, 18);

  Future<AppState> app() async {
    final dir = Directory.systemTemp.createTempSync('fix18b');
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    return s;
  }

  PlanDay day(String id) => PlanDay(name: 'A', items: [PlanItem(exerciseId: id, sets: 3, repLow: 5, repHigh: 8, restSec: 120)]);

  group('P1-1 an older 4-week swap is never guessed onto the plan in use', () {
    test('two plans have the variation: nothing is rewritten and a plain note says so', () async {
      final s = await app();
      await s.usePlan(Plan(name: 'A', days: [day('front_squat')])); // A: the swapped plan
      await s.usePlan(Plan(name: 'Other', days: [day('front_squat')])); // Other: front squat on purpose
      await s.repo.kvSet('block_swaps', jsonEncode({'front_squat': {'orig': 'back_squat', 'until': 3}}));
      await s.reload();
      expect(s.plan!.name, 'Other');
      expect(s.plan!.days.first.items.first.exerciseId, 'front_squat');
      expect(s.blockSwaps, isEmpty);
      expect(s.programNotes.join(), contains('could not be matched to a plan'));
    });

    test('only one plan has it: nothing is rewritten, a note names the plan (review 4, P1-2)', () async {
      final s = await app();
      await s.usePlan(Plan(name: 'B', days: [day('front_squat')])); // B: front squat on purpose
      final b = s.plan!;
      await s.usePlan(Plan(name: 'A', days: [day('back_squat')]));
      await s.repo.kvSet('block_swaps', jsonEncode({'front_squat': {'orig': 'back_squat', 'until': 3}}));
      await s.reload();
      expect(s.plan!.days.first.items.first.exerciseId, 'back_squat'); // A untouched
      expect(s.blockSwaps, isEmpty, reason: 'the old entry is dropped');
      expect(s.programNotes.where((n) => n.contains('may still be in your plan "B"')), hasLength(1));
      await s.restorePlan(b.id);
      expect(s.plan!.days.first.items.first.exerciseId, 'front_squat', reason: 'B keeps its front squat');
    });
  });

  group('P1-2 and P2-6 goals', () {
    Aim aim(String kind, double target, double start, {DateTime? created, DateTime? by}) =>
        Aim(id: 'g', kind: kind, exercise: kind == 'lift' ? 'bench_press' : '', target: target, start: start, created: created ?? now.subtract(const Duration(days: 30)), by: by);

    test('a lift or tonnes target below today is reached; tonnes count from 0 each month', () {
      expect(aimState(aim('lift', 100, 105), [Pt(now, 105, 's')], now).reached, isTrue);
      expect(aimState(aim('volume', 20, 78.6), [Pt(now, 78.6, '')], now).reached, isTrue);
      final v = aimState(aim('volume', 20, 5), [Pt(now, 12, '')], now);
      expect(v.done, closeTo(0.6, 0.001));
      final next = aimState(aim('volume', 10, 12), [Pt(now, 2, '')], now);
      expect(next.reached, isFalse);
      expect(next.done, closeTo(0.2, 0.001));
    });

    test('a body goal set before any weigh-in waits for one, then starts there', () async {
      final b = aim('body', 80, 0);
      expect(aimState(b, const [], now).waiting, isTrue);
      final st = aimState(b, [Pt(now, 92, '')], now);
      expect(st.reached, isFalse);
      expect(st.done, 0);
      final s = await app();
      await s.addAim('body', 80);
      expect(s.aims.single.start, 0, reason: 'no weigh-in yet: it starts at the first one');
    });

    test('"at this rate" needs 4 workouts over 3 weeks and gives a month; on track waits', () {
      final g = aim('lift', 140, 80, created: now.subtract(const Duration(days: 5)), by: now.add(const Duration(days: 85)));
      final fast = [Pt(now.subtract(const Duration(days: 4)), 80, 'a'), Pt(now.subtract(const Duration(days: 2)), 85, 'b'), Pt(now, 90, 'c')];
      expect(aimState(g, fast, now).eta, isNull, reason: '3 points in 4 days say nothing yet');
      expect(aimState(g, fast, now).onTrack, isNull, reason: 'too early to say');
      final g2 = aim('lift', 120, 100, created: now.subtract(const Duration(days: 43)));
      final steady = [for (var k = 0; k < 7; k++) Pt(now.subtract(Duration(days: 42 - 7 * k)), 100 + k * 1.0, 's$k')];
      final st = aimState(g2, steady, now);
      expect(st.eta, isNotNull);
      expect(aroundMonth(st.eta!, now), startsWith('around '));
      final early = aim('lift', 120, 100, created: now.subtract(const Duration(days: 10)), by: now.add(const Duration(days: 80)));
      expect(aimState(early, const [], now).onTrack, isNull, reason: 'no "behind" 10 days in with no workout');
    });
  });

  test('P2-9 a workout of only missed sets adds no point', () {
    final sets = [
      SetLog(id: 'a', sessionId: 's1', exerciseId: 'bench_press', kg: 100, reps: 5, at: now),
      SetLog(id: 'b', sessionId: 's2', exerciseId: 'bench_press', kg: 140, reps: 0, at: now.add(const Duration(days: 3))),
    ];
    expect(seriesOf(sets, ChartKind.e1rm).length, 1);
    expect(seriesOf(sets, ChartKind.bestSetVolume).length, 1);
  });

  Workout wk(DateTime t) => Workout('w${t.millisecondsSinceEpoch}', t, 50);

  test('P2-1 no badge flood: the first look with older history is silent; then a count, not a list', () async {
    final s = await app();
    for (var k = 0; k < 12; k++) {
      final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
      final t = DateTime.now().subtract(Duration(days: 30 - k * 2));
      final x = await s.repo.logSet(ses.id, 'bench_press', 60, 8);
      await s.repo.db.update('set_log', {'at': t.millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [x.id]);
      await s.repo.db.update('session', {'started': t.millisecondsSinceEpoch, 'finished': t.millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [ses.id]);
    }
    await s.reload();
    await s.startWorkout();
    await s.repo.logSet(s.session!.id, s.session!.day.items.first.exerciseId, 60, 8, slot: liftKey(s.session!.day.items.first));
    await s.finishWorkout();
    expect(s.programNotes.where((n) => n.contains('badge')), isEmpty, reason: 'older badges are marked seen without a note');
  });

  test('P2-2 days and weeks stay at midnight across the clock changes', () {
    var d = DateTime(2026);
    while (d.year == 2026) {
      expect(d.hour, 0, reason: '$d');
      d = addDays(d, 1);
    }
    for (final (wkStart, _, _) in perWeek(const [], DateTime(2026, 11, 4), weeks: 40)) {
      expect([wkStart.hour, wkStart.weekday], [0, DateTime.monday], reason: '$wkStart');
    }
  });

  test('P2-3 the week so far is compared with the same days of last week', () {
    final wed = DateTime(2026, 11, 18, 20);
    final ws = [wk(DateTime(2026, 11, 16, 18)), wk(DateTime(2026, 11, 9, 18)), wk(DateTime(2026, 11, 11, 18)), wk(DateTime(2026, 11, 13, 18))];
    final (a, b, _) = weekReports(wed, ws, const [], lib);
    expect([a.workouts, b.workouts], [1, 2]);
    expect(changeText(a.workouts, b.workouts), '−50%');
    // review 4 P3-N18: early on Wednesday, last Wednesday's evening workout still counts (whole days)
    final early = DateTime(2026, 11, 18, 8);
    final (c, d, _) = weekReports(early, ws, const [], lib);
    expect([c.workouts, d.workouts], [1, 2]);
  });

  test('P2-4 and P2-5 a new lifter: no load comparison, no weeks before the start', () {
    final sets = [
      for (var d = 0; d < 9; d += 2)
        for (var k = 0; k < 9; k++) SetLog(id: '$d-$k', sessionId: 's$d', exerciseId: 'bench_press', kg: 60, reps: 8, at: now.subtract(Duration(days: d)))
    ];
    final (_, _, weeks) = trainingLoad(sets, now);
    expect(weeks, lessThan(3));
    final ws = [wk(now), wk(now.subtract(const Duration(days: 1)))];
    expect(planKept(ws, const [], now, 3).length, 1);
  });

  test('P2-8 the weekly goal is the program\'s days; ring and streak count the same days', () async {
    final s = await app();
    await s.saveProfile(full.copyWith(days: 3));
    await s.startProgram(buildProgram(templateById('531_base')!, s.profile!, lib), {'overhead_press': 60, 'deadlift': 160, 'bench_press': 100, 'back_squat': 140});
    expect(s.perWeekGoal, 4);
    final mon = DateTime(2026, 11, 9, 8), mon2 = DateTime(2026, 11, 9, 19), wed = DateTime(2026, 11, 11, 18);
    final ws = [wk(mon), wk(mon2), wk(wed)];
    final sun = DateTime(2026, 11, 15, 20);
    expect(weekStrip(ws, sun).where((x) => x).length, 2);
    expect(weekStreak(ws, sun, perWeek: 3), 0, reason: 'two training days are not three');
  });

  test('P2-10 the AI goal tool refuses impossible and past dates', () async {
    final s = await app();
    expect(parseToolReply('SAY: x\nDO: goal body 80 by 2027-13-45', s).errors.join(), contains('YYYY-MM-DD'));
    expect(parseToolReply('SAY: x\nDO: goal body 80 by 2020-01-01', s).errors.join(), contains('past'));
    expect(parseToolReply('SAY: x\nDO: goal body 80 by 2030-02-01', s).errors, isEmpty);
  });

  testWidgets('P2-7 Simple mode: no Reports on History, no Goals on Progress', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    engineAvailableOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
    late AppState s;
    Future<void> settle([int n = 10]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('fix18bw');
      s = await AppState.forTest(await Repo.open('${dir.path}/w.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(full);
      await s.makeBuiltInPlan();
      await s.saveSettings(s.settings.copyWith(simple: true));
      await s.startWorkout();
      await s.repo.logSet(s.session!.id, s.session!.day.items.first.exerciseId, 60, 8, slot: liftKey(s.session!.day.items.first));
      await s.finishWorkout();
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: HistoryScreen(s: s))));
    await settle();
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Reports'), findsNothing);
    await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: buildTheme(), home: Scaffold(body: ProgressScreen(s: s))));
    await settle();
    expect(find.byTooltip('Goals'), findsNothing);
    expect(s.programNotes.where((n) => n.contains('badge')), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await settle(2);
    await tester.runAsync(() => s.repo.close());
  });
}
