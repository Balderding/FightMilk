// ignore_for_file: invalid_use_of_visible_for_testing_member
// Renders the app's real screens at phone size with sample data, for the README.
// Run: flutter test test_screens/screenshots_test.dart --update-goldens
// Output: ../docs/screenshots/*.png (1080 x 2340). Sample data only - nothing personal.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/ai.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/llm/native.dart';
import 'package:workout/main.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/domain/programs.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/body_screen.dart';
import 'package:workout/ui/export_screen.dart';
import 'package:workout/ui/plan_screen.dart';
import 'package:workout/ui/programs_screen.dart';
import 'package:workout/ui/reports_screen.dart';
import 'package:workout/ui/lift_chart.dart';
import 'package:workout/ui/log_screen.dart';
import 'package:workout/ui/muscles_screen.dart';
import 'package:workout/ui/pickers.dart';
import 'package:workout/ui/theme.dart';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    final b = File(f).readAsBytesSync();
    l.addFont(Future.value(ByteData.view(b.buffer)));
  }
  await l.load();
}

void main() {
  sqfliteFfiInit();
  final fonts = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: {Equipment.barbell, Equipment.dumbbell, Equipment.machine, Equipment.cable}, avoid: {}, unit: Unit.lb);

  setUpAll(() async {
    await _font('Roboto', ['$fonts/roboto-regular.ttf', '$fonts/roboto-medium.ttf', '$fonts/roboto-bold.ttf']);
    await _font('MaterialIcons', ['$fonts/materialicons-regular.otf']);
    engineAvailableOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
  });

  testWidgets('screens', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('shots');
    late AppState s;
    final key = GlobalKey();

    Future<void> settle([int n = 10]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    Future<void> shot(String name) async {
      await settle(4);
      await expectLater(find.byKey(key), matchesGoldenFile('../../docs/screenshots/$name.png'));
    }

    await tester.runAsync(() async {
      final repo = await Repo.open('${dir.path}/s.db', factory: databaseFactoryFfiNoIsolate);
      s = await AppState.forTest(repo, PackStore(dir.path), lib);
    });

    Widget app(Widget home) => RepaintBoundary(key: key, child: MaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: buildTheme(), home: home));

    // 1. first-time setup
    await tester.pumpWidget(app(Home(s: s)));
    await settle();
    await shot('1-setup');

    // sample history: 4 weeks of upper/lower with steady progress
    await tester.runAsync(() async {
      await s.saveProfile(profile);
      await s.makeBuiltInPlan();
      final plan = s.plan!;
      final start = DateTime(2026, 10, 19, 18);
      for (var w = 0; w < 4; w++) {
        for (var d = 0; d < 4; d++) {
          final day = plan.days[d];
          final ses = await s.repo.startSession(plan, d, day);
          for (final it in day.items) {
            final e = lib.byId(it.exerciseId)!;
            final base = switch (e.equipment) { Equipment.barbell => 185.0 + (e.compound ? 40 : 0), Equipment.dumbbell => 45.0, Equipment.machine => 150.0, _ => 80.0 };
            final kg = lbToKg(base + w * 5);
            for (var k = 0; k < it.sets; k++) {
              await s.repo.logSet(ses.id, it.exerciseId, e.bodyweight ? 0 : kg, it.repHigh - (k > 1 ? 1 : 0));
            }
          }
          await s.repo.finishSession(ses.id, lib, Unit.lb);
          final when = start.add(Duration(days: w * 7 + d * 2));
          await s.repo.db.update('session', {'started': when.millisecondsSinceEpoch, 'finished': when.add(const Duration(minutes: 58)).millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [ses.id]);
          await s.repo.db.update('set_log', {'at': when.millisecondsSinceEpoch}, where: 'session_id = ?', whereArgs: [ses.id]);
        }
      }
      await s.saveSettings(s.settings.copyWith(aiOn: true, ai: const AiConfig(kind: AiKind.onDevice, model: 'lfm2.5-1.2b-instruct')));
      await s.reload();
    });

    // 2. today
    await tester.pumpWidget(app(Home(s: s)));
    await settle();
    await shot('2-today');

    // 3. exercise info with animation (mid-lift)
    final first = lib.byId(s.today!.items.first.exerciseId)!;
    await tester.tap(find.text(first.name));
    await settle();
    await tester.pump(const Duration(milliseconds: 450));
    await shot('3-how-to');
    await tester.tapAt(const Offset(20, 40));
    await settle();

    // 4. logging mid-workout: two sets done, resting
    await tester.runAsync(() async {
      final ses = await s.startWorkout();
      final it = ses.day.items.first;
      final st = await s.targetFor(it);
      await s.repo.logSet(ses.id, it.exerciseId, st.kg ?? lbToKg(225), it.repHigh);
      await s.repo.logSet(ses.id, it.exerciseId, st.kg ?? lbToKg(225), it.repHigh - 1);
    });
    await tester.pumpWidget(app(LogScreen(s: s)));
    await settle();
    s.startRest(const Duration(seconds: 138));
    await settle();
    await tester.pump(const Duration(milliseconds: 300));
    await shot('4-workout');

    // 5. plan / 6. progress / 7. settings (AI coach on the phone)
    for (final (i, tab, name) in [(1, 'Plan', '5-plan'), (3, 'Progress', '6-progress'), (4, 'Settings', '7-settings')]) {
      await tester.pumpWidget(app(Home(s: s)));
      await settle();
      await tester.tap(find.text(tab).last);
      await settle();
      if (name == '7-settings') {
        await tester.tap(find.text('Ask AI').first); // the AI section of Settings
        await settle();
      }
      await shot(name);
      expect(i, isNonZero);
    }

    // 8. exercise library
    await tester.pumpWidget(app(ExercisePicker(s: s, title: 'All exercises', browse: true)));
    await settle();
    await shot('8-library');

    // 9. the program library
    await tester.pumpWidget(app(ProgramsScreen(s: s)));
    await settle();
    await shot('9-programs');

    // 10. a 5/3/1 workout: one target per set, from the training max
    await tester.runAsync(() async {
      await s.throwAwayWorkout();
      final pl = buildProgram(templateById('531_bbb')!, s.profile!, lib);
      await s.startProgram(pl, {'overhead_press': lbToKg(135), 'deadlift': lbToKg(315), 'bench_press': lbToKg(205), 'back_squat': lbToKg(275)});
      final ses = await s.startWorkout();
      final it = ses.day.items.first;
      final st = await s.targetFor(it);
      await s.repo.logSet(ses.id, it.exerciseId, st.perSet![0]!, 5);
    });
    await tester.pumpWidget(app(LogScreen(s: s)));
    await settle();
    await shot('10-program-workout');

    // 11. lift rules
    await tester.pumpWidget(app(LiftRulesScreen(s: s)));
    await settle();
    await shot('11-lift-rules');

    // 12. a program's plan: weeks folded, the current one open
    await tester.pumpWidget(app(Scaffold(body: PlanScreen(s: s))));
    await settle();
    await shot('12-program-plan');

    // 13. muscles: this week's sets against each range, balance, recovery (two recent workouts)
    await tester.runAsync(() async {
      for (final (ago, ids) in [
        (3, ['back_squat', 'romanian_deadlift', 'leg_press', 'lying_leg_curl', 'standing_calf_raise']),
        (1, ['bench_press', 'barbell_row', 'overhead_press', 'lat_pulldown', 'db_curl', 'triceps_pushdown', 'db_lateral_raise']),
      ]) {
        final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
        for (final id in ids) {
          for (var k = 0; k < 4; k++) {
            await s.repo.logSet(ses.id, id, lbToKg(lib.byId(id)!.compound ? 185 : 40), 8);
          }
        }
        await s.repo.finishSession(ses.id, lib, Unit.lb);
        final when = DateTime.now().subtract(Duration(days: ago, hours: 2));
        await s.repo.db.update('session', {'started': when.millisecondsSinceEpoch, 'finished': when.add(const Duration(minutes: 55)).millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [ses.id]);
        await s.repo.db.update('set_log', {'at': when.millisecondsSinceEpoch}, where: 'session_id = ?', whereArgs: [ses.id]);
      }
    });
    await tester.pumpWidget(app(MusclesScreen(s: s)));
    await settle();
    await shot('13-muscles');

    // 14. the records board
    await tester.pumpWidget(app(RecordsScreen(s: s)));
    await settle();
    await shot('14-records');

    // 15. reports and 16. the calendar
    await tester.pumpWidget(app(ReportsScreen(s: s)));
    await settle();
    await shot('15-reports');
    await tester.pumpWidget(app(CalendarScreen(s: s)));
    await settle();
    await shot('16-calendar');

    // 17. body weight with its goal line, body numbers and strength (batch 19)
    await tester.runAsync(() async {
      await s.saveProfile(s.profile!.copyWith(bodyKg: lbToKg(190), heightCm: 180));
      for (var i = 0; i < 40; i++) {
        final lb = 192 - i * 0.12 + (i % 3 == 0 ? 0.8 : (i % 3 == 1 ? -0.5 : 0.1));
        await s.repo.logBody(lbToKg(lb), fat: i == 39 ? 17.5 : null, at: DateTime.now().subtract(Duration(days: 39 - i, hours: -7)));
      }
      await s.addAim('body', lbToKg(185));
      await s.addTape('waist', 86);
      await s.addTape('arm', 38.5, side: 'R');
      await s.reload();
    });
    await tester.pumpWidget(app(BodyScreen(s: s)));
    await settle();
    await shot('17-body');

    // 18. the Export screen (batch 20)
    await tester.pumpWidget(app(ExportScreen(s: s)));
    await settle();
    await shot('18-export');

    await tester.pumpWidget(const SizedBox());
    await settle();
    await tester.runAsync(() => s.repo.close());
  });
}
