import 'exercise.dart';

/// A general warm-up and a cool-down for the muscles of the day, by plain rules (no AI).

const _upperM = {'chest', 'back', 'lats', 'shoulders', 'rear_delts', 'biceps', 'triceps', 'traps', 'forearms'};
const _lowerM = {'quads', 'hamstrings', 'glutes', 'calves', 'adductors'};

(bool, bool) _parts(List<Exercise> ex) {
  final m = {for (final e in ex) ...e.primary};
  return (m.any(_upperM.contains), m.any(_lowerM.contains));
}

/// About 5 minutes before the first lift.
List<String> generalWarmup(List<Exercise> ex) {
  final (up, low) = _parts(ex);
  return [
    up && !low ? '3-5 min easy rower, arm bike or brisk walk' : '3-5 min easy bike, rower or brisk walk',
    if (up) 'Arm circles forwards and back, 10 each',
    if (up) 'Band pull-aparts or face pulls, 15 light',
    if (up) 'Push-ups or wall push-ups, 10 easy',
    if (low) 'Leg swings front-to-back and side-to-side, 10 each leg',
    if (low) 'Bodyweight squats, 10 slow',
    if (low) 'Glute bridges, 10 with a squeeze at the top',
    if (!up && !low) 'Cat-cow and hip circles, 10 each',
    'Then the warm-up sets of your first lift',
  ];
}

/// Stretches after the session, for what was trained (hold each 20-30 s, breathe slowly).
List<String> coolDown(List<Exercise> ex) {
  final m = {for (final e in ex) ...e.primary};
  return [
    if (m.contains('chest')) 'Doorway chest stretch',
    if (m.contains('shoulders') || m.contains('rear_delts')) 'Cross-body shoulder stretch',
    if (m.contains('back') || m.contains('lats')) 'Lat stretch: hold a post, sink the hips back',
    if (m.contains('triceps')) 'Overhead triceps stretch',
    if (m.contains('biceps') || m.contains('forearms')) 'Wall biceps and forearm stretch',
    if (m.contains('quads')) 'Standing quad stretch',
    if (m.contains('hamstrings')) 'Seated or standing hamstring stretch',
    if (m.contains('glutes')) 'Figure-four glute stretch',
    if (m.contains('calves')) 'Wall calf stretch, knee straight then bent',
    if (m.contains('adductors')) 'Butterfly stretch',
    if (m.contains('core')) "Child's pose",
    '2 min easy walk to finish',
  ];
}
