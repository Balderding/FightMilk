import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/domain/coach.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/program.dart';
import 'package:workout/domain/programs.dart';
import 'package:workout/domain/progression.dart';
import 'package:workout/domain/units.dart';

/// The P3 polish items of the first review (REVIEW-2026-11-22-0746).
void main() {
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());

  test('P3-5 GZCLP T2: after the last stage, back to 3x10 at the last 3x10 weight + about 15-20 lb', () {
    final r = templateById('gzclp')!.rules['bench_press#T2']!;
    expect(r.resetUp, 3);
    expect(templateById('gzclp')!.rules['back_squat#T2']!.resetUp, 4);
    final bench = lib.byId('bench_press')!;
    List<SetLog> sets(int n, int reps) => [for (var i = 0; i < 3; i++) SetLog(exerciseId: 'bench_press', kg: 50, reps: reps)];
    var st = const LiftState(exerciseId: 'bench_press#T2', workKg: 50);
    st = programNext(st, r, bench, sets(3, 9), parseSets('3x10'), Unit.kg).state; // miss on 3x10
    expect([st.stage, st.base], [1, 50]);
    st = programNext(st, r, bench, sets(3, 7), parseSets('3x8'), Unit.kg).state; // miss on 3x8
    expect(st.stage, 2);
    st = programNext(st, r, bench, sets(3, 5), parseSets('3x6'), Unit.kg).state; // miss on 3x6: reset
    expect([st.stage, st.workKg], [0, 57.5]); // 50 + 3 x 2.5 kg
    expect(LiftState.fromJson(st.toJson()).base, 57.5);
    expect(r.describe(Unit.lb, StepKind.barbell), contains('+15 lb'));
  });

  test('P3-7 the coach does not repeat the warm-up when the warm-up card is on screen', () {
    String line(bool shown) => guideLine(name: 'Squat', setNo: 1, sets: 3, reps: '5', resting: false, restOver: false, exerciseDone: false, workoutDone: false, firstOfWorkout: true, warmupShown: shown);
    expect(line(false), contains('warm-up'));
    expect(line(true), isNot(contains('warm-up')));
  });

  test('P3-6 the nSuns 4-day card says how it differs from the published layout', () {
    expect(templateById('nsuns_4')!.credit, startsWith('In the style of'));
    expect(templateById('nsuns_5')!.credit, startsWith('Follows the published'));
  });
}
