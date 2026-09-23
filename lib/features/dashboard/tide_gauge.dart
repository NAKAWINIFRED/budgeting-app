import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A card whose water level shows how much of this period's income is left.
/// [level] goes from 0 (empty) to 1 (nothing spent). The water rises into
/// place on first load and drifts gently; it stays still if the phone's
/// "reduce motion" accessibility setting is on.
class TideGauge extends StatefulWidget {
  const TideGauge({
    super.key,
    required this.level,
    required this.child,
    this.height = 220,
  });

  final double level;
  final Widget child;
  final double height;

  @override
  State<TideGauge> createState() => _TideGaugeState();
}

class _TideGaugeState extends State<TideGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _wave.stop();
    } else if (!_wave.isAnimating) {
      _wave.repeat();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.level.clamp(0.0, 1.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: widget.height,
        child: ColoredBox(
          color: AppColors.deepWater,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: target),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (context, level, child) => AnimatedBuilder(
              animation: _wave,
              builder: (context, child) => CustomPaint(
                painter: _TidePainter(level: level, phase: _wave.value),
                child: child,
              ),
              child: child,
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _TidePainter extends CustomPainter {
  _TidePainter({required this.level, required this.phase});

  final double level;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (level <= 0) return;

    // Keep a little headroom so the wave's crest is always visible.
    final visualLevel = 0.06 + level * 0.84;
    final baseY = size.height * (1 - visualLevel);
    final angle = phase * 2 * math.pi;

    _drawWave(
      canvas,
      size,
      baseY: baseY - 5,
      amplitude: 6,
      angle: -angle + math.pi / 2,
      color: AppColors.tide.withValues(alpha: 0.35),
    );
    _drawWave(
      canvas,
      size,
      baseY: baseY,
      amplitude: 7,
      angle: angle,
      color: AppColors.tide,
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size, {
    required double baseY,
    required double amplitude,
    required double angle,
    required Color color,
  }) {
    final path = Path()..moveTo(0, size.height);
    for (double x = 0; x <= size.width; x += 4) {
      final y = baseY +
          math.sin((x / size.width) * 2 * math.pi + angle) * amplitude;
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TidePainter old) =>
      old.level != level || old.phase != phase;
}
