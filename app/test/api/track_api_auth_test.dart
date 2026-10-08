import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/access_tokens.dart';
import 'package:lasono_app/api/track_api.dart';

const _trackJson = {
  'id': 'abc',
  'title': 'Vietnamese',
  'description': '',
  'status': 'READY',
};

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

class _FakeTokens implements AccessTokens {
  _FakeTokens({this.accessToken, this.next});

  @override
  String? accessToken;

  /// What a refresh gives; null means the session is over.
  String? next;
  int refreshCalls = 0;

  @override
  Future<String?> refreshAccessToken() async {
    refreshCalls++;
    accessToken = next;
    return next;
  }
}

/// A server that answers each request with the next of [answers], and keeps
/// what it was asked.
class _Server {
  _Server(this.answers);

  final List<http.Response> answers;
  final requests = <http.Request>[];

  MockClient get client => MockClient((request) async {
        requests.add(request);
        return answers[requests.length - 1];
      });

  List<String?> get authorizations =>
      requests.map((r) => r.headers['authorization']).toList();
}

TrackApi _api(_Server server, AccessTokens? tokens) =>
    TrackApi(baseUrl: 'http://api.test', client: server.client, auth: tokens);

void main() {
  final audio = Uint8List.fromList(List.filled(16, 1));
  final created = _json({'trackId': 'abc'}, 201);
  final pageJson = {'items': [_trackJson], 'nextCursor': null};

  group('the access token is sent when there is one', () {
    test('on getTrack', () async {
      final server = _Server([_json(_trackJson, 200)]);

      await _api(server, _FakeTokens(accessToken: 't-1')).getTrack('abc');

      expect(server.authorizations, ['Bearer t-1']);
    });

    test('on listTracks', () async {
      final server = _Server([_json(pageJson, 200)]);

      await _api(server, _FakeTokens(accessToken: 't-1')).listTracks();

      expect(server.authorizations, ['Bearer t-1']);
    });

    test('on uploadTrack', () async {
      final server = _Server([created]);

      await _api(server, _FakeTokens(accessToken: 't-1'))
          .uploadTrack(title: 'T', filename: 'a.mp3', bytes: audio);

      expect(server.authorizations, ['Bearer t-1']);
    });

    test('and no header is sent when nobody is signed in', () async {
      final server = _Server([_json(_trackJson, 200), _json(_trackJson, 200)]);

      await _api(server, _FakeTokens()).getTrack('abc');
      await _api(server, null).getTrack('abc');

      expect(server.authorizations, [null, null]);
    });
  });

  group('a request the server refuses with 401', () {
    test('is repeated once with a new token', () async {
      final server = _Server([http.Response('', 401), _json(_trackJson, 200)]);
      final tokens = _FakeTokens(accessToken: 'old', next: 'new');

      final track = await _api(server, tokens).getTrack('abc');

      expect(track.id, 'abc');
      expect(server.authorizations, ['Bearer old', 'Bearer new']);
      expect(tokens.refreshCalls, 1);
    });

    test('is repeated for an upload, with the whole form sent again', () async {
      final server = _Server([http.Response('', 401), created]);
      final tokens = _FakeTokens(accessToken: 'old', next: 'new');

      final id = await _api(server, tokens)
          .uploadTrack(title: 'My Song', filename: 'a.mp3', bytes: audio);

      expect(id, 'abc');
      expect(server.authorizations, ['Bearer old', 'Bearer new']);
      for (final request in server.requests) {
        expect(request.body, contains('My Song'));
        expect(request.bodyBytes.length, greaterThan(audio.length));
      }
    });

    test('is not repeated when the session is over', () async {
      final server = _Server([http.Response('', 401)]);
      final tokens = _FakeTokens(accessToken: 'old', next: null);

      await expectLater(
        _api(server, tokens).getTrack('abc'),
        throwsA(isA<TrackApiException>()
            .having((e) => e.message, 'message', 'Please log in again')),
      );

      expect(server.requests, hasLength(1));
    });

    test('is repeated only once, so a token that is refused again ends it',
        () async {
      final server = _Server([http.Response('', 401), http.Response('', 401)]);
      final tokens = _FakeTokens(accessToken: 'old', next: 'new');

      await expectLater(
        _api(server, tokens).uploadTrack(title: 'T', filename: 'a.mp3', bytes: audio),
        throwsA(isA<TrackApiException>()
            .having((e) => e.message, 'message', 'Please log in again')),
      );

      expect(server.requests, hasLength(2));
      expect(tokens.refreshCalls, 1);
    });

    test('does not try to refresh when nobody was signed in', () async {
      final server = _Server([http.Response('', 401)]);
      final tokens = _FakeTokens(next: 'new');

      await expectLater(
        _api(server, tokens)
            .uploadTrack(title: 'T', filename: 'a.mp3', bytes: audio),
        throwsA(isA<TrackApiException>()
            .having((e) => e.message, 'message', 'Please log in again')),
      );

      expect(tokens.refreshCalls, 0);
    });
  });
}
