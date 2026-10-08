import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/track.dart';
import '../models/track_page.dart';
import 'access_tokens.dart';

/// Backend origin. Override with `--dart-define=API_BASE_URL=...`.
const defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

/// Mirrors `spring.servlet.multipart.max-file-size` on the backend.
const maxUploadBytes = 50 * 1024 * 1024;

const _fileTooLarge = 'File too large (max 50 MB)';
const _logInAgain = 'Please log in again';

class TrackApiException implements Exception {
  const TrackApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TrackApi {
  TrackApi({
    String baseUrl = defaultApiBaseUrl,
    http.Client? client,
    this._auth,
    this._uploadTimeout = const Duration(minutes: 5),
    this._requestTimeout = const Duration(seconds: 30),
  })  : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client();

  static const _prefix = '/api/v1';

  final String _baseUrl;
  final http.Client _client;
  final AccessTokens? _auth;
  final Duration _uploadTimeout;
  final Duration _requestTimeout;

  Future<Track> getTrack(String id) async {
    final response = await _get(
      Uri.parse('$_baseUrl$_prefix/tracks/${Uri.encodeComponent(id)}'),
    );

    return switch (response.statusCode) {
      200 => Track.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
      401 => throw const TrackApiException(_logInAgain),
      404 => throw const TrackApiException('Track not found'),
      400 => throw const TrackApiException('Invalid id'),
      final status => throw TrackApiException('Server error ($status)'),
    };
  }

  /// Lists tracks newest first, one page at a time. Pass the previous page's
  /// [TrackPage.nextCursor] as [cursor] to get the page after it.
  Future<TrackPage> listTracks({String? cursor, int? limit}) async {
    // A `?` followed by nothing is not added when there are no parameters.
    final query = {'cursor': ?cursor, 'limit': ?limit?.toString()};
    final uri = Uri.parse('$_baseUrl$_prefix/tracks')
        .replace(queryParameters: query.isEmpty ? null : query);
    final response = await _get(uri);

    return switch (response.statusCode) {
      200 => TrackPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
      401 => throw const TrackApiException(_logInAgain),
      final status => throw TrackApiException('Server error ($status)'),
    };
  }

  Future<http.Response> _get(Uri uri) => _authorized(
        (token) => _call(
          () => _client.get(uri, headers: _bearer(token)),
          _requestTimeout,
          'Request timed out',
        ),
      );

  // The server refuses a token that has run out, also on the routes anyone may
  // read. A new token is asked for once and the request is sent once more; a
  // second refusal is the answer. Without a token there is nothing to renew.
  Future<http.Response> _authorized(
    Future<http.Response> Function(String? token) send,
  ) async {
    final auth = _auth;
    final token = auth?.accessToken;
    final response = await send(token);
    if (response.statusCode != 401 || auth == null || token == null) {
      return response;
    }
    final renewed = await auth.refreshAccessToken();
    return renewed == null ? response : send(renewed);
  }

  Map<String, String> _bearer(String? token) =>
      {'Authorization': ?(token == null ? null : 'Bearer $token')};

  // Without a timeout a request the server never answers would wait forever.
  Future<http.Response> _call(
    Future<http.Response> Function() request,
    Duration timeout,
    String timeoutMessage,
  ) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw TrackApiException(timeoutMessage);
    } on http.ClientException {
      throw const TrackApiException('Cannot reach the server');
    }
  }

  /// Asks for an address the audio player can open. The player cannot send the
  /// login header, so the server signs the permission into the address.
  Future<Uri> fetchStreamUrl(String id) async {
    final response = await _get(
      Uri.parse('$_baseUrl$_prefix/tracks/${Uri.encodeComponent(id)}/stream-url'),
    );

    return switch (response.statusCode) {
      // The server gives the path and the query; the host is the one we asked.
      200 => Uri.parse(
          '$_baseUrl${(jsonDecode(response.body) as Map<String, dynamic>)['url']}',
        ),
      401 => throw const TrackApiException(_logInAgain),
      404 => throw const TrackApiException('Track not found'),
      final status => throw TrackApiException('Server error ($status)'),
    };
  }

  /// Changes a track of the logged-in user. A field left null stays as it is;
  /// an empty [description] clears it.
  Future<Track> updateTrack(
    String id, {
    String? title,
    String? description,
    String? visibility,
  }) async {
    final body = jsonEncode({
      'title': ?title,
      'description': ?description,
      'visibility': ?visibility,
    });
    final response = await _authorized(
      (token) => _call(
        () => _client.patch(
          _trackUri(id),
          headers: {'Content-Type': 'application/json', ..._bearer(token)},
          body: body,
        ),
        _requestTimeout,
        'Request timed out',
      ),
    );

    return switch (response.statusCode) {
      200 => Track.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
      400 => throw TrackApiException(_problemDetail(response) ?? 'Invalid change'),
      final status => throw _changeFailure(status),
    };
  }

  /// Deletes a track of the logged-in user.
  Future<void> deleteTrack(String id) async {
    final response = await _authorized(
      (token) => _call(
        () => _client.delete(_trackUri(id), headers: _bearer(token)),
        _requestTimeout,
        'Request timed out',
      ),
    );

    if (response.statusCode != 204) throw _changeFailure(response.statusCode);
  }

  Uri _trackUri(String id) =>
      Uri.parse('$_baseUrl$_prefix/tracks/${Uri.encodeComponent(id)}');

  // The answers a change or a delete has in common.
  TrackApiException _changeFailure(int status) => switch (status) {
        401 => const TrackApiException(_logInAgain),
        403 => const TrackApiException('Only the owner can change this track'),
        404 => const TrackApiException('Track not found'),
        409 => const TrackApiException(
            'This track is still being processed. Try again in a moment.',
          ),
        _ => TrackApiException('Server error ($status)'),
      };

  /// Uploads an audio file and returns the new track id.
  Future<String> uploadTrack({
    required String title,
    String description = '',
    String visibility = 'PUBLIC',
    required String filename,
    required Uint8List bytes,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) throw const TrackApiException('Enter a title');
    final contentType = _audioContentType(filename);
    if (bytes.isEmpty) throw const TrackApiException('File is empty');
    if (bytes.length > maxUploadBytes) {
      throw const TrackApiException(_fileTooLarge);
    }

    // A request can be sent only once, so a second try builds it again.
    http.MultipartRequest buildRequest(String? token) =>
        http.MultipartRequest('POST', Uri.parse('$_baseUrl$_prefix/tracks'))
          ..headers.addAll(_bearer(token))
          ..fields['title'] = trimmedTitle
          ..fields['description'] = description
          ..fields['visibility'] = visibility
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: filename,
              contentType: contentType,
            ),
          );

    // Without a timeout a request the server never answers (for example a body
    // it rejected early) leaves the form disabled forever.
    final response = await _authorized(
      (token) => _call(
        () async => http.Response.fromStream(
          await _client.send(buildRequest(token)),
        ),
        _uploadTimeout,
        'Upload timed out',
      ),
    );

    return switch (response.statusCode) {
      201 => (jsonDecode(response.body) as Map<String, dynamic>)['trackId']
          as String,
      401 => throw const TrackApiException(_logInAgain),
      415 => throw const TrackApiException('Unsupported audio format'),
      400 => throw TrackApiException(_problemDetail(response) ?? 'Invalid upload'),
      413 => throw const TrackApiException(_fileTooLarge),
      final status => throw TrackApiException('Server error ($status)'),
    };
  }

  // The backend trusts the part's Content-Type, and MultipartFile defaults to
  // application/octet-stream, so it must be set explicitly from the extension.
  MediaType _audioContentType(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.mp3')) return MediaType('audio', 'mpeg');
    if (name.endsWith('.wav')) return MediaType('audio', 'wav');
    throw const TrackApiException('Only MP3 and WAV files are supported');
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
