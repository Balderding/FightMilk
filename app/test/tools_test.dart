import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/grammar.dart';
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
  setUp(() => dir = Directory.systemTemp.createTempSync('tools'));
  tearDown(() => stepOverrides.clear());

  Future<AppState> app({Profile? p}) async {
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(p ?? profile);
    await s.makeBuiltInPlan();
    return s;
  }

  String firstOf(Equipment e, String muscle) => lib.all.firstWhere((x) => x.equipment == e && x.primary.first == muscle).id;

  test('a new workout for today, settings and a swap, then undo puts it all back', () async {
    final s = await app();
    final before = s.today!.toJson();
    final chest = firstOf(Equipment.machine, 'chest');
    final shoulders = firstOf(Equipment.dumbbell, 'shoulders');
    final arms = firstOf(Equipment.cable, 'triceps');
    final reply = '''
SAY: Here is a chest, shoulders and arms day.
DO: today
DAY: Chest Shoulders Arms
$chest | 4 | 8-12 | 90
$shoulders | 3 | 10-12 | 75
$arms | 3 | 12-15 | 60
DO: setting rest 120
DO: setting reminders mon,wed,fri
DO: setting reminder_time 18:00
''';
    final r = parseToolReply(reply, s);
    expect(r.errors, isEmpty);
    expect(r.say, 'Here is a chest, shoulders and arms day.');
    expect(r.actions.length, 4);
    final did = await s.runActions('chest shoulders arms', r.actions);
    expect(did.first, contains('Chest Shoulders Arms'));
    expect(s.today!.name, 'Chest Shoulders Arms');
    expect(s.today!.items.length, 3);
    expect(s.settings.rest, 120);
    expect(s.settings.remindDays, [1, 3, 5]);
    expect(s.settings.remindAt, 18 * 60);

    final swapTo = firstOf(Equipment.dumbbell, 'chest');
    final r2 = parseToolReply('SAY: ok\nDO: swap $chest -> $swapTo today', s);
    expect(r2.errors, isEmpty);
    await s.runActions('swap', r2.actions);
    expect(s.today!.items.first.exerciseId, swapTo);

    await s.undoChange(1); // the first batch: also takes the later swap back
    expect(s.today!.toJson(), before);
    expect(s.settings.rest, isNull);
    expect(s.settings.remindDays, isEmpty);
    expect(s.aiChanges.every((c) => c.undone), isTrue);
    await s.repo.close();
  });

  test('the app refuses bad changes and nothing runs', () async {
    final s = await app(p: profile.copyWith(have: {Equipment.dumbbell, Equipment.bodyweight}, avoid: {Joint.knees}));
    final machine = firstOf(Equipment.machine, 'chest');
    final r = parseToolReply('''
SAY: sure
DO: add $machine 3 8-12 90 today
DO: setting api_key abc
DO: setting ai_auto on
DO: launch rockets
DO: change ${s.today!.items.first.exerciseId} sets=99 today
''', s);
    expect(r.errors.length, 5);
    expect(r.errors[0], contains('which your gym does not have'));
    expect(r.errors[1], contains('cannot change its own setup'));
    expect(r.errors[2], contains('cannot change its own setup'));
    expect(r.errors[3], contains('no tool called'));
    expect(r.errors[4], contains('sets must be 1-10'));
    await s.repo.close();
  });

  test('add, change, remove for today and always; profile tools', () async {
    final s = await app();
    final first = s.today!.items.first.exerciseId;
    final extra = lib.all.firstWhere((x) => x.equipment == Equipment.cable && !s.today!.items.any((i) => i.exerciseId == x.id)).id;
    var r = parseToolReply('DO: add $extra 3 10-12 60 always\nDO: change $first sets=5 reps=3-5 rest=180 today\nDO: profile minutes 45\nDO: profile unit kg', s);
    expect(r.errors, isEmpty);
    expect(r.say, '');
    await s.runActions('edit', r.actions);
    expect(s.today!.items.last.exerciseId, extra);
    expect(s.plan!.days[s.todayIndex].items.last.exerciseId, extra, reason: 'always = in the plan too');
    final f = s.today!.items.first;
    expect([f.sets, f.repLow, f.repHigh, f.restSec], [5, 3, 5, 180]);
    expect(s.profile!.minutes, 45);
    expect(s.profile!.unit, Unit.kg);
    r = parseToolReply('DO: remove $extra always', s);
    await s.runActions('remove', r.actions);
    expect(s.plan!.days[s.todayIndex].items.any((i) => i.exerciseId == extra), isFalse);
    await s.repo.close();
  });

  test('newer settings, notes, steps and fill have AI tools too', () async {
    final s = await app();
    final first = s.today!.items.first.exerciseId;
    var r = parseToolReply('DO: setting checkin on\nDO: setting effort_chips on\nDO: setting simple on\nDO: setting formula brzycki\nDO: setting drop_pct 15\nDO: setting effort_drives off\nDO: setting steps dumbbell 10\nDO: step $first 10\nDO: note $first seat 4, wide grip', s);
    expect(r.errors, isEmpty);
    await s.runActions('new', r.actions);
    final st = s.settings;
    expect([st.checkin, st.effortChips, st.simple, st.formula, st.dropPct, st.effortDrives], [true, true, true, 'brzycki', 15, false]);
    expect(st.steps['dumbbell_lb'], 10);
    expect(s.exStep[first], closeTo(fromUnit(10, Unit.lb), 0.001));
    expect(await s.repo.exNote(first), 'seat 4, wide grip');
    expect(parseToolReply('DO: setting formula wrong', s).errors, isNotEmpty);
    expect(parseToolReply('DO: fill $first 100 5', s).errors, isNotEmpty, reason: 'no workout is going');
    await s.startWorkout();
    r = parseToolReply('DO: fill $first 100 5', s);
    expect(r.errors, isEmpty);
    await s.runActions('fill', r.actions);
    final planned = s.session!.day.items.first.sets;
    expect((await s.repo.setsFor(s.session!.id)).length, planned);
    // quick command, no AI
    final q = quickCommand('turn off simple mode', s)!;
    await s.runActions('q', q.actions);
    expect(s.settings.simple, isFalse);
    await s.repo.close();
  });

  test('on-phone grammar names real tools and only this gym\'s exercises', () {
    final p = profile.copyWith(have: {Equipment.dumbbell});
    final g = toolGrammar(lib, p, 4);
    expect(g, contains('root ::= "SAY: "'));
    expect(g, contains('"pick day " ("1" | "2" | "3" | "4")'));
    expect(g, isNot(contains('"${firstOf(Equipment.machine, 'chest')}"')));
    expect(g, contains('"${firstOf(Equipment.dumbbell, 'chest')}"'));
    expect(g, isNot(contains('api_key')));
  });
  group('quick commands (no AI)', () {
    test('chest, shoulders and arms workout from this gym only', () async {
      final s = await app(p: profile.copyWith(have: {Equipment.dumbbell, Equipment.machine, Equipment.cable, Equipment.bodyweight}));
      final r = quickCommand("I want a shoulders, arms and chest focused workout with drop sets", s)!;
      expect(r.actions.length, 1);
      await s.runActions('q', r.actions);
      final d = s.today!;
      expect(d.name, 'Shoulders, Arms & Chest');
      expect(d.items.length, inInclusiveRange(4, 6));
      final muscles = {for (final i in d.items) s.lib.byId(i.exerciseId)!.primary.first};
      expect(muscles.intersection({'shoulders', 'chest', 'biceps', 'triceps'}).length, greaterThanOrEqualTo(3));
      expect(d.items.every((i) => s.lib.byId(i.exerciseId)!.equipment != Equipment.barbell), isTrue);
      expect(r.say, contains('drop set'));
      expect(d.items.skip(1).every((i) => i.style == 'drop'), isTrue);
      await s.repo.close();
    });

    test('reminders, rest, units, minutes, taken, skip', () async {
      final s = await app();
      var r = quickCommand('Remind me to train Monday, Wednesday and Friday at 6 pm', s)!;
      await s.runActions('q', r.actions);
      expect(s.settings.remindDays, [1, 3, 5]);
      expect(s.settings.remindAt, 18 * 60);
      r = quickCommand('give me 2 minutes rest between sets', s)!;
      await s.runActions('q', r.actions);
      expect(s.settings.rest, 120);
      r = quickCommand('switch to kg', s)!;
      await s.runActions('q', r.actions);
      expect(s.profile!.unit, Unit.kg);
      final n = s.today!.items.length;
      r = quickCommand('I only have 30 minutes today', s)!;
      await s.runActions('q', r.actions);
      expect(s.today!.items.length, lessThanOrEqualTo(5));
      expect(s.today!.items.length, lessThanOrEqualTo(n));
      final first = s.lib.byId(s.today!.items.first.exerciseId)!;
      r = quickCommand('the ${first.name.toLowerCase()} is taken', s)!;
      expect(r.actions, isNotEmpty, reason: r.say);
      await s.runActions('q', r.actions);
      expect(s.today!.items.first.exerciseId, isNot(first.id));
      expect(quickCommand('how long should I rest between heavy sets?', s), isNull);
      expect(quickCommand('my lower back is sore, what should I do', s), isNull);
      r = quickCommand('skip today', s)!;
      expect(r.actions.single.says, startsWith('Skip'));
      await s.repo.close();
    });

    test('tidy keeps one action per thing and drops an unasked start', () async {
      final s = await app();
      final r = parseToolReply(['DO: setting rest 150', 'DO: setting rest 120', 'DO: start workout', 'DO: setting reminder_time 18:00', 'SAY: ok'].join(String.fromCharCode(10)), s);
      final t = tidyActions(r.actions, 'give me 2 minutes rest');
      expect(t.map((a) => a.says), ['Rest between sets: 120s', 'Reminder time 18:00']);
      await s.repo.close();
    });
  });
}
