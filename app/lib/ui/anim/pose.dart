import 'dart:ui';

/// A stick-figure pose on a 64x64 grid.
class Pose {
  final Offset head;
  final List<List<Offset>> body;
  final List<Offset> hands;
  const Pose({required this.head, required this.body, required this.hands});
}

/// Both ends of a movement. [liftAB]: going a->b is the lift (the effort), b->a the lowering.
class PosePair {
  final Pose a, b;
  final List<List<Offset>> props; // bench, floor, pads: they don't move
  final String kind; // how equipment sits in the hands (see gen_icons.py)
  final bool liftAB;
  const PosePair({required this.a, required this.b, required this.props, required this.kind, required this.liftAB});
}

Pose lerpPose(Pose a, Pose b, double t) => Pose(
      head: Offset.lerp(a.head, b.head, t)!,
      body: [
        for (var i = 0; i < a.body.length; i++) [for (var j = 0; j < a.body[i].length; j++) Offset.lerp(a.body[i][j], b.body[i][j], t)!]
      ],
      hands: [for (var i = 0; i < a.hands.length; i++) Offset.lerp(a.hands[i], b.hands[i], t)!],
    );

enum Phase { lift, top, lower, bottom }

/// One rep, the way you should do it: lift in about 0.9 s, short squeeze, lower slowly in about
/// 1.5 s, short pause. Returns how far from the start pose (0) to the end pose (1), and the phase.
(double, Phase) repAt(double seconds) {
  const lift = 0.9, top = 0.25, lower = 1.5, bottom = 0.35;
  const cycle = lift + top + lower + bottom;
  final s = seconds % cycle;
  double ease(double x) => x < .5 ? 2 * x * x : 1 - 2 * (1 - x) * (1 - x);
  if (s < lift) return (ease(s / lift), Phase.lift);
  if (s < lift + top) return (1, Phase.top);
  if (s < lift + top + lower) return (1 - ease((s - lift - top) / lower), Phase.lower);
  return (0, Phase.bottom);
}

const repSeconds = 3.0;
