import 'package:flutter/material.dart';

import 'api/track_api.dart';
import 'audio_picker.dart';
import 'player_service.dart';
import 'screens/track_list_screen.dart';

void main() {
  runApp(const LasonoApp());
}

class LasonoApp extends StatelessWidget {
  const LasonoApp({super.key, this.api, this.pickAudio, this.player});

  final TrackApi? api;
  final AudioPicker? pickAudio;
  final PlayerService? player;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LaSono',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: TrackListScreen(api: api, pickAudio: pickAudio, player: player),
    );
  }
}
