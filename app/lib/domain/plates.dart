import 'exercise.dart';
import 'units.dart';

/// Plate maths: what goes on each side of the bar, from the plates the gym has.

/// Standard plate sets (each side), heaviest first, in the unit people think in.
const defaultPlatesLb = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];
const defaultPlatesKg = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];

/// The usual bar: 45 lb or 20 kg.
double defaultBarKg(Unit u) => u == Unit.lb ? lbToKg(45) : 20;

/// Plates per side (in the user's unit) for [totalKg] on a bar of [barKg]; nearest loadable at
/// or below the total. Returns the plates and the total they make (kg). An empty list = the bar
/// alone (or nothing on a machine).
(List<double>, double) platesFor(double totalKg, double barKg, List<double> platesInUnit, Unit u) {
  final perSide = (toUnit(totalKg, u) - toUnit(barKg, u)) / 2;
  final out = <double>[];
  var left = perSide;
  final sorted = [...platesInUnit]..sort((a, b) => b.compareTo(a));
  for (final p in sorted) {
    while (left + 1e-6 >= p) {
      out.add(p);
      left -= p;
    }
  }
  final made = toUnit(barKg, u) + 2 * out.fold<double>(0, (a, b) => a + b);
  return (out, fromUnit(made, u));
}

/// One row of the % table (review 2, P1-1): the plates per side in the person's unit, "the bar",
/// "below the bar", and "≈ X" when the plates make a different weight than the row's.
String plateLine(double kg, double barKg, List<double> platesInUnit, Unit u) {
  if (kg < barKg - 0.01) return 'below the bar';
  final pl = platesFor(kg, barKg, platesInUnit, u);
  // plates keep two decimals (1.25 kg), no trailing zeros
  String pf(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  final s = pl.$1.isEmpty ? 'the bar' : 'per side ${pl.$1.map(pf).join(' + ')}';
  return (toUnit(pl.$2, u) - toUnit(kg, u)).abs() > 0.05 ? '$s ≈ ${fmtWeight(pl.$2, u)}' : s;
}

/// Does this exercise get loaded with plates, and what does the bar weigh?
/// null = not plate-loaded (dumbbells, pin-loaded machines, cables, bodyweight).
double? barFor(Exercise e, {required double barKg, double smithKg = 0}) {
  if (e.equipment == Equipment.smith) return smithKg;
  if (e.equipment == Equipment.barbell) {
    if (e.id.startsWith('trap_bar')) return barKg; // most trap bars weigh about the same as a bar
    if (e.id.startsWith('ez_')) return null; // often a fixed-weight EZ bar
    return barKg;
  }
  const plateMachines = {'leg_press', 'leg_press_single', 'leg_press_calf_raise', 'hack_squat', 'pendulum_squat', 'belt_squat', 'v_squat', 'hammer_chest_press', 'iso_lateral_row', 't_bar_row', 'sled_push'};
  if (plateMachines.contains(e.id)) return 0; // the weight you log is the plates you add
  return null;
}

/// "45 + 25 + 5" (per side).
String platesText(List<double> plates) => plates.isEmpty ? 'just the bar' : plates.map(fmtNum).join(' + ');

/// Warm-up ramp for a working weight: (kg, reps). Bar first for barbell lifts; nothing under the
/// bar; steps that round to the same weight are dropped; nothing for light work.
List<(double, int)> warmupsFor(double workKg, Exercise e, Unit u, {double? barKg}) {
  if (workKg <= 0 || e.bodyweight || e.timed) return const [];
  final bar = barKg ?? 0;
  final steps = <(double, int)>[
    if (barKg != null && barKg > 0) (bar, 10),
    (workKg * 0.4, 5),
    (workKg * 0.6, 3),
    (workKg * 0.8, 1),
  ];
  final out = <(double, int)>[];
  for (final (kg, reps) in steps) {
    final r = roundToStep(kg, e.step, u);
    if (r < bar - 0.01 || r >= workKg - 0.01 || r <= 0) continue;
    if (out.isNotEmpty && (out.last.$1 - r).abs() < 0.01) continue;
    out.add((r, reps));
  }
  // light lifts need less: under ~2x the bar (or 30 kg) one step is plenty
  if (workKg < (bar > 0 ? bar * 2 : 30) && out.length > 1) return [out.last];
  return out;
}

/// The weight for n reps from a 1RM (Epley, the same formula as [e1rm]).
double weightForReps(double oneRmKg, int reps) => reps <= 1 ? oneRmKg : oneRmKg / (1 + reps / 30);

/// RPE chart (reps in reserve style): % of 1RM for [reps] at [rpe] (Tuchscherer-style table).
double rpePercent(int reps, double rpe) {
  // % of 1RM at RPE 10 for 1..12 reps, then 2.5-3% less per RPE step down
  const at10 = [100.0, 95.5, 92.2, 89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 70.7, 68.0];
  final r = reps.clamp(1, 12);
  return at10[r - 1] - (10 - rpe) * 3.0;
}
