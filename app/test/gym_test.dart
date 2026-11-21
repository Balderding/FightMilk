import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/plan_json.dart';
import 'package:workout/ai/quick.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/gym.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.lb);
  final pf = gymTemplates.firstWhere((t) => t.id == 'planet_fitness');
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('gym'));
  tearDown(() => stepOverrides.clear());

  Future<AppState> app() async {
    final r = await Repo.open('${dir.path}/g.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(profile);
    await s.makeBuiltInPlan();
    return s;
  }

  test('every machine exercise names its machine; every item id is real', () {
    for (final e in lib.all) {
      for (final opt in needsOf(e)) {
        for (final i in opt) {
          expect(gymItemById.containsKey(i), isTrue, reason: '${e.id} needs unknown item $i');
        }
      }
    }
    final full = {for (final i in gymItems) i.id};
    expect(lib.all.where((e) => !gymAllows(e, full)).map((e) => e.id), isEmpty, reason: 'a gym with everything can do every exercise');
    expect(lib.all.where((e) => gymAllows(e, const {})).every((e) => e.equipment == Equipment.bodyweight), isTrue);
  });

  test('Planet Fitness: Smith and machines, no barbell squat, no hack squat', () {
    final ok = {for (final e in lib.all) if (gymAllows(e, pf.items)) e.id};
    for (final id in ['smith_squat', 'smith_bench_press', 'machine_chest_press', 'lat_pulldown', 'seated_cable_row', 'leg_extension', 'seated_leg_curl', 'db_bench_press', 'barbell_curl', 'pull_up', 'dips', 'trx_row']) {
      expect(ok, contains(id));
    }
    for (final id in ['back_squat', 'bench_press', 'deadlift', 'hack_squat', 'trap_bar_deadlift', 'leg_press', 'lying_leg_curl', 't_bar_row']) {
      expect(ok, isNot(contains(id)));
    }
    final p = profile.copyWith(have: kindsOf(pf.items), items: pf.items);
    final plan = makePlan(p, lib);
    for (final d in plan.days) {
      for (final it in d.items) {
        expect(gymAllows(lib.byId(it.exerciseId)!, pf.items), isTrue, reason: '${d.name}: ${it.exerciseId}');
      }
    }
    // the AI check refuses what the gym lacks, and says what is missing
    final r = parseDay('DAY: Legs\nback_squat | 4 | 5-8 | 150\nleg_extension | 3 | 10-12 | 90', lib, profile: p);
    expect(r.day, isNull);
    expect(r.errors.single, contains('power rack'));
  });

  test('switch gyms, taken today, and the tools', () async {
    final s = await app();
    expect(s.profile!.items, isNull);
    await s.saveGym(Gym.create('PF Hull', {...pf.items}));
    expect(s.activeGym!.name, 'PF Hull');
    expect(s.profile!.items, pf.items);
    expect(s.lib.usable(s.lib.byId('back_squat')!, s.profile!.have, {}, items: s.profile!.items), isFalse);

    await s.setTaken('smith', true);
    expect(s.profile!.items!.contains('smith'), isFalse);
    expect(s.lib.usable(s.lib.byId('smith_squat')!, s.profile!.have, {}, items: s.profile!.items), isFalse);
    await s.setTaken('smith', false);
    expect(s.profile!.items!.contains('smith'), isTrue);

    var r = parseToolReply('SAY: ok\nDO: gym new home_garage Garage\nDO: gym add dip_station', s);
    expect(r.errors, isEmpty);
    await s.runActions('garage', r.actions.take(1).toList());
    expect(s.activeGym!.name, 'Garage');
    r = parseToolReply('DO: gym add dip_station\nDO: gym taken power_rack', s);
    await s.runActions('garage 2', r.actions);
    expect(s.activeGym!.items, contains('dip_station'));
    expect(s.takenToday, contains('power_rack'));

    final q = quickCommand("I'm at PF Hull today", s)!;
    await s.runActions('q', q.actions);
    expect(s.activeGym!.name, 'PF Hull');
    expect(s.gyms.length, 2);

    await s.undoChange(0);
    expect(s.activeGym!.name, 'Garage', reason: 'undo switches back');
    await s.repo.close();
  });

  test("quick: I'm at Planet Fitness makes the gym from the template", () async {
    final s = await app();
    final q = quickCommand("I'm at planet fitness", s)!;
    expect(q.actions.single.says, contains('Planet Fitness'));
    await s.runActions('q', q.actions);
    expect(s.activeGym!.items, pf.items);
    await s.repo.close();
  });
}
