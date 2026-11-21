import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout/domain/exercise.dart';
import 'package:workout/domain/gym.dart';
import 'package:workout/domain/library.dart';
import 'package:workout/domain/plates.dart';
import 'package:workout/domain/units.dart';
import 'package:workout/domain/warmup_text.dart';

void main() {
  final lib = Library.fromJsonString(File('assets/exercises.json').readAsStringSync());
  tearDown(() => stepOverrides.clear());

  test('plates per side, lb and kg, nearest below when it cannot be made', () {
    final (a, ma) = platesFor(lbToKg(225), lbToKg(45), defaultPlatesLb, Unit.lb);
    expect(a, [45, 45]);
    expect(toUnit(ma, Unit.lb), closeTo(225, 0.01));
    final (b, _) = platesFor(lbToKg(185), lbToKg(45), defaultPlatesLb, Unit.lb);
    expect(b, [45, 25]);
    final (c, mc) = platesFor(102.5, 20, defaultPlatesKg, Unit.kg);
    expect(c, [25, 15, 1.25]);
    expect(mc, closeTo(102.5, 0.01));
    final (d, md) = platesFor(lbToKg(137), lbToKg(45), defaultPlatesLb, Unit.lb); // 46 per side: 45 + nothing for 1
    expect(d, [45]);
    expect(toUnit(md, Unit.lb), closeTo(135, 0.01));
    final (e, _) = platesFor(lbToKg(45), lbToKg(45), defaultPlatesLb, Unit.lb);
    expect(e, isEmpty);
    expect(platesText(const []), 'just the bar');
    expect(platesText(const [45, 25, 2.5]), '45 + 25 + 2.5');
  });

  test('which lifts take plates', () {
    expect(barFor(lib.byId('bench_press')!, barKg: 20), 20);
    expect(barFor(lib.byId('smith_squat')!, barKg: 20, smithKg: 7), 7);
    expect(barFor(lib.byId('leg_press')!, barKg: 20), 0);
    expect(barFor(lib.byId('machine_chest_press')!, barKg: 20), isNull);
    expect(barFor(lib.byId('db_bench_press')!, barKg: 20), isNull);
  });

  test('warm-up ramp: bar first, rounded, nothing at or above the working weight', () {
    final bench = lib.byId('bench_press')!;
    final w = warmupsFor(lbToKg(225), bench, Unit.lb, barKg: lbToKg(45));
    expect([for (final (kg, _) in w) toUnit(kg, Unit.lb).round()], [45, 90, 135, 180]);
    expect([for (final (_, r) in w) r], [10, 5, 3, 1]);
    // light: one step
    expect(warmupsFor(lbToKg(65), bench, Unit.lb, barKg: lbToKg(45)).length, 1);
    // machine with no bar
    final mc = warmupsFor(60, lib.byId('machine_chest_press')!, Unit.kg);
    expect(mc.every((x) => x.$1 < 60), isTrue);
    expect(warmupsFor(0, bench, Unit.lb, barKg: 20), isEmpty);
  });

  test('general warm-up and cool-down follow the day', () {
    final up = [lib.byId('bench_press')!, lib.byId('lat_pulldown')!];
    final low = [lib.byId('back_squat')!, lib.byId('seated_leg_curl')!];
    expect(generalWarmup(up).join(' '), contains('Arm circles'));
    expect(generalWarmup(up).join(' '), isNot(contains('Leg swings')));
    expect(generalWarmup(low).join(' '), contains('Leg swings'));
    expect(coolDown(up).join(' '), contains('chest'));
    expect(coolDown(low).join(' '), contains('hamstring'));
  });

  test('gym keeps bar, smith and plates', () {
    final g = Gym.create('X', {'barbell'}).copyWith(barKg: 15, smithKg: 7, plates: [20, 10, 5], platesUnit: 'kg');
    final j = Gym.fromJson(g.toJson());
    expect([j.barKg, j.smithKg, j.plates, j.platesUnit], [15, 7, [20, 10, 5], 'kg']);
    expect(rpePercent(1, 10), 100);
    expect(rpePercent(5, 8), lessThan(rpePercent(5, 10)));
    expect(weightForReps(e1rm(100, 5), 5), closeTo(100, 0.01));
  });
}
