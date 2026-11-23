import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout/ai/grammar.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/data/import_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/export.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/import.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';
import 'package:workout/ui/import_screen.dart';
import 'package:workout/ui/theme.dart';

/// Batch 21 import (F330-F335): reading other apps' files, safely.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  group('CSV', () {
    test('quotes, doubled quotes, CRLF, a BOM, semicolons and tabs', () {
      expect(readCsv('﻿a,b\r\n"x, y","say ""hi"""\r\n'), [
        ['a', 'b'],
        ['x, y', 'say "hi"'],
      ]);
      expect(readCsv('a;b\n1;2\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
      expect(readCsv('a\tb\n1\t2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('hidden marks out, the export formula guard taken off, cells cut', () {
      expect(cleanCell("'=1+1"), '=1+1');
      expect(cleanCell("'Tom's"), "'Tom's", reason: 'only before formula characters');
      expect(cleanCell('Bench‮ press​'), 'Bench press');
      expect(cleanCell('x' * 1000).length, 300);
    });
  });

  group('formats', () {
    test('Strong: our own export reads back (F335), with workouts, warm-ups and seconds', () async {
      final dir = Directory.systemTemp.createTempSync('imp');
      final s = await AppState.forTest(await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi), PackStore(dir.path), lib);
      await s.saveProfile(full);
      await s.makeBuiltInPlan();
      final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
      await s.repo.logSet(ses.id, 'back_squat', 60, 5, type: SetType.warmup);
      await s.repo.logSet(ses.id, 'back_squat', 100, 5);
      await s.repo.logSet(ses.id, 'plank', 0, 60);
      await s.repo.finishSession(ses.id, s.lib, s.unit);
      final csv = utf8.decode((await buildExport(ExportKind.strong, s.repo, lib, const ExportOptions(unit: Unit.kg))).bytes);
      final r = readImport(csv, appUnit: Unit.kg);
      expect(r.ok, isTrue, reason: r.problem);
      expect(r.format, ImportFormat.strong);
      expect(r.workouts.single.sets.map((x) => (x.exercise, x.kg, x.reps, x.type)).toList(), [('Back squat', 60.0, 5, SetType.warmup), ('Back squat', 100.0, 5, SetType.work), ('Plank', 0.0, 0, SetType.work)]);
      expect(r.workouts.single.sets.last.secs, 60);
      expect(r.unitGuessed, isTrue, reason: 'Strong does not say its unit: the person is told');
      expect(r.unitWhy, contains('does not say'));
      final all = utf8.decode((await buildExport(ExportKind.everything, s.repo, lib, const ExportOptions(unit: Unit.kg))).bytes);
      final r2 = readImport(all, appUnit: Unit.lb);
      expect(r2.format, ImportFormat.fightmilk);
      expect(r2.unitGuessed, isFalse);
      expect(r2.workouts.single.sets[1].kg, 100);
    });

    test('Hevy in lb, FitNotes, Liftosaur, Fitbod, a generic file and a body log', () {
      final hevy = readImport('"title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_km","duration_seconds","rpe"\n'
          '"Push","5 Nov 2026, 18:30","5 Nov 2026, 19:20","","Bench Press (Barbell)","","","0","warmup","95","10","","",""\n'
          '"Push","5 Nov 2026, 18:30","5 Nov 2026, 19:20","","Bench Press (Barbell)","","","1","normal","225","5","","","8"\n', appUnit: Unit.kg);
      expect(hevy.format, ImportFormat.hevy);
      expect(hevy.unit, Unit.lb);
      expect(hevy.workouts.single.sets.last.kg, closeTo(lbToKg(225), 0.01));
      expect(hevy.workouts.single.sets.first.type, SetType.warmup);
      expect(hevy.workouts.single.start, DateTime(2026, 11, 5, 18, 30));
      expect(hevy.workouts.single.end, DateTime(2026, 11, 5, 19, 20));
      final fit = readImport('Date,Exercise,Category,Weight (kgs),Reps,Distance,Distance Unit,Time,Comment\n2026-11-05,Flat Barbell Bench Press,Chest,100.0,5,,,,\n2026-11-05,Plank,Abs,,,,,0:01:00,\n', appUnit: Unit.lb);
      expect(fit.format, ImportFormat.fitnotes);
      expect(fit.unit, Unit.kg);
      expect(fit.sets, 2);
      final lo = readImport('Workout DateTime,Program,Day Name,Exercise,Equipment,Is Warmup Set?,Required Reps,Completed Reps,RPE,Completed Weight Value,Completed Weight Unit,Completed Time\n2026-11-05T18:30:00Z,P,Day 1,Squat,Barbell,0,5,5,,225,lb,\n2026-11-05T18:30:00Z,P,Day 1,Squat,Barbell,1,5,5,,45,lb,\n', appUnit: Unit.kg);
      expect(lo.format, ImportFormat.liftosaur);
      expect(lo.workouts.single.sets.first.kg, closeTo(lbToKg(225), 0.01));
      expect(lo.workouts.single.sets.last.type, SetType.warmup);
      final fb = readImport('Date,Exercise,Reps,Weight(kg),Duration(s),Distance(m),Incline,Resistance,isWarmup,Note,multiplier\n2026-11-05 18:30:00 +0000,Deadlift,5,140,0,0,0,0,false,,1\n', appUnit: Unit.lb);
      expect(fb.format, ImportFormat.fitbod);
      expect(fb.workouts.single.sets.single.kg, 140);
      final gen = readImport('when,lift,load (lbs),reps\n2026-11-05,squat,225,5\n', appUnit: Unit.kg);
      expect(gen.format, ImportFormat.generic);
      expect(gen.unit, Unit.lb);
      final body = readImport('Date,Weight (kg),Body fat\n2026-11-01,82.5,18\n2026-11-02,82.1,\n2026-11-03,5000,\n', appUnit: Unit.kg);
      expect(body.format, ImportFormat.body);
      expect(body.body.map((b) => b.$2), [82.5, 82.1]);
      expect(body.body.first.$3, 18);
      expect(body.skipped.single, contains('out of range'));
    });

    test('dates: every common form; 05/06 asks; 31 Feb is no day', () {
      expect(readDate('2026-11-05 18:30:00'), DateTime(2026, 11, 5, 18, 30));
      expect(readDate('2026/11/05'), DateTime(2026, 11, 5, 12));
      expect(readDate('5 Nov 2026, 18:30'), DateTime(2026, 11, 5, 18, 30));
      expect(readDate('Nov 5, 2026 6:30 PM'), DateTime(2026, 11, 5, 18, 30));
      expect(readDate('25/11/2026'), DateTime(2026, 11, 25, 12));
      // only the hour (review 7, P3-14)
      expect(readDate('2026-11-05T18'), DateTime(2026, 11, 5, 18));
      expect(readDate('2026-11-05 07'), DateTime(2026, 11, 5, 7));
      expect(readDate('2026-11-05 6pm'), DateTime(2026, 11, 5, 18));
      expect(readDate('Nov 5, 2026 6 AM'), DateTime(2026, 11, 5, 6));
      expect(readDate('2026-11-05T18Z'), DateTime.utc(2026, 11, 5, 18).toLocal());
      expect(readDate('2026-11-05T25'), isNull);
      expect(readDate('2026-11-05 13pm'), isNull);
      expect(readDate('11/25/2026'), DateTime(2026, 11, 25, 12));
      expect(readDate('05/06/2026', dayFirst: true), DateTime(2026, 6, 5, 12));
      expect(readDate('05/06/2026', dayFirst: false), DateTime(2026, 5, 6, 12));
      expect(readDate('31/02/2026'), isNull);
      final r = readImport('Date,Exercise,Weight,Reps\n05/06/2026,Squat,100,5\n', appUnit: Unit.kg);
      expect(r.dateAmbiguous, isTrue, reason: 'the person picks the order');
      expect(readImport('Date,Exercise,Weight,Reps\n25/06/2026,Squat,100,5\n', appUnit: Unit.kg).dateAmbiguous, isFalse);
    });
  });

  test('F332 other apps\' names find our lifts; odd ones are left to the person', () {
    const want = {
      'Bench Press (Barbell)': 'bench_press',
      'Squat (Barbell)': 'back_squat',
      'Deadlift (Barbell)': 'deadlift',
      'Overhead Press (Barbell)': 'overhead_press',
      'Bent Over Row (Barbell)': 'barbell_row',
      'Lat Pulldown (Cable)': 'lat_pulldown',
      'Pull Up': 'pull_up',
      'Chin Up': 'chin_up',
      'Push Up': 'push_up',
      'Incline Bench Press (Dumbbell)': 'incline_db_press',
      'Romanian Deadlift (Barbell)': 'romanian_deadlift',
      'Leg Press': 'leg_press',
      'Hip Thrust (Barbell)': 'hip_thrust',
      'Front Squat': 'front_squat',
      'Dumbbell Bench Press': 'db_bench_press',
      'Seated Cable Row': 'seated_cable_row',
      'Flat Barbell Bench Press': 'bench_press',
    };
    final got = {for (final n in want.keys) n: matchExercise(n, lib)?.id};
    expect(got, want);
    expect(matchExercise('Underwater basket weaving', lib), isNull);
  });

  test('fuzz: random, cut short, wrong encoding, huge rows, formula and bidi names never throw', () {
    final rnd = Random(21);
    final good = 'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n'
        '2026-11-05 18:30:00,"=1+1",1h 5m,"Bench Press (Barbell)‮",1,100,5,0,0,"\'=HYPERLINK(""x"")",,8\n';
    for (var n = 0; n <= good.length; n++) {
      expect(() => readImport(good.substring(0, n), appUnit: Unit.kg), returnsNormally);
    }
    for (var i = 0; i < 300; i++) {
      final s = String.fromCharCodes([for (var k = 0; k < rnd.nextInt(600); k++) rnd.nextInt(0x2FF)]);
      expect(() => readImport(s, appUnit: Unit.kg), returnsNormally);
      expect(() => readImport('Date,Exercise,Weight,Reps\n$s', appUnit: Unit.kg), returnsNormally);
    }
    final r = readImport(good, appUnit: Unit.kg);
    expect(r.ok, isTrue);
    expect(r.workouts.single.name, '=1+1', reason: 'kept as text; the app never runs it and the export guards it again');
    expect(r.names.single, 'Bench Press (Barbell)', reason: 'no bidi mark');
    expect(readImport('x' * (importMaxBytes + 1), appUnit: Unit.kg).problem, contains('too big'));
    expect(readImport('a,b\n\u0000\u0001', appUnit: Unit.kg).problem, contains('not a text file'));
    final wide = 'Date,Exercise,Weight,Reps,${List.filled(300, 'x').join(',')}\n';
    expect(readImport(wide, appUnit: Unit.kg).ok, isFalse);
    final huge = StringBuffer('Date,Exercise,Weight,Reps,Note\n');
    for (var i = 0; i < 500; i++) {
      huge.write('2026-11-05,Squat,100,5,set $i\n'); // different rows: identical ones are dropped as repeated
    }
    final hr = readImport(huge.toString(), appUnit: Unit.kg);
    expect(hr.workouts.single.sets.length, 300, reason: 'at most 300 sets in one workout');
    expect(hr.skippedCount, 200);
  });

  const strongFile = 'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n'
      '2026-10-01 18:00:00,"Day A",1h 0m,"Squat (Barbell)",1,100,5,0,0,,,\n'
      '2026-10-01 18:00:00,"Day A",1h 0m,"Squat (Barbell)",2,100,5,0,0,,,\n'
      '2026-10-01 18:00:00,"Day A",1h 0m,"Zottman Wiggle",1,10,10,0,0,,,\n'
      '2026-10-03 18:00:00,"Day B",50m,"Bench Press (Barbell)",1,80,5,0,0,,,\n';

  Future<AppState> app({DatabaseFactory? f}) async {
    final dir = Directory.systemTemp.createTempSync('imp2');
    final s = await AppState.forTest(await Repo.open('${dir.path}/t.db', factory: f ?? databaseFactoryFfi), PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    return s;
  }

  test('F333 an import only adds, skips what is already here, and can be undone; F336 progression follows', () async {
    final s = await app();
    final mine = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
    await s.repo.logSet(mine.id, 'back_squat', 60, 5);
    await s.repo.finishSession(mine.id, s.lib, s.unit);
    final r = readImport(strongFile, appUnit: Unit.kg);
    final names = {for (final n in r.names) n: matchExercise(n, lib)?.id};
    expect(names['Zottman Wiggle'], isNull, reason: 'left to the person');
    final rec = await saveImport(s.repo, r, names, label: 'Strong');
    await s.historyChanged(rec.exercises);
    expect(rec.sessions.length, 2);
    expect((await s.repo.history()).length, 3, reason: 'my own workout stays');
    expect((await s.repo.lift('back_squat'))?.workKg, isNotNull, reason: 'the squat moved on from the imported history');
    // the same file again: both workouts are already here
    expect(await duplicates(s.repo, r), {0, 1});
    await undoImport(s.repo, rec.id);
    expect((await s.repo.history()).length, 1);
    expect(await importRecords(s.repo), isEmpty);
  });

  test('the AI can undo the last import, nothing else', () async {
    final s = await app();
    final r = readImport(strongFile, appUnit: Unit.kg);
    await saveImport(s.repo, r, {for (final n in r.names) n: matchExercise(n, lib)?.id}, label: 'Strong');
    await s.reload(); // as the import screen does
    final a = parseToolReply('SAY: ok\nDO: import undo', s);
    expect(a.errors, isEmpty);
    await a.actions.single.run(s);
    expect(await s.repo.history(), isEmpty);
    expect(parseToolReply('SAY: x\nDO: import file.csv', s).errors, isNotEmpty);
    expect(toolGrammar(s.lib, s.profile!, s.plan!.days.length), contains('"import undo"'));
  });

  testWidgets('the preview says the guesses, leaves an unknown name to the person, and saves nothing before Import', (tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(() => app(f: databaseFactoryFfiNoIsolate)))!;
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: ImportScreen(s: s, text: strongFile)));
    await settle();
    expect(find.text('Strong (or FightMilk) CSV'), findsOneWidget);
    expect(find.textContaining('2 workouts, 4 sets'), findsOneWidget);
    final why = tester.widget<Text>(find.byKey(const Key('unitWhy')));
    expect(why.data, contains('does not say'));
    expect(why.style!.color, C.gold, reason: 'a guess is shown in gold, never silent');
    expect(find.text('Not found: pick one, or it is left out'), findsOneWidget);
    expect(find.text('Guessed: Back squat. Check it'), findsOneWidget, reason: 'a synonym match is a guess, in gold (review 6 P1-2)');
    expect(tester.widget<Text>(find.byKey(const Key('guessed'))).style!.color, C.gold);
    expect((await tester.runAsync(() => s.repo.history()))!, isEmpty, reason: 'nothing saved yet');
    await tester.tap(find.byKey(const Key('doImport')));
    await settle();
    expect((await tester.runAsync(() => s.repo.history()))!.length, 2);
    expect(find.text('Your imports'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  test('looksLikeCsv tells a table from a plan or a link', () {
    expect(looksLikeCsv(strongFile), isTrue);
    expect(looksLikeCsv('{"fightmilk":"plan"}'), isFalse);
    expect(looksLikeCsv('fightmilk://plan#abc'), isFalse);
    expect(looksLikeCsv('Push day\nBench press 3x8'), isFalse);
  });
}
