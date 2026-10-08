import 'dart:async';

import 'package:flutter/material.dart';

import 'api/auth_api.dart';
import 'api/profile_api.dart';
import 'api/track_api.dart';
import 'audio_picker.dart';
import 'auth/session_controller.dart';
import 'player_service.dart';
import 'screens/track_list_screen.dart';

void main() {
  // The track API sends the access token of whoever is logged in, so both
  // are made here and share the session.
  final session = SessionController(AuthApi());
  runApp(
    LasonoApp(
      session: session,
      api: TrackApi(auth: session),
      profileApi: ProfileApi(auth: session),
    ),
  );
}

class LasonoApp extends StatefulWidget {
  const LasonoApp({
    super.key,
    required this.session,
    this.api,
    this.profileApi,
    this.pickAudio,
    this.player,
  });

  final SessionController session;
  final TrackApi? api;
  final ProfileApi? profileApi;
  final AudioPicker? pickAudio;
  final PlayerService? player;

  @override
  State<LasonoApp> createState() => _LasonoAppState();
}

class _LasonoAppState extends State<LasonoApp> {
  @override
  void initState() {
    super.initState();
    // A reload of the page loses the access token, which lives in memory only.
    // The refresh cookie gets it back, before anything is asked for the user.
    if (widget.session.status == SessionStatus.restoring) {
      unawaited(widget.session.restore());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LaSono',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          // The first list of tracks differs for a logged-in user (it holds
          // their private tracks), so it waits until the answer is known.
          if (widget.session.status == SessionStatus.restoring) {
            return Scaffold(
              appBar: AppBar(title: const Text('LaSono')),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          return TrackListScreen(
            session: widget.session,
            api: widget.api,
            profileApi: widget.profileApi,
            pickAudio: widget.pickAudio,
            player: widget.player,
          );
        },
      ),
    );
  }
}
