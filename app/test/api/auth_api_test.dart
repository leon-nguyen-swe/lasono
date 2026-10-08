import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/auth_api.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

const _tokens = {
  'accessToken': 'access-1',
  'tokenType': 'Bearer',
  'expiresIn': 900,
};

AuthApi _api(Future<http.Response> Function(http.Request request) handler) =>
    AuthApi(baseUrl: 'http://api.test', client: MockClient(handler));

void main() {
  group('AuthApi.login', () {
    test('posts the email and the password and returns the access token',
        () async {
      late http.Request captured;
      final api = _api((request) async {
        captured = request;
        return _json(_tokens, 200);
      });

      final tokens = await api.login(email: 'a@example.com', password: 'secret pass');

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'http://api.test/api/v1/auth/login');
      expect(captured.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(captured.body),
          {'email': 'a@example.com', 'password': 'secret pass'});
      expect(tokens.accessToken, 'access-1');
      expect(tokens.expiresIn, const Duration(seconds: 900));
    });

    test('says the email or the password is wrong on a 401', () async {
      final api = _api((_) async => _json({'detail': 'Bad credentials'}, 401));

      expect(
        () => api.login(email: 'a@example.com', password: 'nope'),
        throwsA(isA<AuthApiException>()
            .having((e) => e.message, 'message', 'Wrong email or password')),
      );
    });

    test('says the server cannot be reached when the request fails', () async {
      final api = _api((_) async => throw http.ClientException('down'));

      expect(
        () => api.login(email: 'a@example.com', password: 'x'),
        throwsA(isA<AuthApiException>()
            .having((e) => e.message, 'message', 'Cannot reach the server')),
      );
    });
  });

  group('AuthApi.refresh', () {
    test('posts to the refresh route and returns the new access token',
        () async {
      late http.Request captured;
      final api = _api((request) async {
        captured = request;
        return _json(_tokens, 200);
      });

      final tokens = await api.refresh();

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'http://api.test/api/v1/auth/refresh');
      expect(tokens?.accessToken, 'access-1');
    });

    test('gives null when the server says the session is no longer valid',
        () async {
      final api = _api((_) async => _json({'detail': 'Invalid'}, 401));

      expect(await api.refresh(), isNull);
    });

    test('throws when the server cannot be reached, so a network problem is not taken for a logout',
        () async {
      final api = _api((_) async => throw http.ClientException('down'));

      expect(api.refresh, throwsA(isA<AuthApiException>()));
    });

    test('throws on a server error', () async {
      final api = _api((_) async => http.Response('', 500));

      expect(
        api.refresh,
        throwsA(isA<AuthApiException>()
            .having((e) => e.message, 'message', 'Server error (500)')),
      );
    });
  });

  group('AuthApi.register', () {
    test('posts the new account and returns it', () async {
      late http.Request captured;
      final api = _api((request) async {
        captured = request;
        return _json({
          'userId': 'u-1',
          'email': 'a@example.com',
          'displayName': 'Ann',
        }, 201);
      });

      final account = await api.register(
          email: 'a@example.com', displayName: 'Ann', password: 'secret pass');

      expect(captured.url.toString(), 'http://api.test/api/v1/auth/register');
      expect(jsonDecode(captured.body), {
        'email': 'a@example.com',
        'displayName': 'Ann',
        'password': 'secret pass',
      });
      expect(account.userId, 'u-1');
      expect(account.displayName, 'Ann');
    });

    test('shows the reason the server gives for a bad field', () async {
      final api = _api((_) async =>
          _json({'detail': 'Password must be at least 8 characters'}, 400));

      expect(
        () => api.register(email: 'a@example.com', displayName: 'A', password: 'x'),
        throwsA(isA<AuthApiException>().having((e) => e.message, 'message',
            'Password must be at least 8 characters')),
      );
    });

    test('says the email is taken on a 409', () async {
      final api = _api((_) async => _json({'detail': 'Taken'}, 409));

      expect(
        () => api.register(email: 'a@example.com', displayName: 'A', password: 'secret pass'),
        throwsA(isA<AuthApiException>().having(
            (e) => e.message, 'message', 'This email is already registered')),
      );
    });
  });

  group('AuthApi.logout', () {
    test('posts to the logout route', () async {
      late http.Request captured;
      final api = _api((request) async {
        captured = request;
        return http.Response('', 204);
      });

      await api.logout();

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'http://api.test/api/v1/auth/logout');
    });

    test('does not throw when the server cannot be reached, because the app is leaving the session anyway',
        () async {
      final api = _api((_) async => throw http.ClientException('down'));

      await api.logout();
    });
  });

  group('AuthApi.currentUser', () {
    test('sends the access token and returns the account', () async {
      late http.Request captured;
      final api = _api((request) async {
        captured = request;
        return _json({
          'userId': 'u-1',
          'email': 'a@example.com',
          'displayName': 'Ann',
        }, 200);
      });

      final account = await api.currentUser('access-1');

      expect(captured.url.toString(), 'http://api.test/api/v1/users/me');
      expect(captured.headers['authorization'], 'Bearer access-1');
      expect(account.userId, 'u-1');
    });
  });

  test('gives up on a request the server never answers', () async {
    final api = AuthApi(
      baseUrl: 'http://api.test',
      client: MockClient((_) => Completer<http.Response>().future),
      requestTimeout: const Duration(milliseconds: 20),
    );

    expect(
      () => api.login(email: 'a@example.com', password: 'x'),
      throwsA(isA<AuthApiException>()
          .having((e) => e.message, 'message', 'Request timed out')),
    );
  });
}
