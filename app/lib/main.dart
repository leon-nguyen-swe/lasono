import 'package:flutter/material.dart';

import 'api/track_api.dart';
import 'api/auth_api.dart';
import 'audio_picker.dart';
import 'auth/session_controller.dart';
import 'player_service.dart';
import 'screens/track_list_screen.dart';

void main() {
  runApp(const LasonoApp());
}

class LasonoApp extends StatelessWidget {
  const LasonoApp({
    super.key,
    this.api,
    this.pickAudio,
    this.player,
    this.session,
  });

  final SessionController? session;
  final TrackApi? api;
  final AudioPicker? pickAudio;
  final PlayerService? player;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LaSono',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: TrackListScreen(
        session: session ?? SessionController(AuthApi()),
        api: api,
        pickAudio: pickAudio,
        player: player,
      ),
    );
  }
}
