import 'package:flutter/material.dart';

import '../api/track_api.dart';
import '../models/track.dart';
import '../player_service.dart';
import 'track_playback.dart';

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
          TrackPlayback(track: track, api: api, player: player),
        ],
      ),
    );
  }
}
