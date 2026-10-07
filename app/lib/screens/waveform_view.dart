import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Draws the peaks of a track as vertical bars. The bars up to [progress] (0 to 1) are drawn in
/// the "played" colour. A tap calls [onSeek] with the tapped position as a fraction of the width.
class WaveformView extends StatelessWidget {
  const WaveformView({
    super.key,
    required this.peaks,
    this.progress = 0,
    this.onSeek,
    this.height = 64,
  });

  final List<double> peaks;
  final double progress;
  final ValueChanged<double>? onSeek;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final width = constraints.maxWidth;
          if (width > 0) onSeek?.call((details.localPosition.dx / width).clamp(0.0, 1.0));
        },
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: WaveformPainter(
              peaks: peaks,
              progress: progress,
              playedColor: colors.primary,
              restColor: colors.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.playedColor,
    required this.restColor,
  });

  // A silent stretch still shows as a thin line, so the waveform has no holes.
  static const _minBarHeight = 2.0;
  // The part of its slot a bar fills; the rest is the gap between bars.
  static const _barFill = 0.7;

  final List<double> peaks;
  final double progress;
  final Color playedColor;
  final Color restColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;

    final slot = size.width / peaks.length;
    final barWidth = slot * _barFill;
    final playedBars = (progress.clamp(0.0, 1.0) * peaks.length).round();
    final played = Paint()..color = playedColor;
    final rest = Paint()..color = restColor;

    for (var i = 0; i < peaks.length; i++) {
      final barHeight = math.max(_minBarHeight, peaks[i].clamp(0.0, 1.0) * size.height);
      final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * slot + (slot - barWidth) / 2,
          (size.height - barHeight) / 2,
          barWidth,
          barHeight,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(bar, i < playedBars ? played : rest);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) =>
      !listEquals(oldDelegate.peaks, peaks) ||
      oldDelegate.progress != progress ||
      oldDelegate.playedColor != playedColor ||
      oldDelegate.restColor != restColor;
}
