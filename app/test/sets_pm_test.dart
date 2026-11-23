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
import 'package:workout/ui/log_screen.dart';
import 'package:workout/ui/theme.dart';

/// A set fewer or more while lifting, one tap each; and the machine flies by their plain names.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  test('the machine flies have plain names; their ids (and so the history) stay', () {
    expect(lib.byId('pec_deck')!.name, 'Machine chest fly (pec deck)');
    expect(lib.byId('reverse_pec_deck')!.name, 'Machine reverse fly (rear delt)');
  });

  testWidgets('in a workout: − set and + set change today\'s sets, never below the logged ones', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('setpm');
    late AppState s;
    await tester.runAsync(() async {
      s = await AppState.forTest(await Repo.open('${dir.path}/s.db', factory: databaseFactoryFfiNoIsolate), PackStore(dir.path), lib);
      await s.saveProfile(profile);
      await s.makeBuiltInPlan();
      await s.startWorkout();
    });
    final planSets = s.plan!.days[s.session!.dayIndex].items.first.sets;
    final start = s.session!.day.items.first.sets;
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: LogScreen(s: s)));
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await settle();
    await tester.tap(find.byTooltip('One set more'));
    await settle();
    expect(s.session!.day.items.first.sets, start + 1);
    await tester.tap(find.byTooltip('One set fewer'));
    await settle();
    await tester.tap(find.byTooltip('One set fewer'));
    await settle();
    expect(s.session!.day.items.first.sets, start - 1);
    expect(s.plan!.days[s.session!.dayIndex].items.first.sets, planSets, reason: 'today only: the plan stays');
    await tester.pumpWidget(const SizedBox());
    await settle();
  });
}
