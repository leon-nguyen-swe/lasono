import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'access_tokens.dart';
import 'auth_api.dart';
import 'track_api.dart' show defaultApiBaseUrl;

class ProfileApiException implements Exception {
  const ProfileApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What anyone may know about a user: never the email.
class Profile {
  const Profile({required this.userId, required this.displayName});

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
      );

  final String userId;
  final String displayName;
}

class ProfileApi {
  ProfileApi({
    String baseUrl = defaultApiBaseUrl,
    http.Client? client,
    this._auth,
    this._requestTimeout = const Duration(seconds: 30),
  })  : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client();

  static const _logInAgain = 'Please log in again';

  final String _baseUrl;
  final http.Client _client;
  final AccessTokens? _auth;
  final Duration _requestTimeout;

  Future<Profile> getProfile(String userId) async {
    // No token on purpose: a profile is public, and the server refuses a token
    // that has run out even on a public route.
    final response = await _call(
      () => _client.get(
        Uri.parse('$_baseUrl/api/v1/users/${Uri.encodeComponent(userId)}'),
      ),
    );

    return switch (response.statusCode) {
      200 => Profile.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
      404 => throw const ProfileApiException('User not found'),
      final status => throw ProfileApiException('Server error ($status)'),
    };
  }

  /// Changes the display name of the logged-in user.
  Future<Account> changeDisplayName(String displayName) async {
    final body = jsonEncode({'displayName': displayName});
    final response = await sendWithToken(
      _auth,
      (token) => _call(
        () => _client.patch(
          Uri.parse('$_baseUrl/api/v1/users/me'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': ?(token == null ? null : 'Bearer $token'),
          },
          body: body,
        ),
      ),
    );

    return switch (response.statusCode) {
      200 => Account.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
      400 => throw ProfileApiException(_problemDetail(response) ?? 'Invalid name'),
      401 => throw const ProfileApiException(_logInAgain),
      final status => throw ProfileApiException('Server error ($status)'),
    };
  }

  // Without a timeout a request the server never answers would wait forever.
  Future<http.Response> _call(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_requestTimeout);
    } on TimeoutException {
      throw const ProfileApiException('Request timed out');
    } on http.ClientException {
      throw const ProfileApiException('Cannot reach the server');
    }
  }

  String? _problemDetail(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body is Map<String, dynamic> ? body['detail'] as String? : null;
    } on FormatException {
      return null;
    }
  }
}
