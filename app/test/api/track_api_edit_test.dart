import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/access_tokens.dart';
import 'package:lasono_app/api/track_api.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

class _Tokens implements AccessTokens {
  @override
  String? get accessToken => 't-1';

  @override
  Future<String?> refreshAccessToken() async => null;
}

const _updated = {
  'id': 'abc',
  'ownerId': 'u-1',
  'title': 'New title',
  'description': 'New text',
  'visibility': 'PRIVATE',
  'status': 'READY',
};

Matcher _failsWith(String message) => throwsA(
      isA<TrackApiException>().having((e) => e.message, 'message', message),
    );

TrackApi _api(Future<http.Response> Function(http.Request) handler) => TrackApi(
      baseUrl: 'http://api.test',
      client: MockClient(handler),
      auth: _Tokens(),
    );

void main() {
  group('TrackApi.updateTrack', () {
    test('sends PATCH with the login and only the fields that change, and returns the track',
        () async {
      late http.Request captured;
      final api = _api((request) async {
        captured = request;
        return _json(_updated, 200);
      });

      final track = await api.updateTrack('abc', visibility: 'PRIVATE');

      expect(captured.method, 'PATCH');
      expect(captured.url.toString(), 'http://api.test/api/v1/tracks/abc');
      expect(captured.headers['authorization'], 'Bearer t-1');
      expect(captured.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(captured.body), {'visibility': 'PRIVATE'});
      expect(track.visibility, 'PRIVATE');
      expect(track.title, 'New title');
    });

    test('can send every field, and an empty description to clear it', () async {
      late http.Request captured;
      final api = _api((request) async {
        captured = request;
        return _json(_updated, 200);
      });

      await api.updateTrack('abc',
          title: 'T', description: '', visibility: 'PUBLIC');

      expect(jsonDecode(captured.body),
          {'title': 'T', 'description': '', 'visibility': 'PUBLIC'});
    });

    test('says only the owner may change a track on a 403', () async {
      final api = _api((_) async => http.Response('', 403));

      expect(() => api.updateTrack('abc', title: 'T'),
          _failsWith('Only the owner can change this track'));
    });

    test('maps 404 to "Track not found"', () async {
      final api = _api((_) async => http.Response('', 404));

      expect(() => api.updateTrack('abc', title: 'T'),
          _failsWith('Track not found'));
    });

    test('shows the reason the server gives for a bad value', () async {
      final api = _api((_) async => _json({'detail': 'Title is empty'}, 400));

      expect(() => api.updateTrack('abc', title: ' '),
          _failsWith('Title is empty'));
    });

    test('asks to log in again on a 401 that a new token cannot fix', () async {
      final api = _api((_) async => http.Response('', 401));

      expect(() => api.updateTrack('abc', title: 'T'),
          _failsWith('Please log in again'));
    });
  });

  group('TrackApi.deleteTrack', () {
    test('sends DELETE with the login', () async {
      late http.Request captured;
      final api = _api((request) async {
        captured = request;
        return http.Response('', 204);
      });

      await api.deleteTrack('abc');

      expect(captured.method, 'DELETE');
      expect(captured.url.toString(), 'http://api.test/api/v1/tracks/abc');
      expect(captured.headers['authorization'], 'Bearer t-1');
    });

    test('says only the owner may delete a track on a 403', () async {
      final api = _api((_) async => http.Response('', 403));

      expect(() => api.deleteTrack('abc'),
          _failsWith('Only the owner can change this track'));
    });

    test('maps 404 to "Track not found"', () async {
      final api = _api((_) async => http.Response('', 404));

      expect(() => api.deleteTrack('abc'), _failsWith('Track not found'));
    });

    test('says to wait on a 409, because the track is still being processed',
        () async {
      final api = _api((_) async => http.Response('', 409));

      expect(
        () => api.deleteTrack('abc'),
        _failsWith('This track is still being processed. Try again in a moment.'),
      );
    });
  });
}
