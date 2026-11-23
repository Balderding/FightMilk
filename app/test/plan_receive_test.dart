import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_share.dart';
import 'package:workout/domain/program.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/plan_receive.dart';
import 'package:workout/ui/theme.dart';

/// Batch 20: a received plan is shown first, saved as a new plan, its own-script rule stays out
/// unless the person says "Use it", and gym swaps are offered (F327). QR (F325).
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final home = Profile(goal: Goal.both, days: 3, minutes: 45, have: {Equipment.dumbbell, Equipment.bodyweight}, avoid: {}, unit: Unit.kg);
  final sent = Plan(name: 'From a friend', source: 'mine', days: [
    PlanDay(name: 'A', items: [const PlanItem(exerciseId: 'bench_press', sets: 3, repLow: 5, repHigh: 5, restSec: 120), const PlanItem(exerciseId: 'goblet_squat', sets: 3, repLow: 8, repHigh: 12, restSec: 90)]),
  ], program: const ProgramInfo(id: 'shared', rules: {'goblet_squat': LiftRule(kind: 'script', script: 'if top: add 1\nelse: same')}));

  Future<(AppState, Plan)> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('recv');
      final s = await AppState.forTest(await Repo.open('${dir.path}/r.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(home);
      await s.makeBuiltInPlan();
      return s;
    }))!;
    return (s, s.plan!);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, AppState s, String input) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Builder(builder: (c) => Scaffold(body: Center(child: FilledButton(onPressed: () => receivePlan(c, s, input), child: const Text('go'))))),
    ));
    await tester.tap(find.text('go'));
    await settle(tester);
  }

  testWidgets('shown first; saved as a new plan; the script stays out by default; swaps offered', (tester) async {
    final (s, before) = await setup(tester);
    await open(tester, s, sharePlanLink(sent));
    expect(find.text('A plan to add: From a friend'), findsOneWidget);
    expect(find.text('This plan has its own progression rule'), findsOneWidget);
    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.text('Every set at the top of the range: add 1 weight step'), findsOneWidget, reason: 'each line in plain words');
    expect(find.text('if top: add 1\nelse: same'), findsOneWidget);
    expect(find.text('Leave them out'), findsOneWidget);
    expect(find.textContaining('Swap Bench press for'), findsOneWidget, reason: 'a dumbbell gym has no bench press');
    await tester.tap(find.byKey(const Key('receiveSave')));
    await settle(tester);
    expect(s.plan!.id, before.id, reason: 'the plan in use stays');
    final saved = (await tester.runAsync(() => s.repo.oldPlans()))!.firstWhere((p) => p.name == 'From a friend');
    expect(saved.id, isNot(sent.id));
    expect(saved.program?.rules['goblet_squat'], isNull, reason: 'the script is off unless the person says Use it');
    expect(saved.days.first.items.first.exerciseId, isNot('bench_press'), reason: 'the swap was made');
  });

  testWidgets('"Use it" takes the script in; a broken file says why and saves nothing', (tester) async {
    final (s, _) = await setup(tester);
    await open(tester, s, sharePlanJson(sent));
    await tester.tap(find.text('Use these rules'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('receiveUse')));
    await settle(tester);
    expect(s.plan!.name, 'From a friend');
    expect(s.plan!.program!.rules['goblet_squat']!.script, 'if top: add 1\nelse: same');
    final n = (await tester.runAsync(() => s.repo.oldPlans()))!.length;
    await open(tester, s, sharePlanJson(sent).substring(0, 40));
    expect(find.text('Not a plan the app can use'), findsOneWidget);
    expect(find.textContaining('cut short'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect((await tester.runAsync(() => s.repo.oldPlans()))!.length, n);
  });

  test('F325 a plan link fits in one QR code', () {
    final link = sharePlanLink(sent);
    final q = QrImage(QrCode(payload: QrPayload.fromString(link), errorCorrectLevel: QrErrorCorrectLevel.low));
    expect(q.moduleCount, greaterThan(20));
    expect(link, startsWith('fightmilk://plan#'));
    expect(link, isNot(contains('http')), reason: 'no server: the plan is in the link');
  });
}
