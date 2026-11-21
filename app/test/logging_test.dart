import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/quick.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.lb);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('lg'));
  tearDown(() => stepOverrides.clear());

  Future<AppState> app() async {
    final r = await Repo.open('${dir.path}/l.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(profile);
    await s.makeBuiltInPlan();
    return s;
  }

  test('typing "185 x 5" in Ask AI logs a set on the first unfinished exercise', () async {
    final s = await app();
    expect(quickCommand('185 x 5', s), isNull, reason: 'no workout going yet: not a set');
    await s.startWorkout();
    final first = s.session!.day.items.first.exerciseId;
    var q = quickCommand('log 185x5', s)!;
    await s.runActions('q', q.actions);
    q = quickCommand('8 reps at 60 kg', s)!;
    await s.runActions('q', q.actions);
    final sets = await s.repo.setsFor(s.session!.id);
    expect(sets.length, 2);
    expect(sets.first.exerciseId, first);
    expect(toUnit(sets.first.kg, Unit.lb), closeTo(185, 0.01));
    expect(sets.first.reps, 5);
    expect(sets[1].kg, closeTo(60, 0.01));
    expect(sets[1].reps, 8);
    final t = parseToolReply('DO: log ${s.session!.day.items[1].exerciseId} 100 10', s);
    expect(t.errors, isEmpty);
    await s.runActions('t', t.actions);
    expect((await s.repo.setsFor(s.session!.id)).last.reps, 10);
    await s.repo.close();
  });

  test('rest off means no timer; the timer counts up after zero', () async {
    final s = await app();
    await s.saveSettings(s.settings.copyWith(restOff: true));
    s.startRest(const Duration(seconds: 90));
    expect(s.restLeft, isNull);
    await s.saveSettings(s.settings.copyWith(restOff: false));
    s.restEnd = DateTime.now().subtract(const Duration(seconds: 20));
    expect(s.restLeft, Duration.zero);
    expect(s.restOver!.inSeconds, greaterThanOrEqualTo(19));
    final q = quickCommand('rest 90 seconds', s)!;
    await s.saveSettings(s.settings.copyWith(restOff: true));
    await s.runActions('q', q.actions);
    expect(s.settings.restOff, isFalse, reason: 'asking for a rest time turns the timer back on');
    await s.repo.close();
  });

  test('a deleted set comes back with Undo', () async {
    final s = await app();
    final ses = await s.startWorkout();
    final x = await s.repo.logSet(ses.id, ses.day.items.first.exerciseId, 50, 8, type: SetType.warmup);
    await s.repo.deleteSet(x.id);
    expect(await s.repo.setsFor(ses.id), isEmpty);
    await s.repo.restoreSet(x);
    final back = await s.repo.setsFor(ses.id);
    expect(back.single.id, x.id);
    expect(back.single.type, SetType.warmup);
    await s.repo.close();
  });
}
