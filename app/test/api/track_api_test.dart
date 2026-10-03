import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';

const _trackJson = {
  'id': '3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10',
  'title': 'Vietnamese',
  'description': 'A demo track',
  'status': 'PROCESSING',
  'mimeType': 'audio/mpeg',
  'durationSeconds': null,
};

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('TrackApi.getTrack', () {
    test('requests GET {baseUrl}/api/v1/tracks/{id}', () async {
      late http.Request captured;
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          captured = request;
          return _json(_trackJson, 200);
        }),
      );

      await api.getTrack('3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10');

      expect(captured.method, 'GET');
      expect(
        captured.url.toString(),
        'http://api.test/api/v1/tracks/3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10',
      );
    });

    test('ignores a trailing slash on baseUrl', () async {
      late Uri captured;
      final api = TrackApi(
        baseUrl: 'http://api.test/',
        client: MockClient((request) async {
          captured = request.url;
          return _json(_trackJson, 200);
        }),
      );

      await api.getTrack('abc');

      expect(captured.toString(), 'http://api.test/api/v1/tracks/abc');
    });

    test('returns the parsed track on 200', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json(_trackJson, 200)),
      );

      final track = await api.getTrack('abc');

      expect(track.title, 'Vietnamese');
      expect(track.status, 'PROCESSING');
    });

    test('maps 404 to "Track not found"', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json({'status': 404}, 404)),
      );

      expect(
        () => api.getTrack('abc'),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Track not found'),
        ),
      );
    });

    test('maps 400 to "Invalid id"', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json({'status': 400}, 400)),
      );

      expect(
        () => api.getTrack('not-a-uuid'),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Invalid id'),
        ),
      );
    });

    test('maps other statuses to a generic server error', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json({'status': 500}, 500)),
      );

      expect(
        () => api.getTrack('abc'),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Server error (500)'),
        ),
      );
    });

    test('maps a network failure to a generic connection message', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => throw http.ClientException('boom')),
      );

      expect(
        () => api.getTrack('abc'),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Cannot reach the server'),
        ),
      );
    });
  });
}
