import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/auth_api.dart';
import 'package:lasono_app/auth/session_controller.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// The auth routes of the backend, with answers a test can change. It knows
/// one account, Ann, and remembers every request it got.
class FakeAuthServer {
  final requests = <String>[];
  final bodies = <String, Object?>{};

  /// Whether the refresh cookie is valid, so a reload of the app signs in again.
  bool hasSession = false;

  FutureOr<http.Response> Function()? onLogin;
  FutureOr<http.Response> Function()? onRegister;

  static const account = {
    'userId': 'u-1',
    'email': 'ann@example.com',
    'displayName': 'Ann',
  };

  int count(String route) => requests.where((r) => r == route).length;

  late final MockClient client = MockClient((request) async {
    final route = '${request.method} ${request.url.path}';
    requests.add(route);
    if (request.body.isNotEmpty) bodies[route] = jsonDecode(request.body);
    switch (route) {
      case 'POST /api/v1/auth/refresh':
        return hasSession ? _tokens() : _json({'detail': 'Invalid'}, 401);
      case 'POST /api/v1/auth/login':
        return onLogin?.call() ?? _tokens();
      case 'POST /api/v1/auth/register':
        return onRegister?.call() ?? _json(account, 201);
      case 'POST /api/v1/auth/logout':
        return http.Response('', 204);
      case 'GET /api/v1/users/me':
        return _json(account, 200);
    }
    return http.Response('', 404);
  });

  http.Response _tokens() => _json(
        {'accessToken': 'access-1', 'tokenType': 'Bearer', 'expiresIn': 900},
        200,
      );

  SessionController session() => SessionController(
        AuthApi(baseUrl: 'http://api.test', client: client),
      );

  /// A session that has already looked for a login and found none.
  Future<SessionController> signedOutSession() async {
    final session = this.session();
    await session.restore();
    return session;
  }

  /// A session of Ann, who has logged in.
  Future<SessionController> signedInSession() async {
    final session = await signedOutSession();
    await session.login(email: 'ann@example.com', password: 'secret pass');
    return session;
  }
}
