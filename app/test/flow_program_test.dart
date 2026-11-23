// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/programs.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/domain/volume.dart';
import 'package:workout/llm/native.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/log_screen.dart';
import 'package:workout/ui/progress_screen.dart';
import 'package:workout/ui/today_screen.dart';
import 'package:workout/ui/theme.dart';

/// Program workouts through the real screens (review P2-11), not only AppState calls.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  setUpAll(() {
    engineAvailableOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
  });

  testWidgets('5/3/1 BBB week 3: three main sets, then the supplement starts at set 1 of 5 and needs all 5', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('flow');
    late AppState s;
    Future<void> settle([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.runAsync(() async {
      s = await AppState.forTest(await Repo.open('${dir.path}/f.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(profile);
      await s.startProgram(buildProgram(templateById('531_bbb')!, profile, lib), {'overhead_press': 50, 'deadlift': 140, 'bench_press': 90, 'back_squat': 120});
      await s.pickDay(8);
      await s.startWorkout();
    });
    expect(s.session!.day.name, 'W3 · Press');
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: LogScreen(s: s)));
    await settle();

    Future<void> done() async {
      await tester.tap(find.textContaining(RegExp(r'^Done(:| set)')).last); // "Done set" or "Done: as many reps as possible"
      await settle();
    }

    for (var i = 0; i < 3; i++) {
      await done();
    }
    expect(find.textContaining('set 1 of 5'), findsWidgets, reason: 'the supplement starts at its own first set');
    expect(find.textContaining('set 4 of 5'), findsNothing);
    expect(find.textContaining('next time'), findsNothing, reason: 'the program rule decides, not the rep range (P2-6)');
    for (var i = 0; i < 5; i++) {
      await done();
    }
    final sets = await tester.runAsync(() => s.repo.setsFor(s.session!.id));
    final by = <String, int>{};
    for (final x in sets!) {
      by[x.key] = (by[x.key] ?? 0) + 1;
    }
    expect(by['overhead_press'], 3);
    expect(by['overhead_press#B'], 5);
    await tester.pumpWidget(const SizedBox());
    await settle(2);
    await tester.runAsync(() => s.repo.close());
  });

  testWidgets('first workout: Done on a weighted lift with no weight opens the grid, and 0 is never saved (P1-8)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('flow0');
    late AppState s;
    Future<void> settle([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.runAsync(() async {
      s = await AppState.forTest(await Repo.open('${dir.path}/f.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(profile.copyWith(unit: Unit.lb));
      await s.makeBuiltInPlan();
      await s.startWorkout();
    });
    final first = lib.byId(s.session!.day.items.first.exerciseId)!;
    expect(first.bodyweight, isFalse);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: LogScreen(s: s)));
    await settle();
    await tester.tap(find.text('Pick weight'));
    await settle();
    expect(find.textContaining('Pick a weight you can do'), findsOneWidget);
    await tester.tap(find.text('95'));
    await settle();
    final sets = await tester.runAsync(() => s.repo.setsFor(s.session!.id));
    expect(sets!.single.kg, closeTo(lbToKg(95), 0.01));
    expect(find.text('Done set'), findsOneWidget); // the next set keeps 95
    await tester.pumpWidget(const SizedBox());
    await settle(2);
    await tester.runAsync(() => s.repo.close());
  });

  testWidgets('"That hurt" from a logged set: noted on the set, the joint sore today, next time lighter (P2-11)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('flowp');
    late AppState s;
    Future<void> settle([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.runAsync(() async {
      s = await AppState.forTest(await Repo.open('${dir.path}/f.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(profile);
      await s.startProgram(buildProgram(templateById('531_base')!, profile, lib), {'overhead_press': 100, 'deadlift': 200, 'bench_press': 120, 'back_squat': 150});
      await s.startWorkout();
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: LogScreen(s: s)));
    await settle();
    await tester.tap(find.textContaining(RegExp(r'^Done(:| set)')).last);
    await settle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await settle();
    await tester.tap(find.text('✓').first);
    await settle();
    await tester.tap(find.text('That hurt'));
    await settle();
    await tester.tap(find.text('Shoulders'));
    await settle();
    await tester.scrollUntilVisible(find.text('Just note it'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Just note it'));
    await settle();
    final sets = await tester.runAsync(() => s.repo.setsFor(s.session!.id));
    expect(sets!.single.note, contains('Hurt (shoulders)'));
    expect(s.soreToday, contains(Joint.shoulders));
    expect(s.ramp['overhead_press']?['n'], 2);
    await tester.pumpWidget(const SizedBox());
    await settle(2);
    await tester.runAsync(() => s.repo.close());
  });

  testWidgets('Today for a program: tagged "Program", with the length of that day, not the setup minutes (P2-4)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('flowt');
    late AppState s;
    Future<void> settle([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.runAsync(() async {
      s = await AppState.forTest(await Repo.open('${dir.path}/f.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(profile);
      await s.startProgram(buildProgram(templateById('nsuns_4')!, profile, lib), {'overhead_press': 50, 'deadlift': 140, 'bench_press': 90, 'back_squat': 120});
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: TodayScreen(s: s))));
    await settle();
    expect(find.text('Program'), findsOneWidget);
    expect(find.text('Built-in plan'), findsNothing);
    final mins = dayMinutes(s.today!, lib);
    expect(mins, greaterThan(60));
    expect(find.textContaining('~$mins min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(2);
    await tester.runAsync(() => s.repo.close());
  });

  testWidgets('Today rows for program lifts read the sets, not "3 x 1-5" (P2-3)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('flowr');
    late AppState s;
    Future<void> settle([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.runAsync(() async {
      s = await AppState.forTest(await Repo.open('${dir.path}/f.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(profile);
      await s.startProgram(buildProgram(templateById('531_base')!, profile, lib), {'overhead_press': 100, 'deadlift': 160, 'bench_press': 100, 'back_squat': 140});
      await s.pickDay(8); // W3 · Press
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: TodayScreen(s: s))));
    await settle();
    expect(find.text('5, 3, 1+ · 75-95 kg'), findsOneWidget);
    expect(find.textContaining('1-5'), findsNothing);
    await tester.runAsync(() async {
      await s.startProgram(buildProgram(templateById('nsuns_4')!, profile, lib), {'overhead_press': 60, 'deadlift': 160, 'bench_press': 100, 'back_squat': 140});
    });
    await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: buildTheme(), home: Scaffold(body: TodayScreen(s: s))));
    await settle();
    expect(find.textContaining('5, 3, 1+, 3, 3, 3, 5, 5, 5+'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(2);
    await tester.runAsync(() => s.repo.close());
  });

  testWidgets('the finish sheet keeps Save on screen with a whole workout logged (review 2, P2-5)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('flowf');
    late AppState s;
    Future<void> settle([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.runAsync(() async {
      s = await AppState.forTest(await Repo.open('${dir.path}/f.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(profile);
      await s.makeBuiltInPlan();
      await s.startWorkout();
      for (final it in s.session!.day.items) {
        for (var k = 0; k < it.sets; k++) {
          await s.repo.logSet(s.session!.id, it.exerciseId, 40, it.repHigh, slot: liftKey(it));
        }
      }
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: LogScreen(s: s)));
    await settle();
    await tester.tap(find.textContaining('Finish').last);
    await settle();
    final save = find.text('Save and finish');
    expect(save, findsOneWidget);
    final r = tester.getRect(save);
    expect(r.bottom, lessThanOrEqualTo(2340 / 2.75), reason: 'Save and finish is on screen without scrolling');
    expect(find.textContaining('Next time:'), findsOneWidget);
    await tester.tap(find.text('Keep going'));
    await settle();
    await tester.pumpWidget(const SizedBox());
    await settle(2);
    await tester.runAsync(() => s.repo.close());
  });

  testWidgets('Simple mode: no tip on Today; Progress is the lift, one chart and its records (review 2, P2-6)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('flows');
    late AppState s;
    Future<void> settle([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.runAsync(() async {
      s = await AppState.forTest(await Repo.open('${dir.path}/f.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(profile);
      await s.makeBuiltInPlan();
      await s.saveSettings(s.settings.copyWith(simple: true));
      await s.startWorkout();
      final it = s.session!.day.items.first;
      await s.repo.logSet(s.session!.id, it.exerciseId, 60, 8, slot: liftKey(it));
      await s.finishWorkout();
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: TodayScreen(s: s))));
    await settle();
    expect(find.text('Tip'), findsNothing);
    await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: buildTheme(), home: Scaffold(body: ProgressScreen(s: s))));
    await settle(12);
    expect(find.text('At a glance'), findsNothing);
    expect(find.textContaining('Compare'), findsNothing);
    expect(find.text('Records'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await settle(2);
    await tester.runAsync(() => s.repo.close());
  });

  testWidgets('Progress reads the history once, not on every rebuild (review 2, P2-8)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('flowc');
    late AppState s;
    Future<void> settle([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.runAsync(() async {
      s = await AppState.forTest(await Repo.open('${dir.path}/f.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(profile);
      await s.makeBuiltInPlan();
      await s.startWorkout();
      final it = s.session!.day.items.first;
      await s.repo.logSet(s.session!.id, it.exerciseId, 60, 8, slot: liftKey(it));
      await s.finishWorkout();
    });
    Widget page() => MaterialApp(theme: buildTheme(), home: Scaffold(body: ProgressScreen(s: s)));
    await tester.pumpWidget(page());
    await settle(14);
    final after = Repo.setsOfCalls;
    for (var k = 0; k < 3; k++) {
      await tester.pumpWidget(page());
      await settle(4);
    }
    expect(Repo.setsOfCalls, after, reason: 'three rebuilds, no new history reads');
    await tester.pumpWidget(const SizedBox());
    await settle(2);
    await tester.runAsync(() => s.repo.close());
  });
}
