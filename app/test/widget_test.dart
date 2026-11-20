import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/main.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/theme.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('first launch → setup → plan → Today → log a set', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('wt');
    late AppState s;
    await tester.runAsync(() async {
      final repo = await Repo.open('${dir.path}/w.db', factory: databaseFactoryFfi);
      s = await AppState.forTest(repo, PackStore(dir.path), Library.fromJsonString(File('assets/exercises.json').readAsStringSync()));
    });

    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Home(s: s)));
    await settle();
    expect(find.text("Let's set you up"), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Make my plan'), 300);
    await tester.tap(find.text('Make my plan'));
    await settle();
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Upper A'), findsOneWidget); // 4 days by default → upper/lower
    expect(find.text('Swap'), findsWidgets);

    await tester.tap(find.text('Start workout'));
    await settle();
    expect(find.text('Done set'), findsOneWidget);
    // first time with this lift: the app asks what weight to start with
    expect(find.textContaining('First time: '), findsOneWidget);
    expect(find.textContaining("let's start the workout"), findsOneWidget); // the coach greets
    await tester.enterText(find.byType(TextField), '135');
    await tester.tap(find.text('Use it'));
    await settle();
    expect(find.text('135'), findsOneWidget);

    await tester.tap(find.text('Done set'));
    await settle();
    // the coach line moves on to resting, and the shared rest timer is running
    expect(find.textContaining('Rest up'), findsOneWidget);
    expect(s.restLeft, isNotNull);
    expect(s.restLeft!.inSeconds, greaterThan(0));
    // smart rest: heavy compound main lift -> long rest
    expect(s.restLeft!.inSeconds, greaterThan(100));
    await tester.drag(find.text('Done set'), const Offset(0, -500));
    await settle();
    expect(find.text('✓'), findsOneWidget);

    await tester.runAsync(() async {
      final sets = await s.repo.setsFor(s.session!.id);
      expect(sets.length, 1);
    });

    // leave the screen so its timers stop
    await tester.pageBack();
    await settle();
    await tester.pumpWidget(const SizedBox());
    await settle();
    await tester.runAsync(() => s.repo.close());
  });
}
