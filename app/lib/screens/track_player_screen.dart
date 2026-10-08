import 'package:flutter/material.dart';

import '../api/profile_api.dart';
import '../api/track_api.dart';
import '../auth/session_controller.dart';
import '../models/track.dart';
import '../player_service.dart';
import 'edit_track_dialog.dart';
import 'profile_screen.dart';
import 'track_playback.dart';

/// Plays one track chosen from the list. Closing the screen stops the playback,
/// because [PlayerControls] stops the player when it is removed. The owner of the
/// track can also change or delete it here.
class TrackPlayerScreen extends StatefulWidget {
  const TrackPlayerScreen({
    super.key,
    required this.track,
    required this.api,
    required this.player,
    required this.session,
    this.profileApi,
    this.onChanged,
  });

  final Track track;
  final TrackApi api;
  final PlayerService player;
  final SessionController session;

  /// Needed to link to the profile of the owner; without it there is no link.
  final ProfileApi? profileApi;

  /// Called after the owner changed or deleted the track, so the list can load again.
  final VoidCallback? onChanged;

  @override
  State<TrackPlayerScreen> createState() => _TrackPlayerScreenState();
}

class _TrackPlayerScreenState extends State<TrackPlayerScreen> {
  late Track _track = widget.track;
  bool _deleting = false;

  // Only the owner sees the buttons; the server decides again on every request.
  bool get _isOwner {
    final account = widget.session.account;
    return account != null &&
        _track.ownerId.isNotEmpty &&
        account.userId == _track.ownerId;
  }

  Future<void> _edit() async {
    final updated = await showDialog<Track>(
      context: context,
      builder: (_) => EditTrackDialog(track: _track, api: widget.api),
    );
    if (updated == null || !mounted) return;
    setState(() => _track = updated);
    widget.onChanged?.call();
  }

  void _openOwnerProfile(ProfileApi profileApi) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: _track.ownerId,
          session: widget.session,
          trackApi: widget.api,
          profileApi: profileApi,
          player: widget.player,
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this track?'),
        content: const Text('The track and its audio are removed for good.'),
        actions: [
          TextButton(
            key: const Key('cancelDeleteButton'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmDeleteButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.api.deleteTrack(_track.id);
      if (!mounted) return;
      widget.onChanged?.call();
      Navigator.of(context).pop();
    } on TrackApiException catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_track.title),
          actions: [
            if (_isOwner) ...[
              IconButton(
                key: const Key('editAction'),
                icon: const Icon(Icons.edit),
                tooltip: 'Edit',
                onPressed: _deleting ? null : _edit,
              ),
              IconButton(
                key: const Key('deleteAction'),
                icon: const Icon(Icons.delete),
                tooltip: 'Delete',
                onPressed: _deleting ? null : _delete,
              ),
            ],
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_track.description.isNotEmpty) Text(_track.description),
            if (widget.profileApi case final profileApi? when _track.ownerId.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('ownerProfileAction'),
                  icon: const Icon(Icons.person),
                  label: const Text('View profile'),
                  onPressed: () => _openOwnerProfile(profileApi),
                ),
              ),
            TrackPlayback(track: _track, api: widget.api, player: widget.player),
          ],
        ),
      ),
    );
  }
}
