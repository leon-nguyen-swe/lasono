import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/text/time_text.dart';
import '../core/theme/theme.dart';
import '../data/repository_exception.dart';
import '../data/user_directory.dart';
import '../models/comment.dart';
import 'states.dart';
import 'user_avatar.dart';

/// The box to write a comment. A comment belongs to a moment of the track: the box says which ("Bình luận tại 1:23"),
/// takes the moment where the track is playing when the user starts to write, and lets them change it by pressing
/// the time.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.viewerId,
    required this.viewerName,
    required this.durationMs,
    required this.livePosition,
    required this.onSubmit,
    required this.onNeedLogin,
  });

  /// The logged-in user, or null: then the box asks to log in instead of taking text.
  final String? viewerId;
  final String? viewerName;

  /// The length of the track, which no comment may go past. Null when it is not known.
  final int? durationMs;

  /// Where this track is playing now, or null when it is not the one that plays (then a new comment starts at 0:00).
  final ValueListenable<Duration>? livePosition;

  /// Sends the comment. A [RepositoryException] it throws is shown to the user and the text is kept.
  final Future<void> Function(int positionMs, String text) onSubmit;
  final VoidCallback onNeedLogin;

  static const maxLength = 500;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final _text = TextEditingController();
  int? _pinnedMs; // the moment chosen, once the user has started to write or has set one by hand
  bool _manual = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int _clamp(int ms) {
    final end = widget.durationMs;
    if (ms < 0) return 0;
    return end != null && ms > end ? end : ms;
  }

  int get _livePositionMs => _clamp(widget.livePosition?.value.inMilliseconds ?? 0);

  void _onTextChanged() {
    final empty = _text.text.trim().isEmpty;
    setState(() {
      if (empty && !_manual) {
        _pinnedMs = null;
      } else if (!empty && _pinnedMs == null) {
        // The moment is the one where the track is when the user starts to write, not where it is when they send.
        _pinnedMs = _livePositionMs;
      }
    });
  }

  int get _length => _text.text.trim().runes.length;
  bool get _canSend => !_sending && _length >= 1 && _length <= CommentComposer.maxLength;

  Future<void> _send() async {
    if (!_canSend) return;
    final messenger = ScaffoldMessenger.of(context);
    final text = _text.text.trim();
    final position = _pinnedMs ?? _livePositionMs;
    setState(() => _sending = true);
    try {
      await widget.onSubmit(position, text);
      if (!mounted) return;
      _manual = false;
      _pinnedMs = null;
      _text.clear();
    } on RepositoryException catch (e) {
      if (e.needsLogin) {
        if (mounted) widget.onNeedLogin();
      } else {
        showToastOn(messenger, errorMessageFor(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _chooseMoment(int current) async {
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => _MomentDialog(initialMs: current, durationMs: widget.durationMs),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _pinnedMs = _clamp(chosen);
      _manual = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = widget.viewerId != null;
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final tooLong = _length > CommentComposer.maxLength;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (signedIn)
          UserAvatar(userId: widget.viewerId!, displayName: widget.viewerName ?? '', size: 40)
        else
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.surfaceHigh, shape: BoxShape.circle),
            child: Icon(Icons.person_outline_rounded, color: c.textSecondary),
          ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: signedIn ? null : widget.onNeedLogin,
                child: AbsorbPointer(
                  absorbing: !signedIn,
                  child: TextField(
                    key: const Key('commentField'),
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: signedIn ? 'Viết bình luận…' : 'Đăng nhập để bình luận',
                      errorText: tooLong ? 'Tối đa ${CommentComposer.maxLength} ký tự' : null,
                      suffixIcon: IconButton(
                        key: const Key('sendComment'),
                        tooltip: 'Gửi bình luận',
                        onPressed: _canSend ? _send : null,
                        icon: _sending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_rounded),
                      ),
                    ),
                  ),
                ),
              ),
              if (signedIn) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    ValueListenableBuilder<Duration>(
                      valueListenable: widget.livePosition ?? ValueNotifier(Duration.zero),
                      builder: (context, _, _) {
                        final shown = _pinnedMs ?? _livePositionMs;
                        return ActionChip(
                          key: const Key('momentChip'),
                          avatar: const Icon(Icons.schedule_rounded, size: 16),
                          label: Text('Bình luận tại ${formatPosition(shown)}'),
                          onPressed: () => _chooseMoment(shown),
                        );
                      },
                    ),
                    if (_manual && widget.livePosition != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      TextButton(
                        key: const Key('useLivePosition'),
                        onPressed: () => setState(() {
                          _manual = false;
                          _pinnedMs = _text.text.trim().isEmpty ? null : _livePositionMs;
                        }),
                        child: const Text('Dùng vị trí đang phát'),
                      ),
                    ],
                    const Spacer(),
                    if (_length > 400)
                      Text(
                        '$_length/${CommentComposer.maxLength}',
                        key: const Key('commentCounter'),
                        style: text.bodySmall?.copyWith(color: tooLong ? c.error : c.textSecondary),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MomentDialog extends StatefulWidget {
  const _MomentDialog({required this.initialMs, required this.durationMs});

  final int initialMs;
  final int? durationMs;

  @override
  State<_MomentDialog> createState() => _MomentDialogState();
}

class _MomentDialogState extends State<_MomentDialog> {
  late final _field = TextEditingController(text: formatPosition(widget.initialMs));
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _ok() {
    final ms = parsePosition(_field.text);
    final end = widget.durationMs;
    if (ms == null) {
      setState(() => _error = 'Nhập thời điểm dạng m:ss, ví dụ 1:23');
    } else if (end != null && ms > end) {
      setState(() => _error = 'Tối đa ${formatPosition(end)}');
    } else {
      Navigator.of(context).pop(ms);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chọn thời điểm'),
      content: TextField(
        key: const Key('momentField'),
        controller: _field,
        autofocus: true,
        onSubmitted: (_) => _ok(),
        decoration: InputDecoration(hintText: 'm:ss', errorText: _error),
      ),
      actions: [
        TextButton(key: const Key('momentCancel'), onPressed: () => Navigator.of(context).pop(), child: const Text('Huỷ')),
        FilledButton(key: const Key('momentOk'), onPressed: _ok, child: const Text('Chọn')),
      ],
    );
  }
}

/// The comments of a track, in the order they are given. Pressing the time of a comment jumps to it in the track. The
/// author of a comment, and the owner of the track, can delete it.
class CommentList extends StatefulWidget {
  const CommentList({
    super.key,
    required this.comments,
    required this.directory,
    required this.viewerId,
    required this.trackOwnerId,
    required this.onSeekTo,
    required this.onDelete,
    this.clock,
  });

  final List<Comment> comments;
  final UserDirectory directory;
  final String? viewerId;
  final String trackOwnerId;

  /// Called with the position (milliseconds) of the comment whose time was pressed.
  final ValueChanged<int> onSeekTo;

  /// Deletes a comment after the user confirmed. A [RepositoryException] it throws is shown.
  final Future<void> Function(Comment comment) onDelete;

  /// The clock for "3 ngày trước", so a test can fix it.
  final DateTime Function()? clock;

  @override
  State<CommentList> createState() => _CommentListState();
}

class _CommentListState extends State<CommentList> {
  @override
  void initState() {
    super.initState();
    _askForNames();
  }

  @override
  void didUpdateWidget(CommentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _askForNames();
  }

  // One request for all the authors the directory does not know yet; the list redraws when they arrive.
  void _askForNames() {
    widget.directory.profiles(widget.comments.map((c) => c.authorId)).then((_) {}, onError: (_) {});
  }

  bool _canDelete(Comment comment) {
    final viewer = widget.viewerId;
    return viewer != null && (viewer == comment.authorId || viewer == widget.trackOwnerId);
  }

  Future<void> _delete(Comment comment) async {
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showConfirmDialog(
      context,
      title: 'Xoá bình luận?',
      message: 'Bình luận sẽ bị xoá khỏi bài hát.',
      confirmLabel: 'Xoá',
      destructive: true,
    );
    if (!sure) return;
    try {
      await widget.onDelete(comment);
    } on RepositoryException catch (e) {
      showToastOn(messenger, errorMessageFor(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.directory,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final comment in widget.comments)
            _CommentTile(
              key: Key('comment-${comment.id}'),
              comment: comment,
              name: widget.directory.nameOf(comment.authorId, fallback: '…'),
              now: widget.clock?.call(),
              canDelete: _canDelete(comment),
              onSeekTo: () => widget.onSeekTo(comment.positionMs),
              onDelete: () => _delete(comment),
            ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.name,
    required this.now,
    required this.canDelete,
    required this.onSeekTo,
    required this.onDelete,
  });

  final Comment comment;
  final String name;
  final DateTime? now;
  final bool canDelete;
  final VoidCallback onSeekTo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final created = comment.createdAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(userId: comment.authorId, displayName: name, size: 36),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  children: [
                    Text(name, style: text.titleSmall),
                    InkWell(
                      key: const Key('commentTime'),
                      borderRadius: AppRadius.all(AppRadius.xs),
                      onTap: onSeekTo,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                        child: Text(
                          'tại ${formatPosition(comment.positionMs)}',
                          style: text.labelMedium?.copyWith(color: c.accent, fontFeatures: AppTypography.tabularFigures),
                        ),
                      ),
                    ),
                    if (created != null) Text(relativeTime(created, now: now), style: text.bodySmall?.copyWith(color: c.textMuted)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text, style: text.bodyMedium),
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              key: const Key('deleteComment'),
              tooltip: 'Xoá bình luận',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}
