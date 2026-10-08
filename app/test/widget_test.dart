import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/audio_picker.dart';
import 'package:lasono_app/main.dart';
import 'package:lasono_app/player_service.dart';
import 'package:lasono_app/screens/track_screen.dart';

import 'fake_auth_server.dart';
import 'fake_player_service.dart';
import 'support/test_harness.dart';

const _trackId = '3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10';
const _otherTrackId = '9a1c2d3e-0000-4000-8000-000000000001';

TrackApi _api(MockClientHandler handler) =>
    TrackApi(baseUrl: 'http://api.test', client: MockClient(handler));

http.Response _trackResponse([String id = _trackId, String status = 'READY']) => http.Response(
      jsonEncode({
        'id': id,
        'title': 'Vietnamese',
        'description': 'A demo track',
        'status': status,
        'mimeType': 'audio/mpeg',
        'durationSeconds': null,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

AudioPicker _picker(String name) =>
    () async => PickedAudio(name: name, bytes: Uint8List.fromList([1, 2, 3]));

/// Answers GET /api/v1/tracks/{id} with a track carrying that id, and
/// GET /api/v1/tracks/{id}/stream-url with a signed address for it.
TrackApi _trackApi() => _api((request) async {
      final segments = request.url.pathSegments;
      if (segments.last == 'stream-url') {
        return http.Response(
          jsonEncode({
            'url': '/api/v1/tracks/${segments[segments.length - 2]}/stream?expires=1&signature=sig',
            'expiresAt': '2030-01-01T00:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return _trackResponse(segments.last);
    });

Future<void> _loadTrack(WidgetTester tester, String id) async {
  await tester.enterText(find.byKey(const Key('trackIdField')), id);
  await tester.tap(find.byKey(const Key('loadButton')));
  await tester.pumpAndSettle();
}

/// The upload / load-by-id / player screen on its own, without the track list.
Widget _uploadScreen({
  TrackApi? api,
  AudioPicker? pickAudio,
  PlayerService? player,
}) =>
    MaterialApp(
      home: Scaffold(
        body: TrackScreen(api: api, pickAudio: pickAudio, player: player),
      ),
    );

/// A server whose track list is one page with these titles.
MockClient _listClient(List<String> titles) => MockClient(
      (_) async => http.Response(
        jsonEncode({
          'items': [
            for (final (index, title) in titles.indexed)
              {
                'id': 'id-$index',
                'title': title,
                'description': '',
                'status': 'PROCESSING',
              },
          ],
          'nextCursor': null,
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

TrackApi _listApi(List<String> titles) => TrackApi(baseUrl: 'http://api.test', client: _listClient(titles));

void main() {
  testWidgets('shows the LaSono title screen', (WidgetTester tester) async {
    await tester.pumpWidget(LasonoApp(session: FakeAuthServer().session(), api: _listApi([])));

    expect(find.text('LaSono'), findsOneWidget);
  });

  testWidgets('does not ship the counter demo', (WidgetTester tester) async {
    await tester.pumpWidget(LasonoApp(session: FakeAuthServer().session(), api: _listApi([])));

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('opens on the list of tracks', (WidgetTester tester) async {
    TestEnv.window(tester, width: 1280, height: 1000);
    final env = await TestEnv.create(client: _listClient(['Vietnamese', 'Second']));
    await tester.pumpWidget(env.app());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Vietnamese'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.byKey(const Key('uploadButton')), findsOneWidget);
  });

  group('load a track by id', () {
    testWidgets('Load fetches the trimmed id and shows the track metadata',
        (WidgetTester tester) async {
      late Uri requested;
      final api = _api((request) async {
        requested = request.url;
        return _trackResponse(_trackId, 'PROCESSING');
      });
      await tester.pumpWidget(_uploadScreen(api: api, player: FakePlayerService()));

      await tester.enterText(
        find.byKey(const Key('trackIdField')),
        '  $_trackId  ',
      );
      await tester.tap(find.byKey(const Key('loadButton')));
      await tester.pumpAndSettle();

      expect(requested.path, '/api/v1/tracks/$_trackId');
      expect(find.text('Vietnamese'), findsOneWidget);
      expect(find.text('A demo track'), findsOneWidget);
      expect(find.text('PROCESSING'), findsOneWidget);
    });

    testWidgets('shows "Track not found" on a 404',
        (WidgetTester tester) async {
      final api = _api((_) async => http.Response('{"status":404}', 404));
      await tester.pumpWidget(_uploadScreen(api: api, player: FakePlayerService()));

      await _loadTrack(tester, _trackId);

      expect(find.text('Track not found'), findsOneWidget);
    });

    testWidgets('asks for an id without calling the API when it is empty',
        (WidgetTester tester) async {
      var calls = 0;
      final api = _api((_) async {
        calls++;
        return http.Response('{}', 200);
      });
      await tester.pumpWidget(_uploadScreen(api: api, player: FakePlayerService()));

      await tester.tap(find.byKey(const Key('loadButton')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a track id'), findsOneWidget);
      expect(calls, 0);
    });
  });

  group('upload a track', () {
    testWidgets('uploads the chosen file, then loads and shows the new track',
        (WidgetTester tester) async {
      late http.Request uploadRequest;
      late Uri trackRequest;
      final api = _api((request) async {
        if (request.method == 'POST') {
          uploadRequest = request;
          return http.Response(
            jsonEncode({
              'trackId': _trackId,
              'title': 'My Song',
              'status': 'PROCESSING',
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        trackRequest = request.url;
        return _trackResponse(_trackId, 'PROCESSING');
      });
      await tester.pumpWidget(
        _uploadScreen(
          api: api,
          pickAudio: _picker('song.mp3'),
          player: FakePlayerService(),
        ),
      );

      await tester.enterText(find.byKey(const Key('titleField')), 'My Song');
      await tester.tap(find.byKey(const Key('chooseFileButton')));
      await tester.pumpAndSettle();
      expect(find.text('song.mp3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('uploadButton')));
      await tester.pumpAndSettle();

      expect(uploadRequest.url.path, '/api/v1/tracks');
      expect(trackRequest.path, '/api/v1/tracks/$_trackId');
      expect(find.widgetWithText(TextField, _trackId), findsOneWidget);
      expect(find.text('PROCESSING'), findsOneWidget);
    });

    testWidgets('uploads a public track unless Private is switched on',
        (WidgetTester tester) async {
      final bodies = <String>[];
      final api = _api((request) async {
        if (request.method == 'POST') {
          bodies.add(request.body);
          return http.Response(
            jsonEncode({'trackId': _trackId}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return _trackResponse(_trackId, 'PROCESSING');
      });
      await tester.pumpWidget(
        _uploadScreen(
          api: api,
          pickAudio: _picker('song.mp3'),
          player: FakePlayerService(),
        ),
      );
      await tester.enterText(find.byKey(const Key('titleField')), 'My Song');
      await tester.tap(find.byKey(const Key('chooseFileButton')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('privateSwitch'))).value,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('uploadButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privateSwitch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('uploadButton')));
      await tester.pumpAndSettle();

      expect(bodies, hasLength(2));
      expect(bodies[0], contains('PUBLIC'));
      expect(bodies[1], contains('PRIVATE'));
    });

    testWidgets('shows the server error and keeps no track on a 415',
        (WidgetTester tester) async {
      final api = _api((_) async => http.Response('{"status":415}', 415));
      await tester.pumpWidget(
        _uploadScreen(
          api: api,
          pickAudio: _picker('song.mp3'),
          player: FakePlayerService(),
        ),
      );

      await tester.enterText(find.byKey(const Key('titleField')), 'My Song');
      await tester.tap(find.byKey(const Key('chooseFileButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('uploadButton')));
      await tester.pumpAndSettle();

      expect(find.text('Unsupported audio format'), findsOneWidget);
      expect(find.text('PROCESSING'), findsNothing);
    });

    testWidgets('asks to choose a file before uploading',
        (WidgetTester tester) async {
      var calls = 0;
      final api = _api((_) async {
        calls++;
        return http.Response('{}', 201);
      });
      await tester.pumpWidget(_uploadScreen(api: api, pickAudio: _picker('a.mp3')));

      await tester.enterText(find.byKey(const Key('titleField')), 'My Song');
      await tester.tap(find.byKey(const Key('uploadButton')));
      await tester.pumpAndSettle();

      expect(find.text('Choose an audio file'), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('shows the client-side title error without calling the API',
        (WidgetTester tester) async {
      var calls = 0;
      final api = _api((_) async {
        calls++;
        return http.Response('{}', 201);
      });
      await tester.pumpWidget(
        _uploadScreen(api: api, pickAudio: _picker('song.mp3')),
      );

      await tester.tap(find.byKey(const Key('chooseFileButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('uploadButton')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a title'), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('a cancelled picker leaves the selection empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(_uploadScreen(pickAudio: () async => null));

      await tester.tap(find.byKey(const Key('chooseFileButton')));
      await tester.pumpAndSettle();

      expect(find.text('No file chosen'), findsOneWidget);
    });
  });

  group('play a track', () {
    late FakePlayerService player;

    Future<void> pumpApp(WidgetTester tester) async {
      // Tall enough that the player controls are inside the visible viewport.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      player = FakePlayerService();
      await tester.pumpWidget(_uploadScreen(api: _trackApi(), player: player));
    }

    testWidgets('shows no player controls until a track is loaded',
        (WidgetTester tester) async {
      await pumpApp(tester);

      expect(find.byKey(const Key('playButton')), findsNothing);

      await _loadTrack(tester, _trackId);

      expect(find.byKey(const Key('playButton')), findsOneWidget);
    });

    testWidgets('Play loads the stream url and starts playback',
        (WidgetTester tester) async {
      await pumpApp(tester);
      await _loadTrack(tester, _trackId);

      await tester.tap(find.byKey(const Key('playButton')));
      await tester.pumpAndSettle();

      expect(player.loaded, [
        Uri.parse('http://api.test/api/v1/tracks/$_trackId/stream?expires=1&signature=sig'),
      ]);
      expect(player.playCalls, 1);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('Pause pauses and the next Play does not reload the stream',
        (WidgetTester tester) async {
      await pumpApp(tester);
      await _loadTrack(tester, _trackId);

      await tester.tap(find.byKey(const Key('playButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playButton')));
      await tester.pumpAndSettle();
      expect(player.pauseCalls, 1);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.byKey(const Key('playButton')));
      await tester.pumpAndSettle();

      expect(player.loaded.length, 1);
      expect(player.playCalls, 2);
    });

    testWidgets('shows position and duration from the player',
        (WidgetTester tester) async {
      await pumpApp(tester);
      await _loadTrack(tester, _trackId);
      expect(find.text('0:00 / 0:00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('playButton')));
      await tester.pumpAndSettle();
      player.emitDuration(const Duration(minutes: 3, seconds: 20));
      player.emitPosition(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('0:05 / 3:20'), findsOneWidget);
    });

    testWidgets('shows a loading indicator while the stream loads',
        (WidgetTester tester) async {
      await pumpApp(tester);
      final gate = Completer<void>();
      player.loadGate = gate;
      await _loadTrack(tester, _trackId);

      await tester.tap(find.byKey(const Key('playButton')));
      await tester.pump();
      expect(find.byKey(const Key('playerLoading')), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playerLoading')), findsNothing);
      expect(player.playCalls, 1);
    });

    testWidgets('shows an error and does not play when the stream fails',
        (WidgetTester tester) async {
      await pumpApp(tester);
      player.loadError = const PlaybackException('404');
      await _loadTrack(tester, _trackId);

      await tester.tap(find.byKey(const Key('playButton')));
      await tester.pumpAndSettle();

      expect(find.text('Cannot play this track'), findsOneWidget);
      expect(player.playCalls, 0);
      expect(find.byKey(const Key('playerLoading')), findsNothing);
    });

    testWidgets('loading another track stops the previous one and reloads',
        (WidgetTester tester) async {
      await pumpApp(tester);
      await _loadTrack(tester, _trackId);
      await tester.tap(find.byKey(const Key('playButton')));
      await tester.pumpAndSettle();

      await _loadTrack(tester, _otherTrackId);
      expect(player.stopCalls, greaterThanOrEqualTo(1));

      await tester.tap(find.byKey(const Key('playButton')));
      await tester.pumpAndSettle();

      expect(player.loaded, [
        Uri.parse('http://api.test/api/v1/tracks/$_trackId/stream?expires=1&signature=sig'),
        Uri.parse('http://api.test/api/v1/tracks/$_otherTrackId/stream?expires=1&signature=sig'),
      ]);
    });

    group('player lifecycle', () {
      testWidgets("a newly loaded track does not show the previous track's time",
          (WidgetTester tester) async {
        await pumpApp(tester);
        player.durationOnLoad = const Duration(seconds: 200);
        await _loadTrack(tester, _trackId);
        await tester.tap(find.byKey(const Key('playButton')));
        await tester.pumpAndSettle();
        player.emitPosition(const Duration(seconds: 100));
        await tester.pumpAndSettle();
        expect(find.text('1:40 / 3:20'), findsOneWidget);

        player.durationOnLoad = const Duration(seconds: 60);
        await _loadTrack(tester, _otherTrackId);

        expect(find.text('0:00 / 0:00'), findsOneWidget);
        expect(
          tester.widget<Slider>(find.byKey(const Key('seekSlider'))).onChanged,
          isNull,
        );

        await tester.tap(find.byKey(const Key('playButton')));
        await tester.pumpAndSettle();

        expect(find.text('0:00 / 1:00'), findsOneWidget);
      });

      testWidgets('when playback completes it rewinds and offers Play again',
          (WidgetTester tester) async {
        await pumpApp(tester);
        player.durationOnLoad = const Duration(seconds: 200);
        await _loadTrack(tester, _trackId);
        await tester.tap(find.byKey(const Key('playButton')));
        await tester.pumpAndSettle();
        player.emitPosition(const Duration(seconds: 200));
        await tester.pumpAndSettle();

        player.emitCompleted();
        await tester.pumpAndSettle();

        expect(player.pauseCalls, 1);
        expect(player.seeks.last, Duration.zero);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(find.text('0:00 / 3:20'), findsOneWidget);

        await tester.tap(find.byKey(const Key('playButton')));
        await tester.pumpAndSettle();

        expect(player.playCalls, 2);
        expect(player.loaded.length, 1);
        expect(find.byIcon(Icons.pause), findsOneWidget);
      });
    });

    group('seek', () {
      const duration = Duration(minutes: 3, seconds: 20);
      const durationMs = 200000.0;
      final slider = find.byKey(const Key('seekSlider'));

      Future<void> startPlaying(WidgetTester tester) async {
        await pumpApp(tester);
        await _loadTrack(tester, _trackId);
        await tester.tap(find.byKey(const Key('playButton')));
        await tester.pumpAndSettle();
        player.emitDuration(duration);
        await tester.pumpAndSettle();
      }

      testWidgets('the slider is disabled until the duration is known',
          (WidgetTester tester) async {
        await pumpApp(tester);
        await _loadTrack(tester, _trackId);
        expect(tester.widget<Slider>(slider).onChanged, isNull);

        await tester.tap(find.byKey(const Key('playButton')));
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(slider).onChanged, isNull);

        player.emitDuration(duration);
        await tester.pumpAndSettle();

        expect(tester.widget<Slider>(slider).onChanged, isNotNull);
        expect(tester.widget<Slider>(slider).max, durationMs);
      });

      testWidgets('the thumb follows the playback position',
          (WidgetTester tester) async {
        await startPlaying(tester);

        player.emitPosition(const Duration(seconds: 50));
        await tester.pumpAndSettle();

        expect(tester.widget<Slider>(slider).value, 50000.0);
      });

      testWidgets('a position past the duration is clamped to the end',
          (WidgetTester tester) async {
        await startPlaying(tester);

        player.emitPosition(const Duration(seconds: 250));
        await tester.pumpAndSettle();

        expect(tester.widget<Slider>(slider).value, durationMs);
        expect(tester.takeException(), isNull);
      });

      testWidgets('tapping the slider seeks once, proportionally',
          (WidgetTester tester) async {
        await startPlaying(tester);

        await tester.tap(slider);
        await tester.pumpAndSettle();

        expect(player.seeks.length, 1);
        expect(player.seeks.single.inSeconds, inInclusiveRange(80, 120));
      });

      testWidgets('dragging to the far end seeks to the end of the track',
          (WidgetTester tester) async {
        await startPlaying(tester);

        await tester.drag(slider, const Offset(2000, 0));
        await tester.pumpAndSettle();

        expect(player.seeks.last, duration);
      });
    });
  });
}
