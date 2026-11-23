import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/log_screen.dart';
import 'package:workout/ui/reports_screen.dart';
import 'package:workout/ui/theme.dart';
import 'package:workout/ui/today_screen.dart';
import 'package:workout/ui/widgets.dart';

/// Batch B1 (PLAN-next): see clearly. Contrast (F362), no text under 12 sp and the phone's text
/// size followed (F364, F365), tap targets and labels (F367, F368; starts F374).
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble(); // WCAG relative luminance
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  double ratio(Color a, Color b) {
    final x = lum(a), y = lum(b);
    return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
  }

  test('F362: borders reach 3:1 on the background, cards and chips', () {
    for (final (name, bg) in [('bg', C.bg), ('card', C.card), ('card2', C.card2)]) {
      expect(ratio(C.line, bg), greaterThanOrEqualTo(3.0), reason: name);
    }
  });

  test('F365: no text size under 12 in the app\'s screens (PDF point sizes are not screens)', () {
    final small = RegExp(r'(fontSize|size): ?([0-9]|1[01])(\.[0-9]+)?[,)]');
    final hits = <String>[];
    for (final f in Directory('lib/ui').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (small.hasMatch(lines[i]) && !lines[i].contains('Icon(') && !lines[i].contains('size: Size')) hits.add('${f.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty);
  });

  Future<AppState> app(WidgetTester tester, {bool workout = false}) async {
    final dir = Directory.systemTemp.createTempSync('a11y');
    late AppState s;
    await tester.runAsync(() async {
      s = await AppState.forTest(await Repo.open('${dir.path}/a.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(profile);
      await s.makeBuiltInPlan();
      await s.startWorkout();
      final it = s.session!.day.items.first;
      await s.repo.logSet(s.session!.id, it.exerciseId, 60, 8, slot: liftKey(it));
      if (!workout) await s.finishWorkout();
    });
    return s;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child, {double scale = 1}) => MaterialApp(
        theme: buildTheme(),
        home: Builder(builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Scaffold(body: child))),
      );

  for (final screen in ['Today', 'the workout screen']) {
    testWidgets('F367, F368: $screen meets the tap-target and label guidelines', (tester) async {
      phone(tester);
      final handle = tester.ensureSemantics();
      final s = await app(tester, workout: screen != 'Today');
      await tester.pumpWidget(host(screen == 'Today' ? TodayScreen(s: s) : LogScreen(s: s)));
      await settle(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      handle.dispose();
    });

    testWidgets('F364: $screen at 200 % text has no overflow', (tester) async {
      phone(tester);
      final s = await app(tester, workout: screen != 'Today');
      await tester.pumpWidget(host(screen == 'Today' ? TodayScreen(s: s) : LogScreen(s: s), scale: 2));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
  }

  testWidgets('F364: painted chart labels grow with the text size, up to the chart\'s room', (tester) async {
    late TextStyle at1, at2, at3;
    await tester.pumpWidget(host(Builder(builder: (c) {
      at1 = paintLabel(c);
      return const SizedBox();
    })));
    await tester.pumpWidget(host(Builder(builder: (c) {
      at2 = paintLabel(c);
      return const SizedBox();
    }), scale: 1.3));
    await tester.pumpWidget(host(Builder(builder: (c) {
      at3 = paintLabel(c);
      return const SizedBox();
    }), scale: 2));
    expect(at1.fontSize, 12);
    expect(at2.fontSize, closeTo(15.6, 0.01));
    expect(at3.fontSize, closeTo(12 * chartScaleMax, 0.01), reason: 'capped to fit the fixed-height charts');
    // the largest label fits the line chart's margins and a reports row
    expect(textHeight(at3), lessThanOrEqualTo(22.0));
  });

  testWidgets('F364: the reports charts lay out at 200 % without overflow', (tester) async {
    phone(tester);
    final s = await app(tester);
    await tester.pumpWidget(host(ReportsScreen(s: s), scale: 2));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
