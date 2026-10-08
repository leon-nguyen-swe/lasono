import 'dart:async';

import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../api/profile_api.dart';
import '../api/track_api.dart';
import '../auth/session_controller.dart';
import '../format_duration.dart';
import '../models/track.dart';
import '../models/track_page.dart';
import '../player_service.dart';
import 'status_badge.dart';
import 'track_player_screen.dart';

/// A user's public page: the name and the tracks, a page at a time. The user
/// themselves also sees their private tracks here, and can change their name.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.userId,
    required this.session,
    required this.trackApi,
    required this.profileApi,
    required this.player,
  });

  final String userId;
  final SessionController session;
  final TrackApi trackApi;
  final ProfileApi profileApi;
  final PlayerService player;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _profile;
  final _tracks = <Track>[];
  String? _nextCursor;
  String? _error;
  String? _moreError;
  bool _loading = true;
  bool _loadingMore = false;

  // Set by the player screen when the owner changed or deleted a track.
  bool _changedInPlayer = false;

  bool get _isMine => widget.session.account?.userId == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // The profile and the first page are asked together, and shown together.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Profile profile;
      final TrackPage page;
      (profile, page) = await (
        widget.profileApi.getProfile(widget.userId),
        widget.trackApi.listUserTracks(widget.userId),
      ).wait;
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _tracks
          ..clear()
          ..addAll(page.items);
        _nextCursor = page.nextCursor;
        _moreError = null;
      });
    } on ParallelWaitError<(Profile?, TrackPage?), (AsyncError?, AsyncError?)> catch (e) {
      if (!mounted) return;
      final first = e.errors.$1 ?? e.errors.$2;
      setState(() => _error = _message(first?.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object? error) => switch (error) {
        ProfileApiException(:final message) => message,
        TrackApiException(:final message) => message,
        _ => 'Something went wrong',
      };

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (_loadingMore || cursor == null) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await widget.trackApi.listUserTracks(widget.userId, cursor: cursor);
      if (!mounted) return;
      setState(() {
        _tracks.addAll(page.items);
        _nextCursor = page.nextCursor;
      });
    } on TrackApiException catch (e) {
      if (mounted) setState(() => _moreError = e.message);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openPlayer(Track track) async {
    _changedInPlayer = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TrackPlayerScreen(
          track: track,
          api: widget.trackApi,
          player: widget.player,
          session: widget.session,
          onChanged: () => _changedInPlayer = true,
        ),
      ),
    );
    if (mounted && _changedInPlayer) _load();
  }

  Future<void> _rename() async {
    final profile = _profile;
    if (profile == null) return;
    final account = await showDialog<Account>(
      context: context,
      builder: (_) => _RenameDialog(
        currentName: profile.displayName,
        api: widget.profileApi,
      ),
    );
    if (account == null || !mounted) return;
    widget.session.accountChanged(account);
    setState(() => _profile = Profile(userId: profile.userId, displayName: account.displayName));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_profile?.displayName ?? 'Profile'),
          actions: [
            if (_isMine && _profile != null)
              IconButton(
                key: const Key('renameAction'),
                icon: const Icon(Icons.edit),
                tooltip: 'Change name',
                onPressed: _rename,
              ),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading && _profile == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('retryButton'),
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_tracks.isEmpty) return const Center(child: Text('No tracks yet'));

    return ListView(
      children: [
        for (final track in _tracks)
          ListTile(
            key: Key('track-${track.id}'),
            title: Text(track.title),
            subtitle: track.description.isEmpty ? null : Text(track.description),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatSeconds(track.durationSeconds)),
                const SizedBox(width: 12),
                StatusBadge(status: track.status),
              ],
            ),
            onTap: () => _openPlayer(track),
          ),
        if (_moreError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _moreError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_nextCursor != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _loadingMore
                ? const Center(child: CircularProgressIndicator())
                : OutlinedButton(
                    key: const Key('loadMoreButton'),
                    onPressed: _loadMore,
                    child: const Text('Load more'),
                  ),
          ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.currentName, required this.api});

  final String currentName;
  final ProfileApi api;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.currentName);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final account = await widget.api.changeDisplayName(_name.text);
      if (mounted) Navigator.of(context).pop(account);
    } on ProfileApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('renameField'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('cancelRenameButton'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('saveRenameButton'),
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
