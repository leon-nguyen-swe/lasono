import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/models/track.dart';
import 'package:lasono_app/screens/player_controls.dart';
import 'package:lasono_app/screens/track_playback.dart';
import 'package:lasono_app/screens/waveform_view.dart';

import '../fake_player_service.dart';

const _pollInterval = Duration(seconds: 3);

Track _track(
  String status, {
  double? durationSeconds,
  List<double>? waveform,
  String id = 'id-1',
}) =>
    Track(
      id: id,
      title: 'My Song',
      description: '',
      status: status,
      durationSeconds: durationSeconds,
      waveform: waveform,
    );

http.Response _trackResponse(
  String status, {
  double? durationSeconds,
  List<double>? waveform,
}) =>
    http.Response(
      jsonEncode({
        'id': 'id-1',
        'title': 'My Song',
        'description': '',
        'status': status,
        'mimeType': 'audio/mpeg',
        'durationSeconds': durationSeconds,
        'waveform': waveform,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

/// A fake server: answers every request with [handler] and counts them.
class _Server {
  _Server([FutureOr<http.Response> Function(int call)? handler])
      : handler = handler ?? ((_) => http.Response('{}', 500));

  final FutureOr<http.Response> Function(int call) handler;
  var calls = 0;

  late final TrackApi api = TrackApi(
    baseUrl: 'http://api.test',
    client: MockClient((_) async => handler(calls++)),
  );
}

Widget _app(Track track, _Server server) => MaterialApp(
      home: Scaffold(
        body: TrackPlayback(track: track, api: server.api, player: FakePlayerService()),
      ),
    );

Future<void> _pump(WidgetTester tester, Track track, [_Server? server]) =>
    tester.pumpWidget(_app(track, server ?? _Server()));

/// Lets the poll timer fire and its response arrive.
Future<void> _waitOnePoll(WidgetTester tester) async {
  await tester.pump(_pollInterval);
  await tester.pump();
}

void main() {
  testWidgets('a ready track shows its duration and can be played',
      (WidgetTester tester) async {
    await _pump(tester, _track('READY', durationSeconds: 185, waveform: [0.5]));

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

  group('polling a track that is processing', () {
    testWidgets('asks again every 3 seconds, then shows the controls and stops once READY',
        (WidgetTester tester) async {
      final server = _Server((call) =>
          call == 0
              ? _trackResponse('PROCESSING')
              : _trackResponse('READY', durationSeconds: 185, waveform: [0.5, 1.0]));
      await _pump(tester, _track('PROCESSING'), server);

      await tester.pump(const Duration(seconds: 2));
      expect(server.calls, 0, reason: 'nothing before the first interval');

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(server.calls, 1);
      expect(find.byType(PlayerControls), findsNothing, reason: 'still PROCESSING');

      await _waitOnePoll(tester);
      expect(server.calls, 2);
      expect(find.byType(PlayerControls), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
      expect(find.text('3:05'), findsOneWidget);
      expect(find.byType(WaveformView), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      expect(server.calls, 2, reason: 'a READY track is not polled any more');
    });

    testWidgets('stops and shows the failure when processing fails',
        (WidgetTester tester) async {
      final server = _Server((_) => _trackResponse('FAILED'));
      await _pump(tester, _track('PROCESSING'), server);

      await _waitOnePoll(tester);

      expect(find.text('Processing failed. This track cannot be played.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(server.calls, 1);
    });

    testWidgets('does not poll a track that is already READY', (WidgetTester tester) async {
      final server = _Server((_) => _trackResponse('READY'));
      await _pump(tester, _track('READY', waveform: [0.5]), server);

      await tester.pump(const Duration(seconds: 30));

      expect(server.calls, 0);
    });

    testWidgets('loads the waveform once for a READY track that came without it',
        (WidgetTester tester) async {
      // The track list does not carry the waveform, only GET /tracks/{id} does.
      final server = _Server((_) => _trackResponse('READY', waveform: [0.2, 0.8]));
      await _pump(tester, _track('READY'), server);
      await tester.pump();

      expect(find.byType(WaveformView), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(server.calls, 1);
    });

    testWidgets('keeps asking when one request fails', (WidgetTester tester) async {
      final server = _Server((call) {
        if (call == 0) throw http.ClientException('offline');
        return _trackResponse('READY');
      });
      await _pump(tester, _track('PROCESSING'), server);

      await _waitOnePoll(tester);
      expect(find.byType(PlayerControls), findsNothing);

      await _waitOnePoll(tester);
      expect(find.byType(PlayerControls), findsOneWidget);
    });

    testWidgets('stops asking when the screen is closed', (WidgetTester tester) async {
      final server = _Server((_) => _trackResponse('PROCESSING'));
      await _pump(tester, _track('PROCESSING'), server);
      await _waitOnePoll(tester);
      expect(server.calls, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));

      expect(server.calls, 1);
    });

    testWidgets('shows another track when it is given one', (WidgetTester tester) async {
      final server = _Server((_) => _trackResponse('PROCESSING'));
      await _pump(tester, _track('READY', durationSeconds: 185), server);
      expect(find.text('3:05'), findsOneWidget);

      await tester.pumpWidget(_app(_track('PROCESSING', id: 'id-2'), server));

      expect(find.text('--:--'), findsOneWidget);
      expect(find.byType(PlayerControls), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
