import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/repository_exception.dart';
import 'access_tokens.dart';
import 'auth_api.dart';
import 'track_api.dart' show defaultApiBaseUrl;

class ProfileApiException extends RepositoryException {
  const ProfileApiException(super.message, {super.kind});
}

/// What anyone may know about a user: never the email.
///
/// The counts and [isFollowedByMe] come with Phase 5; a backend that does not send them gives zero and
/// false, so the same code runs against the Phase 1-4 backend.
class Profile {
  const Profile({
    required this.userId,
    required this.displayName,
    this.followerCount = 0,
    this.followingCount = 0,
    this.isFollowedByMe = false,
    this.avatarUrl,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
        followerCount: (json['followerCount'] as num?)?.toInt() ?? 0,
        followingCount: (json['followingCount'] as num?)?.toInt() ?? 0,
        isFollowedByMe: json['isFollowedByMe'] as bool? ?? false,
        avatarUrl: json['avatarUrl'] as String?,
      );

  final String userId;
  final String displayName;
  final int followerCount;
  final int followingCount;

  /// Whether the logged-in user follows this user; false when nobody is logged in and for oneself.
  final bool isFollowedByMe;

  /// An address of an avatar image; null when there is none (the app draws the initials).
  final String? avatarUrl;

  Profile copyWith({
    String? displayName,
    int? followerCount,
    int? followingCount,
    bool? isFollowedByMe,
  }) =>
      Profile(
        userId: userId,
        displayName: displayName ?? this.displayName,
        followerCount: followerCount ?? this.followerCount,
        followingCount: followingCount ?? this.followingCount,
        isFollowedByMe: isFollowedByMe ?? this.isFollowedByMe,
        avatarUrl: avatarUrl,
      );
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
      404 => throw const ProfileApiException('User not found', kind: RepositoryErrorKind.notFound),
      final status => throw ProfileApiException('Server error ($status)', kind: RepositoryErrorKind.server),
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
      400 => throw ProfileApiException(_problemDetail(response) ?? 'Invalid name', kind: RepositoryErrorKind.invalid),
      401 => throw const ProfileApiException(_logInAgain, kind: RepositoryErrorKind.unauthorized),
      final status => throw ProfileApiException('Server error ($status)', kind: RepositoryErrorKind.server),
    };
  }

  // Without a timeout a request the server never answers would wait forever.
  Future<http.Response> _call(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_requestTimeout);
    } on TimeoutException {
      throw const ProfileApiException('Request timed out', kind: RepositoryErrorKind.network);
    } on http.ClientException {
      throw const ProfileApiException('Cannot reach the server', kind: RepositoryErrorKind.network);
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
