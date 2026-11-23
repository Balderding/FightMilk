import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

/// Review 4 P3 polish done while review 5 runs (N20, N22, N23).
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  Future<AppState> app() async {
    final dir = Directory.systemTemp.createTempSync('polish19');
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    return s;
  }

  test('N22 a broken saved value never stops the load; it keeps its default and is named', () async {
    final s = await app();
    final planId = s.plan!.id;
    await s.repo.kvSet('ramp', '{"bench_press": "not a map"}');
    await s.repo.kvSet('tape', '{broken');
    await s.repo.kvSet('aims', '[1, 2]');
    await s.repo.kvSet('settings', '{"rest": "soon"');
    await s.repo.kvSet('override', '{"plan": 3');
    await s.reload();
    expect(s.plan!.id, planId, reason: 'the plan still loads');
    expect(s.tape, isEmpty);
    expect(s.loadProblems, containsAll(['settings', 'body']));
    expect(s.loadProblems.length, greaterThanOrEqualTo(3));
    // fixed values load again with nothing named
    await s.repo.kvSet('ramp', '{}');
    await s.repo.kvSet('tape', '[]');
    await s.repo.kvSet('aims', '[]');
    await s.repo.kvSet('settings', '{}');
    await s.repo.kvSet('override', '{}');
    await s.reload();
    expect(s.loadProblems, isEmpty);
  });

  test('N23 a weigh-in today is known, so its reminder is skipped', () async {
    final s = await app();
    expect(s.weighedToday, isFalse);
    await s.repo.logBody(80, at: DateTime.now().subtract(const Duration(days: 1)));
    await s.reload();
    expect(s.weighedToday, isFalse, reason: 'yesterday does not count');
    await s.repo.logBody(80);
    await s.reload();
    expect(s.weighedToday, isTrue);
  });
}
