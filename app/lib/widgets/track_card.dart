import 'package:flutter/material.dart';

import '../core/text/time_text.dart';
import '../core/theme/theme.dart';
import '../data/social_repository.dart';
import '../data/user_directory.dart';
import '../data/waveform_cache.dart';
import '../format_duration.dart';
import '../models/track.dart';
import '../playback/playback_controller.dart';
import 'cover_art.dart';
import 'highlighted_text.dart';
import 'like_button.dart';
import 'states.dart';
import 'waveform_view.dart';

enum _OwnerAction { edit, visibility, delete }

/// A track in a list: its cover, its author and title, a big play button, its waveform (press it to play from that
/// place), likes and comments, and how long ago it was posted. A track that is still being processed or that failed
/// says so and cannot be played. The owner also has a menu to edit, hide or delete it.
///
/// The card does not decide which tracks come after this one: when the user presses play, [onPlay] makes the list the
/// queue (see [PlaybackController.playQueue]).
class TrackCard extends StatefulWidget {
  const TrackCard({
    super.key,
    required this.track,
    required this.playback,
    required this.directory,
    required this.waveforms,
    required this.social,
    required this.viewerId,
    required this.onPlay,
    required this.onOpen,
    required this.onOpenUser,
    required this.onNeedLogin,
    this.onChanged,
    this.onEdit,
    this.onDelete,
    this.onToggleVisibility,
    this.clock,
    this.highlight,
  });

  final Track track;
  final PlaybackController playback;
  final UserDirectory directory;
  final WaveformCache waveforms;
  final SocialRepository social;

  /// The logged-in user, or null.
  final String? viewerId;

  /// Starts this track as part of its list. Completes when it is playing.
  final Future<void> Function() onPlay;
  final VoidCallback onOpen;
  final ValueChanged<String> onOpenUser;
  final VoidCallback onNeedLogin;

  /// The track after a change the card made (a like), so the list can keep its copy up to date.
  final ValueChanged<Track>? onChanged;

  /// The owner's menu; an entry is shown for each callback that is given.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleVisibility;

  /// The clock for "3 ngày trước", so a test can fix it.
  final DateTime Function()? clock;

  /// What was searched for: the part of the title that matches is highlighted.
  final String? highlight;

  @override
  State<TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<TrackCard> {
  List<double>? _peaks;

  Track get _track => widget.track;

  @override
  void initState() {
    super.initState();
    _peaks = widget.waveforms.cached(_track);
    _loadPeaks();
    _loadAuthor();
  }

  @override
  void didUpdateWidget(TrackCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != _track.id || oldWidget.track.status != _track.status) {
      _peaks = widget.waveforms.cached(_track);
      _loadPeaks();
    }
    if (oldWidget.track.ownerId != _track.ownerId) _loadAuthor();
  }

  // The list carries no waveform, so a ready card reads its own, once (the cache keeps it for the next time).
  void _loadPeaks() {
    if (_peaks != null || !_track.isReady) return;
    final id = _track.id;
    widget.waveforms.peaksOf(_track).then((peaks) {
      if (mounted && peaks != null && _track.id == id) setState(() => _peaks = peaks);
    });
  }

  void _loadAuthor() {
    if (_track.ownerId.isEmpty) return;
    widget.directory.profile(_track.ownerId).then((_) {}, onError: (_) {});
  }

  bool get _isCurrent => widget.playback.current?.id == _track.id;

  Future<void> _pressPlay() async {
    if (!_track.isReady) return;
    if (_isCurrent) {
      await widget.playback.togglePlay();
    } else {
      await widget.onPlay();
    }
  }

  // Pressing the waveform of a track that is not playing starts it, and then jumps to the place that was pressed.
  Future<void> _seek(double fraction) async {
    if (!_track.isReady) return;
    if (!_isCurrent) {
      await widget.onPlay();
      if (!mounted || !_isCurrent) return;
    }
    await widget.playback.seekFraction(fraction);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.playback, widget.directory]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) => _card(context, compact: constraints.maxWidth < 560),
      ),
    );
  }

  Widget _card(BuildContext context, {required bool compact}) {
    final c = AppColors.of(context);
    final current = _isCurrent;
    final cover = InkWell(
      key: const Key('trackCover'),
      borderRadius: AppRadius.all(AppRadius.md),
      onTap: widget.onOpen,
      child: CoverArt(trackId: _track.id, imageUrl: _track.coverUrl, size: compact ? 88 : 168, radius: AppRadius.md),
    );

    final header = _header(context, compact: compact);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _waveformArea(context),
        const SizedBox(height: AppSpacing.sm),
        _actions(context),
      ],
    );

    return AnimatedContainer(
      duration: AppDurations.normal,
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(color: current ? c.accent.withValues(alpha: 0.55) : c.outline),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [cover, const SizedBox(width: AppSpacing.md), Expanded(child: header)]),
                const SizedBox(height: AppSpacing.md),
                body,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cover,
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [header, const SizedBox(height: AppSpacing.md), body],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _header(BuildContext context, {required bool compact}) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final author = widget.directory.nameOf(_track.ownerId);
    final created = _track.createdAt;
    final playback = widget.playback;
    final error = _isCurrent ? playback.error : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[_playButton(context, size: 56), const SizedBox(width: AppSpacing.md)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (author.isNotEmpty)
                InkWell(
                  key: const Key('trackAuthor'),
                  borderRadius: AppRadius.all(AppRadius.xs),
                  onTap: () => widget.onOpenUser(_track.ownerId),
                  child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: c.textSecondary)),
                )
              else
                const SizedBox(height: 16),
              InkWell(
                key: const Key('trackTitle'),
                borderRadius: AppRadius.all(AppRadius.xs),
                onTap: widget.onOpen,
                child: HighlightedText(_track.title, query: widget.highlight, maxLines: 2, overflow: TextOverflow.ellipsis, style: compact ? text.titleMedium : text.titleLarge),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(error, key: const Key('trackError'), maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: c.error)),
                ),
            ],
          ),
        ),
        if (compact) ...[const SizedBox(width: AppSpacing.sm), _playButton(context, size: 44)],
        if (created != null && !compact) ...[
          const SizedBox(width: AppSpacing.md),
          Text(relativeTime(created, now: widget.clock?.call()), key: const Key('trackAge'), style: text.bodySmall?.copyWith(color: c.textMuted)),
        ],
      ],
    );
  }

  Widget _playButton(BuildContext context, {required double size}) {
    final c = AppColors.of(context);
    final playback = widget.playback;
    final enabled = _track.isReady;
    final loading = _isCurrent && playback.loading;
    final playing = _isCurrent && playback.playing;
    return Semantics(
      button: true,
      enabled: enabled,
      label: playing ? 'Tạm dừng' : 'Phát',
      excludeSemantics: true,
      child: Material(
        color: enabled ? c.accent : c.surfaceHigh,
        shape: const CircleBorder(),
        child: InkWell(
          key: const Key('trackPlayButton'),
          customBorder: const CircleBorder(),
          onTap: enabled ? _pressPlay : null,
          child: SizedBox.square(
            dimension: size,
            child: loading
                ? Padding(padding: EdgeInsets.all(size * 0.28), child: CircularProgressIndicator(strokeWidth: 2.5, color: c.onAccent))
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: size * 0.62,
                    color: enabled ? c.onAccent : c.textMuted,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _waveformArea(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    switch (_track.status) {
      case 'PROCESSING':
        return _Notice(
          key: const Key('trackProcessing'),
          icon: Icons.hourglass_top_rounded,
          message: 'Đang xử lý âm thanh… Bạn có thể phát bài này ngay khi xử lý xong.',
          colour: c.textSecondary,
          showSkeleton: true,
        );
      case 'FAILED':
        return _Notice(
          key: const Key('trackFailed'),
          icon: Icons.error_outline_rounded,
          message: 'Xử lý âm thanh thất bại. Bài hát này không phát được.',
          colour: c.error,
        );
    }
    final peaks = _peaks;
    final playback = widget.playback;
    final label = text.bodySmall?.copyWith(color: c.textMuted, fontFeatures: AppTypography.tabularFigures);
    final total = formatSeconds(_track.durationSeconds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (peaks == null)
          const SkeletonLoader(key: Key('waveformSkeleton'), height: 56, radius: AppRadius.sm)
        else
          ValueListenableBuilder<Duration>(
            valueListenable: playback.position,
            builder: (context, position, _) => ValueListenableBuilder<Duration>(
              valueListenable: playback.duration,
              builder: (context, duration, _) {
                final fraction = _isCurrent && duration.inMilliseconds > 0
                    ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0;
                return WaveformView(
                  peaks: peaks,
                  progress: fraction,
                  durationMs: _track.durationMs,
                  onSeek: _seek,
                  height: 56,
                );
              },
            ),
          ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_isCurrent)
              ValueListenableBuilder<Duration>(
                valueListenable: playback.position,
                builder: (context, position, _) => Text(formatPosition(position.inMilliseconds), key: const Key('trackPosition'), style: label),
              )
            else
              const SizedBox.shrink(),
            Text(total, key: const Key('trackDuration'), style: label),
          ],
        ),
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final isOwner = widget.viewerId != null && widget.viewerId == _track.ownerId;
    final hasMenu = isOwner && (widget.onEdit != null || widget.onDelete != null || widget.onToggleVisibility != null);
    final created = _track.createdAt;
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    return Row(
      children: [
        LikeButton(
          trackId: _track.id,
          liked: _track.isLikedByMe,
          count: _track.likeCount,
          social: widget.social,
          signedIn: widget.viewerId != null,
          onNeedLogin: widget.onNeedLogin,
          onChanged: (state) => widget.onChanged?.call(_track.copyWith(isLikedByMe: state.liked, likeCount: state.likeCount)),
        ),
        const SizedBox(width: AppSpacing.xs),
        InkWell(
          key: const Key('commentCountButton'),
          borderRadius: AppRadius.all(AppRadius.pill),
          onTap: widget.onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 20, color: c.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  formatCount(_track.commentCount),
                  key: const Key('commentCount'),
                  style: text.labelLarge?.copyWith(color: c.textSecondary, fontFeatures: AppTypography.tabularFigures),
                ),
              ],
            ),
          ),
        ),
        // The things at the end go to the next line when there is no room (a narrow phone, a private track).
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              children: [
                if (compact && created != null)
                  Text(relativeTime(created, now: widget.clock?.call()), key: const Key('trackAge'), style: text.bodySmall?.copyWith(color: c.textMuted)),
                if (_track.isPrivate)
                  const Chip(
                    key: Key('privateChip'),
                    avatar: Icon(Icons.lock_outline_rounded, size: 14),
                    label: Text('Riêng tư'),
                    visualDensity: VisualDensity.compact,
                  ),
                if (hasMenu)
                  PopupMenuButton<_OwnerAction>(
                    key: const Key('trackMenu'),
                    tooltip: 'Tuỳ chọn',
                    onSelected: (action) => switch (action) {
                      _OwnerAction.edit => widget.onEdit?.call(),
                      _OwnerAction.visibility => widget.onToggleVisibility?.call(),
                      _OwnerAction.delete => widget.onDelete?.call(),
                    },
                    itemBuilder: (_) => [
                      if (widget.onEdit != null) const PopupMenuItem(key: Key('editAction'), value: _OwnerAction.edit, child: Text('Chỉnh sửa')),
                      if (widget.onToggleVisibility != null)
                        PopupMenuItem(
                          key: const Key('visibilityAction'),
                          value: _OwnerAction.visibility,
                          child: Text(_track.isPrivate ? 'Chuyển sang công khai' : 'Chuyển sang riêng tư'),
                        ),
                      if (widget.onDelete != null) const PopupMenuItem(key: Key('deleteAction'), value: _OwnerAction.delete, child: Text('Xoá')),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.icon, required this.message, required this.colour, this.showSkeleton = false});

  final IconData icon;
  final String message;
  final Color colour;
  final bool showSkeleton;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: c.surfaceRaised, borderRadius: AppRadius.all(AppRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colour),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colour))),
            ],
          ),
          if (showSkeleton) ...[
            const SizedBox(height: AppSpacing.md),
            const SkeletonLoader(height: 28, radius: AppRadius.sm),
          ],
        ],
      ),
    );
  }
}
