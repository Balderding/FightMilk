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
import 'package:workout/ui/plan_screen.dart';
import 'package:workout/ui/theme.dart';

/// Add and remove an exercise: on a plan day, on Today before starting, and in a workout.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  Future<AppState> app({DatabaseFactory? f}) async {
    final dir = Directory.systemTemp.createTempSync('addrm');
    final s = await AppState.forTest(await Repo.open('${dir.path}/a.db', factory: f ?? databaseFactoryFfi), PackStore(dir.path), lib);
    await s.saveProfile(profile);
    await s.makeBuiltInPlan();
    return s;
  }

  List<String> ids(PlanDay d) => [for (final it in d.items) it.exerciseId];

  test('Today before starting: remove for today only, or from the plan too; Undo puts both back', () async {
    final s = await app();
    final planDay = ids(s.plan!.days[s.todayIndex]);
    final first = s.today!.items.first.exerciseId;
    var r = await s.removeFromToday(0);
    expect(ids(s.today!), isNot(contains(first)));
    expect(ids(s.plan!.days[s.todayIndex]), planDay, reason: 'today only: the plan stays');
    await s.undoRemoveToday(r);
    expect(ids(s.today!), planDay);
    r = await s.removeFromToday(0, forever: true);
    expect(ids(s.plan!.days[s.todayIndex]), isNot(contains(first)), reason: 'from the plan too');
    expect(ids(s.today!), isNot(contains(first)));
    await s.undoRemoveToday(r);
    expect(ids(s.plan!.days[s.todayIndex]), planDay);
    expect(ids(s.today!), planDay);
    await s.repo.close();
  });

  test('Add for today only, or to the plan too', () async {
    final s = await app();
    final e = lib.byId('face_pull')!;
    final planDay = ids(s.plan!.days[s.todayIndex]);
    await s.addToToday(e);
    expect(ids(s.today!).last, 'face_pull');
    expect(ids(s.plan!.days[s.todayIndex]), planDay);
    final e2 = lib.byId('hammer_curl')!;
    await s.addToToday(e2, forever: true);
    expect(ids(s.plan!.days[s.todayIndex]).last, 'hammer_curl');
    expect(ids(s.today!), containsAll(['face_pull', 'hammer_curl']), reason: "today's other change stays");
    await s.repo.close();
  });

  test('In a workout: remove an exercise with logged sets deletes those sets; Undo brings them back', () async {
    final s = await app();
    await s.startWorkout();
    final it = s.session!.day.items.first;
    final other = s.session!.day.items[1];
    await s.repo.logSet(s.session!.id, it.exerciseId, 60, 8, slot: liftKey(it));
    await s.repo.logSet(s.session!.id, it.exerciseId, 60, 7, slot: liftKey(it));
    await s.repo.logSet(s.session!.id, other.exerciseId, 40, 10, slot: liftKey(other));
    final r = await s.removeFromToday(0);
    expect(ids(s.session!.day), isNot(contains(it.exerciseId)));
    final left = await s.repo.setsFor(s.session!.id);
    expect(left.map((x) => x.exerciseId), [other.exerciseId], reason: "the other exercise's set stays");
    await s.undoRemoveToday(r);
    expect(ids(s.session!.day).first, it.exerciseId);
    expect((await s.repo.setsFor(s.session!.id)).length, 3);
    // adding during the workout
    await s.addToToday(lib.byId('face_pull')!);
    expect(ids(s.session!.day).last, 'face_pull');
    await s.repo.close();
  });

  testWidgets('a plan day has a Remove button on every exercise, with Undo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(() => app(f: databaseFactoryFfiNoIsolate)))!;
    final before = ids(s.plan!.days.first);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: DayEditor(s: s, dayIndex: 0)));
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await settle();
    // every row on screen has one (a long day's last rows are built when scrolled to)
    expect(find.byTooltip('Remove from this day'), findsNWidgets(find.byTooltip('Change sets, reps, rest').evaluate().length));
    expect(find.byTooltip('Remove from this day'), findsAtLeastNWidgets(4));
    await tester.tap(find.byTooltip('Remove from this day').first);
    await settle();
    expect(ids(s.plan!.days.first), before.sublist(1));
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle();
    expect(ids(s.plan!.days.first), before);
    await tester.pumpWidget(const SizedBox());
    await settle();
  });
}
