import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/access_tokens.dart';
import 'package:lasono_app/api/profile_api.dart';
import 'package:lasono_app/api/track_api.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

class _Tokens implements AccessTokens {
  _Tokens({this.accessToken = 't-1', this.next});

  @override
  String? accessToken;
  String? next;
  int refreshCalls = 0;

  @override
  Future<String?> refreshAccessToken() async {
    refreshCalls++;
    return next;
  }
}

Matcher _failsWith(String message) => throwsA(
      isA<ProfileApiException>().having((e) => e.message, 'message', message),
    );

ProfileApi _api(
  Future<http.Response> Function(http.Request) handler, [
  AccessTokens? tokens,
]) =>
    ProfileApi(
      baseUrl: 'http://api.test/',
      client: MockClient(handler),
      auth: tokens ?? _Tokens(),
    );

void main() {
  group('ProfileApi.getProfile', () {
    test('asks GET /users/{id}, without a login, and gives the public profile',
        () async {
      late http.Request captured;
      final api = _api((request) async {
        captured = request;
        return _json({'userId': 'u-2', 'displayName': 'Bob'}, 200);
      });

      final profile = await api.getProfile('u-2');

      expect(captured.method, 'GET');
      expect(captured.url.toString(), 'http://api.test/api/v1/users/u-2');
      // A profile is public, and the server refuses a token that has run out
      // even on a public route, so no token is sent.
      expect(captured.headers.containsKey('authorization'), isFalse);
      expect(profile.userId, 'u-2');
      expect(profile.displayName, 'Bob');
    });

    test('maps 404 to "User not found"', () async {
      final api = _api((_) async => http.Response('', 404));

      expect(() => api.getProfile('nobody'), _failsWith('User not found'));
    });

    test('says the server cannot be reached', () async {
      final api = _api((_) async => throw http.ClientException('down'));

      expect(() => api.getProfile('u-2'), _failsWith('Cannot reach the server'));
    });

    test('says a server error with its number', () async {
      final api = _api((_) async => http.Response('', 500));

      expect(() => api.getProfile('u-2'), _failsWith('Server error (500)'));
    });
  });

  group('ProfileApi.changeDisplayName', () {
    const account = {
      'userId': 'u-1',
      'email': 'ann@example.com',
      'displayName': 'Ann B.',
    };

    test('sends PATCH /users/me with the login and the new name, and gives the account',
        () async {
      late http.Request captured;
      final api = _api((request) async {
        captured = request;
        return _json(account, 200);
      });

      final result = await api.changeDisplayName('Ann B.');

      expect(captured.method, 'PATCH');
      expect(captured.url.toString(), 'http://api.test/api/v1/users/me');
      expect(captured.headers['authorization'], 'Bearer t-1');
      expect(jsonDecode(captured.body), {'displayName': 'Ann B.'});
      expect(result.displayName, 'Ann B.');
      expect(result.email, 'ann@example.com');
    });

    test('shows the reason the server gives for a bad name', () async {
      final api = _api((_) async => _json({'detail': 'Name is too long'}, 400));

      expect(() => api.changeDisplayName('x' * 99), _failsWith('Name is too long'));
    });

    test('renews a refused token once and sends the change again', () async {
      final calls = <String?>[];
      final tokens = _Tokens(accessToken: 'old', next: 'new');
      final api = _api((request) async {
        calls.add(request.headers['authorization']);
        return calls.length == 1 ? http.Response('', 401) : _json(account, 200);
      }, tokens);

      await api.changeDisplayName('Ann B.');

      expect(calls, ['Bearer old', 'Bearer new']);
      expect(tokens.refreshCalls, 1);
    });

    test('asks to log in again when the session is over', () async {
      final api = _api((_) async => http.Response('', 401), _Tokens(next: null));

      expect(() => api.changeDisplayName('Ann B.'), _failsWith('Please log in again'));
    });

    test('gives up on a request the server never answers', () async {
      final api = ProfileApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) => Completer<http.Response>().future),
        auth: _Tokens(),
        requestTimeout: const Duration(milliseconds: 20),
      );

      expect(() => api.changeDisplayName('Ann'), _failsWith('Request timed out'));
    });
  });

  group('TrackApi.listUserTracks', () {
    final page = {
      'items': [
        {
          'id': 'abc',
          'ownerId': 'u-2',
          'title': 'Bob song',
          'description': '',
          'visibility': 'PUBLIC',
          'status': 'READY',
        },
      ],
      'nextCursor': 'next-1',
    };

    test('asks GET /users/{id}/tracks with the login, the cursor and the limit',
        () async {
      late http.Request captured;
      final api = TrackApi(
        baseUrl: 'http://api.test',
        auth: _Tokens(),
        client: MockClient((request) async {
          captured = request;
          return _json(page, 200);
        }),
      );

      final result = await api.listUserTracks('u-2', cursor: 'c-1', limit: 20);

      expect(captured.url.path, '/api/v1/users/u-2/tracks');
      expect(captured.url.queryParameters, {'cursor': 'c-1', 'limit': '20'});
      expect(captured.headers['authorization'], 'Bearer t-1');
      expect(result.items.single.title, 'Bob song');
      expect(result.nextCursor, 'next-1');
    });

    test('adds no query when there is no cursor and no limit', () async {
      late Uri captured;
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          captured = request.url;
          return _json(page, 200);
        }),
      );

      await api.listUserTracks('u-2');

      expect(captured.toString(), 'http://api.test/api/v1/users/u-2/tracks');
    });

    test('says a server error with its number', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => http.Response('', 500)),
      );

      expect(
        () => api.listUserTracks('u-2'),
        throwsA(isA<TrackApiException>()
            .having((e) => e.message, 'message', 'Server error (500)')),
      );
    });
  });
}
