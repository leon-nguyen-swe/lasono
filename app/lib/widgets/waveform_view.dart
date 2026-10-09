import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/text/time_text.dart';
import '../core/theme/theme.dart';
import '../core/waveform_contrast.dart';
import 'user_avatar.dart';

/// A comment pinned on the waveform: where it is, who wrote it and what it says.
class WaveformMarker {
  const WaveformMarker({
    required this.id,
    required this.positionMs,
    required this.authorId,
    required this.authorName,
    required this.text,
  });

  final String id;
  final int positionMs;
  final String authorId;
  final String authorName;
  final String text;
}

/// The shape of a track as square bars on a line, with a fainter reflection under them. The part already played has the
/// accent colour, a thin line marks where it is playing, and under the pointer the time that a press would jump to is
/// shown; pressing seeks there. Comments appear as small avatars in the reflection, at their position, and their text
/// floats above when the pointer is on the avatar or when the playing reaches it.
class WaveformView extends StatefulWidget {
  const WaveformView({
    super.key,
    required this.peaks,
    this.progress = 0,
    this.durationMs,
    this.onSeek,
    this.height = 72,
    this.markers = const [],
    this.onMarkerTap,
  });

  /// Heights of the bars, from 0 to 1.
  final List<double> peaks;

  /// How much has been played, from 0 to 1.
  final double progress;

  /// The length of the track. Without it there is no time to show and no place for the comments.
  final int? durationMs;

  /// Called with a fraction (0 to 1) of the width when the user presses. Null makes the view read-only.
  final ValueChanged<double>? onSeek;
  final double height;
  final List<WaveformMarker> markers;
  final ValueChanged<WaveformMarker>? onMarkerTap;

  /// How close (in milliseconds) the playing must be to a comment for its text to appear on its own.
  static const nearMs = 1500;

  /// The width of an avatar on the row of comments; avatars closer than this are shown as one.
  static const markerSize = 22.0;

  static const _bubbleSpace = 40.0;

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  // The peaks as drawn: spread over the range of the track (see [emphasizePeaks]), made again only for new peaks.
  List<double>? _rawPeaks;
  List<double> _shownPeaks = const [];

  List<double> get _peaks {
    if (!identical(_rawPeaks, widget.peaks)) {
      _rawPeaks = widget.peaks;
      _shownPeaks = emphasizePeaks(widget.peaks);
    }
    return _shownPeaks;
  }

  double? _hover; // fraction under the pointer
  WaveformMarker? _pointed; // the comment whose avatar the pointer is on

  bool get _hasMarkers => widget.markers.isNotEmpty && (widget.durationMs ?? 0) > 0;

  WaveformMarker? get _playingNow {
    final duration = widget.durationMs ?? 0;
    if (!_hasMarkers || widget.progress <= 0) return null;
    final at = widget.progress * duration;
    WaveformMarker? best;
    var bestGap = WaveformView.nearMs + 1.0;
    for (final marker in widget.markers) {
      final gap = (marker.positionMs - at).abs();
      if (gap <= WaveformView.nearMs && gap < bestGap) {
        best = marker;
        bestGap = gap;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final shown = _pointed ?? _playingNow;
    return Semantics(
      label: 'Dạng sóng của bài hát',
      value: '${(widget.progress * 100).round()}%',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasMarkers) SizedBox(height: WaveformView._bubbleSpace, child: _bubble(context, shown, width)),
              SizedBox(
                height: widget.height,
                child: MouseRegion(
                  cursor: widget.onSeek == null ? MouseCursor.defer : SystemMouseCursors.click,
                  onHover: (event) => setState(() => _hover = (event.localPosition.dx / width).clamp(0.0, 1.0)),
                  onExit: (_) => setState(() => _hover = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: widget.onSeek == null || width <= 0
                        ? null
                        : (details) => widget.onSeek!((details.localPosition.dx / width).clamp(0.0, 1.0)),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            key: const Key('waveformPaint'),
                            painter: WaveformBarsPainter(
                              peaks: _peaks,
                              progress: widget.progress,
                              hover: _pointed == null ? _hover : null,
                              playedColor: c.waveformPlayed,
                              restColor: c.waveformUnplayed,
                              hoverColor: c.waveformHover,
                              lineColor: c.textPrimary,
                            ),
                          ),
                        ),
                        // The comments sit in the reflection under the bars, each at its place in the track.
                        if (_hasMarkers)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: widget.height * WaveformBarsPainter.topShare + 2,
                            height: WaveformView.markerSize,
                            child: _markerRow(context, width),
                          ),
                        if (_hover != null && _pointed == null && (widget.durationMs ?? 0) > 0)
                          Positioned(
                            top: -2,
                            left: (_hover! * width - 22).clamp(0.0, math.max(0.0, width - 44)).toDouble(),
                            child: _TimeLabel(text: formatPosition((_hover! * widget.durationMs!).round())),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bubble(BuildContext context, WaveformMarker? marker, double width) {
    if (marker == null) return const SizedBox.shrink();
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final x = marker.positionMs / widget.durationMs! * width;
    const bubbleWidth = 260.0;
    final left = (x - bubbleWidth / 2).clamp(0.0, math.max(0.0, width - bubbleWidth)).toDouble();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          bottom: 6,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: bubbleWidth),
            child: Container(
              key: const Key('markerBubble'),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
              decoration: BoxDecoration(
                color: c.surfaceHigh,
                borderRadius: AppRadius.all(AppRadius.md),
                border: Border.all(color: c.outline),
                boxShadow: AppElevation.low(Theme.of(context).brightness),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${marker.authorName} · ${formatPosition(marker.positionMs)}  ', style: text.labelMedium),
                    TextSpan(text: marker.text, style: text.bodySmall?.copyWith(color: c.textPrimary)),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _markerRow(BuildContext context, double width) {
    final duration = widget.durationMs!;
    final sorted = [...widget.markers]..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    // Comments closer together than one avatar share a place: the first is drawn, with how many there are.
    final groups = <List<WaveformMarker>>[];
    double? lastX;
    for (final marker in sorted) {
      final x = (marker.positionMs / duration).clamp(0.0, 1.0) * width;
      if (lastX != null && x - lastX < WaveformView.markerSize) {
        groups.last.add(marker);
      } else {
        groups.add([marker]);
        lastX = x;
      }
    }
    final c = AppColors.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final group in groups)
          Positioned(
            left: ((group.first.positionMs / duration).clamp(0.0, 1.0) * width - WaveformView.markerSize / 2)
                .clamp(0.0, math.max(0.0, width - WaveformView.markerSize))
                .toDouble(),
            top: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _pointed = group.first),
              onExit: (_) => setState(() => _pointed = null),
              child: GestureDetector(
                key: Key('marker-${group.first.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onMarkerTap == null ? null : () => widget.onMarkerTap!(group.first),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.background, width: 1.5)),
                      child: UserAvatar(
                        userId: group.first.authorId,
                        displayName: group.first.authorName,
                        size: WaveformView.markerSize - 3,
                      ),
                    ),
                    if (group.length > 1)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          key: const Key('markerCount'),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(color: c.accent, borderRadius: AppRadius.all(AppRadius.pill)),
                          child: Text(
                            '+${group.length - 1}',
                            style: TextStyle(color: c.onAccent, fontSize: 9, fontWeight: FontWeight.w700, height: 1.4),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return IgnorePointer(
      child: Container(
        key: const Key('hoverTime'),
        width: 44,
        padding: const EdgeInsets.symmetric(vertical: 1),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: AppRadius.all(AppRadius.xs)),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.textPrimary, fontFeatures: AppTypography.tabularFigures)),
      ),
    );
  }
}

/// Draws the bars: square-cornered, standing on a thin line, with a shorter and fainter reflection under each. Those up to
/// [progress] are in the played colour, the rest in the other. A thin line marks the place that is playing now. When the
/// pointer is [hover]ing ahead of the playing, the stretch between them is in the hover colour, and a line marks the pointer.
class WaveformBarsPainter extends CustomPainter {
  const WaveformBarsPainter({
    required this.peaks,
    required this.progress,
    required this.playedColor,
    required this.restColor,
    required this.hoverColor,
    required this.lineColor,
    this.hover,
  });

  /// A silent stretch still shows as a thin line, so the waveform has no holes.
  static const minBarHeight = 3.0;

  /// The part of its slot a bar fills; the rest is the gap between bars.
  static const barFill = 0.7;

  /// The share of the height above the line the bars stand on; the rest is the reflection.
  static const topShare = 0.68;

  /// The reflection is this much of the bar, so it never fills all the room under the line.
  static const reflectionScale = 0.9;

  /// How faint the reflection is, compared with the bar it belongs to.
  static const reflectionOpacity = 0.35;

  final List<double> peaks;
  final double progress;
  final double? hover;
  final Color playedColor;
  final Color restColor;
  final Color hoverColor;
  final Color lineColor;

  double _barWidth(Size size) => math.max(1.0, size.width / peaks.length * barFill);

  /// Where bar [i] is drawn, standing on the line.
  Rect barRect(int i, Size size) {
    final slot = size.width / peaks.length;
    final width = _barWidth(size);
    final baseline = size.height * topShare;
    final height = math.max(minBarHeight, peaks[i].clamp(0.0, 1.0) * baseline);
    return Rect.fromLTWH(i * slot + (slot - width) / 2, baseline - height, width, height);
  }

  /// Where the reflection of bar [i] is drawn, hanging under the line.
  Rect reflectionRect(int i, Size size) {
    final bar = barRect(i, size);
    final room = size.height * (1 - topShare);
    final height = math.min(room, math.max(1.5, bar.height / (size.height * topShare) * room * reflectionScale));
    return Rect.fromLTWH(bar.left, size.height * topShare, bar.width, height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final playedBars = (progress.clamp(0.0, 1.0) * peaks.length).round();
    final hoverBars = hover == null ? 0 : (hover!.clamp(0.0, 1.0) * peaks.length).round();

    Color colourOf(int i) => i < playedBars ? playedColor : (i < hoverBars ? hoverColor : restColor);

    for (var i = 0; i < peaks.length; i++) {
      canvas.drawRect(barRect(i, size), Paint()..color = colourOf(i));
    }
    for (var i = 0; i < peaks.length; i++) {
      canvas.drawRect(reflectionRect(i, size), Paint()..color = colourOf(i).withValues(alpha: reflectionOpacity));
    }
    // The line the bars stand on.
    canvas.drawRect(Rect.fromLTWH(0, size.height * topShare - 0.5, size.width, 1), Paint()..color = lineColor.withValues(alpha: 0.16));

    if (progress > 0 && progress < 1) {
      final x = progress * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()..color = lineColor.withValues(alpha: 0.9)..strokeWidth = 1.5);
    }
    if (hover != null) {
      final x = hover!.clamp(0.0, 1.0) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()..color = lineColor.withValues(alpha: 0.5)..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(WaveformBarsPainter old) =>
      old.progress != progress ||
      old.hover != hover ||
      old.playedColor != playedColor ||
      old.restColor != restColor ||
      old.hoverColor != hoverColor ||
      old.lineColor != lineColor ||
      old.peaks.length != peaks.length ||
      !identical(old.peaks, peaks);
}
