import 'exercise.dart';
import 'plan.dart';

/// How a set felt (optional one-tap after a set).
enum Effort { easy, good, hard, max }

const effortLabel = {Effort.easy: 'Easy', Effort.good: 'Good', Effort.hard: 'Hard', Effort.max: 'All-out'};

/// Rest that fits how hard the set was.
/// - Heavier work (fewer reps) and bigger lifts (compounds) rest longer.
/// - Missing the bottom of the rep range adds 45 s; beating the top by 2+ takes 15 s off.
/// - An effort tap replaces that guess: easy -30, good 0, hard +30, all-out +60.
/// - After the last set of an exercise: 90 s to set up the next one.
/// Always 30-300 s, in 15 s steps.
int smartRest(Exercise e, PlanItem it, int repsDone, {required bool lastSet, Effort? effort}) {
  if (lastSet) return 90;
  if (e.timed) return 60;
  final lo = it.repLow;
  final c = e.compound;
  var r = lo <= 5
      ? (c ? 210 : 120)
      : lo <= 8
          ? (c ? 150 : 90)
          : lo <= 12
              ? (c ? 120 : 75)
              : (c ? 90 : 60);
  if (effort != null) {
    r += switch (effort) { Effort.easy => -30, Effort.good => 0, Effort.hard => 30, Effort.max => 60 };
  } else if (repsDone < it.repLow) {
    r += 45;
  } else if (repsDone >= it.repHigh + 2) {
    r -= 15;
  }
  r = r.clamp(30, 300);
  return (r / 15).round() * 15;
}

/// What the coach says right now, in plain words.
String guideLine({
  required String name,
  required int setNo, // the set coming up (1-based)
  required int sets,
  String? weight, // "225 lb", or null when unknown
  required String reps,
  required bool resting,
  required bool restOver,
  required bool exerciseDone,
  String? nextName,
  required bool workoutDone,
  required bool firstOfWorkout,
}) {
  final w = weight == null ? '' : ' at $weight';
  if (workoutDone) return "That's the whole workout. Amazing work! Tap Finish to save it.";
  if (exerciseDone) return nextName == null ? '$name done! Add another exercise or tap Finish.' : '$name done! Next up: $nextName.';
  if (resting) return 'Rest up and breathe. Next: set $setNo of $sets$w.';
  if (restOver) return "Rest's over: set $setNo of $sets, $reps reps. Let's go!";
  if (firstOfWorkout) return "Hey, let's start the workout! First up: $name, $sets sets of $reps$w. Do a light warm-up set or two first.";
  if (setNo >= sets) return 'Last set of $name! Make it count.';
  return "Set $setNo of $sets: $reps reps$w. You've got this.";
}
