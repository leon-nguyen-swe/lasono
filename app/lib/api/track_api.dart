import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/track.dart';

/// Backend origin. Override with `--dart-define=API_BASE_URL=...`.
const defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

/// Mirrors `spring.servlet.multipart.max-file-size` on the backend.
const maxUploadBytes = 50 * 1024 * 1024;

const _fileTooLarge = 'File too large (max 50 MB)';

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
    this._uploadTimeout = const Duration(minutes: 5),
  })  : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client();

  static const _prefix = '/api/v1';

  final String _baseUrl;
  final http.Client _client;
  final Duration _uploadTimeout;

  Future<Track> getTrack(String id) async {
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$_baseUrl$_prefix/tracks/${Uri.encodeComponent(id)}'),
      );
    } on http.ClientException {
      throw const TrackApiException('Cannot reach the server');
    }

    return switch (response.statusCode) {
      200 => Track.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
      404 => throw const TrackApiException('Track not found'),
      400 => throw const TrackApiException('Invalid id'),
      final status => throw TrackApiException('Server error ($status)'),
    };
  }

  Uri streamUrl(String id) =>
      Uri.parse('$_baseUrl$_prefix/tracks/${Uri.encodeComponent(id)}/stream');

  /// Uploads an audio file and returns the new track id.
  Future<String> uploadTrack({
    required String title,
    String description = '',
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

    final request =
        http.MultipartRequest('POST', Uri.parse('$_baseUrl$_prefix/tracks'))
          ..fields['title'] = trimmedTitle
          ..fields['description'] = description
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
    final http.Response response;
    try {
      response = await (() async =>
              http.Response.fromStream(await _client.send(request)))()
          .timeout(_uploadTimeout);
    } on TimeoutException {
      throw const TrackApiException('Upload timed out');
    } on http.ClientException {
      throw const TrackApiException('Cannot reach the server');
    }

    return switch (response.statusCode) {
      201 => (jsonDecode(response.body) as Map<String, dynamic>)['trackId']
          as String,
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
