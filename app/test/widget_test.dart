import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/audio_picker.dart';
import 'package:lasono_app/main.dart';

const _trackId = '3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10';

TrackApi _api(MockClientHandler handler) =>
    TrackApi(baseUrl: 'http://api.test', client: MockClient(handler));

http.Response _trackResponse() => http.Response(
      jsonEncode({
        'id': _trackId,
        'title': 'Vietnamese',
        'description': 'A demo track',
        'status': 'PROCESSING',
        'mimeType': 'audio/mpeg',
        'durationSeconds': null,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

AudioPicker _picker(String name) =>
    () async => PickedAudio(name: name, bytes: Uint8List.fromList([1, 2, 3]));

void main() {
  testWidgets('shows the LaSono title screen', (WidgetTester tester) async {
    await tester.pumpWidget(const LasonoApp());

    expect(find.text('LaSono'), findsOneWidget);
  });

  testWidgets('does not ship the counter demo', (WidgetTester tester) async {
    await tester.pumpWidget(const LasonoApp());

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  group('load a track by id', () {
    testWidgets('Load fetches the trimmed id and shows the track metadata',
        (WidgetTester tester) async {
      late Uri requested;
      final api = _api((request) async {
        requested = request.url;
        return _trackResponse();
      });
      await tester.pumpWidget(LasonoApp(api: api));

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
      await tester.pumpWidget(LasonoApp(api: api));

      await tester.enterText(find.byKey(const Key('trackIdField')), _trackId);
      await tester.tap(find.byKey(const Key('loadButton')));
      await tester.pumpAndSettle();

      expect(find.text('Track not found'), findsOneWidget);
    });

    testWidgets('asks for an id without calling the API when it is empty',
        (WidgetTester tester) async {
      var calls = 0;
      final api = _api((_) async {
        calls++;
        return http.Response('{}', 200);
      });
      await tester.pumpWidget(LasonoApp(api: api));

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
        return _trackResponse();
      });
      await tester.pumpWidget(
        LasonoApp(api: api, pickAudio: _picker('song.mp3')),
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

    testWidgets('shows the server error and keeps no track on a 415',
        (WidgetTester tester) async {
      final api = _api((_) async => http.Response('{"status":415}', 415));
      await tester.pumpWidget(
        LasonoApp(api: api, pickAudio: _picker('song.mp3')),
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
      await tester.pumpWidget(LasonoApp(api: api, pickAudio: _picker('a.mp3')));

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
        LasonoApp(api: api, pickAudio: _picker('song.mp3')),
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
      await tester.pumpWidget(LasonoApp(pickAudio: () async => null));

      await tester.tap(find.byKey(const Key('chooseFileButton')));
      await tester.pumpAndSettle();

      expect(find.text('No file chosen'), findsOneWidget);
    });
  });
}
