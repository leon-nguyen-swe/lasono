import 'package:flutter/material.dart';

import '../api/track_api.dart';
import '../format_duration.dart';
import '../models/track.dart';
import '../player_service.dart';
import 'player_controls.dart';
import 'status_badge.dart';

/// The state of one track and what can be done with it: a READY track can be played, a track that
/// is still processing or has failed cannot (the server answers 409 to its stream request).
class TrackPlayback extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
        _playback(context),
      ],
    );
  }

  Widget _playback(BuildContext context) {
    return switch (track.status) {
      'READY' => PlayerControls(
          key: ValueKey(track.id),
          player: player,
          streamUrl: api.streamUrl(track.id),
        ),
      'FAILED' => Text(
          'Processing failed. This track cannot be played.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      _ => const Text('Processing the audio. You can play it as soon as it is ready.'),
    };
  }
}
