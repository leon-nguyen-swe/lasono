import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/text/time_text.dart';
import '../core/theme/theme.dart';
import '../data/repository_exception.dart';
import '../models/comment.dart';
import '../models/track.dart';
import '../shell/app_context.dart';
import '../shell/app_shell.dart';
import '../widgets/comments.dart';
import '../widgets/cover_art.dart';
import '../widgets/like_button.dart';
import '../widgets/states.dart';
import '../widgets/waveform_view.dart';
import 'track_actions.dart';

/// One track, in full: the cover, the big waveform with the comments on it, the actions, and the comments below.
///
/// While the server is still processing the audio the page shows that, and asks again every few seconds until the
/// track is ready (or failed), so a user who has just uploaded sees it change by itself.
class TrackPage extends StatefulWidget {
  const TrackPage({super.key, required this.trackId, this.pollEvery = const Duration(seconds: 3)});

  final String trackId;

  /// How often a track that is being processed is asked for again.
  final Duration pollEvery;

  /// How many comments are read at a time for the list, and for the markers on the waveform.
  static const listPage = 20;
  static const markerPage = 100;

  @override
  State<TrackPage> createState() => _TrackPageState();
}

enum _OwnerAction { edit, visibility, delete }

class _TrackPageState extends State<TrackPage> {
  Track? _track;
  Object? _error;
  bool _loading = true;
  List<double>? _peaks;
  Timer? _poll;
  bool _started = false;

  List<Comment> _recent = [];
  List<Comment> _marks = [];
  String? _recentCursor;
  bool _commentsLoading = true;
  bool _commentsLoadingMore = false;
  Object? _commentsError;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final repos = context.repos;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final track = await repos.tracks.getTrack(widget.trackId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _track = track;
        _loading = false;
        _peaks = repos.waveforms.cached(track);
      });
      _afterTrackChanged(track);
      _loadComments();
      repos.directory.profile(track.ownerId).then((_) {}, onError: (_) {});
    } on RepositoryException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _afterTrackChanged(Track track) {
    if (track.isReady && _peaks == null) {
      context.repos.waveforms.peaksOf(track).then((peaks) {
        if (mounted && peaks != null && _track?.id == track.id) setState(() => _peaks = peaks);
      });
    }
    _poll?.cancel();
    if (track.status == 'PROCESSING') {
      _poll = Timer.periodic(widget.pollEvery, (_) => _refreshStatus());
    }
  }

  Future<void> _refreshStatus() async {
    final repos = context.repos;
    try {
      final fresh = await repos.tracks.getTrack(widget.trackId);
      if (!mounted) return;
      final before = _track;
      if (before == null || fresh.status == before.status) return;
      setState(() => _track = fresh.copyWith(likeCount: before.likeCount, commentCount: before.commentCount, isLikedByMe: before.isLikedByMe));
      context.playback.replaceTrack(fresh);
      _afterTrackChanged(fresh);
    } on RepositoryException {
      // The next tick asks again; a short failure is not worth telling the user.
    }
  }

  Future<void> _loadComments() async {
    final social = context.repos.social;
    final generation = _generation;
    setState(() {
      _commentsLoading = true;
      _commentsError = null;
    });
    try {
      final results = await Future.wait([
        social.comments(widget.trackId, order: CommentOrder.recent, limit: TrackPage.listPage),
        social.comments(widget.trackId, order: CommentOrder.position, limit: TrackPage.markerPage),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _recent = results[0].items;
        _recentCursor = results[0].nextCursor;
        _marks = results[1].items;
        _commentsLoading = false;
      });
    } on RepositoryException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _commentsError = e;
        _commentsLoading = false;
      });
    }
  }

  Future<void> _moreComments() async {
    final cursor = _recentCursor;
    if (cursor == null || _commentsLoadingMore) return;
    final social = context.repos.social;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _commentsLoadingMore = true);
    try {
      final page = await social.comments(widget.trackId, order: CommentOrder.recent, cursor: cursor, limit: TrackPage.listPage);
      if (!mounted) return;
      final known = {for (final c in _recent) c.id};
      setState(() {
        _recent = [..._recent, ...page.items.where((c) => !known.contains(c.id))];
        _recentCursor = page.nextCursor;
      });
    } on RepositoryException catch (e) {
      showToastOn(messenger, errorMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _commentsLoadingMore = false);
    }
  }

  // ----- playing -----

  bool get _isCurrent => context.playback.current?.id == widget.trackId;

  Future<void> _pressPlay() async {
    final track = _track;
    if (track == null || !track.isReady) return;
    final playback = context.playback;
    if (_isCurrent) {
      await playback.togglePlay();
    } else {
      await playback.playQueue([track], sourceId: 'track:${track.id}');
    }
  }

  Future<void> _playAndSeek(int positionMs) async {
    final track = _track;
    if (track == null || !track.isReady) return;
    final playback = context.playback;
    if (!_isCurrent) {
      await playback.playQueue([track], sourceId: 'track:${track.id}');
      if (!mounted || !_isCurrent) return;
    }
    await playback.seek(Duration(milliseconds: positionMs));
  }

  Future<void> _seekFraction(double fraction) async {
    final track = _track;
    if (track == null || !track.isReady) return;
    final playback = context.playback;
    if (!_isCurrent) {
      await playback.playQueue([track], sourceId: 'track:${track.id}');
      if (!mounted || !_isCurrent) return;
    }
    await playback.seekFraction(fraction);
  }

  // ----- comments -----

  Future<void> _postComment(int positionMs, String text) async {
    final social = context.repos.social;
    final comment = await social.postComment(widget.trackId, positionMs: positionMs, text: text);
    if (!mounted) return;
    setState(() {
      _recent = [comment, ..._recent];
      _marks = [..._marks, comment]..sort((a, b) => a.positionMs.compareTo(b.positionMs));
      _track = _track?.copyWith(commentCount: (_track?.commentCount ?? 0) + 1);
    });
  }

  Future<void> _deleteComment(Comment comment) async {
    await context.repos.social.deleteComment(widget.trackId, comment.id);
    if (!mounted) return;
    setState(() {
      _recent = _recent.where((c) => c.id != comment.id).toList();
      _marks = _marks.where((c) => c.id != comment.id).toList();
      final count = _track?.commentCount ?? 0;
      _track = _track?.copyWith(commentCount: count > 0 ? count - 1 : 0);
    });
  }

  // ----- the owner -----

  Future<void> _edit() async {
    final track = _track!;
    final updated = await showEditTrack(context, track);
    if (updated != null && mounted) _replace(track.copyWith(title: updated.title, description: updated.description, visibility: updated.visibility));
  }

  Future<void> _toggleVisibility() async {
    final updated = await toggleTrackVisibility(context, _track!);
    if (updated != null && mounted) _replace(updated);
  }

  Future<void> _delete() async {
    if (await confirmAndDeleteTrack(context, _track!) && mounted) context.go('/');
  }

  void _replace(Track updated) {
    context.playback.replaceTrack(updated);
    setState(() => _track = updated);
  }

  Future<void> _copyLink() async {
    final messenger = ScaffoldMessenger.of(context);
    final link = Uri.base.resolve('/tracks/${Uri.encodeComponent(widget.trackId)}').toString();
    await Clipboard.setData(ClipboardData(text: link));
    showToastOn(messenger, 'Đã sao chép liên kết.');
  }

  // ----- drawing -----

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _Loading();
    final error = _error;
    if (error != null) {
      final notFound = error is RepositoryException && error.kind == RepositoryErrorKind.notFound;
      return Center(
        child: notFound
            ? EmptyState(
                key: const Key('trackNotFound'),
                icon: Icons.music_off_outlined,
                title: 'Không tìm thấy bài hát',
                message: 'Bài hát không tồn tại, đã bị xoá hoặc đang ở chế độ riêng tư.',
                action: FilledButton(key: const Key('goHomeButton'), onPressed: () => context.go('/'), child: const Text('Về trang chủ')),
              )
            : ErrorState.from(error, key: const Key('trackError'), onRetry: _load),
      );
    }
    final track = _track!;
    return SingleChildScrollView(
      child: PageContainer(
        child: ListenableBuilder(
          listenable: Listenable.merge([context.playback, context.repos.directory]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _hero(context, track),
              const SizedBox(height: AppSpacing.xl),
              _waveformArea(context, track),
              const SizedBox(height: AppSpacing.lg),
              _actions(context, track),
              if (track.description.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(track.description, key: const Key('trackDescription'), style: Theme.of(context).textTheme.bodyLarge),
              ],
              const SizedBox(height: AppSpacing.xxl),
              _commentsSection(context, track),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, Track track) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final playback = context.playback;
    final current = _isCurrent;
    final playing = current && playback.playing;
    final loading = current && playback.loading;
    final author = context.repos.directory.nameOf(track.ownerId, fallback: '…');
    final created = track.createdAt;
    final compact = context.screenSize == ScreenSize.compact;
    final cover = CoverArt(key: const Key('trackCover'), trackId: track.id, imageUrl: track.coverUrl, size: compact ? 120 : 220, radius: AppRadius.lg);

    final playButton = Semantics(
      button: true,
      enabled: track.isReady,
      label: playing ? 'Tạm dừng' : 'Phát',
      excludeSemantics: true,
      child: Material(
        color: track.isReady ? c.accent : c.surfaceHigh,
        shape: const CircleBorder(),
        child: InkWell(
          key: const Key('trackPlayButton'),
          customBorder: const CircleBorder(),
          onTap: track.isReady ? _pressPlay : null,
          child: SizedBox.square(
            dimension: 64,
            child: loading
                ? Padding(padding: const EdgeInsets.all(18), child: CircularProgressIndicator(strokeWidth: 3, color: c.onAccent))
                : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 40, color: track.isReady ? c.onAccent : c.textMuted),
          ),
        ),
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(track.title, key: const Key('trackTitle'), style: compact ? text.headlineSmall : text.headlineLarge),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InkWell(
              key: const Key('trackAuthor'),
              borderRadius: AppRadius.all(AppRadius.xs),
              onTap: track.ownerId.isEmpty ? null : () => context.openUser(track.ownerId),
              child: Text(author, style: text.titleMedium?.copyWith(color: c.textSecondary)),
            ),
            if (created != null) Text('· ${relativeTime(created)}', key: const Key('trackAge'), style: text.bodyMedium?.copyWith(color: c.textMuted)),
            if (track.isPrivate)
              const Chip(
                key: Key('privateChip'),
                avatar: Icon(Icons.lock_outline_rounded, size: 14),
                label: Text('Riêng tư'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        playButton,
      ],
    );

    return compact
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [cover, const SizedBox(height: AppSpacing.lg), info])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [cover, const SizedBox(width: AppSpacing.xl), Expanded(child: info)]);
  }

  Widget _waveformArea(BuildContext context, Track track) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final playback = context.playback;
    if (track.status == 'PROCESSING') {
      return Container(
        key: const Key('trackProcessing'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(color: c.surface, borderRadius: AppRadius.all(AppRadius.lg), border: Border.all(color: c.outline)),
        child: Row(
          children: [
            Icon(Icons.hourglass_top_rounded, color: c.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Đang xử lý âm thanh… Trang sẽ tự cập nhật khi bài hát sẵn sàng.',
                style: text.bodyMedium?.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    if (track.status == 'FAILED') {
      return Container(
        key: const Key('trackFailed'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(color: c.error.withValues(alpha: 0.12), borderRadius: AppRadius.all(AppRadius.lg)),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: c.error),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text('Xử lý âm thanh thất bại. Bài hát này không phát được.', style: text.bodyMedium)),
          ],
        ),
      );
    }
    final peaks = _peaks;
    if (peaks == null) return const SkeletonLoader(key: Key('waveformSkeleton'), height: 96, radius: AppRadius.sm);
    final markers = [
      for (final comment in _marks)
        WaveformMarker(
          id: comment.id,
          positionMs: comment.positionMs,
          authorId: comment.authorId,
          authorName: context.repos.directory.nameOf(comment.authorId, fallback: '…'),
          text: comment.text,
        ),
    ];
    return ValueListenableBuilder<Duration>(
      valueListenable: playback.position,
      builder: (context, position, _) => ValueListenableBuilder<Duration>(
        valueListenable: playback.duration,
        builder: (context, duration, _) {
          final fraction = _isCurrent && duration.inMilliseconds > 0 ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;
          return WaveformView(
            key: const Key('trackWaveform'),
            peaks: peaks,
            progress: fraction,
            durationMs: track.durationMs,
            onSeek: _seekFraction,
            height: 96,
            markers: markers,
            onMarkerTap: (marker) => _playAndSeek(marker.positionMs),
          );
        },
      ),
    );
  }

  Widget _actions(BuildContext context, Track track) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final isOwner = context.viewerId != null && context.viewerId == track.ownerId;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        LikeButton(
          trackId: track.id,
          liked: track.isLikedByMe,
          count: track.likeCount,
          social: context.repos.social,
          signedIn: context.viewerId != null,
          onNeedLogin: context.askToLogin,
          onChanged: (state) => setState(() => _track = track.copyWith(isLikedByMe: state.liked, likeCount: state.likeCount)),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 20, color: c.textSecondary),
            const SizedBox(width: AppSpacing.xs),
            Text(formatCount(track.commentCount), key: const Key('commentCount'), style: text.labelLarge?.copyWith(color: c.textSecondary)),
          ],
        ),
        TextButton.icon(
          key: const Key('copyLinkButton'),
          onPressed: _copyLink,
          icon: const Icon(Icons.link_rounded, size: 20),
          label: const Text('Sao chép liên kết'),
        ),
        if (isOwner)
          PopupMenuButton<_OwnerAction>(
            key: const Key('trackMenu'),
            tooltip: 'Tuỳ chọn',
            onSelected: (action) => switch (action) {
              _OwnerAction.edit => _edit(),
              _OwnerAction.visibility => _toggleVisibility(),
              _OwnerAction.delete => _delete(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(key: Key('editAction'), value: _OwnerAction.edit, child: Text('Chỉnh sửa')),
              PopupMenuItem(
                key: const Key('visibilityAction'),
                value: _OwnerAction.visibility,
                child: Text(track.isPrivate ? 'Chuyển sang công khai' : 'Chuyển sang riêng tư'),
              ),
              const PopupMenuItem(key: Key('deleteAction'), value: _OwnerAction.delete, child: Text('Xoá')),
            ],
          ),
      ],
    );
  }

  Widget _commentsSection(BuildContext context, Track track) {
    final text = Theme.of(context).textTheme;
    final viewerId = context.viewerId;
    final playback = context.playback;
    final account = context.session.account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Bình luận (${formatCount(track.commentCount)})', key: const Key('commentsTitle'), style: text.titleLarge),
        const SizedBox(height: AppSpacing.md),
        CommentComposer(
          viewerId: viewerId,
          viewerName: account?.displayName,
          durationMs: track.durationMs,
          livePosition: _isCurrent ? playback.position : null,
          onSubmit: _postComment,
          onNeedLogin: context.askToLogin,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_commentsLoading)
          const Padding(
            key: Key('commentsLoading'),
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
          )
        else if (_commentsError != null)
          ErrorState.from(_commentsError!, key: const Key('commentsError'), onRetry: _loadComments, compact: true)
        else if (_recent.isEmpty)
          const EmptyState(
            key: Key('commentsEmpty'),
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Chưa có bình luận',
            message: 'Hãy là người đầu tiên bình luận tại một khoảnh khắc của bài hát.',
          )
        else ...[
          CommentList(
            comments: _recent,
            directory: context.repos.directory,
            viewerId: viewerId,
            trackOwnerId: track.ownerId,
            onSeekTo: _playAndSeek,
            onDelete: _deleteComment,
          ),
          if (_recentCursor != null)
            Center(
              child: TextButton(
                key: const Key('moreComments'),
                onPressed: _commentsLoadingMore ? null : _moreComments,
                child: Text(_commentsLoadingMore ? 'Đang tải…' : 'Xem thêm bình luận'),
              ),
            ),
        ],
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const PageContainer(
      child: Column(
        key: Key('trackLoading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLoader(width: 220, height: 220, radius: AppRadius.lg),
              SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader(width: 280, height: 32),
                    SizedBox(height: AppSpacing.md),
                    SkeletonLoader(width: 160, height: 18),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.xl),
          SkeletonLoader(height: 96, radius: AppRadius.sm),
        ],
      ),
    );
  }
}
