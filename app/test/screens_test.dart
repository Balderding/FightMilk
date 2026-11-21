import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/gym.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/calculators_screen.dart';
import 'package:workout/ui/gyms_screen.dart';
import 'package:workout/ui/theme.dart';
import 'package:workout/ui/timers_screen.dart';

void main() {
  sqfliteFfiInit();

  Future<AppState> app(WidgetTester tester) async {
    late AppState s;
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('sc');
      final r = await Repo.open('${dir.path}/s.db', factory: databaseFactoryFfi);
      s = await AppState.forTest(r, PackStore(dir.path), Library.fromJsonString(File('assets/exercises.json').readAsStringSync()));
      await s.saveProfile(Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.lb));
      await s.makeBuiltInPlan();
    });
    return s;
  }

  testWidgets('timers: modes and the rep counter', (tester) async {
    final s = await app(tester);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: TimersScreen(s: s)));
    await tester.tap(find.text('Rep counter'));
    await tester.pump();
    await tester.tap(find.text('0'));
    await tester.pump();
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('Tabata'));
    await tester.pump();
    expect(find.textContaining('round 1 of 8'), findsOneWidget);
    await tester.runAsync(() => s.repo.close());
  });

  testWidgets('calculators: 1RM, plates', (tester) async {
    final s = await app(tester);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: CalculatorsScreen(s: s)));
    await tester.enterText(find.widgetWithText(TextField, 'Weight').first, '225');
    await tester.pump();
    expect(find.textContaining('Estimated 1RM: 262.5'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(TextField, 'Total'), 300, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextField, 'Total'), '185');
    await tester.pump();
    expect(find.textContaining('Per side: 45 + 25'), findsOneWidget);
    await tester.runAsync(() => s.repo.close());
  });

  testWidgets('gym editor shows every area and the bar/plates', (tester) async {
    final s = await app(tester);
    final pf = gymTemplates.first;
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: GymEditScreen(s: s, gym: Gym.create('PF', {...pf.items, 'barbell'}), isNew: true)));
    await tester.pump();
    expect(find.text('Machines (pin-loaded)'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Bar and plates'), 400, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Bar and plates'), findsOneWidget);
    await tester.runAsync(() => s.repo.close());
  });
}
