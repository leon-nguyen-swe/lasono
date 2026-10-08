import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../data/user_directory.dart';
import '../format_duration.dart';
import '../models/track.dart';
import '../playback/playback_controller.dart';
import '../widgets/cover_art.dart';

/// The bar at the bottom of every page, once something is playing: the cover, the name of the track and of its
/// author (press either to open it), previous, play or pause, next, a bar to seek in, the times and the volume.
/// On a narrow screen it shrinks to a mini bar: the cover, the names, and play or pause, with a thin line of
/// progress on top.
class PlayerBar extends StatefulWidget {
  const PlayerBar({
    super.key,
    required this.playback,
    required this.directory,
    required this.onOpenTrack,
    required this.onOpenUser,
  });

  final PlaybackController playback;
  final UserDirectory directory;
  final ValueChanged<Track> onOpenTrack;
  final ValueChanged<String> onOpenUser;

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  String? _askedFor;

  // The name of the author is asked for once per track shown, and the bar redraws when it arrives.
  void _ensureAuthor(Track? track) {
    final owner = track?.ownerId;
    if (owner == null || owner.isEmpty || owner == _askedFor) return;
    _askedFor = owner;
    widget.directory.profile(owner).then((_) {}, onError: (_) {
      // Not being able to read a name is not worth a message: the line stays empty.
      _askedFor = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.playback, widget.directory]),
      builder: (context, _) {
        final track = widget.playback.current;
        _ensureAuthor(track);
        final size = context.screenSize;
        final compact = size == ScreenSize.compact;
        final content = track == null
            ? const SizedBox.shrink(key: Key('playerBarEmpty'))
            : Material(
                key: const Key('playerBar'),
                color: c.surface,
                elevation: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.outline)),
                    boxShadow: AppElevation.medium(Theme.of(context).brightness).map((s) => BoxShadow(
                          color: s.color,
                          blurRadius: s.blurRadius,
                          offset: Offset(0, -s.offset.dy),
                        )).toList(),
                  ),
                  child: SafeArea(
                    top: false,
                    child: compact ? _mini(context, track) : _full(context, track, showVolume: size == ScreenSize.expanded),
                  ),
                ),
              );
        return AnimatedSize(
          duration: AppDurations.normal,
          curve: AppCurves.standard,
          alignment: Alignment.bottomCenter,
          child: content,
        );
      },
    );
  }

  // -- the parts -----------------------------------------------------------------------------------------------

  Widget _titleAndAuthor(BuildContext context, Track track) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final author = widget.directory.nameOf(track.ownerId);
    final error = widget.playback.error;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Pressable(
          key: const Key('playerTitle'),
          onTap: () => widget.onOpenTrack(track),
          child: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
        ),
        if (error != null)
          Text(error, key: const Key('playerError'), maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: c.error))
        else if (author.isNotEmpty)
          _Pressable(
            key: const Key('playerArtist'),
            onTap: () => widget.onOpenUser(track.ownerId),
            child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
          ),
      ],
    );
  }

  Widget _playPause(BuildContext context, {double size = 44}) {
    final c = AppColors.of(context);
    final playback = widget.playback;
    final failed = playback.error != null;
    return Semantics(
      button: true,
      label: playback.playing ? 'Tạm dừng' : 'Phát',
      excludeSemantics: true,
      child: Material(
        color: c.accent,
        shape: const CircleBorder(),
        child: InkWell(
          key: const Key('playPauseButton'),
          customBorder: const CircleBorder(),
          onTap: playback.togglePlay,
          child: SizedBox.square(
            dimension: size,
            child: playback.loading
                ? Padding(
                    padding: EdgeInsets.all(size * 0.28),
                    child: CircularProgressIndicator(key: const Key('playerLoading'), strokeWidth: 2.5, color: c.onAccent),
                  )
                : Icon(
                    failed ? Icons.refresh_rounded : (playback.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    color: c.onAccent,
                    size: size * 0.6,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _full(BuildContext context, Track track, {required bool showVolume}) {
    final playback = widget.playback;
    return SizedBox(
      height: 76,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.contentMaxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Row(
              children: [
                SizedBox(
                  width: 280,
                  child: Row(
                    children: [
                      CoverArt(key: const Key('playerCover'), trackId: track.id, imageUrl: track.coverUrl, size: 52, radius: AppRadius.sm),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: _titleAndAuthor(context, track)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                IconButton(
                  key: const Key('previousButton'),
                  tooltip: 'Bài trước',
                  onPressed: playback.previous,
                  icon: const Icon(Icons.skip_previous_rounded, size: 28),
                ),
                const SizedBox(width: AppSpacing.xs),
                _playPause(context),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  key: const Key('nextButton'),
                  tooltip: 'Bài kế tiếp',
                  onPressed: playback.hasNext ? playback.next : null,
                  icon: const Icon(Icons.skip_next_rounded, size: 28),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: _SeekBar(playback: playback)),
                if (showVolume) ...[
                  const SizedBox(width: AppSpacing.lg),
                  _Volume(playback: playback),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mini(BuildContext context, Track track) {
    final c = AppColors.of(context);
    final playback = widget.playback;
    return InkWell(
      key: const Key('miniPlayer'),
      onTap: () => widget.onOpenTrack(track),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<Duration>(
            valueListenable: playback.position,
            builder: (context, position, _) => ValueListenableBuilder<Duration>(
              valueListenable: playback.duration,
              builder: (context, duration, _) {
                final fraction = duration.inMilliseconds == 0 ? 0.0 : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
                return LinearProgressIndicator(
                  key: const Key('miniProgress'),
                  value: fraction,
                  minHeight: 2,
                  color: c.accent,
                  backgroundColor: c.waveformUnplayed.withValues(alpha: 0.4),
                );
              },
            ),
          ),
          SizedBox(
            height: 62,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  CoverArt(key: const Key('playerCover'), trackId: track.id, imageUrl: track.coverUrl, size: 44, radius: AppRadius.sm),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _titleAndAuthor(context, track)),
                  IconButton(
                    key: const Key('nextButton'),
                    tooltip: 'Bài kế tiếp',
                    onPressed: playback.hasNext ? playback.next : null,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  _playPause(context, size: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text that can be pressed, with an underline under the pointer, so the user can tell it opens something.
class _Pressable extends StatefulWidget {
  const _Pressable({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: DefaultTextStyle.merge(
          style: TextStyle(decoration: _hover ? TextDecoration.underline : TextDecoration.none),
          child: widget.child,
        ),
      ),
    );
  }
}

/// The time played, a bar to drag or press, and the length. The times use digits of one width so they do not jitter.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.playback});

  final PlaybackController playback;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragFraction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodySmall?.copyWith(fontFeatures: AppTypography.tabularFigures);
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.playback.position,
      builder: (context, position, _) => ValueListenableBuilder<Duration>(
        valueListenable: widget.playback.duration,
        builder: (context, duration, _) {
          final total = duration.inMilliseconds;
          final canSeek = total > 0 && !widget.playback.loading;
          final fraction = _dragFraction ?? (total == 0 ? 0.0 : (position.inMilliseconds / total).clamp(0.0, 1.0));
          final shown = _dragFraction == null ? position : Duration(milliseconds: (total * _dragFraction!).round());
          return Row(
            children: [
              SizedBox(width: 44, child: Text(formatSeconds(shown.inMilliseconds / 1000), key: const Key('playerPosition'), style: text, textAlign: TextAlign.right)),
              Expanded(
                child: Slider(
                  key: const Key('seekSlider'),
                  value: fraction.toDouble(),
                  onChanged: canSeek ? (value) => setState(() => _dragFraction = value) : null,
                  onChangeEnd: canSeek
                      ? (value) {
                          setState(() => _dragFraction = null);
                          widget.playback.seekFraction(value);
                        }
                      : null,
                ),
              ),
              SizedBox(width: 44, child: Text(formatSeconds(total / 1000), key: const Key('playerDuration'), style: text)),
            ],
          );
        },
      ),
    );
  }
}

class _Volume extends StatelessWidget {
  const _Volume({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('volumeButton'),
            tooltip: playback.muted ? 'Bật tiếng' : 'Tắt tiếng',
            onPressed: playback.toggleMute,
            icon: Icon(
              playback.muted
                  ? Icons.volume_off_rounded
                  : (playback.volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
            ),
          ),
          SizedBox(
            width: 96,
            child: Slider(
              key: const Key('volumeSlider'),
              value: playback.volume,
              onChanged: playback.setVolume,
            ),
          ),
        ],
      ),
    );
  }
}
