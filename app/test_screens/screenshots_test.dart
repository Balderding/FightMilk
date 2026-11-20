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
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/log_screen.dart';
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
      final repo = await Repo.open('${dir.path}/s.db', factory: databaseFactoryFfi);
      s = await AppState.forTest(repo, PackStore(dir.path), lib);
    });

    Widget app(Widget home) => RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: home));

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
        await tester.drag(find.byType(ListView).first, const Offset(0, -250));
        await settle();
      }
      await shot(name);
      expect(i, isNonZero);
    }

    // 8. exercise library
    await tester.pumpWidget(app(ExercisePicker(s: s, title: 'All exercises', browse: true)));
    await settle();
    await shot('8-library');

    await tester.pumpWidget(const SizedBox());
    await settle();
    await tester.runAsync(() => s.repo.close());
  });
}
