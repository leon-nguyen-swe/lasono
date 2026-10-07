import 'dart:async';

import 'package:flutter/material.dart';

import '../api/track_api.dart';
import '../format_duration.dart';
import '../models/track.dart';
import '../player_service.dart';
import 'player_controls.dart';
import 'status_badge.dart';

/// The state of one track and what can be done with it: a READY track can be played, a track that
/// is still processing or has failed cannot (the server answers 409 to its stream request).
class TrackPlayback extends StatefulWidget {
  const TrackPlayback({
    super.key,
    required this.track,
    required this.api,
    required this.player,
  });

  final Track track;
  final TrackApi api;
  final PlayerService player;

  @override
  State<TrackPlayback> createState() => _TrackPlaybackState();
}

class _TrackPlaybackState extends State<TrackPlayback> {
  static const _pollInterval = Duration(seconds: 3);

  late Track _track = widget.track;
  Timer? _timer;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _pollWhileProcessing();
  }

  @override
  void didUpdateWidget(TrackPlayback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.track, widget.track)) {
      _track = widget.track;
      _pollWhileProcessing();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // The server converts the audio in the background, so a track that was just uploaded is
  // PROCESSING for a while. Ask again every few seconds until it is READY or FAILED.
  void _pollWhileProcessing() {
    _timer?.cancel();
    _timer = _track.status == 'PROCESSING'
        ? Timer.periodic(_pollInterval, (_) => _askForTheTrack())
        : null;
  }

  Future<void> _askForTheTrack() async {
    if (_asking) return; // the previous answer has not arrived yet
    _asking = true;
    final askedId = _track.id;
    try {
      final latest = await widget.api.getTrack(askedId);
      if (!mounted || _track.id != askedId) return;
      setState(() => _track = latest);
      if (latest.status != 'PROCESSING') {
        _timer?.cancel();
        _timer = null;
      }
    } on TrackApiException {
      // A failed request is not a failed track: ask again at the next tick.
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Status: '),
            StatusBadge(status: track.status),
            const SizedBox(width: 16),
            Text(formatSeconds(track.durationSeconds)),
          ],
        ),
        const SizedBox(height: 8),
        _playback(context, track),
      ],
    );
  }

  Widget _playback(BuildContext context, Track track) {
    return switch (track.status) {
      'READY' => PlayerControls(
          key: ValueKey(track.id),
          player: widget.player,
          streamUrl: widget.api.streamUrl(track.id),
        ),
      'FAILED' => Text(
          'Processing failed. This track cannot be played.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      _ => const Text('Processing the audio. You can play it as soon as it is ready.'),
    };
  }
}
