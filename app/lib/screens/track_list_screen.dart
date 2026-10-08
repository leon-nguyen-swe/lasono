import 'package:flutter/material.dart';

import '../api/track_api.dart';
import '../audio_picker.dart';
import '../auth/session_controller.dart';
import '../format_duration.dart';
import '../models/track.dart';
import '../player_service.dart';
import 'auth_screen.dart';
import 'status_badge.dart';
import 'track_player_screen.dart';
import 'track_screen.dart';

/// The newest-first list of tracks. It loads one page at a time and asks for the
/// next page when the user scrolls near the end.
class TrackListScreen extends StatefulWidget {
  const TrackListScreen({
    super.key,
    required this.session,
    this.api,
    this.pickAudio,
    this.player,
  });

  final SessionController session;
  final TrackApi? api;
  final AudioPicker? pickAudio;
  final PlayerService? player;

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  // Ask for the next page when the list is this close to its end.
  static const _loadMoreDistance = 200.0;

  late final TrackApi _api = widget.api ?? TrackApi();

  // One player shared by the player and upload screens, so only one track plays at a time.
  PlayerService? _ownedPlayer;
  PlayerService get _player =>
      widget.player ?? (_ownedPlayer ??= JustAudioPlayerService());

  final _scroll = ScrollController();
  final _tracks = <Track>[];
  final _knownIds = <String>{};

  // Set by the player screen when the owner changed or deleted the track.
  bool _changedInPlayer = false;

  // Who the list was loaded for: what a user may see differs from one account to another.
  String? _userId;

  String? _nextCursor;
  bool _firstPageLoaded = false;
  bool _loading = false;
  String? _error;

  bool get _hasMore => !_firstPageLoaded || _nextCursor != null;

  @override
  void initState() {
    super.initState();
    _userId = widget.session.account?.userId;
    widget.session.addListener(_onSessionChanged);
    _scroll.addListener(_loadMoreIfNearEnd);
    _loadNextPage();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _scroll.dispose();
    _ownedPlayer?.dispose();
    super.dispose();
  }

  // A login or a logout changes which tracks the user may see (the private
  // ones of the owner), so the list starts again. A new access token for the
  // same user changes nothing on screen.
  void _onSessionChanged() {
    if (!mounted) return;
    final userId = widget.session.account?.userId;
    if (userId == _userId) {
      setState(() {});
      return;
    }
    _userId = userId;
    _refresh();
  }

  void _loadMoreIfNearEnd() {
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels <= _loadMoreDistance) {
      _loadNextPage();
    }
  }

  void _retry() {
    setState(() => _error = null);
    _loadNextPage();
  }

  // Back to the first page, as if the screen had just opened.
  void _refresh() {
    setState(() {
      _tracks.clear();
      _knownIds.clear();
      _nextCursor = null;
      _firstPageLoaded = false;
      _error = null;
    });
    _loadNextPage();
  }

  // The owner can change or delete the track in the player, so when that
  // happened the list starts again from the top.
  Future<void> _openPlayer(Track track) async {
    _changedInPlayer = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TrackPlayerScreen(
          track: track,
          api: _api,
          player: _player,
          session: widget.session,
          onChanged: () => _changedInPlayer = true,
        ),
      ),
    );
    if (mounted && _changedInPlayer) _refresh();
  }

  Future<void> _openAuth() => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => AuthScreen(session: widget.session)),
      );

  // The upload form is where new tracks come from, so show the list again from
  // the top when the user comes back. Only a logged-in user can upload, so
  // someone who is not is asked to log in first.
  Future<void> _openUpload() async {
    if (widget.session.status != SessionStatus.signedIn) {
      await _openAuth();
      if (!mounted || widget.session.status != SessionStatus.signedIn) return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Upload')),
          body: TrackScreen(
            api: _api,
            pickAudio: widget.pickAudio,
            player: _player,
          ),
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _loadNextPage() async {
    if (_loading || _error != null || !_hasMore) return;

    // Set before the first await, so a second call made while this page is
    // still loading sees it and returns instead of asking for the same page.
    setState(() => _loading = true);
    try {
      final page = await _api.listTracks(cursor: _nextCursor);
      if (!mounted) return;
      setState(() {
        for (final track in page.items) {
          if (_knownIds.add(track.id)) _tracks.add(track);
        }
        _nextCursor = page.nextCursor;
        _firstPageLoaded = true;
      });
      // A page that does not fill the screen cannot be scrolled, so no scroll
      // would ever ask for more. Check again once this page is laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _loadMoreIfNearEnd();
      });
    } on TrackApiException catch (e) {
      // Keep the tracks and the cursor, so Retry asks for the same page again.
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LaSono'),
        actions: [
          IconButton(
            key: const Key('uploadAction'),
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload',
            onPressed: _openUpload,
          ),
          ..._accountActions(),
        ],
      ),
      body: _body(),
    );
  }

  List<Widget> _accountActions() {
    final session = widget.session;
    final account = session.account;
    if (session.status == SessionStatus.signedIn && account != null) {
      return [
        PopupMenuButton<String>(
          key: const Key('accountMenu'),
          tooltip: 'Account',
          onSelected: (_) => session.logout(),
          itemBuilder: (_) => const [
            PopupMenuItem<String>(
              key: Key('logoutAction'),
              value: 'logout',
              child: Text('Log out'),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: Text(account.displayName)),
          ),
        ),
      ];
    }
    if (session.status == SessionStatus.signedOut) {
      return [
        TextButton(
          key: const Key('loginAction'),
          onPressed: _openAuth,
          child: const Text('Log in'),
        ),
      ];
    }
    return const [];
  }

  Widget _body() {
    if (!_firstPageLoaded) {
      final error = _error;
      return error == null
          ? const Center(child: CircularProgressIndicator())
          : Center(child: _ErrorMessage(message: error, onRetry: _retry));
    }
    if (_tracks.isEmpty) return const Center(child: Text('No tracks yet'));

    final showFooter = _loading || _error != null;
    return ListView.builder(
      controller: _scroll,
      itemCount: _tracks.length + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _tracks.length) {
          final error = _error;
          return error == null
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _ErrorMessage(message: error, onRetry: _retry);
        }
        final track = _tracks[index];
        return ListTile(
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
        );
      },
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('retryButton'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
