import 'package:flutter/material.dart';

import '../api/track_api.dart';
import '../models/track.dart';
import '../player_service.dart';
import 'player_controls.dart';

/// Plays one track chosen from the list. Closing the screen stops the playback,
/// because [PlayerControls] stops the player when it is removed.
class TrackPlayerScreen extends StatelessWidget {
  const TrackPlayerScreen({
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
    return Scaffold(
      appBar: AppBar(title: Text(track.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (track.description.isNotEmpty) Text(track.description),
          Row(
            children: [
              const Text('Status: '),
              Text(track.status),
            ],
          ),
          PlayerControls(
            key: ValueKey(track.id),
            player: player,
            streamUrl: api.streamUrl(track.id),
          ),
        ],
      ),
    );
  }
}
