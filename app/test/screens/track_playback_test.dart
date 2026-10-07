import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/models/track.dart';
import 'package:lasono_app/screens/player_controls.dart';
import 'package:lasono_app/screens/track_playback.dart';

import '../fake_player_service.dart';

Track _track(String status, {double? durationSeconds}) => Track(
      id: 'id-1',
      title: 'My Song',
      description: '',
      status: status,
      durationSeconds: durationSeconds,
    );

Future<void> _pump(WidgetTester tester, Track track) {
  final api = TrackApi(
    baseUrl: 'http://api.test',
    client: MockClient((_) async => http.Response('{}', 500)),
  );
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TrackPlayback(track: track, api: api, player: FakePlayerService()),
      ),
    ),
  );
}

void main() {
  testWidgets('a ready track shows its duration and can be played',
      (WidgetTester tester) async {
    await _pump(tester, _track('READY', durationSeconds: 185));

    expect(find.text('READY'), findsOneWidget);
    expect(find.text('3:05'), findsOneWidget);
    expect(find.byType(PlayerControls), findsOneWidget);
  });

  testWidgets('a track that is still processing cannot be played yet',
      (WidgetTester tester) async {
    await _pump(tester, _track('PROCESSING'));

    expect(find.byType(PlayerControls), findsNothing);
    expect(find.text('Processing the audio. You can play it as soon as it is ready.'),
        findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);
  });

  testWidgets('a track whose processing failed says so and cannot be played',
      (WidgetTester tester) async {
    await _pump(tester, _track('FAILED'));

    expect(find.byType(PlayerControls), findsNothing);
    expect(find.text('Processing failed. This track cannot be played.'), findsOneWidget);
  });
}
