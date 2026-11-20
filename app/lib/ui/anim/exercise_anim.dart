import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/exercise.dart';
import '../theme.dart';
import 'pose.dart';
import 'pose_data.dart';

const _fig = Color(0xFFDFE7EC);
const _prop = Color(0xFF5B6B77);

Color equipColor(Equipment e) => switch (e) {
      Equipment.barbell || Equipment.smith => C.teal,
      Equipment.dumbbell || Equipment.kettlebell => C.gold,
      Equipment.machine => C.green,
      Equipment.cable => C.sky,
      Equipment.band => const Color(0xFFC3A6FF),
      Equipment.bodyweight => C.dim,
    };

/// A looping animation of one rep of [e]: lift, squeeze, lower slowly, pause.
class ExerciseAnim extends StatefulWidget {
  final Exercise e;
  final double size;
  final bool showCue; // "Lift" / "Lower slowly" under the figure
  const ExerciseAnim({super.key, required this.e, this.size = 160, this.showCue = true});
  @override
  State<ExerciseAnim> createState() => _ExerciseAnimState();
}

class _ExerciseAnimState extends State<ExerciseAnim> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _cue(Phase p, bool timed) {
    if (timed) return 'Hold steady, breathe';
    return switch (p) { Phase.lift => 'Lift', Phase.top => 'Squeeze', Phase.lower => 'Lower slowly', Phase.bottom => 'Reset' };
  }

  @override
  Widget build(BuildContext context) {
    final pair = poseData[widget.e.pattern];
    if (pair == null) return SizedBox(width: widget.size, height: widget.size);
    return AnimatedBuilder(
      animation: _c,
      builder: (c, _) {
        final (t0, ph) = repAt(_c.value * repSeconds);
        // poses run start->end for the lift; patterns stored the other way round run backwards
        final t = pair.liftAB ? t0 : 1 - t0;
        final timed = widget.e.timed;
        final pose = timed ? lerpPose(pair.a, pair.b, .5 + .5 * math.sin(_c.value * 2 * math.pi) * .15) : lerpPose(pair.a, pair.b, t);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(widget.size * .12)),
            child: CustomPaint(painter: PosePainter(pose, pair, widget.e.equipment)),
          ),
          if (widget.showCue)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_cue(ph, timed), style: TextStyle(color: ph == Phase.lift ? C.teal : C.dim, fontWeight: FontWeight.w600)),
            ),
        ]);
      },
    );
  }
}

class PosePainter extends CustomPainter {
  final Pose pose;
  final PosePair pair;
  final Equipment eq;
  PosePainter(this.pose, this.pair, this.eq);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    canvas.save();
    canvas.scale(s);
    Paint line(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void poly(List<Offset> p, Paint paint) {
      final path = Path()..moveTo(p.first.dx, p.first.dy);
      for (final o in p.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint);
    }

    for (final pr in pair.props) {
      poly(pr, line(_prop, 3));
    }
    final c = equipColor(eq);
    if (eq == Equipment.machine) _machine(canvas, c, line);
    for (final b in pose.body) {
      poly(b, line(_fig, 4.5));
    }
    canvas.drawCircle(pose.head, 4.5, Paint()..color = _fig);
    if (eq != Equipment.machine) _equipment(canvas, c, line, poly);
    canvas.restore();
  }

  void _machine(Canvas canvas, Color c, Paint Function(Color, double) line) {
    canvas.drawRRect(RRect.fromLTRBR(3, 3, 61, 61, const Radius.circular(6)), line(c.withValues(alpha: .55), 2.5));
    for (final h in pose.hands) {
      canvas.drawRRect(RRect.fromLTRBR(h.dx - 4, h.dy - 3, h.dx + 4, h.dy + 3, const Radius.circular(2)), Paint()..color = c);
    }
  }

  void _equipment(Canvas canvas, Color c, Paint Function(Color, double) line, void Function(List<Offset>, Paint) poly) {
    final k = pair.kind;
    if (eq == Equipment.bodyweight || k == 'none') return;
    final fill = Paint()..color = c;
    if (eq == Equipment.cable) {
      canvas.drawCircle(const Offset(56, 8), 4, line(c, 2.5));
      for (final h in pose.hands) {
        poly([const Offset(56, 8), h], line(c, 2));
        canvas.drawCircle(h, 3, fill);
      }
      return;
    }
    if (eq == Equipment.band) {
      for (final h in pose.hands) {
        final path = Path()
          ..moveTo(h.dx, h.dy)
          ..quadraticBezierTo(h.dx + 6, (h.dy + 60) / 2, h.dx, 60);
        canvas.drawPath(path, line(c, 2.5));
        canvas.drawCircle(h, 3, fill);
      }
      return;
    }
    if (eq == Equipment.smith) {
      poly([const Offset(6, 2), const Offset(6, 62)], line(c, 2));
      poly([const Offset(58, 2), const Offset(58, 62)], line(c, 2));
    }
    for (final h in pose.hands) {
      if (eq == Equipment.barbell || eq == Equipment.smith) {
        if (k == 'bar_front') {
          final y = pose.hands.map((x) => x.dy).reduce(math.min);
          poly([Offset(6, y), Offset(58, y)], line(c, 3));
          canvas.drawRRect(RRect.fromLTRBR(4, y - 7, 9, y + 7, const Radius.circular(1.5)), fill);
          canvas.drawRRect(RRect.fromLTRBR(55, y - 7, 60, y + 7, const Radius.circular(1.5)), fill);
          return;
        }
        canvas.drawCircle(h, 7, line(c, 3));
        canvas.drawCircle(h, 2, fill);
      } else if (eq == Equipment.kettlebell) {
        canvas.drawCircle(h + const Offset(0, 5), 5, fill);
      } else {
        poly([h - const Offset(5, 0), h + const Offset(5, 0)], line(c, 2.5));
        canvas.drawRRect(RRect.fromLTRBR(h.dx - 8, h.dy - 4, h.dx - 4, h.dy + 4, const Radius.circular(1)), fill);
        canvas.drawRRect(RRect.fromLTRBR(h.dx + 4, h.dy - 4, h.dx + 8, h.dy + 4, const Radius.circular(1)), fill);
      }
    }
  }

  @override
  bool shouldRepaint(PosePainter old) => true;
}
