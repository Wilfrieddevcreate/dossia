import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Anneau de progression animé. [ratio] nul : anneau vide en pointillés
/// (aucune pièce obligatoire).
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.ratio,
    this.size = 48,
    this.stroke = 5,
    this.child,
    this.color,
    this.semanticLabel,
  });

  final double? ratio;
  final double size;
  final double stroke;
  final Widget? child;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final complete = (ratio ?? 0) >= 1;
    final arc =
        color ??
        (complete ? theme.colorScheme.primary : theme.colorScheme.secondary);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: ratio ?? 0),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => CustomPaint(
            painter: _RingPainter(
              value: value,
              stroke: stroke,
              track: palette.muted,
              arc: arc,
              empty: ratio == null,
            ),
            child: child,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.arc,
    required this.empty,
  });

  final double value;
  final double stroke;
  final Color track;
  final Color arc;
  final bool empty;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = rect.deflate(stroke / 2);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (empty) {
      // Pointillés : rien à mesurer.
      const dashes = 24;
      const sweep = 2 * math.pi / dashes;
      for (var i = 0; i < dashes; i++) {
        canvas.drawArc(circle, i * sweep, sweep * 0.55, false, trackPaint);
      }
      return;
    }
    canvas.drawArc(circle, 0, 2 * math.pi, false, trackPaint);
    if (value <= 0) return;
    final arcPaint = Paint()
      ..color = arc
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      circle,
      -math.pi / 2,
      2 * math.pi * value.clamp(0, 1),
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.arc != arc ||
      old.track != track ||
      old.empty != empty;
}

/// Barre de progression arrondie et animée.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.ratio, this.height = 8});

  final double? ratio;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: ratio ?? 0),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => LinearProgressIndicator(
          value: value,
          minHeight: height,
          backgroundColor: palette.muted,
          color: value >= 1
              ? theme.colorScheme.primary
              : theme.colorScheme.secondary,
        ),
      ),
    );
  }
}
