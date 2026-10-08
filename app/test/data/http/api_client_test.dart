import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/api/access_tokens.dart';
import 'package:lasono_app/data/http/api_client.dart';
import 'package:lasono_app/data/repository_exception.dart';

class _Tokens implements AccessTokens {
  _Tokens({this.accessToken, this.next});

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

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

ApiClient _client(Future<http.Response> Function(http.Request) handler, {AccessTokens? auth, Duration? timeout}) =>
    ApiClient(
      baseUrl: 'http://api.test/',
      client: MockClient(handler),
      auth: auth,
      timeout: timeout ?? const Duration(seconds: 5),
    );

void main() {
  group('the request', () {
    test('goes to /api/v1 under the base address, without a double slash', () async {
      late http.Request seen;
      final api = _client((r) async {
        seen = r;
        return _json({});
      });

      await api.get('/tracks');

      expect(seen.method, 'GET');
      expect(seen.url.toString(), 'http://api.test/api/v1/tracks');
    });

    test('leaves out a query parameter that is null and keeps the others', () async {
      late Uri seen;
      final api = _client((r) async {
        seen = r.url;
        return _json({});
      });

      await api.get('/feed', query: {'cursor': null, 'limit': '20'});

      expect(seen.queryParameters, {'limit': '20'});
    });

    test('has no "?" at all when every parameter is null', () async {
      late Uri seen;
      final api = _client((r) async {
        seen = r.url;
        return _json({});
      });

      await api.get('/feed', query: {'cursor': null});

      expect(seen.toString(), 'http://api.test/api/v1/feed');
    });

    test('sends a JSON body with its content type', () async {
      late http.Request seen;
      final api = _client((r) async {
        seen = r;
        return _json({}, 201);
      });

      await api.send('POST', '/tracks/t1/comments', jsonBody: {'positionMs': 1000, 'text': 'hay'});

      expect(seen.method, 'POST');
      expect(seen.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(seen.body), {'positionMs': 1000, 'text': 'hay'});
    });

    test('adds the login when there is one, and nothing when there is not', () async {
      final seen = <String?>[];
      final api = _client(
        (r) async {
          seen.add(r.headers['authorization']);
          return _json({});
        },
        auth: _Tokens(accessToken: 'tok'),
      );
      await api.get('/tracks');
      await api.get('/tracks', withLogin: false);

      final anonymous = _client((r) async {
        seen.add(r.headers['authorization']);
        return _json({});
      });
      await anonymous.get('/tracks');

      expect(seen, ['Bearer tok', null, null]);
    });

    test('renews an expired login once and sends the request again', () async {
      final tokens = _Tokens(accessToken: 'old', next: 'new');
      final seen = <String?>[];
      final api = _client(
        (r) async {
          seen.add(r.headers['authorization']);
          return r.headers['authorization'] == 'Bearer new' ? _json({'ok': true}) : _json({}, 401);
        },
        auth: tokens,
      );

      final response = await api.get('/feed');

      expect(response.status, 200);
      expect(seen, ['Bearer old', 'Bearer new']);
      expect(tokens.refreshCalls, 1);
    });
  });

  group('the answer', () {
    test('has the status and the JSON object of the body', () async {
      final api = _client((r) async => _json({'liked': true, 'likeCount': 3}));
      final response = await api.get('/tracks/t1/like');
      expect(response.status, 200);
      expect(response.object['likeCount'], 3);
    });

    test('reads Vietnamese text without damage', () async {
      final api = _client(
        (r) async => http.Response.bytes(
          utf8.encode(jsonEncode({'title': 'Nắng ấm xa dần'})),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect((await api.get('/tracks/t1')).object['title'], 'Nắng ấm xa dần');
    });

    test('a body that is empty or not JSON gives no object and no detail, not a crash', () async {
      final api = _client((r) async => http.Response('<html>Bad gateway</html>', 502));
      final response = await api.get('/tracks');
      expect(response.json, isNull);
      expect(response.object, isEmpty);
      expect(response.detail, isNull);
    });

    test('the reason of a refusal is the detail of the problem body', () async {
      final api = _client(
        (r) async => _json({'title': 'Bad Request', 'status': 400, 'detail': 'positionMs must be between 0 and 213400'}, 400),
      );
      expect((await api.get('/x')).detail, 'positionMs must be between 0 and 213400');
    });
  });

  group('failure() says what went wrong in terms of a kind', () {
    ApiResponse answer(int status, [Object? body]) => ApiResponse(status, body == null ? '' : jsonEncode(body));

    final cases = <(int, RepositoryErrorKind)>[
      (400, RepositoryErrorKind.invalid),
      (413, RepositoryErrorKind.invalid),
      (415, RepositoryErrorKind.invalid),
      (401, RepositoryErrorKind.unauthorized),
      (403, RepositoryErrorKind.forbidden),
      (404, RepositoryErrorKind.notFound),
      (409, RepositoryErrorKind.conflict),
      (500, RepositoryErrorKind.server),
      (502, RepositoryErrorKind.server),
    ];
    for (final (status, kind) in cases) {
      test('$status is $kind', () {
        expect(answer(status).failure().kind, kind);
      });
    }

    test('a 400 carries the reason the server gave', () {
      expect(answer(400, {'detail': 'You cannot follow yourself'}).failure().message, 'You cannot follow yourself');
    });

    test('a 401 asks to log in', () {
      expect(answer(401).failure().needsLogin, isTrue);
      expect(answer(404).failure().needsLogin, isFalse);
    });

    test('a message for the status replaces the default', () {
      expect(answer(404).failure(messages: const {404: 'Track not found'}).message, 'Track not found');
    });

    test('an unexpected status names itself, so a bug report says what happened', () {
      expect(answer(503).failure().message, 'Server error (503)');
    });
  });

  group('a connection that fails', () {
    test('is a network error with a message, not a raw exception', () async {
      final api = _client((r) async => throw http.ClientException('connection refused'));
      await expectLater(
        api.get('/tracks'),
        throwsA(isA<RepositoryException>()
            .having((e) => e.kind, 'kind', RepositoryErrorKind.network)
            .having((e) => e.message, 'message', 'Cannot reach the server')),
      );
    });

    test('that never answers gives up after the timeout', () async {
      final never = Completer<http.Response>();
      final api = _client((r) => never.future, timeout: const Duration(milliseconds: 50));
      await expectLater(
        api.get('/tracks'),
        throwsA(isA<RepositoryException>()
            .having((e) => e.kind, 'kind', RepositoryErrorKind.network)
            .having((e) => e.message, 'message', 'Request timed out')),
      );
    });
  });
}
