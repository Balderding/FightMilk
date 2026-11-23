import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/log_screen.dart';
import 'package:workout/ui/theme.dart';
import 'package:workout/ui/widgets.dart';

/// F085: left-handed mode mirrors the steppers and the workout button row.
/// F086: a dark screen while resting; a touch on it only wakes it.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  Future<AppState> app() async {
    final dir = Directory.systemTemp.createTempSync('lefty');
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    return s;
  }

  tearDown(() => leftHandedLayout = false);

  Future<(double, double)> xs(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: BigStepper(value: '60', unit: 'kg', onMinus: () {}, onPlus: () {}))));
    return (tester.getCenter(find.byIcon(Icons.remove)).dx, tester.getCenter(find.byIcon(Icons.add)).dx);
  }

  testWidgets('the stepper is minus-left normally and plus-left when left-handed', (tester) async {
    final (m, p) = await xs(tester);
    expect(m, lessThan(p));
    leftHandedLayout = true;
    final (m2, p2) = await xs(tester);
    expect(m2, greaterThan(p2));
    expect(find.text('60'), findsOneWidget); // the number itself reads the same
  });

  test('the setting is saved, sets the layout and is an AI tool', () async {
    final s = await app();
    expect(s.settings.leftHanded, isFalse);
    final r = parseToolReply('SAY: ok\nDO: setting left_handed on', s);
    expect(r.errors, isEmpty);
    await r.actions.single.run(s);
    expect(s.settings.leftHanded, isTrue);
    expect(leftHandedLayout, isTrue);
    expect(Settings.fromJson(s.settings.toJson()).leftHanded, isTrue);
    expect(toolGrammar(s.lib, s.profile!, s.plan!.days.length), contains('"left_handed "'));
    await s.saveSettings(s.settings.copyWith(leftHanded: false));
    expect(leftHandedLayout, isFalse);
  });

  testWidgets('F086 dark while resting: a touch wakes it and presses nothing', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    restDimAfter = Duration.zero;
    addTearDown(() => restDimAfter = const Duration(seconds: 8));
    late AppState s;
    Future<void> settle([int n = 6]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('dim');
      s = await AppState.forTest(await Repo.open('${dir.path}/d.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(full);
      await s.makeBuiltInPlan();
      await s.saveSettings(s.settings.copyWith(dimRest: true));
      await s.startWorkout();
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: LogScreen(s: s)));
    await settle();
    expect(find.byKey(const Key('restDim')), findsNothing, reason: 'no rest yet');
    s.startRest(const Duration(seconds: 90));
    await tester.pump(const Duration(seconds: 1)); // the screen redraws on its half-second tick
    await settle();
    expect(find.byKey(const Key('restDim')), findsOneWidget);
    expect(find.text('Resting · tap to wake'), findsOneWidget);
    expect(find.ancestor(of: find.text('Resting · tap to wake'), matching: find.byType(Material)), findsWidgets, reason: 'a Material above: no yellow underline (review 5, P2-6)');
    expect(find.descendant(of: find.byKey(const Key('restDim')), matching: find.byType(Material)), findsNothing);
    final sets = (await tester.runAsync(() => s.repo.setsFor(s.session!.id)))!.length;
    restDimAfter = const Duration(minutes: 1); // so it stays awake after the wake touch
    await tester.tapAt(tester.getCenter(find.byType(FilledButton).last, warnIfMissed: false));
    await tester.pump();
    expect(find.byKey(const Key('restDim')), findsNothing, reason: 'the touch woke it');
    expect((await tester.runAsync(() => s.repo.setsFor(s.session!.id)))!.length, sets, reason: 'and pressed nothing under it');
    // dark again: Back only wakes it, the workout screen stays (review 5, P3-N39)
    restDimAfter = Duration.zero;
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('restDim')), findsOneWidget);
    restDimAfter = const Duration(minutes: 1);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('restDim')), findsNothing, reason: 'Back woke it');
    expect(find.byType(LogScreen), findsOneWidget, reason: 'and did not leave the workout');
    s.stopRest();
    await tester.pumpWidget(const SizedBox());
    await settle(2);
  });

  test('F086 the setting is an AI tool', () async {
    final s = await app();
    final r = parseToolReply('SAY: ok\nDO: setting dim_rest on', s);
    expect(r.errors, isEmpty);
    await r.actions.single.run(s);
    expect(s.settings.dimRest, isTrue);
    expect(Settings.fromJson(s.settings.toJson()).dimRest, isTrue);
    expect(toolGrammar(s.lib, s.profile!, s.plan!.days.length), contains('"dim_rest "'));
  });
}
