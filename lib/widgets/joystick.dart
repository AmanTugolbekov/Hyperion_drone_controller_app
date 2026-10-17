
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/alatoo_theme.dart';

/// Which axes snap back when the finger lifts.
enum JoystickReturn {
  /// Both axes recentre — used for roll/pitch and yaw.
  both,

  /// The vertical axis stays where it was left — used for a throttle stick on
  /// drones with no altitude hold, so the drone keeps its power.
  horizontalOnly,
}

/// A two-axis stick. Reports -1..1 on each axis with y positive upwards.
class Joystick extends StatefulWidget {
  const Joystick({
    super.key,
    required this.onChanged,
    this.returnBehavior = JoystickReturn.both,
    this.size = 190,
    this.haptics = true,
    this.labelX,
    this.labelY,
  });

  /// Where the knob rests before anyone touches it, in the same -1..1 scale
  /// the stick reports (y positive upwards).
  Offset get restingPosition => returnBehavior == JoystickReturn.horizontalOnly
      // A throttle stick that holds its position must start at zero power, or
      // a centred knob would mean half throttle the moment the drone arms.
      ? const Offset(0, -1)
      : Offset.zero;

  final void Function(double x, double y) onChanged;
  final JoystickReturn returnBehavior;
  final double size;
  final bool haptics;
  final String? labelX;
  final String? labelY;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  late Offset _knob; // -1..1 in both axes, y down
  bool _wasAtEdge = false;

  @override
  void initState() {
    super.initState();
    final rest = widget.restingPosition;
    _knob = Offset(rest.dx, -rest.dy);
    // Publish the resting value so the drone is never left guessing what the
    // stick is set to before the first touch.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onChanged(rest.dx, rest.dy),
    );
  }

  double get _radius => widget.size / 2;

  void _update(Offset local) {
    final centre = Offset(_radius, _radius);
    var delta = local - centre;

    final limit = _radius - _knobRadius;
    if (delta.distance > limit) {
      delta = Offset.fromDirection(delta.direction, limit);
    }

    final atEdge = delta.distance >= limit - 0.5;
    if (widget.haptics && atEdge && !_wasAtEdge) {
      HapticFeedback.selectionClick();
    }
    _wasAtEdge = atEdge;

    setState(() => _knob = Offset(delta.dx / limit, delta.dy / limit));
    widget.onChanged(_knob.dx, -_knob.dy);
  }

  void _release() {
    setState(() {
      _knob = widget.returnBehavior == JoystickReturn.horizontalOnly
          ? Offset(0, _knob.dy)
          : Offset.zero;
    });
    _wasAtEdge = false;
    widget.onChanged(_knob.dx, -_knob.dy);
  }

  double get _knobRadius => widget.size * 0.17;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => _update(d.localPosition),
      onPanUpdate: (d) => _update(d.localPosition),
      onPanEnd: (_) => _release(),
      onPanCancel: _release,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _JoystickPainter(
            knob: _knob,
            knobRadius: _knobRadius,
            labelX: widget.labelX,
            labelY: widget.labelY,
          ),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({
    required this.knob,
    required this.knobRadius,
    this.labelX,
    this.labelY,
  });

  final Offset knob;
  final double knobRadius;
  final String? labelX;
  final String? labelY;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );
    canvas.drawCircle(
      centre,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.22),
    );

    // Cross-hairs, so the neutral point stays visible under the thumb.
    final hair = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(centre.dx - radius * 0.5, centre.dy),
        Offset(centre.dx + radius * 0.5, centre.dy), hair);
    canvas.drawLine(Offset(centre.dx, centre.dy - radius * 0.5),
        Offset(centre.dx, centre.dy + radius * 0.5), hair);

    final limit = radius - knobRadius;
    final knobCentre = centre + Offset(knob.dx * limit, knob.dy * limit);

    // Travel line from centre to thumb.
    if (knob.distance > 0.02) {
      canvas.drawLine(
        centre,
        knobCentre,
        Paint()
          ..color = AlatooColors.crimson.withValues(alpha: 0.55)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawCircle(
      knobCentre,
      knobRadius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFD7DEEC)],
        ).createShader(
          Rect.fromCircle(center: knobCentre, radius: knobRadius),
        ),
    );
    canvas.drawCircle(
      knobCentre,
      knobRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AlatooColors.navy.withValues(alpha: 0.35),
    );

    _label(canvas, labelY, Offset(centre.dx, 10), size);
    _label(canvas, labelX, Offset(size.width - 12, centre.dy), size,
        alignRight: true);
  }

  void _label(Canvas canvas, String? text, Offset at, Size size,
      {bool alignRight = false}) {
    if (text == null) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 10,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      alignRight
          ? Offset(at.dx - painter.width, at.dy - painter.height / 2)
          : Offset(at.dx - painter.width / 2, at.dy),
    );
  }

  @override
  bool shouldRepaint(_JoystickPainter old) => old.knob != knob;
}
