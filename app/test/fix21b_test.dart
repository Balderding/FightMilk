import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/ai/tools.dart';
import 'package:workout/domain/progression.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout/data/csv_export.dart';
import 'package:workout/data/import_store.dart';
import 'package:workout/domain/program.dart';
import 'package:workout/domain/reports.dart';
import 'package:workout/data/repo.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/import.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plan.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/packs/pack.dart';
import 'package:workout/ui/app_state.dart';

/// Fix batch 21b: review 6 (REVIEW-2026-11-22-1824) and self7, merged in MERGED-2026-11-22-fix21b.md.
void main() {
  sqfliteFfiInit();
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  final full = Profile(goal: Goal.both, days: 4, minutes: 60, have: Equipment.values.toSet(), avoid: {}, unit: Unit.kg);

  Future<AppState> app() async {
    final dir = Directory.systemTemp.createTempSync('fix21b');
    final s = await AppState.forTest(await Repo.open('${dir.path}/t.db', factory: databaseFactoryFfi), PackStore(dir.path), lib);
    await s.saveProfile(full);
    await s.makeBuiltInPlan();
    return s;
  }

  /// Strong 6.x: three clean 3 x 8 bench sessions (80, 82.5, 85), a warm-up and a rest timer each.
  String strong6({String sep = ';', String unit = 'kg'}) {
    String row(List<String> c) => c.map((x) => '"$x"').join(sep);
    final b = StringBuffer('${row(['Workout #', 'Date', 'Workout Name', 'Duration (sec)', 'Exercise Name', 'Set Order', 'Weight ($unit)', 'Reps', 'RPE', 'Distance (meters)', 'Seconds', 'Notes', 'Workout Notes'])}\n');
    for (var w = 0; w < 3; w++) {
      final dt = '2026-10-${(1 + w * 3).toString().padLeft(2, '0')} 18:00:00';
      b.write('${row(['${w + 1}', dt, 'Push', '3600', 'Bench Press (Barbell)', 'W', '40', '10', '', '', '', '', ''])}\n');
      for (var k = 1; k <= 3; k++) {
        b.write('${row(['${w + 1}', dt, 'Push', '3600', 'Bench Press (Barbell)', '$k', '${80 + w * 2.5}', '8', '', '', '', '', ''])}\n');
      }
      b.write('${row(['${w + 1}', dt, 'Push', '3600', 'Bench Press (Barbell)', 'Rest Timer', '', '', '', '', '120', '', ''])}\n');
    }
    return b.toString();
  }

  group('1 (P1) Strong 6.x', () {
    test('read as Strong: names, warm-ups, no rest-timer sets, the duration in seconds, the unit from the header', () {
      for (final (sep, unit) in [(';', 'kg'), (',', 'lbs')]) {
        final r = readImport(strong6(sep: sep, unit: unit), appUnit: Unit.kg);
        expect(r.format, ImportFormat.strong, reason: '$sep $unit');
        expect(r.unit, unit == 'kg' ? Unit.kg : Unit.lb);
        expect(r.unitGuessed, isFalse, reason: 'the header says the unit');
        expect(r.workouts.map((w) => w.name).toSet(), {'Push'}, reason: 'never "1", "2", "3"');
        expect(r.workouts.length, 3);
        final w0 = r.workouts.first;
        expect(w0.sets.length, 4, reason: 'a warm-up and 3 work sets; no rest-timer set');
        expect(w0.sets.first.type, SetType.warmup);
        expect(w0.sets.skip(1).every((x) => x.type == SetType.work && x.reps == 8), isTrue);
        expect(w0.end!.difference(w0.start).inMinutes, 60);
        expect(r.skipped.first, '3 rest-timer rows left out (they are not sets)');
      }
    });

    test('three clean sessions move the bench up, with no misses', () async {
      final s = await app();
      final r = readImport(strong6(), appUnit: Unit.kg);
      final rec = await saveImport(s.repo, r, {for (final x in r.names) x: matchExercise(x, lib)?.id}, label: 'Strong');
      await s.historyChanged(rec.exercises);
      final l = await s.repo.lift('bench_press');
      expect(l!.misses, 0);
      expect(l.workKg, greaterThan(85));
    });

    test('a generic file never names workouts after a "#" column, and reads its set order', () {
      final r = readImport('Workout #,Date,Exercise,Weight,Reps,Set Order\n1,2026-11-05 18:00,Squat,60,5,W\n1,2026-11-05 18:00,Squat,100,5,1\n', appUnit: Unit.kg);
      expect(r.workouts.single.name, 'Imported workout');
      expect(r.workouts.single.sets.first.type, SetType.warmup);
    });
  });

  group('2 (P1) exercise names', () {
    test('143 real names from Strong, Hevy and FitNotes (reviews 6 and 7): no wrong lift', () {
      const names = {
'Bench Press (Barbell)': 'bench_press', 'Bench Press (Dumbbell)': 'db_bench_press', 'Bench Press (Smith Machine)': 'smith_bench_press', 'Incline Bench Press (Barbell)': 'incline_bench_press',
      'Squat (Barbell)': 'back_squat', 'Front Squat (Barbell)': 'front_squat', 'Deadlift (Barbell)': 'deadlift', 'Romanian Deadlift (Barbell)': 'romanian_deadlift', 'Sumo Deadlift (Barbell)': 'sumo_deadlift',
      'Overhead Press (Barbell)': 'overhead_press', 'Overhead Press (Dumbbell)': 'seated_db_press', 'Bent Over Row (Barbell)': 'barbell_row', 'Bent Over Row (Dumbbell)': 'one_arm_db_row',
      'Lat Pulldown (Cable)': 'lat_pulldown', 'Seated Row (Cable)': 'seated_cable_row', 'Bicep Curl (Barbell)': 'barbell_curl', 'Bicep Curl (Dumbbell)': 'db_curl', 'Hammer Curl (Dumbbell)': 'hammer_curl',
      'Triceps Pushdown (Cable - Straight Bar)': 'triceps_pushdown', 'Skullcrusher (Barbell)': 'skull_crusher', 'Lateral Raise (Dumbbell)': 'db_lateral_raise', 'Leg Press': 'leg_press', 'Leg Extension (Machine)': 'leg_extension',
      'Lying Leg Curl (Machine)': 'lying_leg_curl', 'Seated Leg Curl (Machine)': 'seated_leg_curl', 'Calf Raise (Machine)': 'standing_calf_raise', 'Hip Thrust (Barbell)': 'hip_thrust', 'Pull Up': 'pull_up', 'Chin Up': 'chin_up',
      'Pull Up (Assisted)': 'assisted_pull_up', 'Push Up': 'push_up', 'Shrug (Dumbbell)': 'db_shrug', 'Face Pull (Cable)': 'face_pull', 'Chest Fly (Dumbbell)': 'db_fly', 'Cable Crossover': 'cable_crossover_low',
      'Goblet Squat (Kettlebell)': 'kb_goblet_squat', 'Lunge (Dumbbell)': 'walking_lunge', 'Bulgarian Split Squat': 'db_split_squat', 'T Bar Row': 't_bar_row', 'Shoulder Press (Machine)': 'machine_shoulder_press',
      'Chest Press (Machine)': 'machine_chest_press', 'Reverse Fly (Dumbbell)': 'db_rear_delt_fly', 'Preacher Curl (Barbell)': 'ez_preacher_curl', 'Arnold Press (Dumbbell)': 'arnold_press', 'Crunch': 'crunch', 'Plank': 'plank',
      'Squat (Smith Machine)': 'smith_squat', 'Incline Bench Press (Dumbbell)': 'incline_db_press', 'Lat Pulldown (Machine)': 'machine_pulldown', 'Seated Cable Row - V Grip (Cable)': 'seated_cable_row', 'Shoulder Press (Dumbbell)': 'seated_db_press',
      'Bicep Curl (Cable)': 'cable_curl', 'Triceps Rope Pushdown': 'rope_pushdown', 'Hack Squat (Machine)': 'hack_squat', 'Deadlift (Trap bar)': 'trap_bar_deadlift', 'Hip Abduction (Machine)': 'hip_abduction', 'Dumbbell Row': 'one_arm_db_row',
      'Flat Barbell Bench Press': 'bench_press', 'Barbell Squat': 'back_squat', 'Conventional Deadlift': 'deadlift', 'Overhead Press': 'overhead_press', 'Barbell Row': 'barbell_row', 'Incline Dumbbell Fly': 'incline_db_fly',
      'Flat Dumbbell Bench Press': 'db_bench_press', 'Dumbbell Curl': 'db_curl', 'EZ-Bar Curl': 'ez_bar_curl', 'Cable Crunch': 'cable_crunch', 'Seated Calf Raise Machine': 'seated_calf_raise', 'Close Grip Barbell Bench Press': 'close_grip_bench',
      'Running (Treadmill)': '', 'Squat': 'back_squat', 'Bench': 'bench_press', 'Row': '', 'Press': '', 'Curl': '',
'Incline Bench Press (Smith Machine)': 'smith_incline_press', 'Romanian Deadlift (Dumbbell)': 'db_romanian_deadlift', 'Deadlift (Dumbbell)': '', 'Squat (Dumbbell)': 'db_squat',
      'Bench Press - Close Grip (Barbell)': 'close_grip_bench', 'Bench Press - Wide Grip (Barbell)': 'bench_press', 'Lateral Raise (Cable)': 'cable_lateral_raise', 'Leg Press (Machine)': 'leg_press',
      'Single Leg Press': 'leg_press_single', 'Overhead Press (Smith Machine)': 'smith_overhead_press', 'Push Press': 'push_press', 'Box Squat (Barbell)': 'box_squat', 'Pause Squat (Barbell)': 'pause_squat',
      'Floor Press (Barbell)': 'floor_press', 'Reverse Curl (Barbell)': 'reverse_curl', 'Seated Overhead Press (Barbell)': 'seated_barbell_press', 'Kettlebell Swing': 'kb_swing', 'Front Raise (Plate)': 'plate_front_raise',
      'Upright Row (Barbell)': 'barbell_upright_row', 'Good Morning (Barbell)': 'good_morning', 'Glute Bridge': 'glute_bridge', 'Leg Curl (Machine)': '', 'Hip Thrust (Machine)': 'machine_hip_thrust',
      'Bent Over Row (Cable)': '', 'Chest Dip': 'dips', 'Triceps Dip': 'dips', 'Hanging Leg Raise': 'hanging_leg_raise', 'Ab Wheel': 'ab_wheel', 'Russian Twist': 'russian_twist',
      'Incline Curl (Dumbbell)': 'incline_db_curl', 'Concentration Curl (Dumbbell)': 'concentration_curl', 'Preacher Curl (Dumbbell)': 'db_preacher_curl', 'Preacher Curl (Machine)': 'preacher_curl_machine',
      'Fly (Cable)': 'cable_fly', 'Chest Fly (Machine)': 'pec_deck', 'Rear Delt Fly (Machine)': 'reverse_pec_deck', 'Reverse Fly (Cable)': 'cable_rear_delt_fly', 'Shoulder Press (Smith Machine)': 'smith_overhead_press',
      'Incline Chest Press (Machine)': 'incline_machine_press', 'Lat Pulldown - Close Grip (Cable)': 'close_grip_pulldown', 'Pullover (Dumbbell)': 'db_pullover', 'Straight Arm Pulldown (Cable)': 'straight_arm_pulldown',
      'Triceps Extension (Dumbbell)': 'db_overhead_ext', 'Triceps Extension (Cable)': 'overhead_cable_ext', 'Triceps Pushdown': 'triceps_pushdown', 'Wrist Curl (Barbell)': 'barbell_wrist_curl', 'Shrug (Barbell)': 'barbell_shrug',
      'Front Squat': 'front_squat', 'Clean': '', 'Power Clean': 'power_clean', 'Snatch': '', 'Clean and Jerk (Barbell)': 'clean_and_jerk', 'Thruster (Barbell)': 'thruster', 'Lunge (Barbell)': 'reverse_lunge',
      'Walking Lunge': 'walking_lunge', 'Step-up (Dumbbell)': 'db_step_up', 'Split Squat (Dumbbell)': 'db_split_squat', 'Calf Press on Leg Press': 'leg_press_calf_raise', 'Seated Calf Raise (Plate Loaded)': 'seated_calf_raise',
      'Standing Calf Raise (Smith Machine)': 'smith_calf_raise', 'Iso-Lateral Row (Machine)': 'iso_lateral_row', 'Iso-Lateral Chest Press (Machine)': 'hammer_chest_press', 'Pendlay Row (Barbell)': 'pendlay_row',
      'Sumo Squat (Kettlebell)': '', 'Single Arm Row (Dumbbell)': 'one_arm_db_row', 'Rack Pull': 'rack_pull', 'Deficit Deadlift (Barbell)': 'deficit_deadlift', 'Stiff Leg Deadlift (Barbell)': 'stiff_leg_deadlift',
        // self7's probes
        'Press (Barbell)': '', 'Row (Cable)': '', 'Jefferson Deadlift': '',
      };
      var wrong = 0, right = 0, none = 0;
      final bad = <String>[];
      for (final e in names.entries) {
        final got = matchExercise(e.key, lib)?.id;
        final want = e.value.isEmpty ? null : e.value;
        if (got == want) {
          right++;
        } else if (got == null) {
          none++;
        } else {
          wrong++;
          bad.add('${e.key} -> $got (want $want)');
        }
      }
      // ignore: avoid_print
      print('MATCH right $right, none $none, wrong $wrong of ${names.length}');
      expect(bad, isEmpty, reason: 'a wrong lift writes wrong history; asking is fine');
      expect(right, greaterThan(names.length * 0.6), reason: 'still finds most of them');
    });

    test('review 7 P3-13: same-lift words match, and are sure; a standing leg curl is still asked', () {
      for (final (n, id) in [
        ('Single Arm Row (Dumbbell)', 'one_arm_db_row'),
        ('Lat Pulldown - Close Grip (Cable)', 'close_grip_pulldown'),
        ('Shoulder Press (Smith Machine)', 'smith_overhead_press'),
        ('Standing Calf Raise (Smith Machine)', 'smith_calf_raise'),
        ('Reverse Fly (Cable)', 'cable_rear_delt_fly'),
        ('Seated Calf Raise (Plate Loaded)', 'seated_calf_raise'),
        ('Lat Pulldown (Cable)', 'lat_pulldown'),
        ('Shoulder Press (Machine)', 'machine_shoulder_press'),
      ]) {
        final (e, sure) = matchName(n, lib);
        expect(e?.id, id, reason: n);
        expect(sure, isTrue, reason: n);
      }
      expect(matchExercise('Leg Curl (Machine)', lib), isNull, reason: 'seated, lying or standing: ask');
    });

    test('Smith names are Smith lifts; a guess is marked as a guess', () {
      expect(matchExercise('Incline Bench Press (Smith Machine)', lib)?.id, 'smith_incline_press');
      expect(matchExercise('Overhead Press (Smith Machine)', lib)?.id, 'smith_overhead_press');
      expect(matchName('Bench Press', lib).$2, isTrue, reason: 'the library name: sure');
      expect(matchName('Bench Press (Barbell)', lib), (lib.byId('bench_press'), true));
      expect(matchName('Squat (Barbell)', lib).$2, isFalse, reason: 'a synonym: a guess to check');
    });
  });

  group('3 (P1) dates', () {
    test('no rolled-over, impossible, too early or far-future dates', () {
      for (final d in ['2026-02-31', '2023-02-29', '2026-13-01', '2026-11-05 25:61', '2026-11-05 18:30:75', '0000-00-00', '9999-12-31', '2101-01-01', '1989-12-31']) {
        expect(readDate(d), isNull, reason: d);
      }
      expect(readDate('2024-02-29'), DateTime(2024, 2, 29, 12), reason: 'a real leap day');
      expect(readDate('2026-11-05T18:30:00Z'), DateTime.utc(2026, 11, 5, 18, 30).toLocal(), reason: 'a time zone still works');
      expect(readDate('2026-11-05 18:30:15'), DateTime(2026, 11, 5, 18, 30, 15));
    });

    test('a row dated in the future is left out with its reason, the rest is kept', () {
      final next = DateTime.now().add(const Duration(days: 40));
      final r = readImport('Date,Exercise,Weight,Reps\n${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')} 18:00,Bench press,20,5\n2026-10-01 18:00,Bench press,65,8\n', appUnit: Unit.kg);
      expect(r.workouts.single.sets.single.kg, 65);
      expect(r.skipped.single, contains('a date in the future'));
      expect(readImport('Date,Weight\n2099-01-01,80\n2026-10-01,81\n', appUnit: Unit.kg).body.single.$2, 81);
    });
  });

  const oldSquats = 'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n'
      '2025-06-01 18:00:00,Legs,1h 0m,Squat (Barbell),1,140,5,0,0,,,\n'
      '2025-06-04 18:00:00,Legs,1h 0m,Squat (Barbell),1,142.5,5,0,0,,,\n';

  Future<(AppState, ImportRecord)> imported() async {
    final s = await app();
    await s.repo.saveLift(const LiftState(exerciseId: 'back_squat', workKg: 80, tm: 110));
    final r = readImport(oldSquats, appUnit: Unit.kg);
    final rec = await saveImport(s.repo, r, {for (final x in r.names) x: matchExercise(x, lib)?.id}, label: 'Strong');
    await s.historyChanged(rec.exercises);
    await s.reload();
    return (s, rec);
  }

  group('5 (P1) Undo puts the lifts back', () {
    test('the working weight and training max come back exactly', () async {
      final before = jsonOf(const LiftState(exerciseId: 'back_squat', workKg: 80, tm: 110));
      final (s, rec) = await imported();
      expect((await s.repo.lift('back_squat'))!.workKg, isNot(80), reason: 'the import moved it');
      expect(rec.lifts.keys, ['back_squat']);
      final rebuild = await undoImport(s.repo, rec.id);
      await s.historyChanged(rebuild);
      expect(rebuild, isEmpty, reason: 'put back, not worked out again');
      final after = await s.repo.lift('back_squat');
      expect(after!.workKg, 80);
      expect(after.tm, 110);
      expect(jsonOf(after), before);
    });

    test('a lift trained in the app since the import is worked out from the history that is left', () async {
      final (s, rec) = await imported();
      final ses = await s.repo.startSession(s.plan!, 0, s.plan!.days.first);
      await s.repo.logSet(ses.id, 'back_squat', 90, 5);
      await s.repo.finishSession(ses.id, s.lib, s.unit);
      expect(await undoImport(s.repo, rec.id), ['back_squat']);
    });
  });

  group('4 (P1) the AI taking out an import', () {
    test('always asks, says what goes, and the change list never calls it undone', () async {
      final (s, _) = await imported();
      final r = parseToolReply('SAY: ok\nDO: import undo', s);
      final a = r.actions.single;
      expect(a.alwaysAsk, isTrue, reason: 'never on Auto');
      expect(a.undoable, isFalse);
      expect(a.says, contains('Take out the last import (Strong): 2 workouts'));
      expect(a.says, contains('cannot bring them back'));
      await s.runActions('take that import out', r.actions);
      expect(await s.repo.history(), isEmpty);
      expect(s.aiChanges.first.partial, isTrue);
      await s.undoChange(0);
      expect(s.aiChanges.first.partial, isTrue, reason: 'still marked after Undo, so the screen says the import did not come back');
      expect(parseToolReply('SAY: x\nDO: import undo', s).errors.join(), contains('no import to undo'));
    });
  });

  group('P2 reading', () {
    test('6 numbers: unreadable weights are left out with the reason; units in the cell; ambiguous commas', () {
      const head = 'Date,Exercise,Weight,Reps\n';
      final r = readImport('$head'
          '2026-10-01 18:00,Squat,,5\n' // empty: bodyweight, kept
          '2026-10-01 18:00,Squat,100 kg,5\n'
          '2026-10-01 18:00,Squat,225lbs,4\n'
          '2026-10-01 18:00,Squat,abc,3\n'
          '2026-10-01 18:00,Squat,NaN,2\n'
          '2026-10-01 18:00,Squat,1e308,1\n'
          '2026-10-01 18:00,Squat,"1,005",6\n'
          '2026-10-01 18:00,Squat,"1.234,5",7\n'
          '2026-10-01 18:00,Squat,"102,5",8\n', appUnit: Unit.kg);
      expect(r.ok, isTrue, reason: 'one bad cell never throws the file away');
      final kgs = [for (final s in r.workouts.single.sets) s.kg];
      expect(kgs.length, 4);
      expect(kgs[0], 0);
      expect(kgs[1], 100);
      expect(kgs[2], closeTo(lbToKg(225), 0.01));
      expect(kgs[3], 102.5);
      expect(r.skipped.where((x) => x.contains('not a number')).length, 3);
      expect(r.skipped.any((x) => x.contains('could be a thousand or a decimal')), isTrue);
      expect(r.skipped.any((x) => x.contains('out of range')), isTrue);
      expect(readSecs('99999999999999999999'), isNull);
      expect(readSecs('1:2:3:4'), isNull);
      expect(readSecs('1:30'), 90);
    });

    test('8 a file with reps but no exercise is not a body log; Activity names the exercise; lb-looking weights are said', () {
      expect(readImport('Date,Workout Name,Weight,Reps\n2026-10-01,A,100,5\n', appUnit: Unit.kg).problem, 'No exercise column was found.');
      expect(readImport('Date,Activity,Weight,Reps\n2026-10-01,Squat,100,5\n', appUnit: Unit.kg).workouts.single.sets.single.exercise, 'Squat');
      final b = readImport('Date,Weight\n2026-10-01,182\n2026-10-02,181\n2026-10-03,180\n', appUnit: Unit.kg);
      expect(b.format, ImportFormat.body);
      expect(b.unitWhy, contains('they look like lb'));
    });

    test('9 an unclosed quote is said, with its line', () {
      final r = readImport('Date,Exercise,Weight,Reps\n2026-10-01,"Squat,100,5\n2026-10-02,Squat,100,5\n2026-10-03,Squat,100,5\n', appUnit: Unit.kg);
      expect(r.ok, isFalse);
      expect(r.problem, contains('opened on line 2 is never closed'));
    });

    test('11 per-set times stay one workout; 13 a clock Time column and a Sets column; 14 distance units', () {
      final r = readImport('Date,Time,Exercise,Weight,Reps,Sets\n2026-10-01,23:58,Squat,100,5,3\n2026-10-02,00:03,Squat,100,5,1\n2026-10-02,05:30,Squat,60,5,1\n', appUnit: Unit.kg);
      expect(r.workouts.length, 2, reason: '23:58 and 00:03 are one workout; 05:30 is another');
      expect(r.workouts.first.start, DateTime(2026, 10, 1, 23, 58));
      expect(r.workouts.first.end, DateTime(2026, 10, 2, 0, 3));
      expect(r.workouts.first.sets.length, 4, reason: 'Sets = 3 makes three sets');
      expect(r.workouts.first.sets.every((s) => s.secs == null), isTrue, reason: 'a clock time is not seconds');
      final fit = readImport('Date,Exercise,Category,Weight (kgs),Reps,Distance,Distance Unit,Time,Comment\n2026-10-01,Running,Cardio,,,5,km,0:25:00,\n2026-10-01,Walking,Cardio,,,2,mi,,\n', appUnit: Unit.kg);
      expect(fit.workouts.single.sets.map((s) => s.meters), [5000, closeTo(3218.69, 0.01)]);
      final strongOld = readImport('Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n2026-10-01 18:00:00,Run,30m,Running (Treadmill),1,0,0,5,1800,,,\n', appUnit: Unit.kg);
      expect(strongOld.workouts.single.sets.single.meters, 5000, reason: 'the old Strong Distance is km');
      final hevy = readImport('title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_miles,duration_seconds,rpe\nRun,"1 Oct 2026, 18:00","1 Oct 2026, 18:30",,Treadmill,,,0,normal,,,3,1800,\n', appUnit: Unit.kg);
      expect(hevy.workouts.single.sets.single.meters, closeTo(4828.03, 0.01));
    });

    test('N52 two exports pasted together: the second header and repeated rows are left out; capped only when cut', () {
      const f = 'Date,Exercise,Weight,Reps\n2026-10-01 18:00,Squat,100,5\nDate,Exercise,Weight,Reps\n2026-10-01 18:00,Squat,100,5\n2026-10-01 18:00,Squat,102.5,5\n';
      final r = readImport(f, appUnit: Unit.kg);
      expect(r.workouts.single.sets.length, 2);
      expect(r.skipped.single, contains('2 repeated rows left out'));
    });
  });

  test('7 weigh-ins already here, or twice in the file, are duplicates', () async {
    final s = await app();
    await s.repo.logBody(82, at: DateTime(2026, 10, 1, 7));
    final r = readImport('Date,Body weight (kg)\n2026-10-01 07:05,82.1\n2026-10-02 07:00,81.9\n2026-10-02 07:03,81.9\n', appUnit: Unit.kg);
    final d = await bodyDuplicates(s.repo, r);
    expect(d, {0, 2});
    await saveImport(s.repo, r, const {}, skipBody: d, label: 'Body');
    expect((await s.repo.bodyLog()).length, 2, reason: 'mine and the one new weigh-in');
  });

  test('10 shared text: history files go to the import, plans to the plan reader', () {
    for (final csv in [
      '"title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps"\n"Upper","2 Nov 2026, 18:00",,,"Bench Press (Barbell)",,,0,normal,80,5',
      'title,start_time,exercise_title,set_index,weight_lbs,reps\nUpper,"2 Nov 2026, 18:00",Bench,0,185,5',
      '"Workout #";"Date";"Workout Name";"Duration (sec)";"Exercise Name";"Set Order";"Weight (kg)";"Reps"\n"1";"2026-11-02";"A";"60";"Squat";"1";"100";"5"',
      '\uFEFFDate,Exercise,Weight,Reps\n2026-11-05,Squat,100,5',
      'Date,Body weight (kg)\n2026-11-05,82',
    ]) {
      expect(looksLikeCsv(csv), isTrue, reason: csv.split('\n').first);
    }
    for (final plan in [
      'Update day, 3x5 heavy\nBench press 3x5\nSquat 3x5',
      'Validate, then deload week\nSquat 3x5',
      'Push day (updated), date night after\nBench press 3x8',
      'Legs, updated\nSquat 3x5',
    ]) {
      expect(looksLikeCsv(plan), isFalse, reason: plan.split('\n').first);
    }
  });

  test('N43 an import remembers the dates of what it brought in', () async {
    final s = await app();
    final r = readImport(oldSquats, appUnit: Unit.kg);
    final rec = await saveImport(s.repo, r, {for (final x in r.names) x: matchExercise(x, lib)?.id}, label: 'Strong');
    expect(rec.from, DateTime(2025, 6, 1, 18));
    expect(rec.to, DateTime(2025, 6, 4, 18));
    final back = (await importRecords(s.repo)).single;
    expect((back.from, back.to), (rec.from, rec.to), reason: 'kept in the saved list');
  });

  group('P3', () {
    test('N44 a big drop in a received script is marked and says it goes down', () {
      expect(scriptWords('if always: add -50 kg'), [('Every workout: add -50 kg (goes down)', true)]);
      expect(scriptWords('if miss: add -1'), [('After a short set: add -1 weight step (goes down)', false)]);
    });

    test('N45 / S7 P3-6 the formula guard looks past leading spaces, and the import takes it off again', () {
      expect(csvField(' =1+1'), '"\' =1+1"');
      expect(csvField('\r=1'), '"\'\r=1"');
      expect(cleanCell("' =1+1", quoted: true), ' =1+1');
      expect(cleanCell("'\n=1", quoted: true), '\n=1');
      expect(cleanCell("'Tom"), "'Tom");
    });

    test('S7 P3-9 the week so far counts whole calendar days, also across a clock change', () {
      // a Wednesday after a spring-forward Sunday night: Monday, Tuesday and Wednesday are 3 days
      final wed = DateTime(2026, 3, 25, 9); // the EU clocks moved on 29 March; any week works the same in UTC days
      final (a, b, _) = weekReports(wed, const [], const [], lib);
      expect(b.to.difference(b.from).inDays, 3);
      expect(a.workouts, 0);
    });

    testWidgets('N47 settings that could not be read are said in Settings', (tester) async {
      final s = (await tester.runAsync(app))!;
      await tester.runAsync(() async {
        await s.repo.kvSet('tape', '{broken');
        await s.reload();
      });
      expect(s.loadProblems, contains('body'));
    });
  });
}

String jsonOf(LiftState l) => '${l.workKg}/${l.tm}/${l.misses}/${l.stage}/${l.workReps}';
