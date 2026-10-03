import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';

/// Backend origin. Override with `--dart-define=API_BASE_URL=...`.
const defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

class TrackApiException implements Exception {
  const TrackApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TrackApi {
  TrackApi({String baseUrl = defaultApiBaseUrl, http.Client? client})
      : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client();

  static const _prefix = '/api/v1';

  final String _baseUrl;
  final http.Client _client;

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
}
