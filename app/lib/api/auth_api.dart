import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'credentials_client.dart';
import 'track_api.dart' show defaultApiBaseUrl;

class AuthApiException implements Exception {
  const AuthApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a login or a refresh gives back. The refresh token is not here: it is
/// in a cookie that a script cannot read.
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.expiresIn});

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['accessToken'] as String,
        expiresIn: Duration(seconds: (json['expiresIn'] as num).toInt()),
      );

  final String accessToken;
  final Duration expiresIn;
}

class Account {
  const Account({
    required this.userId,
    required this.email,
    required this.displayName,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        userId: json['userId'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
      );

  final String userId;
  final String email;
  final String displayName;
}

class AuthApi {
  AuthApi({
    String baseUrl = defaultApiBaseUrl,
    http.Client? client,
    this._requestTimeout = const Duration(seconds: 30),
  })  : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        // The refresh cookie is set and sent by the browser, and only when the
        // client asks for credentials.
        _client = client ?? createCredentialsClient();

  static const _prefix = '/api/v1/auth';

  final String _baseUrl;
  final http.Client _client;
  final Duration _requestTimeout;

  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    final response = await _post('/login', {'email': email, 'password': password});

    return switch (response.statusCode) {
      200 => AuthTokens.fromJson(_object(response)),
      401 => throw const AuthApiException('Wrong email or password'),
      400 => throw AuthApiException(_problemDetail(response) ?? 'Invalid login'),
      final status => throw AuthApiException('Server error ($status)'),
    };
  }

  /// Trades the refresh cookie for a new access token. Gives null when the
  /// server says the session is over; throws when it cannot say anything, so a
  /// network problem is not taken for a logout.
  Future<AuthTokens?> refresh() async {
    final response = await _post('/refresh');

    return switch (response.statusCode) {
      200 => AuthTokens.fromJson(_object(response)),
      401 => null,
      final status => throw AuthApiException('Server error ($status)'),
    };
  }

  Future<Account> register({
    required String email,
    required String displayName,
    required String password,
  }) async {
    final response = await _post('/register', {
      'email': email,
      'displayName': displayName,
      'password': password,
    });

    return switch (response.statusCode) {
      201 => Account.fromJson(_object(response)),
      409 => throw const AuthApiException('This email is already registered'),
      400 => throw AuthApiException(_problemDetail(response) ?? 'Invalid details'),
      final status => throw AuthApiException('Server error ($status)'),
    };
  }

  /// Ends the session on the server and removes the cookie. A server that
  /// cannot be reached is not an error here: the app leaves the session anyway.
  Future<void> logout() async {
    try {
      await _post('/logout');
    } on AuthApiException {
      // Nothing to do: the access token is dropped by the caller.
    }
  }

  Future<Account> currentUser(String accessToken) async {
    final response = await _send(
      () => _client.get(
        Uri.parse('$_baseUrl/api/v1/users/me'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ),
    );

    return switch (response.statusCode) {
      200 => Account.fromJson(_object(response)),
      401 => throw const AuthApiException('Please log in again'),
      final status => throw AuthApiException('Server error ($status)'),
    };
  }

  Future<http.Response> _post(String path, [Map<String, String>? body]) {
    return _send(
      () => _client.post(
        Uri.parse('$_baseUrl$_prefix$path'),
        headers: {if (body != null) 'Content-Type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  // Without a timeout a request the server never answers would wait forever.
  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(_requestTimeout);
    } on TimeoutException {
      throw const AuthApiException('Request timed out');
    } on http.ClientException {
      throw const AuthApiException('Cannot reach the server');
    }
  }

  Map<String, dynamic> _object(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

  String? _problemDetail(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body is Map<String, dynamic> ? body['detail'] as String? : null;
    } on FormatException {
      return null;
    }
  }
}
