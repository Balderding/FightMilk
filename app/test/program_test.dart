import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/plan_maker.dart';
import 'package:workout/domain/program.dart';
import 'package:workout/domain/programs.dart';
import 'package:workout/domain/progression.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('prog'));
  tearDown(() => progressRules = const ProgressRules());

  Future<AppState> app({Profile? p}) async {
    final r = await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi);
    final s = await AppState.forTest(r, PackStore(dir.path), lib);
    await s.saveProfile(p ?? full);
    await s.makeBuiltInPlan();
    return s;
  }

  SetLog set(String ex, double kg, int reps, {SetType type = SetType.work}) => SetLog(id: 'x', sessionId: 's', exerciseId: ex, kg: kg, reps: reps, ord: 0, type: type);

  Future<void> logAll(AppState s, List<(double, int)> sets, {int item = 0, SetType? lastType}) async {
    final it = s.session!.day.items[item];
    for (var i = 0; i < sets.length; i++) {
      await s.repo.logSet(s.session!.id, it.exerciseId, sets[i].$1, sets[i].$2, type: i == sets.length - 1 && lastType != null ? lastType : SetType.work);
    }
  }

  group('set text', () {
    test('short set texts read and write back', () {
      final l = parseSets('1x5@65 1x5@75 1x5+@85');
      expect(l.map((x) => (x.reps, x.pct, x.amrap)), [(5, 0.65, false), (5, 0.75, false), (5, 0.85, true)]);
      expect(setsText(l), '1x5@65 1x5@75 1x5+@85');
      expect(setsText(parseSets('5x5')), '5x5');
      expect(setsText(parseSets('2x5 1x5+')), '3x5+');
      expect(parseSets('3x8-12').first.hi, 12);
      expect(setsPlain(parseSets('1x5+@85')), contains('85%'));
      expect(() => parseSets('five'), throwsFormatException);
      expect(() => parseSets('3x5@300'), throwsFormatException);
    });

    test('plan items from per-set targets, and back to JSON', () {
      final a = PlanItem.of('bench_press', parseSets('3x5+'));
      expect([a.sets, a.repLow, a.repHigh, a.style, a.perSet], [3, 5, 5, 'amrap', null]);
      final b = PlanItem.of('bench_press', parseSets('1x5@65 1x3+@90'), tier: 'T2', tmOf: 'overhead_press', bump: 'tm');
      expect(b.perSet!.length, 2);
      final c = PlanItem.fromJson(b.toJson());
      expect([c.tier, c.tmOf, c.bump, c.perSet!.last.amrap, c.perSet!.last.pct], ['T2', 'overhead_press', 'tm', true, 0.9]);
      expect(liftKey(c), 'bench_press#T2');
      expect(tmKey(c), 'overhead_press');
    });
  });

  group('library', () {
    test('every program builds in full at a gym with everything', () {
      for (final t in programTemplates) {
        final pl = buildProgram(t, full, lib);
        var want = 0;
        for (final w in t.weeks) {
          for (final d in w) {
            want += d.items.where((i) => i.sets.isNotEmpty).length;
          }
        }
        final got = pl.days.fold<int>(0, (a, d) => a + d.items.length);
        expect(got, want, reason: '${t.id}: every exercise exists in the library');
        expect(pl.days.length, t.weeks.fold<int>(0, (a, w) => a + w.length), reason: t.id);
        expect(pl.weeksPerCycle, t.weeks.length);
        expect(pl.program!.id, t.id);
        for (final r in t.rules.values) {
          for (final id in r.ladder) {
            expect(lib.byId(id), isNotNull, reason: '${t.id} ladder $id');
          }
        }
        expect(Plan.fromJson(pl.toJson()).toJson(), pl.toJson(), reason: '${t.id} survives saving');
      }
      expect(programTemplates.map((t) => t.id).toSet().length, programTemplates.length, reason: 'ids are unique');
      for (final g in programTemplates.map((t) => t.group)) {
        expect(programGroups, contains(g));
      }
    });

    test('a dumbbell-only gym gets swaps and the picker suggests home programs first', () {
      final home = full.copyWith(have: {Equipment.dumbbell, Equipment.bodyweight});
      final t = templateById('stronglifts')!;
      final pl = buildProgram(t, home, lib);
      for (final d in pl.days) {
        for (final it in d.items) {
          final e = lib.byId(it.exerciseId)!;
          expect({Equipment.dumbbell, Equipment.bodyweight}, contains(e.equipment), reason: e.id);
        }
      }
      expect(programSwaps(t, home, lib), isNotEmpty);
      final best = suggestPrograms(level: 0, days: 3, goal: 'size', have: {Equipment.dumbbell, Equipment.bodyweight}).first;
      expect(best.needs.every({Equipment.dumbbell, Equipment.bodyweight}.contains), isTrue, reason: best.id);
      final lifter = suggestPrograms(level: 1, days: 4, goal: 'strength', have: Equipment.values.toSet()).take(5).map((t) => t.id);
      expect(lifter.any((id) => id.startsWith('531') || id.startsWith('nsuns')), isTrue);
    });
  });

  group('rules', () {
    final bench = lib.byId('bench_press')!;
    final dead = lib.byId('deadlift')!;
    test('linear: a step on a hit, 90% after three misses', () {
      const r = LiftRule(kind: 'linear', inc: 1, misses: 3);
      var st = const LiftState(exerciseId: 'bench_press', workKg: 100);
      final plan = parseSets('5x5');
      st = programNext(st, r, bench, [for (var i = 0; i < 5; i++) set('bench_press', 100, 5)], plan, Unit.kg).state;
      expect(st.workKg, 102.5);
      for (var k = 0; k < 2; k++) {
        st = programNext(st, r, bench, [set('bench_press', 102.5, 5), set('bench_press', 102.5, 3)], plan, Unit.kg).state;
        expect(st.workKg, 102.5);
      }
      st = programNext(st, r, bench, [set('bench_press', 102.5, 4)], plan, Unit.kg).state;
      expect(st.workKg, closeTo(92.5, 0.01));
      expect(st.misses, 0);
    });

    test('linear with a + goal doubles the jump (Greyskull)', () {
      const r = LiftRule(kind: 'linear', inc: 1, misses: 1, amrapGoal: 10);
      final st = programNext(const LiftState(exerciseId: 'deadlift', workKg: 100), r, dead, [set('deadlift', 100, 12, type: SetType.amrap)], parseSets('1x5+'), Unit.kg).state;
      expect(st.workKg, 105);
    });

    test('training max: + set hits, the max goes up; nSuns adds by reps; test sets a new max', () {
      const r = LiftRule(kind: 'tm', inc: 2, misses: 2);
      final plan = parseSets('1x5@75 1x3@85 1x1+@95');
      final st0 = const LiftState(exerciseId: 'deadlift', workKg: 150, tm: 200);
      final ok = programNext(st0, r, dead, [set('deadlift', 150, 5), set('deadlift', 170, 3), set('deadlift', 190, 3)], plan, Unit.kg, bump: 'tm');
      expect(ok.state.tm, 205);
      expect(ok.note, contains('up'));
      final short = programNext(st0, r, dead, [set('deadlift', 150, 5), set('deadlift', 170, 3), set('deadlift', 190, 0)], plan, Unit.kg, bump: 'tm');
      expect(short.state.tm, 200);
      expect(short.state.misses, 1);
      const n = LiftRule(kind: 'tm', inc: 1);
      final ns = programNext(st0, n, dead, [set('deadlift', 190, 4)], parseSets('1x1+@95'), Unit.kg, bump: 'amrap').state;
      expect(ns.tm, 205, reason: '4-5 reps on the 1+ set: two steps');
      final none = programNext(st0, n, dead, [set('deadlift', 190, 1)], parseSets('1x1+@95'), Unit.kg, bump: 'amrap').state;
      expect(none.tm, 200);
      // the whole nSuns T1 day: 2 reps on the 1+ at 95%, 11 on the 65%+ back-off set -> one step (P1-2)
      final day = parseSets('1x5@75 1x3@85 1x1+@95 1x3@90 1x3@85 1x3@80 1x5@75 1x5@70 1x5+@65');
      final reps = [5, 3, 2, 3, 3, 3, 5, 5, 11];
      final full = programNext(const LiftState(exerciseId: 'deadlift', workKg: 75, tm: 100), n, dead, [for (var i = 0; i < 9; i++) set('deadlift', 100 * day[i].pct!, reps[i])], day, Unit.kg, bump: 'amrap').state;
      expect(full.tm, 102.5, reason: 'the 1+ set decides, not the last + set');
      final test = programNext(st0, n, dead, [set('deadlift', 240, 1)], parseSets('1x1+@100'), Unit.kg, bump: 'test').state;
      expect(test.tm, 215, reason: '90% of 240, to a 2.5 step');
      final first = programNext(const LiftState(exerciseId: 'deadlift', workKg: 100), n, dead, [set('deadlift', 100, 5)], parseSets('1x5@75'), Unit.kg);
      expect(first.state.tm, isNotNull, reason: 'no max yet: set from the day');
    });

    test('every training-max lift in every program is raised by some day of it (P1-3)', () {
      for (final t in programTemplates) {
        final p = buildProgram(t, full, lib);
        final items = p.days.expand((d) => d.items).toList();
        for (final e in p.program!.rules.entries.where((e) => e.value.kind == 'tm')) {
          expect(items.any((i) => tmKey(i) == e.key && i.bump.isNotEmpty), isTrue, reason: '${t.id}: ${e.key} has a training max nothing raises');
        }
      }
    });

    test('PHAT power day: every set at the top of the range moves the weight and the max (P1-3)', () {
      const r = LiftRule(kind: 'tm', inc: 1);
      final plan = parseSets('3x3-5');
      const st = LiftState(exerciseId: 'bench_press', workKg: 80, tm: 90);
      final bench = lib.byId('bench_press')!;
      final up = programNext(st, r, bench, [for (var i = 0; i < 3; i++) set('bench_press', 80, 5)], plan, Unit.kg, bump: 'tm').state;
      expect([up.workKg, up.tm], [82.5, 92.5]);
      final same = programNext(st, r, bench, [for (var i = 0; i < 3; i++) set('bench_press', 80, 4)], plan, Unit.kg, bump: 'tm').state;
      expect([same.workKg, same.tm], [80, 90]);
    });

    test('stages: a miss moves to the next stage, the last one resets', () {
      const r = LiftRule(kind: 'stage', inc: 1, stages: ['5x3+', '6x2+', '10x1+'], reset: 0.85);
      var st = const LiftState(exerciseId: 'bench_press', workKg: 100);
      st = programNext(st, r, bench, [for (var i = 0; i < 5; i++) set('bench_press', 100, 3)], parseSets('5x3+'), Unit.kg).state;
      expect([st.workKg, st.stage], [102.5, 0]);
      st = programNext(st, r, bench, [set('bench_press', 102.5, 3), set('bench_press', 102.5, 2)], parseSets('5x3+'), Unit.kg).state;
      expect([st.workKg, st.stage], [102.5, 1]);
      st = programNext(st, r, bench, [set('bench_press', 102.5, 1)], parseSets('6x2+'), Unit.kg).state;
      expect(st.stage, 2);
      st = programNext(st, r, bench, [set('bench_press', 102.5, 0)], parseSets('10x1+'), Unit.kg).state;
      expect(st.stage, 0);
      expect(st.workKg, closeTo(87.5, 0.01));
      expect(stageSets(r, 1)!.length, 6);
    });

    test('my own rule: the first line that fits wins; bad lines are named', () {
      const sc = 'if amrap >= 10: add 2\nif top: add 1\nif miss 2: times 0.9\nif miss: same\nelse: reps +1';
      expect(checkScript(sc), isNull);
      expect(checkScript('if top add 1'), contains('line 1'));
      expect(checkScript('if top: times 9'), contains('times'));
      final plan = parseSets('3x8-12');
      var st = const LiftState(exerciseId: 'bench_press', workKg: 50);
      expect(runScript(sc, st, bench, [set('bench_press', 50, 12), set('bench_press', 50, 12), set('bench_press', 50, 12)], plan, Unit.kg).state.workKg, 52.5);
      st = runScript(sc, st, bench, [set('bench_press', 50, 7)], plan, Unit.kg).state;
      expect([st.workKg, st.misses], [50, 1]);
      st = runScript(sc, st, bench, [set('bench_press', 50, 6)], plan, Unit.kg).state;
      expect(st.workKg, 45);
      expect(runScript('if hit: add 5kg\nelse: same', const LiftState(exerciseId: 'b', workKg: 50), bench, [set('b', 50, 8), set('b', 50, 9), set('b', 50, 8)], plan, Unit.kg).state.workKg, 55);
    });
  });

  group('running a program', () {
    test('5/3/1: % sets from the training max; week 3 raises it', () async {
      final s = await app();
      final pl = buildProgram(templateById('531_base')!, full, lib);
      expect(programMaxes(pl).keys.toSet(), {'overhead_press', 'deadlift', 'bench_press', 'back_squat'});
      await s.startProgram(pl, {'overhead_press': 100, 'deadlift': 200, 'bench_press': 120, 'back_squat': null});
      expect(s.plan!.program!.id, '531_base');
      expect(s.today!.name, 'W1 · Press');
      final t = await s.targetFor(s.today!.items.first);
      expect(t.perSet, [65, 75, 85]);
      expect(t.tm, 100);
      expect(s.programWeek, (1, 1));
      // the 3rd week's press day
      await s.pickDay(8);
      expect(s.today!.name, 'W3 · Press');
      expect((await s.targetFor(s.today!.items.first)).perSet, [75, 85, 95]);
      await s.startWorkout();
      await logAll(s, [(75, 5), (85, 3), (95, 4)], lastType: SetType.amrap);
      await s.finishWorkout();
      expect((await s.repo.lift('overhead_press'))!.tm, 102.5);
      expect(s.programNotes.join(), contains('Overhead press'));
      // a lift with no max yet: you pick, the first workout sets it
      await s.pickDay(3);
      expect(s.today!.name, 'W1 · Squat');
      final sq = await s.targetFor(s.today!.items.first);
      expect(sq.perSet!.every((x) => x == null), isTrue);
      expect(sq.why, contains('No training max'));
      await s.repo.close();
    });

    test('GZCLP: a T1 miss puts the lift on its next stage; T2 has its own weights', () async {
      final s = await app();
      await s.startProgram(buildProgram(templateById('gzclp')!, full, lib), const {});
      final d = s.today!;
      expect(d.items.first.exerciseId, 'back_squat');
      expect([d.items.first.sets, d.items.first.repLow, d.items.first.style], [5, 3, 'amrap']);
      expect(liftKey(d.items[1]), 'bench_press#T2');
      await s.startWorkout();
      await logAll(s, [(100, 3), (100, 3), (100, 3), (100, 2), (100, 2)]);
      await logAll(s, [(60, 10), (60, 10), (60, 10)], item: 1);
      await s.finishWorkout();
      expect((await s.repo.lift('back_squat'))!.stage, 1);
      expect((await s.repo.lift('bench_press#T2'))!.workKg, 62.5);
      expect(await s.repo.lift('bench_press'), isNull, reason: 'the T1 bench is untouched');
      await s.pickDay(0);
      expect([s.today!.items.first.sets, s.today!.items.first.repLow], [6, 2]);
      await s.repo.close();
    });

    test('a ladder moves the plan on to the harder exercise', () async {
      final s = await app();
      await s.startProgram(buildProgram(templateById('bwf_rr')!, full, lib), const {});
      final first = s.today!.items.first;
      expect(first.exerciseId, 'band_assisted_pull_up');
      await s.startWorkout();
      await logAll(s, [(0, 8), (0, 8), (0, 8)]);
      await s.finishWorkout();
      expect(s.plan!.days.first.items.first.exerciseId, 'chin_up');
      expect(s.plan!.program!.rules.containsKey('chin_up'), isTrue);
      expect(s.plan!.program!.rules.containsKey('band_assisted_pull_up'), isFalse);
      await s.repo.close();
    });

    test('editing a past workout keeps the training max', () async {
      final s = await app();
      await s.repo.saveLift(const LiftState(exerciseId: 'bench_press', workKg: 80, tm: 110, stage: 1));
      await s.startWorkout();
      await s.repo.logSet(s.session!.id, 'bench_press', 80, 8);
      await s.finishWorkout();
      await s.repo.rebuildLifts(['bench_press'], lib, Unit.kg);
      final st = (await s.repo.lift('bench_press'))!;
      expect([st.tm, st.stage], [110, 1]);
      await s.repo.close();
    });

    test('lift rules on any plan: my own rule moves the weight', () async {
      final s = await app();
      final it = s.today!.items.first;
      await s.setRule(it.exerciseId, const LiftRule(kind: 'script', script: 'if hit: add 2\nelse: same'));
      expect(ruleFor(s.plan!.program, it)!.kind, 'script');
      await s.startWorkout();
      for (var i = 0; i < it.sets; i++) {
        await s.repo.logSet(s.session!.id, it.exerciseId, 100, it.repLow);
      }
      await s.finishWorkout();
      final e = lib.byId(it.exerciseId)!;
      expect((await s.repo.lift(it.exerciseId))!.workKg, closeTo(100 + 2 * stepKg(e.step, Unit.kg), 0.01));
      await s.repo.close();
    });
  });

  group('plans', () {
    test('more days, lengths, splits, goals and experience', () {
      expect(makePlan(full.copyWith(days: 1), lib).days.length, 1);
      expect(makePlan(full.copyWith(days: 7), lib).days.length, 7);
      expect(makePlan(full.copyWith(split: 'phul'), lib).days.map((d) => d.name), ['Upper power', 'Lower power', 'Upper hypertrophy', 'Lower hypertrophy']);
      for (final sp in splitLabel.keys) {
        final pl = makePlan(full.copyWith(split: sp), lib);
        expect(pl.days.every((d) => d.items.length >= 3), isTrue, reason: sp);
        expect(splitHelp[sp], isNotNull);
      }
      expect(makePlan(full.copyWith(minutes: 20), lib).days.first.items.length, lessThanOrEqualTo(4));
      expect(makePlan(full.copyWith(minutes: 120), lib).days.first.items.length, greaterThanOrEqualTo(8));
      for (final g in Goal.values) {
        final it = makePlan(full.copyWith(goal: g), lib).days.first.items.first;
        expect(it.repLow, greaterThan(0), reason: g.name);
        expect(goalHelp[g], isNotNull);
      }
      expect(makePlan(full.copyWith(goal: Goal.fitness), lib).days.first.items.first.repLow, 10);
      expect(makePlan(full.copyWith(experience: 'new'), lib).days.first.items.first.sets, 3);
      expect(Profile.fromJson(full.copyWith(experience: 'years', weekdays: [1, 3, 5], priority: {'chest'}, sportDays: {6}, bodyKg: 80, age: 40, sex: 'f', special: 'back').toJson()).toJson(),
          full.copyWith(experience: 'years', weekdays: [1, 3, 5], priority: {'chest'}, sportDays: {6}, bodyKg: 80, age: 40, sex: 'f', special: 'back').toJson());
    });

    test('priority muscles get more sets; a focus block more again; others held', () {
      int chestSets(Plan p) => p.days.expand((d) => d.items).where((i) => lib.byId(i.exerciseId)!.primary.first == 'chest').fold(0, (a, i) => a + i.sets);
      int legSets(Plan p) => p.days.expand((d) => d.items).where((i) => lib.byId(i.exerciseId)!.primary.first == 'hamstrings').fold(0, (a, i) => a + i.sets);
      final base = makePlan(full, lib);
      final pri = makePlan(full.copyWith(priority: {'chest'}), lib);
      final focus = makePlan(full.copyWith(special: 'chest'), lib);
      expect(chestSets(pri), greaterThan(chestSets(base)));
      expect(chestSets(focus), greaterThan(chestSets(pri)));
      expect(legSets(focus), lessThanOrEqualTo(legSets(base)));
      expect(focus.name, contains('focus'));
      final low = makePlan(full.copyWith(low: {'chest'}), lib);
      expect(chestSets(low), lessThan(chestSets(base)));
    });

    test('balance: big before small, lopsided warnings, accessory rotation', () {
      final pl = makePlan(full.copyWith(days: 4), lib);
      for (final d in pl.days) {
        final rest = d.items.skip(1).map((i) => lib.byId(i.exerciseId)!).toList();
        final firstIso = rest.indexWhere((e) => !e.compound);
        if (firstIso >= 0) expect(rest.skip(firstIso).any((e) => e.compound), isFalse, reason: '${d.name}: compounds before isolation');
      }
      final push = Plan(name: 'p', days: const [
        PlanDay(name: 'a', items: [
          PlanItem(exerciseId: 'bench_press', sets: 5, repLow: 5, repHigh: 5, restSec: 90),
          PlanItem(exerciseId: 'overhead_press', sets: 5, repLow: 5, repHigh: 5, restSec: 90),
          PlanItem(exerciseId: 'back_squat', sets: 3, repLow: 5, repHigh: 5, restSec: 90),
        ])
      ]);
      final w = planWarnings(push, lib);
      expect(w.any((x) => x.contains('pulling')), isTrue);
      expect(w.any((x) => x.contains('hamstring')), isTrue);
      final rot = rotateAccessories(pl, full, lib);
      var changed = 0;
      for (var d = 0; d < pl.days.length; d++) {
        expect(rot.days[d].items.first.exerciseId, pl.days[d].items.first.exerciseId, reason: 'main lift stays');
        for (var i = 0; i < pl.days[d].items.length; i++) {
          if (rot.days[d].items[i].exerciseId != pl.days[d].items[i].exerciseId) {
            changed++;
            expect(lib.byId(rot.days[d].items[i].exerciseId)!.swap, lib.byId(pl.days[d].items[i].exerciseId)!.swap);
          }
        }
      }
      expect(changed, greaterThan(0));
    });

    test('training weekdays, rest days and sport days', () async {
      final today = DateTime.now().weekday;
      final other = today % 7 + 1;
      final s = await app(p: full.copyWith(days: 1, weekdays: [other]));
      expect(s.plan!.days.length, 1);
      expect(s.restDay, isTrue);
      expect(s.nextTrainingDay, weekdayShort[other - 1]);
      await s.pickDay(s.todayIndex);
      expect(s.restDay, isFalse, reason: 'train anyway');
      await s.saveProfile(s.profile!.copyWith(weekdays: [today]));
      s.pickedDay = null;
      expect(s.restDay, isFalse);
      // a sport day today: leg exercises one set fewer
      await s.saveProfile(s.profile!.copyWith(weekdays: const [], sportDays: {today}));
      await s.makeBuiltInPlan();
      final legs = {'quads', 'hamstrings', 'glutes', 'calves'};
      final planned = s.plan!.days[s.todayIndex].items;
      final now = s.today!.items;
      for (var i = 0; i < planned.length; i++) {
        final e = lib.byId(planned[i].exerciseId)!;
        if (legs.contains(e.primary.first) && planned[i].sets > 2) expect(now[i].sets, planned[i].sets - 1, reason: e.id);
      }
      await s.repo.close();
    });

    test('a body weight gives a first guess; copies, folders, weak points, duplicate days', () async {
      final s = await app(p: full.copyWith(bodyKg: 80, experience: 'new'));
      final g = s.startGuess(lib.byId('back_squat')!);
      expect(g, 40);
      expect(s.startGuess(lib.byId('db_curl')!), isNull);
      final n = s.plan!.days.length;
      await s.savePlanEdits(s.plan!.duplicateDay(0));
      expect(s.plan!.days.length, n + 1);
      expect(s.plan!.days[1].name, contains('copy'));
      await s.duplicatePlan();
      var saved = await s.savedPlans();
      expect(saved.length, 1);
      await s.setPlanFolder(saved.first.id, 'Home');
      saved = await s.savedPlans();
      expect(saved.first.folder, 'Home');
      await s.setPlanFolder(s.plan!.id, 'Gym');
      expect(s.plan!.folder, 'Gym');
      // weak point: an exercise after the lift
      await s.usePlan(buildProgram(templateById('stronglifts')!, full, lib));
      final added = await s.addWeakPoint('bench_press', 'Lockout');
      expect(added, 'Close-grip bench press');
      final day = s.plan!.days.firstWhere((d) => d.items.any((i) => i.exerciseId == 'bench_press'));
      final at = day.items.indexWhere((i) => i.exerciseId == 'bench_press');
      expect(day.items[at + 1].exerciseId, 'close_grip_bench');
      await s.setRotation(6);
      expect(s.plan!.rotateWeeks, 6);
      await s.repo.close();
    });
  });

  test('every new part has an AI tool', () async {
    final s = await app(p: full.copyWith(unit: Unit.lb));
    var r = parseToolReply('DO: program start gzclp\nDO: profile goal fat_loss\nDO: profile experience new\nDO: profile weekdays mon,wed,fri\nDO: profile priority add chest\nDO: profile focus back\nDO: profile sport_days sat\nDO: profile body_weight 180\nDO: profile age 41\nDO: profile sex m', s);
    expect(r.errors, isEmpty);
    await s.runActions('ai', r.actions);
    expect(s.plan!.program!.id, 'gzclp');
    final p = s.profile!;
    expect([p.goal, p.experience, p.weekdays, p.priority, p.special, p.sportDays, p.age, p.sex], [Goal.fatLoss, 'new', [1, 3, 5], {'chest'}, 'back', {6}, 41, 'm']);
    expect(p.bodyKg, closeTo(lbToKg(180), 0.01));
    r = parseToolReply(
        'DO: program tm back_squat 225\nDO: program rule bench_press linear inc=2 misses=3 reset=85\nDO: program rule deadlift script if top: add 1; else: same\nDO: program stage back_squat 2\nDO: plans copy\nDO: plans folder Home\nDO: plans variety 4\nDO: day copy 1\nDO: weak bench_press lockout',
        s);
    expect(r.errors, isEmpty);
    await s.runActions('ai', r.actions);
    expect((await s.repo.lift('back_squat'))!.tm, closeTo(lbToKg(225), 0.01));
    expect((await s.repo.lift('back_squat'))!.stage, 1);
    final rules = s.plan!.program!.rules;
    expect([rules['bench_press']!.kind, rules['bench_press']!.inc, rules['bench_press']!.misses, rules['bench_press']!.reset], ['linear', 2, 3, 0.85]);
    expect(rules['deadlift']!.script, 'if top: add 1\nelse: same');
    expect(s.plan!.folder, 'Home');
    expect(s.plan!.rotateWeeks, 4);
    expect((await s.savedPlans()).length, greaterThanOrEqualTo(2));
    expect(s.plan!.days.any((d) => d.items.any((i) => i.exerciseId == 'close_grip_bench')), isTrue);
    r = parseToolReply('DO: program start nope\nDO: program rule bench_press script if top add\nDO: plans variety 5\nDO: profile focus elbows\nDO: weak bench_press nowhere', s);
    expect(r.errors.length, 5);
    r = parseToolReply('DO: plans use gzclp (copy)\nDO: program rule bench_press none', s);
    expect(r.errors, isEmpty);
    await s.runActions('ai', r.actions);
    expect(s.plan!.name, contains('copy'));
    final g = toolGrammar(lib, s.profile!, 4);
    expect(g, contains('"program start "'));
    expect(g, contains('"fat_loss"'));
    expect(toolHelp(lib), contains('DO: program rule'));
    await s.repo.close();
  });
}
