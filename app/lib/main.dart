import 'package:flutter/material.dart';

import 'api/track_api.dart';
import 'audio_picker.dart';
import 'screens/track_screen.dart';

void main() {
  runApp(const LasonoApp());
}

class LasonoApp extends StatelessWidget {
  const LasonoApp({super.key, this.api, this.pickAudio});

  final TrackApi? api;
  final AudioPicker? pickAudio;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LaSono',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('LaSono')),
        body: TrackScreen(api: api, pickAudio: pickAudio),
      ),
    );
  }
}
