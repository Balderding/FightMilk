import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/quick.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/superset.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.lb);
  PlanItem it(String id) => PlanItem(exerciseId: id, sets: 3, repLow: 8, repHigh: 12, restSec: 90);
  tearDown(() => stepOverrides.clear());

  test('pair, label, ungroup', () {
    var l = [it('bench_press'), it('cable_curl'), it('triceps_pushdown'), it('lat_pulldown')];
    l = supersetWithNext(l, 1);
    expect([for (var i = 0; i < l.length; i++) groupLabel(l, i)], ['', 'A1', 'A2', '']);
    l = supersetWithNext(l, 2); // joins A
    expect(groupLabel(l, 3), 'A3');
    l = ungroup(l, 3);
    l = ungroup(l, 2);
    expect(l[1].group, isNull, reason: 'a group of one is no group');
  });

  test('auto pairs opposite muscles, main lift alone', () {
    final l = autoSupersets([it('bench_press'), it('cable_curl'), it('lat_pulldown'), it('triceps_pushdown'), it('incline_db_press')], lib);
    expect(l.first.group, isNull);
    final byG = <int, List<String>>{};
    for (final x in l.skip(1)) {
      if (x.group != null) (byG[x.group!] ??= []).add(lib.byId(x.exerciseId)!.primary.first);
    }
    expect(byG.values.any((p) => p.toSet().containsAll({'biceps', 'triceps'})), isTrue);
    expect(byG.values.any((p) => p.contains('chest') && (p.contains('back') || p.contains('lats'))), isTrue);
  });

  test('the round: partner next, then back to the first with sets left', () {
    final l = supersetWithNext([it('bench_press'), it('cable_curl'), it('triceps_pushdown')], 1);
    expect(nextInRound(l, 1, {'cable_curl': 1}), 2);
    expect(nextInRound(l, 2, {'cable_curl': 1, 'triceps_pushdown': 1}), isNull);
    expect(roundStart(l, 2, {'cable_curl': 1, 'triceps_pushdown': 1}), 1);
    expect(roundStart(l, 2, {'cable_curl': 3, 'triceps_pushdown': 3}), isNull);
    expect(nextInRound(l, 0, const {}), isNull);
  });

  test('tools and quick commands', () async {
    final dir = Directory.systemTemp.createTempSync('ss');
    final r = await Repo.open('${dir.path}/s.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(profile);
    await s.makeBuiltInPlan();
    final items = s.today!.items;
    final t = parseToolReply('DO: superset ${items[3].exerciseId} ${items[1].exerciseId} today', s);
    expect(t.errors, isEmpty);
    await s.runActions('t', t.actions);
    final l = s.today!.items;
    final i = l.indexWhere((x) => x.exerciseId == items[3].exerciseId);
    expect(l[i + 1].exerciseId, items[1].exerciseId);
    expect(l[i].group, isNotNull);
    expect(l[i].group, l[i + 1].group);
    final q = quickCommand('no supersets today', s)!;
    await s.runActions('q', q.actions);
    expect(s.today!.items.every((x) => x.group == null), isTrue);
    final q2 = quickCommand('chest and back workout with supersets', s)!;
    await s.runActions('q2', q2.actions);
    expect(s.today!.items.any((x) => x.group != null), isTrue);
    await r.close();
  });
}
