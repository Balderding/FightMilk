// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/reports.dart';
import 'package:workout/domain/stats.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/llm/native.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/history_screen.dart';
import 'package:workout/ui/reports_screen.dart';
import 'package:workout/ui/theme.dart';
import 'package:workout/ui/today_screen.dart';

/// Reports, calendar, streaks, goals and badges (batch 18, F275-F298).
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final now = DateTime(2026, 11, 18, 18); // a Wednesday
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  /// A workout [daysAgo] days back with [sets] bench sets of [kg] x [reps].
  (Workout, List<SetLog>) w(int daysAgo, {double kg = 100, int reps = 5, int sets = 3, int hour = 18, int minutes = 60, String ex = 'bench_press'}) {
    final t = DateTime(now.year, now.month, now.day, hour).subtract(Duration(days: daysAgo));
    final id = 'w$daysAgo-$hour-$ex';
    return (Workout(id, t, minutes, plannedSets: 4), [for (var i = 0; i < sets; i++) SetLog(id: '$id-$i', sessionId: id, exerciseId: ex, kg: kg, reps: reps, at: t.add(Duration(minutes: i)))]);
  }

  (List<Workout>, List<SetLog>) data(List<(Workout, List<SetLog>)> l) => ([for (final x in l) x.$1], [for (final x in l) ...x.$2]);

  group('reports', () {
    test('a report for any dates; this week against last week and 4 weeks ago', () {
      final (ws, sets) = data([w(0), w(2, kg: 105), w(8), w(29, kg: 90, sets: 2)]);
      final (a, b, c) = weekReports(now, ws, sets, lib);
      expect([a.workouts, a.sets], [2, 6]);
      expect(a.volume, 100 * 5 * 3 + 105 * 5 * 3);
      expect([b.workouts, b.sets], [1, 3]);
      expect([c.workouts, c.sets], [1, 2]);
      expect(a.records, 1, reason: '105 x 5 beat the earlier 100 x 5');
      expect(a.muscles['chest'], 6);
      expect(a.mostDone.single.$1.id, 'bench_press');
      expect(changeText(6, 3), '+100%');
      expect(changeText(2, 4), '−50%');
      expect(changeText(1, 0), 'new');
      // 10 to 1 days back: 100 x 5, then 105 x 5
      final range = reportFor(now.subtract(const Duration(days: 10)), dayOf(now), ws, sets, lib, body: [(now.subtract(const Duration(days: 9)), 81.0), (now.subtract(const Duration(days: 3)), 80.0)]);
      expect(range.workouts, 2);
      expect(range.bodyChange, -1);
      expect(range.mostImproved.single.$1.id, 'bench_press');
      expect(monthsWithWorkouts(ws).first, DateTime(2026, 11));
    });

    test('year wrapped, lifetime fun numbers, per-week bars, when, splits, load, running total, plan kept', () {
      final (ws, sets) = data([w(0), w(1, reps: 12), w(7, reps: 15, hour: 7), w(40)]);
      final y = yearWrap(2026, ws, sets, lib, perWeek: 1);
      expect(y.workouts, 4);
      expect(y.favourite!.id, 'bench_press');
      expect(funWeight(3000), contains('cars'));
      expect(funWeight(12000), contains('elephants'));
      final pw = perWeek(ws, now, weeks: 3);
      expect([for (final x in pw) x.$2], [0, 1, 2]);
      final g = whenGrid(ws);
      expect(g[now.weekday - 1][18], 1);
      expect(g.expand((r) => r).fold(0, (a, b) => a + b), 4);
      final (h, m, l) = repSplit(sets);
      expect([h, m, l].map((x) => (x * 100).round()), [50, 25, 25]);
      final (acute, usual, weeks) = trainingLoad(sets, now);
      expect(acute, 6, reason: 'two workouts this week, 3 sets each, no effort taps = weight 1');
      expect(weeks, 2, reason: 'two of the six weeks before have sets');
      expect(usual, closeTo(6 / 2, 0.01), reason: 'averaged over the weeks with data (review 3, P2-4)');
      final run = runningVolume(ws, sets);
      expect(run.last.$2, sets.fold<double>(0, (a, x) => a + x.kg * x.reps));
      final kept = planKept(ws, sets, now, 4, weeks: 2);
      expect(kept.last.$2, 2);
      expect(kept.last.$5, 8);
    });
  });

  group('calendar, streaks, goals, badges', () {
    test('day volumes and the "days I did" filter', () {
      final (ws, sets) = data([w(0, kg: 80, reps: 5), w(3, kg: 70, reps: 8)]);
      final v = dayVolumes(ws, sets);
      expect(v[dayOf(now)], 80 * 5 * 3);
      expect(daysMatching(sets, 'bench_press', kg: 80, reps: 5), {dayOf(now)});
      expect(daysMatching(sets, 'bench_press', kg: 60, reps: 8), {dayOf(now.subtract(const Duration(days: 3)))});
    });

    test('week streak: rest days never break it; a week still going does not; the week strip', () {
      // now is a Wednesday: last week = 3-9 days back, then 10-16, then 17-23.
      // 2 workouts in each of the last 3 full weeks, 1 so far this week, goal 2 a week
      final (ws, _) = data([w(1), w(4), w(6), w(11), w(13), w(18), w(20)]);
      expect(weekStreak(ws, now, perWeek: 2), 3, reason: 'this week (1 of 2) is not done yet and does not break it');
      final (ws2, _) = data([w(1), w(2), w(4), w(6), w(11), w(13), w(18), w(20)]);
      expect(weekStreak(ws2, now, perWeek: 2), 4);
      final (gap, _) = data([w(1), w(2), w(11), w(13)]);
      expect(weekStreak(gap, now, perWeek: 2), 1, reason: 'last week had none');
      expect(longestWeekStreak(ws2, perWeek: 2), 4);
      final strip = weekStrip(ws2, now);
      expect(strip.where((x) => x).length, 2);
      expect(strip[now.weekday - 1], isFalse);
    });

    test('a goal: how far, on track or behind, and when at this rate; body weight goes down', () {
      final a = Aim(id: 'a', kind: 'lift', exercise: 'bench_press', target: 120, start: 100, created: now.subtract(const Duration(days: 28)), by: now.add(const Duration(days: 28)));
      final series = [for (var k = 0; k < 5; k++) Pt(now.subtract(Duration(days: 28 - 7 * k)), 100 + 2.5 * k, 's$k')];
      final st = aimState(a, series, now);
      expect(st.done, closeTo(0.5, 0.001));
      expect(st.onTrack, isTrue);
      expect(st.eta, isNotNull);
      // from the trend line, so a little later than the raw 4 weeks (review 3, P2-6)
      expect(st.eta!.difference(now).inDays, inInclusiveRange(26, 70));
      final slow = aimState(a, [series.first, Pt(now, 101, 'x')], now);
      expect(slow.onTrack, isFalse);
      final body = Aim(id: 'b', kind: 'body', target: 80, start: 85, created: now.subtract(const Duration(days: 30)));
      expect(aimState(body, [Pt(now, 82.5, '')], now).done, closeTo(0.5, 0.001));
      expect(aimState(body, [Pt(now, 79.9, '')], now).reached, isTrue);
      expect(Aim.fromJson(a.toJson()).by, a.by);
    });

    test('badges and levels', () {
      final (ws, sets) = data([for (var k = 0; k < 10; k++) w(k * 2, kg: 109.0 - k)]); // heavier every time
      final b = badgesEarned(ws, sets, lib, perWeek: 1).map((x) => x.id).toSet();
      expect(b, containsAll(['first', 'w10', 'pr', 'bench_press_1', 'bench_press_2']));
      expect(b, isNot(contains('bench_press_3')));
      expect(levelOf(0), (1, 0, 3));
      expect(levelOf(3).$1, 2);
      expect(levelOf(100).$1, greaterThan(5));
      expect(levelName(1), 'Starter');
    });
  });

  group('in the app', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('rep'));
    setUpAll(() {
      engineAvailableOverride = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
    });

    test('goals and badges through AppState and the AI tools; the AI sees the week', () async {
      final s = await AppState.forTest(await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi), PackStore(dir.path), lib);
      await s.saveProfile(profile);
      await s.makeBuiltInPlan();
      await s.startWorkout();
      final it = s.session!.day.items.first;
      await s.repo.logSet(s.session!.id, it.exerciseId, 60, 8, slot: liftKey(it));
      await s.finishWorkout();
      expect(s.programNotes.join(), contains('New badge'));
      for (final cmd in ['goal lift ${it.exerciseId} 100 by 2027-06-01', 'goal body 80', 'goal reps pull_up 12', 'goal volume 20', 'setting badges off']) {
        final r = parseToolReply('SAY: ok\nDO: $cmd', s);
        expect(r.errors, isEmpty, reason: cmd);
        for (final a in r.actions) {
          await a.run(s);
        }
      }
      expect(s.aims.length, 4);
      expect(s.aims.first.by, DateTime(2027, 6, 1));
      expect(s.aims.first.start, greaterThan(0), reason: 'starts from where the lift is now');
      expect(s.settings.badges, isFalse);
      final rm = parseToolReply('SAY: ok\nDO: goal remove 1', s);
      for (final a in rm.actions) {
        await a.run(s);
      }
      expect(s.aims.length, 3);
      expect(await s.weekLine(), contains('This week: 1 of 4 workouts'));
      // review 3, P3-N17: the AI reads each goal with its unit, how far along and by when
      await s.addAim('lift', 100, exercise: 'bench_press', by: DateTime(2027, 6, 1));
      final line = await s.weekLine();
      expect(line, contains('body weight 80 kg ('), reason: line);
      expect(line, contains('t lifted a month'), reason: line);
      expect(line, contains(' kg est. 1-rep max ('), reason: line);
      expect(line, contains('by 2027-06-01'), reason: line);
      expect(line, contains('% there'), reason: line);
      expect(line, contains('12 reps'), reason: line);
      // review 3, P3-N14: a removed goal comes back as it was, at its place
      final before = [for (final a in s.aims) a.toJson()];
      final gone = (await s.removeAim(s.aims[1].id))!;
      expect(s.aims.length, before.length - 1);
      await s.restoreAim(gone.$1, gone.$2);
      expect([for (final a in s.aims) a.toJson()], before);
      await s.reload();
      expect([for (final a in s.aims) a.toJson()], before, reason: 'saved, not only in memory');
      expect(await s.removeAim('no-such-goal'), isNull);
      final g = toolGrammar(s.lib, s.profile!, s.plan!.days.length);
      expect(g, contains('"goal "'));
      expect(g, contains('"badges "'));
      await s.repo.close();
    });

    testWidgets('Today shows the week strip; History opens Calendar and Reports; Progress opens Goals', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      late AppState s;
      Future<void> settle([int n = 10]) async {
        for (var i = 0; i < n; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 40));
        }
      }

      await tester.runAsync(() async {
        s = await AppState.forTest(await Repo.open('${dir.path}/w.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
        await s.saveProfile(profile);
        await s.makeBuiltInPlan();
        await s.startWorkout();
        final it = s.session!.day.items.first;
        await s.repo.logSet(s.session!.id, it.exerciseId, 60, 8, slot: liftKey(it));
        await s.finishWorkout();
      });
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: TodayScreen(s: s))));
      await settle();
      expect(find.textContaining('of 4 training days this week'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: buildTheme(), home: Scaffold(body: HistoryScreen(s: s))));
      await settle();
      await tester.tap(find.text('Reports'));
      await settle();
      expect(find.text('This week'), findsOneWidget);
      await tester.ensureVisible(find.text('All time'));
      await tester.tap(find.text('All time'));
      await tester.pump(const Duration(milliseconds: 600));
      await settle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -900));
      await settle();
      expect(find.textContaining('Level'), findsOneWidget);
      await tester.pageBack();
      await settle();
      await tester.tap(find.text('Calendar'));
      await settle();
      expect(find.textContaining('Days I did'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: buildTheme(), home: GoalsScreen(s: s)));
      await settle();
      expect(find.text('New goal'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(2);
      await tester.runAsync(() => s.repo.close());
    });
  });
}
