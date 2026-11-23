import 'dart:io';

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
import 'package:workout/ui/history_screen.dart';
import 'package:workout/ui/log_screen.dart';
import 'package:workout/ui/shortcuts.dart';

/// Batch 23: app shortcuts (F352) and the Quick Settings tile (F353) open a screen, never save.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  Future<AppState> app() async {
    final dir = Directory.systemTemp.createTempSync('sc23');
    final s = await AppState.forTest(await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi), PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    return s;
  }

  Future<(BuildContext, List<int>)> host(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox());
    })));
    return (ctx, <int>[]);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('"Log weight" opens the weigh-in and saves nothing by itself', (tester) async {
    final s = (await tester.runAsync(app))!;
    final (ctx, tabs) = await host(tester);
    final before = (await tester.runAsync(() => s.repo.db.query('body')))!.length;
    openShortcut(ctx, s, 'weight', tabs.add).ignore();
    await settle(tester);
    expect(tabs, [0]);
    expect(find.byType(TextField), findsWidgets, reason: 'the weigh-in is open');
    expect((await tester.runAsync(() => s.repo.db.query('body')))!.length, before, reason: 'nothing saved until Save');
  });

  testWidgets('"Today\'s workout" opens a workout in progress where it was left, and starts none', (tester) async {
    final s = (await tester.runAsync(app))!;
    final (ctx, tabs) = await host(tester);
    openShortcut(ctx, s, 'today', tabs.add).ignore();
    await settle(tester);
    expect(tabs, [0]);
    expect(find.byType(LogScreen), findsNothing);
    expect(s.session, isNull, reason: 'a shortcut never starts a workout');
    await tester.runAsync(s.startWorkout);
    openShortcut(ctx, s, 'today', tabs.add).ignore();
    await settle(tester);
    expect(find.byType(LogScreen), findsOneWidget);
  });

  testWidgets('"Last workout" opens it on History, or says there is none', (tester) async {
    final s = (await tester.runAsync(app))!;
    final (ctx, tabs) = await host(tester);
    openShortcut(ctx, s, 'last', tabs.add).ignore();
    await settle(tester);
    expect(find.text('No workout yet.'), findsOneWidget);
    expect(tabs, isEmpty);
    await tester.runAsync(() async {
      await s.startWorkout();
      await s.repo.logSet(s.session!.id, s.session!.day.items.first.exerciseId, 60, 8);
      await s.finishWorkout();
    });
    openShortcut(ctx, s, 'last', tabs.add).ignore();
    await settle(tester);
    expect(tabs, [2]);
    expect(find.byType(SessionDetail), findsOneWidget);
  });

  test('only the known places', () {
    expect(shortcutPlaces, {'today', 'weight', 'last'});
  });

  group('F351 the home-screen widget', () {
    test('its lines: the next workout and this week, never weights or body numbers', () async {
      final s = await app();
      var l = await s.widgetLines();
      expect(l.next, anyOf(startsWith('Today: '), startsWith('Rest day. Next: ')));
      expect(l.next, contains(s.plan!.days[s.todayIndex].name));
      expect(l.week, startsWith('0 of ${s.perWeekGoal} this week'));
      await s.repo.logBody(83.4);
      await s.startWorkout();
      await s.repo.logSet(s.session!.id, s.session!.day.items.first.exerciseId, 61.5, 8);
      l = await s.widgetLines();
      expect(l.next, startsWith('In progress: '));
      await s.finishWorkout();
      l = await s.widgetLines();
      expect(l.week, startsWith('1 of ${s.perWeekGoal} this week'));
      for (final x in [l.next, l.week]) {
        expect(x, isNot(contains('83')), reason: 'no body weight on the home screen');
        expect(x, isNot(contains('61')), reason: 'no lifted weights on the home screen');
        expect(x, isNot(contains('kg')));
      }
    });

    test('pushing the lines never throws without a widget (tests, desktop)', () async {
      final s = await app();
      await s.updateHomeWidget();
    });
  });

  group('F354/F356 links (and NFC stickers) only open a screen', () {
    test('which links open what; anything else opens nothing', () {
      expect(readLink('fightmilk://start')?.go, 'today');
      expect(readLink('FIGHTMILK://Today')?.go, 'today');
      expect(readLink('fightmilk://last')?.go, 'last');
      expect(readLink('fightmilk://weight')?.kg, isNull);
      expect(readLink('fightmilk://weight?kg=80.5')?.kg, 80.5);
      expect(readLink('fightmilk://weight?kg=80,5')?.kg, 80.5);
      expect(readLink('fightmilk://weight?lb=176')!.kg, closeTo(79.83, 0.01));
      for (final odd in ['fightmilk://weight?kg=5', 'fightmilk://weight?kg=9000', 'fightmilk://weight?kg=abc', 'fightmilk://weight?kg=NaN', 'fightmilk://weight?kg=-80']) {
        final l = readLink(odd)!;
        expect(l.go, 'weight', reason: odd);
        expect(l.kg, isNull, reason: odd);
        expect(l.odd, isTrue, reason: odd);
      }
      for (final none in ['fightmilk://plan#abc', 'fightmilk://delete', 'fightmilk://wipe?all=1', 'https://start', 'fightmilk:start', 'fightmilk://${'x' * 300}', '']) {
        expect(readLink(none), isNull, reason: none);
      }
    });

    testWidgets('a weight link fills the weigh-in in, says so, and saves nothing until Save', (tester) async {
      final s = (await tester.runAsync(app))!;
      final (ctx, tabs) = await host(tester);
      final l = readLink('fightmilk://weight?kg=81.5')!;
      openShortcut(ctx, s, l.go, tabs.add, kg: l.kg, fromLink: true, odd: l.odd).ignore();
      await settle(tester);
      expect(find.text('Filled in from a link. Check it, then tap Save.'), findsOneWidget);
      expect(find.widgetWithText(TextField, '81.5'), findsOneWidget);
      expect((await tester.runAsync(() => s.repo.db.query('body')))!, isEmpty);
      await tester.tap(find.text('Save'));
      await settle(tester);
      final rows = (await tester.runAsync(() => s.repo.db.query('body')))!;
      expect(rows.single['kg'], 81.5, reason: 'saved by the tap');
    });

    testWidgets('an odd number in a link is left out and said', (tester) async {
      final s = (await tester.runAsync(app))!;
      final (ctx, tabs) = await host(tester);
      final l = readLink('fightmilk://weight?kg=9000')!;
      openShortcut(ctx, s, l.go, tabs.add, kg: l.kg, fromLink: true, odd: l.odd).ignore();
      await settle(tester);
      expect(find.text('The number in the link did not look like a body weight, so it was left out.'), findsOneWidget);
      expect((await tester.runAsync(() => s.repo.db.query('body')))!, isEmpty);
    });
  });
}
