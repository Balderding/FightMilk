import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/backup.dart';
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
  final base = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final profile = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.lb);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('lp'));
  tearDown(() {
    stepOverrides.clear();
    customNeeds.clear();
  });

  Future<AppState> app() async {
    final r = await Repo.open('${dir.path}/l.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), base);
    await s.saveProfile(profile);
    return s;
  }

  test('hidden never in plans; favourites first; rename shows everywhere', () async {
    final s = await app();
    final p1 = makePlan(s.profile!, s.lib);
    final main = p1.days.first.items.first.exerciseId;
    await s.setHidden(main, true);
    final p2 = makePlan(s.profile!, s.lib);
    expect(p2.days.expand((d) => d.items).any((i) => i.exerciseId == main), isFalse);
    expect(s.lib.usable(s.lib.byId(main)!, s.profile!.have, {}), isFalse);
    // favourite an alternative for the same slot: it is picked
    final alt = s.lib.swapsFor(s.lib.byId(main)!, s.profile!.have, {}).firstWhere((e) => e.compound);
    await s.setFavourite(alt.id, true);
    expect(makePlan(s.profile!, s.lib).days.first.items.first.exerciseId, alt.id);
    await s.renameExercise(alt.id, 'My bench');
    expect(s.lib.byId(alt.id)!.name, 'My bench');
    await s.renameExercise(alt.id, '');
    expect(s.lib.byId(alt.id)!.name, base.byId(alt.id)!.name);
    await s.repo.close();
  });

  test('your own exercise: from a base, with its machine; follows the gym; in the backup', () async {
    final s = await app();
    final b = s.lib.byId('machine_chest_press')!;
    await s.saveCustomExercise(b.copyWith(id: 'my_1', name: 'Hammer wide press'), [{'plate_chest_press'}]);
    final e = s.lib.byId('my_1')!;
    expect(e.name, 'Hammer wide press');
    expect(e.primary, b.primary);
    expect(gymAllows(e, {'plate_chest_press'}), isTrue);
    expect(gymAllows(e, {'chest_press_m'}), isFalse);
    // survives a restart
    final again = await AppState.forTest(s.repo, PackStore(dir.path), base);
    expect(again.lib.byId('my_1')!.name, 'Hammer wide press');
    final text = await exportBackup(s.repo);
    expect((jsonDecode(text)['kv'] as List).any((r) => r['k'] == 'custom_ex'), isTrue);
    await s.deleteCustomExercise('my_1');
    expect(s.lib.byId('my_1'), isNull);
    await s.repo.close();
  });

  test('AI tools for favourites, hiding and names', () async {
    final s = await app();
    final r = parseToolReply('DO: exercise hide leg_press\nDO: exercise favourite hack_squat\nDO: exercise rename lat_pulldown Wide pulldown', s);
    expect(r.errors, isEmpty);
    await s.runActions('x', r.actions);
    expect(s.lib.hidden, contains('leg_press'));
    expect(s.lib.favs, contains('hack_squat'));
    expect(s.lib.byId('lat_pulldown')!.name, 'Wide pulldown');
    await s.undoChange(0);
    expect(s.lib.hidden, isEmpty);
    expect(s.lib.byId('lat_pulldown')!.name, isNot('Wide pulldown'));
    await s.repo.close();
  });
}
