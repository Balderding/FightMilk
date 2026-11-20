import 'exercise.dart';

enum Unit { kg, lb }

const _lbPerKg = 2.20462262;

double lbToKg(double lb) => lb / _lbPerKg;
double kgToLb(double kg) => kg * _lbPerKg;

/// Weight in the user's unit.
double toUnit(double kg, Unit u) => u == Unit.kg ? kg : kgToLb(kg);
double fromUnit(double v, Unit u) => u == Unit.kg ? v : lbToKg(v);

/// The user's own plate/dumbbell steps (Settings), in their unit. Empty = the defaults below.
final Map<(StepKind, Unit), double> stepOverrides = {};

/// Smallest weight change for this kind of equipment, in the user's unit.
double stepIn(StepKind k, Unit u) => stepOverrides[(k, u)] ?? defaultStep(k, u);

double defaultStep(StepKind k, Unit u) => switch ((k, u)) {
      (StepKind.barbell, Unit.lb) => 5,
      (StepKind.barbell, Unit.kg) => 2.5,
      (StepKind.dumbbell, Unit.lb) => 5,
      (StepKind.dumbbell, Unit.kg) => 2,
      (StepKind.machine, Unit.lb) => 10,
      (StepKind.machine, Unit.kg) => 5,
      (StepKind.cable, Unit.lb) => 5,
      (StepKind.cable, Unit.kg) => 2.5,
      (StepKind.bodyweight, Unit.lb) => 5,
      (StepKind.bodyweight, Unit.kg) => 2.5,
    };

double stepKg(StepKind k, Unit u) => fromUnit(stepIn(k, u), u);

/// Rounds a kg weight to the nearest step as seen in the user's unit; returns kg.
double roundToStep(double kg, StepKind k, Unit u) {
  final s = stepIn(k, u);
  final v = (toUnit(kg, u) / s).round() * s;
  return fromUnit(v.toDouble(), u);
}

/// "100", "102.5", "220.5" - at most one decimal, no trailing ".0".
String fmtNum(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
}

String fmtWeight(double kg, Unit u) => fmtNum(toUnit(kg, u));

String unitLabel(Unit u) => u == Unit.kg ? 'kg' : 'lb';

/// Estimated one-rep max (Epley).
double e1rm(double kg, int reps) => reps <= 1 ? kg : kg * (1 + reps / 30);
