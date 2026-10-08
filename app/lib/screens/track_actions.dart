import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../data/app_repositories.dart';
import '../data/repository_exception.dart';
import '../models/track.dart';
import '../shell/app_context.dart';
import '../widgets/states.dart';
import '../widgets/track_card.dart';

/// Opens the form to change a track (title, description, visibility). Gives the changed track when it was saved, or null
/// when the user cancelled. Only what changed is sent, so a change made somewhere else in the meantime is not undone.
Future<Track?> showEditTrack(BuildContext context, Track track) => showDialog<Track>(
      context: context,
      builder: (_) => _EditTrackDialog(track: track, repos: context.repos),
    );

/// Makes a public track private and a private one public. Gives the changed track, or null when it could not be done (a
/// message says why).
Future<Track?> toggleTrackVisibility(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.of(context);
  final repos = context.repos;
  final makePrivate = !track.isPrivate;
  try {
    final updated = await repos.tracks.updateTrack(track.id, visibility: makePrivate ? 'PRIVATE' : 'PUBLIC');
    showToastOn(messenger, makePrivate ? 'Bài hát đã chuyển sang riêng tư.' : 'Bài hát đã được công khai.');
    // The server answers with the track as a list does not have it: keep what the list knows (counts, the owner's name).
    return track.copyWith(visibility: updated.visibility);
  } on RepositoryException catch (e) {
    showToastOn(messenger, errorMessageFor(e), error: true);
    return null;
  }
}

/// Asks "are you sure?", then deletes the track. True when it was deleted. A track that is still being processed cannot
/// be deleted yet: the message says to try again later.
Future<bool> confirmAndDeleteTrack(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.of(context);
  final repos = context.repos;
  final playback = context.playback;
  final sure = await showConfirmDialog(
    context,
    title: 'Xoá bài hát?',
    message: '"${track.title}" và âm thanh của nó sẽ bị xoá vĩnh viễn.',
    confirmLabel: 'Xoá',
    destructive: true,
  );
  if (!sure) return false;
  try {
    await repos.tracks.deleteTrack(track.id);
    if (playback.current?.id == track.id) await playback.stop();
    showToastOn(messenger, 'Đã xoá bài hát.');
    return true;
  } on RepositoryException catch (e) {
    final message = e.kind == RepositoryErrorKind.conflict
        ? 'Bài hát đang được xử lý. Hãy thử xoá lại sau ít phút.'
        : errorMessageFor(e);
    showToastOn(messenger, message, error: true);
    return false;
  }
}

/// A [TrackCard] wired to the app: pressing play makes the list the queue, the heart, the author and the title go where
/// they should, and the owner's menu edits, hides and deletes. [onChanged] and [onDeleted] let the list keep its copy.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
    required this.sourceId,
    this.onChanged,
    this.onDeleted,
  });

  final Track track;

  /// The whole list the track is in, which becomes the queue when it is played.
  final List<Track> queue;
  final int index;

  /// A name for the list, so the queue can grow when the list loads another page.
  final String sourceId;
  final ValueChanged<Track>? onChanged;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final repos = context.repos;
    final playback = context.playback;

    void changed(Track updated) {
      playback.replaceTrack(updated);
      onChanged?.call(updated);
    }

    return TrackCard(
      track: track,
      playback: playback,
      directory: repos.directory,
      waveforms: repos.waveforms,
      social: repos.social,
      viewerId: context.viewerId,
      onPlay: () => playback.playQueue(queue, startIndex: index, sourceId: sourceId),
      onOpen: () => context.openTrack(track.id),
      onOpenUser: context.openUser,
      onNeedLogin: context.askToLogin,
      onChanged: changed,
      onEdit: () async {
        final updated = await showEditTrack(context, track);
        if (updated != null) changed(track.copyWith(title: updated.title, description: updated.description, visibility: updated.visibility));
      },
      onToggleVisibility: () async {
        final updated = await toggleTrackVisibility(context, track);
        if (updated != null) changed(updated);
      },
      onDelete: () async {
        if (await confirmAndDeleteTrack(context, track)) onDeleted?.call();
      },
    );
  }
}

class _EditTrackDialog extends StatefulWidget {
  const _EditTrackDialog({required this.track, required this.repos});

  final Track track;
  final AppRepositories repos;

  @override
  State<_EditTrackDialog> createState() => _EditTrackDialogState();
}

class _EditTrackDialogState extends State<_EditTrackDialog> {
  late final _title = TextEditingController(text: widget.track.title);
  late final _description = TextEditingController(text: widget.track.description);
  late bool _private = widget.track.isPrivate;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final track = widget.track;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Hãy nhập tiêu đề.');
      return;
    }
    final visibility = _private ? 'PRIVATE' : 'PUBLIC';
    // Only what changed is sent.
    final newTitle = title == track.title ? null : title;
    final newDescription = _description.text == track.description ? null : _description.text;
    final newVisibility = visibility == track.visibility ? null : visibility;
    if (newTitle == null && newDescription == null && newVisibility == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.repos.tracks.updateTrack(
        track.id,
        title: newTitle,
        description: newDescription,
        visibility: newVisibility,
      );
      if (mounted) Navigator.of(context).pop(updated);
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = errorMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      title: const Text('Chỉnh sửa bài hát'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('editTitleField'),
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Tiêu đề'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('editDescriptionField'),
                controller: _description,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Mô tả'),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                key: const Key('editPrivateSwitch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Riêng tư'),
                subtitle: const Text('Chỉ mình bạn thấy và nghe được'),
                value: _private,
                onChanged: _saving ? null : (value) => setState(() => _private = value),
              ),
              if (_error != null) Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_error!, key: const Key('editError'), style: TextStyle(color: c.error)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(key: const Key('cancelEditButton'), onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Huỷ')),
        FilledButton(key: const Key('saveEditButton'), onPressed: _saving ? null : _save, child: const Text('Lưu')),
      ],
    );
  }
}
