import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../api/access_tokens.dart';
import '../../api/track_api.dart' show defaultApiBaseUrl;
import '../repository_exception.dart';

/// What the server answered: the status and the body, read once.
class ApiResponse {
  const ApiResponse(this.status, this.body);

  final int status;
  final String body;

  /// The body as JSON, or null when it is empty or not JSON.
  Object? get json {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic> get object => json is Map<String, dynamic> ? json! as Map<String, dynamic> : const {};

  /// The reason the server gave for a refusal (`detail` of a problem+json body), if any.
  String? get detail {
    final value = object['detail'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// The exception for an answer that is not the one expected. [messages] replaces the text for a status.
  RepositoryException failure({Map<int, String> messages = const {}}) {
    final custom = messages[status];
    return switch (status) {
      400 || 413 || 415 || 422 => RepositoryException(
          custom ?? detail ?? 'Invalid request',
          kind: RepositoryErrorKind.invalid,
        ),
      401 => RepositoryException(custom ?? 'Please log in again', kind: RepositoryErrorKind.unauthorized),
      403 => RepositoryException(custom ?? 'You are not allowed to do this', kind: RepositoryErrorKind.forbidden),
      404 => RepositoryException(custom ?? 'Not found', kind: RepositoryErrorKind.notFound),
      409 => RepositoryException(custom ?? detail ?? 'Not possible right now', kind: RepositoryErrorKind.conflict),
      _ => RepositoryException(custom ?? 'Server error ($status)', kind: RepositoryErrorKind.server),
    };
  }
}

/// The one place the new repositories talk HTTP: it builds the address, adds the login, renews an expired login
/// once (see [sendWithToken]), gives up after a timeout, and turns a broken connection into a
/// [RepositoryException]. The repositories above it only know paths, bodies and what the statuses mean.
class ApiClient {
  ApiClient({
    String baseUrl = defaultApiBaseUrl,
    http.Client? client,
    this.auth,
    this.timeout = const Duration(seconds: 30),
  })  : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _client = client ?? http.Client();

  static const _prefix = '/api/v1';

  final String _baseUrl;
  final http.Client _client;
  final AccessTokens? auth;
  final Duration timeout;

  /// The base address, for turning a relative address from the server (a stream address) into a full one.
  String get baseUrl => _baseUrl;

  Future<ApiResponse> get(String path, {Map<String, String?> query = const {}, bool withLogin = true}) =>
      send('GET', path, query: query, withLogin: withLogin);

  /// Sends a request. [path] starts with `/` and is under `/api/v1`. A null value in [query] is left out.
  /// [jsonBody] is sent as JSON.
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, String?> query = const {},
    Object? jsonBody,
    bool withLogin = true,
  }) async {
    final cleaned = {
      for (final entry in query.entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    final uri = Uri.parse('$_baseUrl$_prefix$path').replace(queryParameters: cleaned.isEmpty ? null : cleaned);

    Future<http.Response> once(String? token) async {
      final request = http.Request(method, uri);
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (jsonBody != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(jsonBody);
      }
      return http.Response.fromStream(await _client.send(request));
    }

    try {
      final response = await (withLogin ? sendWithToken(auth, once) : once(null)).timeout(timeout);
      return ApiResponse(response.statusCode, utf8.decode(response.bodyBytes, allowMalformed: true));
    } on TimeoutException {
      throw const RepositoryException('Request timed out', kind: RepositoryErrorKind.network);
    } on http.ClientException {
      throw const RepositoryException('Cannot reach the server', kind: RepositoryErrorKind.network);
    }
  }
}
