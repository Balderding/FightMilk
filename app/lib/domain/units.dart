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
  // a tiny nudge so an exact half step always rounds up, not by kg->lb float error (P1-7)
  final v = (toUnit(kg, u) / s + 1e-6).round() * s;
  return fromUnit(v.toDouble(), u);
}

/// "100", "102.5", "220.5" - at most one decimal, no trailing ".0".
String fmtNum(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
}

String fmtWeight(double kg, Unit u) => fmtNum(toUnit(kg, u));

String unitLabel(Unit u) => u == Unit.kg ? 'kg' : 'lb';

// ---------- lengths (review 4, P2-1): stored in cm, shown in inches for lb users ----------

String lengthUnit(Unit u) => u == Unit.kg ? 'cm' : 'in';
double toLen(double cm, Unit u) => u == Unit.kg ? cm : cm / 2.54;
double fromLen(double v, Unit u) => u == Unit.kg ? v : v * 2.54;

/// "86 cm" or "33.9 in".
String fmtLen(double cm, Unit u) => '${fmtNum(toLen(cm, u))} ${lengthUnit(u)}';

/// "180 cm" or "5 ft 11 in".
String fmtHeight(double cm, Unit u) {
  if (u == Unit.kg) return '${cm.round()} cm';
  final inches = (cm / 2.54).round();
  return '${inches ~/ 12} ft ${inches % 12} in';
}

/// A height typed any common way, in cm: "178", "178 cm", "5'10", "5'10\"", "5 ft 10", "5 10",
/// "70 in". A bare number is cm from 100 up, else inches. Null when it is not a height
/// (100-250 cm).
double? parseHeight(String text) {
  final t = text.trim().toLowerCase().replaceAll('’', "'").replaceAll('″', '"').replaceAll(',', '.');
  final num0 = RegExp(r'^(\d{2,3}(?:\.\d)?)\s*(cm|in|inches|")?$').firstMatch(t);
  // feet need their mark (' ft feet foot) or a second number ("5 10"): a lone 5" or 6 in is inches,
  // not feet, and too short to be a height (review 5, P2-7)
  final ftIn = RegExp(r'''^(\d)\s*(?:'|ft|feet|foot)\s*(\d{1,2}(?:\.\d)?)?\s*(?:"|in|inches)?$''').firstMatch(t) ?? RegExp(r'^(\d)\s+(\d{1,2}(?:\.\d)?)\s*(?:"|in|inches)?$').firstMatch(t);
  double? cm;
  if (num0 != null) {
    final v = double.parse(num0.group(1)!);
    final unit = num0.group(2);
    cm = unit == 'cm' ? v : (unit != null || v < 100) ? v * 2.54 : v;
  } else if (ftIn != null) {
    final ft = int.parse(ftIn.group(1)!), inch = double.tryParse(ftIn.group(2) ?? '0') ?? 0;
    if (inch >= 12) return null;
    cm = (ft * 12 + inch) * 2.54;
  }
  return cm != null && cm >= 100 && cm <= 250 ? cm : null;
}

/// Estimated one-rep max (Epley).
/// 'epley' (default) or 'brzycki' (Settings → Progression).
String e1rmFormula = 'epley';

/// The weight for [reps] reps from a 1-rep max: the active formula run backwards (review 2, P2-2).
double repsAt(double max, int reps) {
  if (reps <= 1) return max;
  if (e1rmFormula == 'brzycki' && reps < 37) return max * (37 - reps) / 36;
  return max / (1 + reps / 30);
}

double e1rm(double kg, int reps) {
  if (reps <= 0) return 0; // a missed rep is not a lift (review 2, P1-2)
  if (reps == 1) return kg;
  if (e1rmFormula == 'brzycki' && reps < 37) return kg * 36 / (37 - reps);
  return kg * (1 + reps / 30);
}
