import 'package:flutter/material.dart';

import '../api/track_api.dart';
import '../models/track.dart';

/// The newest-first list of tracks. It loads one page at a time and asks for the
/// next page when the user scrolls near the end.
class TrackListScreen extends StatefulWidget {
  const TrackListScreen({super.key, this.api});

  final TrackApi? api;

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  // Ask for the next page when the list is this close to its end.
  static const _loadMoreDistance = 200.0;

  late final TrackApi _api = widget.api ?? TrackApi();
  final _scroll = ScrollController();
  final _tracks = <Track>[];
  final _knownIds = <String>{};

  String? _nextCursor;
  bool _firstPageLoaded = false;
  bool _loading = false;
  String? _error;

  bool get _hasMore => !_firstPageLoaded || _nextCursor != null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadMoreIfNearEnd);
    _loadNextPage();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
      appBar: AppBar(title: const Text('LaSono')),
      body: _body(),
    );
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
          trailing: Text(track.status),
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
