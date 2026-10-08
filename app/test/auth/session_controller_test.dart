import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/auth_api.dart';
import 'package:lasono_app/auth/session_controller.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _tokens(String accessToken) =>
    _json({'accessToken': accessToken, 'tokenType': 'Bearer', 'expiresIn': 900}, 200);

final _ann = {'userId': 'u-1', 'email': 'ann@example.com', 'displayName': 'Ann'};

/// A server whose answers each test can change, and which remembers the requests.
class _Server {
  final requests = <String>[];
  final bodies = <String, Object?>{};

  Future<http.Response> Function() onRefresh = () async => _tokens('access-1');
  Future<http.Response> Function() onLogin = () async => _tokens('access-1');
  Future<http.Response> Function() onLogout = () async => http.Response('', 204);

  int count(String route) => requests.where((r) => r == route).length;

  MockClient get client => MockClient((request) {
        final route = '${request.method} ${request.url.path}';
        requests.add(route);
        if (request.body.isNotEmpty) bodies[route] = jsonDecode(request.body);
        return switch (route) {
          'POST /api/v1/auth/refresh' => onRefresh(),
          'POST /api/v1/auth/login' => onLogin(),
          'POST /api/v1/auth/logout' => onLogout(),
          'POST /api/v1/auth/register' => Future.value(_json(_ann, 201)),
          'GET /api/v1/users/me' => Future.value(_json(_ann, 200)),
          _ => Future.value(http.Response('', 404)),
        };
      });
}

SessionController _session(_Server server) => SessionController(
      AuthApi(baseUrl: 'http://api.test', client: server.client),
    );

void main() {
  late _Server server;
  late SessionController session;

  setUp(() {
    server = _Server();
    session = _session(server);
  });

  test('knows nothing about the user until it has looked for a session', () {
    expect(session.status, SessionStatus.restoring);
    expect(session.accessToken, isNull);
    expect(session.account, isNull);
  });

  group('restore', () {
    test('signs in again from the refresh cookie when the app opens', () async {
      await session.restore();

      expect(session.status, SessionStatus.signedIn);
      expect(session.accessToken, 'access-1');
      expect(session.account?.displayName, 'Ann');
    });

    test('stays signed out when there is no valid session', () async {
      server.onRefresh = () async => _json({'detail': 'Invalid'}, 401);

      await session.restore();

      expect(session.status, SessionStatus.signedOut);
      expect(session.accessToken, isNull);
    });

    test('stays signed out, without an error, when the server cannot be reached',
        () async {
      server.onRefresh = () async => throw http.ClientException('down');

      await session.restore();

      expect(session.status, SessionStatus.signedOut);
    });
  });

  group('login', () {
    test('signs in and keeps the token and the account', () async {
      await session.login(email: 'ann@example.com', password: 'secret pass');

      expect(session.status, SessionStatus.signedIn);
      expect(session.accessToken, 'access-1');
      expect(session.account?.email, 'ann@example.com');
    });

    test('tells the listeners that the state changed', () async {
      var notified = 0;
      session.addListener(() => notified++);

      await session.login(email: 'ann@example.com', password: 'secret pass');

      expect(notified, greaterThan(0));
    });

    test('throws on a wrong password and stays signed out', () async {
      // The login screen is only shown after the app looked for a session.
      server.onRefresh = () async => _json({'detail': 'Invalid'}, 401);
      await session.restore();
      server.onLogin = () async => _json({'detail': 'Bad'}, 401);

      await expectLater(
        session.login(email: 'ann@example.com', password: 'nope'),
        throwsA(isA<AuthApiException>()),
      );

      expect(session.status, SessionStatus.signedOut);
      expect(session.accessToken, isNull);
    });
  });

  group('register', () {
    test('creates the account and then signs in with the same details',
        () async {
      await session.register(
        email: 'ann@example.com',
        displayName: 'Ann',
        password: 'secret pass',
      );

      expect(server.requests.take(2),
          ['POST /api/v1/auth/register', 'POST /api/v1/auth/login']);
      expect(server.bodies['POST /api/v1/auth/login'],
          {'email': 'ann@example.com', 'password': 'secret pass'});
      expect(session.status, SessionStatus.signedIn);
    });
  });

  group('logout', () {
    test('forgets the token and the account', () async {
      await session.login(email: 'ann@example.com', password: 'secret pass');

      await session.logout();

      expect(session.status, SessionStatus.signedOut);
      expect(session.accessToken, isNull);
      expect(session.account, isNull);
      expect(server.count('POST /api/v1/auth/logout'), 1);
    });

    test('still signs out when the server cannot be reached', () async {
      await session.login(email: 'ann@example.com', password: 'secret pass');
      server.onLogout = () async => throw http.ClientException('down');

      await session.logout();

      expect(session.status, SessionStatus.signedOut);
    });
  });

  group('refreshAccessToken', () {
    setUp(() async {
      await session.login(email: 'ann@example.com', password: 'secret pass');
      server.requests.clear();
    });

    test('gets a new token and keeps it', () async {
      server.onRefresh = () async => _tokens('access-2');

      expect(await session.refreshAccessToken(), 'access-2');
      expect(session.accessToken, 'access-2');
    });

    // The backend rotates the refresh token: a second request with the old one
    // looks like a stolen token and ends the whole session.
    test('sends one request when several callers ask at the same time',
        () async {
      final answer = Completer<http.Response>();
      server.onRefresh = () => answer.future;

      final calls = [
        session.refreshAccessToken(),
        session.refreshAccessToken(),
        session.refreshAccessToken(),
      ];
      answer.complete(_tokens('access-2'));

      expect(await Future.wait(calls), ['access-2', 'access-2', 'access-2']);
      expect(server.count('POST /api/v1/auth/refresh'), 1);
    });

    test('sends a new request when it is asked again later', () async {
      server.onRefresh = () async => _tokens('access-2');
      await session.refreshAccessToken();
      server.onRefresh = () async => _tokens('access-3');

      expect(await session.refreshAccessToken(), 'access-3');
      expect(server.count('POST /api/v1/auth/refresh'), 2);
    });

    test('signs out and gives null when the session is over', () async {
      server.onRefresh = () async => _json({'detail': 'Invalid'}, 401);

      expect(await session.refreshAccessToken(), isNull);
      expect(session.status, SessionStatus.signedOut);
      expect(session.accessToken, isNull);
    });

    test('gives null but stays signed in when the server cannot be reached',
        () async {
      server.onRefresh = () async => throw http.ClientException('down');

      expect(await session.refreshAccessToken(), isNull);
      expect(session.status, SessionStatus.signedIn);
    });

    test('does not sign the user in again when they logged out meanwhile',
        () async {
      final answer = Completer<http.Response>();
      server.onRefresh = () => answer.future;

      final refreshing = session.refreshAccessToken();
      await session.logout();
      answer.complete(_tokens('access-2'));

      expect(await refreshing, isNull);
      expect(session.status, SessionStatus.signedOut);
      expect(session.accessToken, isNull);
    });
  });
}
