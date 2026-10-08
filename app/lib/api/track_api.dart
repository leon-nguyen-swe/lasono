import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../data/repository_exception.dart';
import '../data/track_repository.dart';
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

class TrackApiException extends RepositoryException {
  const TrackApiException(super.message, {super.kind});
}

class TrackApi implements TrackRepository {
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

  @override
  Future<Track> getTrack(String id) async {
    final response = await _get(
      Uri.parse('$_baseUrl$_prefix/tracks/${Uri.encodeComponent(id)}'),
    );

    return switch (response.statusCode) {
      200 => Track.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
      401 => throw const TrackApiException(_logInAgain, kind: RepositoryErrorKind.unauthorized),
      404 => throw const TrackApiException('Track not found', kind: RepositoryErrorKind.notFound),
      400 => throw const TrackApiException('Invalid id', kind: RepositoryErrorKind.invalid),
      final status => throw TrackApiException('Server error ($status)', kind: RepositoryErrorKind.server),
    };
  }

  /// Lists tracks newest first, one page at a time. Pass the previous page's
  /// [TrackPage.nextCursor] as [cursor] to get the page after it.
  @override
  Future<TrackPage> listTracks({String? cursor, int? limit}) async {
    // A `?` followed by nothing is not added when there are no parameters.
    final query = {'cursor': ?cursor, 'limit': ?limit?.toString()};
    final uri = Uri.parse('$_baseUrl$_prefix/tracks')
        .replace(queryParameters: query.isEmpty ? null : query);
    final response = await _get(uri);

    return switch (response.statusCode) {
      200 => TrackPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
      401 => throw const TrackApiException(_logInAgain, kind: RepositoryErrorKind.unauthorized),
      final status => throw TrackApiException('Server error ($status)', kind: RepositoryErrorKind.server),
    };
  }

  Future<http.Response> _get(Uri uri) => _authorized(
        (token) => _call(
          () => _client.get(uri, headers: _bearer(token)),
          _requestTimeout,
          'Request timed out',
        ),
      );

  Future<http.Response> _authorized(
    Future<http.Response> Function(String? token) send,
  ) =>
      sendWithToken(_auth, send);

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
      throw TrackApiException(timeoutMessage, kind: RepositoryErrorKind.network);
    } on http.ClientException {
      throw const TrackApiException('Cannot reach the server', kind: RepositoryErrorKind.network);
    }
  }

  /// The tracks of one user, newest first, one page at a time. The owner also
  /// gets the private ones when logged in.
  @override
  Future<TrackPage> listUserTracks(
    String userId, {
    String? cursor,
    int? limit,
  }) async {
    final query = {'cursor': ?cursor, 'limit': ?limit?.toString()};
    final uri = Uri.parse(
      '$_baseUrl$_prefix/users/${Uri.encodeComponent(userId)}/tracks',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await _get(uri);

    return switch (response.statusCode) {
      200 => TrackPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
      401 => throw const TrackApiException(_logInAgain, kind: RepositoryErrorKind.unauthorized),
      final status => throw TrackApiException('Server error ($status)', kind: RepositoryErrorKind.server),
    };
  }

  /// Asks for an address the audio player can open. The player cannot send the
  /// login header, so the server signs the permission into the address.
  @override
  Future<Uri> fetchStreamUrl(String id) async {
    final response = await _get(
      Uri.parse('$_baseUrl$_prefix/tracks/${Uri.encodeComponent(id)}/stream-url'),
    );

    return switch (response.statusCode) {
      // The server gives the path and the query; the host is the one we asked.
      200 => Uri.parse(
          '$_baseUrl${(jsonDecode(response.body) as Map<String, dynamic>)['url']}',
        ),
      401 => throw const TrackApiException(_logInAgain, kind: RepositoryErrorKind.unauthorized),
      404 => throw const TrackApiException('Track not found', kind: RepositoryErrorKind.notFound),
      final status => throw TrackApiException('Server error ($status)', kind: RepositoryErrorKind.server),
    };
  }

  /// Changes a track of the logged-in user. A field left null stays as it is;
  /// an empty [description] clears it.
  @override
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
      400 => throw TrackApiException(_problemDetail(response) ?? 'Invalid change', kind: RepositoryErrorKind.invalid),
      final status => throw _changeFailure(status),
    };
  }

  /// Deletes a track of the logged-in user.
  @override
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
        401 => const TrackApiException(_logInAgain, kind: RepositoryErrorKind.unauthorized),
        403 => const TrackApiException('Only the owner can change this track', kind: RepositoryErrorKind.forbidden),
        404 => const TrackApiException('Track not found', kind: RepositoryErrorKind.notFound),
        409 => const TrackApiException(
            'This track is still being processed. Try again in a moment.',
            kind: RepositoryErrorKind.conflict,
          ),
        _ => TrackApiException('Server error ($status)', kind: RepositoryErrorKind.server),
      };

  /// Uploads an audio file and returns the new track id.
  @override
  Future<String> uploadTrack({
    required String title,
    String description = '',
    String visibility = 'PUBLIC',
    required String filename,
    required Uint8List bytes,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) throw const TrackApiException('Enter a title', kind: RepositoryErrorKind.invalid);
    final contentType = _audioContentType(filename);
    if (bytes.isEmpty) throw const TrackApiException('File is empty', kind: RepositoryErrorKind.invalid);
    if (bytes.length > maxUploadBytes) {
      throw const TrackApiException(_fileTooLarge, kind: RepositoryErrorKind.invalid);
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
      401 => throw const TrackApiException(_logInAgain, kind: RepositoryErrorKind.unauthorized),
      415 => throw const TrackApiException('Unsupported audio format', kind: RepositoryErrorKind.invalid),
      400 => throw TrackApiException(_problemDetail(response) ?? 'Invalid upload', kind: RepositoryErrorKind.invalid),
      413 => throw const TrackApiException(_fileTooLarge, kind: RepositoryErrorKind.invalid),
      final status => throw TrackApiException('Server error ($status)', kind: RepositoryErrorKind.server),
    };
  }

  // The backend trusts the part's Content-Type, and MultipartFile defaults to
  // application/octet-stream, so it must be set explicitly from the extension.
  MediaType _audioContentType(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.mp3')) return MediaType('audio', 'mpeg');
    if (name.endsWith('.wav')) return MediaType('audio', 'wav');
    throw const TrackApiException('Only MP3 and WAV files are supported', kind: RepositoryErrorKind.invalid);
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
