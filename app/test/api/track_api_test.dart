import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';

const _trackJson = {
  'id': '3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10',
  'title': 'Vietnamese',
  'description': 'A demo track',
  'status': 'PROCESSING',
  'mimeType': 'audio/mpeg',
  'durationSeconds': null,
};

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('TrackApi.getTrack', () {
    test('requests GET {baseUrl}/api/v1/tracks/{id}', () async {
      late http.Request captured;
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          captured = request;
          return _json(_trackJson, 200);
        }),
      );

      await api.getTrack('3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10');

      expect(captured.method, 'GET');
      expect(
        captured.url.toString(),
        'http://api.test/api/v1/tracks/3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10',
      );
    });

    test('ignores a trailing slash on baseUrl', () async {
      late Uri captured;
      final api = TrackApi(
        baseUrl: 'http://api.test/',
        client: MockClient((request) async {
          captured = request.url;
          return _json(_trackJson, 200);
        }),
      );

      await api.getTrack('abc');

      expect(captured.toString(), 'http://api.test/api/v1/tracks/abc');
    });

    test('returns the parsed track on 200', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json(_trackJson, 200)),
      );

      final track = await api.getTrack('abc');

      expect(track.title, 'Vietnamese');
      expect(track.status, 'PROCESSING');
    });

    test('maps 404 to "Track not found"', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json({'status': 404}, 404)),
      );

      expect(
        () => api.getTrack('abc'),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Track not found'),
        ),
      );
    });

    test('maps 400 to "Invalid id"', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json({'status': 400}, 400)),
      );

      expect(
        () => api.getTrack('not-a-uuid'),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Invalid id'),
        ),
      );
    });

    test('maps other statuses to a generic server error', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json({'status': 500}, 500)),
      );

      expect(
        () => api.getTrack('abc'),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Server error (500)'),
        ),
      );
    });

    test('maps a stalled request to "Request timed out"', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        requestTimeout: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return _json(_trackJson, 200);
        }),
      );

      expect(
        () => api.getTrack('abc'),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Request timed out'),
        ),
      );
    });

    test('maps a network failure to a generic connection message', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => throw http.ClientException('boom')),
      );

      expect(
        () => api.getTrack('abc'),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Cannot reach the server'),
        ),
      );
    });
  });

  group('TrackApi.listTracks', () {
    const pageJson = {
      'items': [
        {
          'id': '3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10',
          'title': 'Vietnamese',
          'description': 'A demo track',
          'status': 'PROCESSING',
        },
      ],
      'nextCursor': 'next-page',
    };

    test('requests GET {baseUrl}/api/v1/tracks without parameters by default',
        () async {
      late http.Request captured;
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          captured = request;
          return _json(pageJson, 200);
        }),
      );

      await api.listTracks();

      expect(captured.method, 'GET');
      expect(captured.url.toString(), 'http://api.test/api/v1/tracks');
    });

    test('sends the cursor and the limit as query parameters', () async {
      late Uri captured;
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          captured = request.url;
          return _json(pageJson, 200);
        }),
      );

      // A cursor can contain characters that need URL encoding.
      await api.listTracks(cursor: 'a+b/c=', limit: 5);

      expect(captured.path, '/api/v1/tracks');
      expect(captured.queryParameters, {'cursor': 'a+b/c=', 'limit': '5'});
    });

    test('returns the parsed page on 200', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json(pageJson, 200)),
      );

      final page = await api.listTracks();

      expect(page.items.single.title, 'Vietnamese');
      expect(page.nextCursor, 'next-page');
    });

    test('maps other statuses to a generic server error', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json({'status': 500}, 500)),
      );

      expect(
        () => api.listTracks(),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Server error (500)'),
        ),
      );
    });

    test('maps a stalled request to "Request timed out"', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        requestTimeout: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return _json(pageJson, 200);
        }),
      );

      expect(
        () => api.listTracks(),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Request timed out'),
        ),
      );
    });

    test('maps a network failure to a generic connection message', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => throw http.ClientException('boom')),
      );

      expect(
        () => api.listTracks(),
        throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', 'Cannot reach the server'),
        ),
      );
    });
  });

  group('TrackApi.streamUrl', () {
    test('points at /api/v1/tracks/{id}/stream on the configured base url', () {
      final api = TrackApi(
        baseUrl: 'http://api.test/',
        client: MockClient((_) async => http.Response('', 200)),
      );

      expect(
        api.streamUrl('abc').toString(),
        'http://api.test/api/v1/tracks/abc/stream',
      );
    });
  });

  group('TrackApi.uploadTrack', () {
    final audio = Uint8List.fromList(List.filled(16, 1));

    TrackApi apiWith(MockClientHandler handler) =>
        TrackApi(baseUrl: 'http://api.test', client: MockClient(handler));

    Matcher failsWith(String message) => throwsA(
          isA<TrackApiException>()
              .having((e) => e.message, 'message', message),
        );

    http.Response created() => _json(
          {'trackId': 'abc', 'title': 'My Song', 'status': 'PROCESSING'},
          201,
        );

    test('posts a multipart form with title, description and the file part',
        () async {
      late http.Request captured;
      final api = apiWith((request) async {
        captured = request;
        return created();
      });

      final trackId = await api.uploadTrack(
        title: 'My Song',
        description: 'desc',
        filename: 'song.mp3',
        bytes: audio,
      );

      expect(trackId, 'abc');
      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'http://api.test/api/v1/tracks');
      expect(captured.headers['content-type'], startsWith('multipart/form-data'));
      final body = captured.body.toLowerCase();
      expect(body, contains('name="title"'));
      expect(body, contains('my song'));
      expect(body, contains('name="description"'));
      expect(body, contains('name="file"'));
      expect(body, contains('filename="song.mp3"'));
      expect(body, contains('content-type: audio/mpeg'));
    });

    test('sends audio/wav for a .WAV file regardless of case', () async {
      late http.Request captured;
      final api = apiWith((request) async {
        captured = request;
        return created();
      });

      await api.uploadTrack(
        title: 'My Song',
        filename: 'SONG.WAV',
        bytes: audio,
      );

      expect(captured.body.toLowerCase(), contains('content-type: audio/wav'));
    });

    test('maps 415 to "Unsupported audio format"', () async {
      final api = apiWith((_) async => _json({'status': 415}, 415));

      expect(
        () => api.uploadTrack(title: 'T', filename: 'a.mp3', bytes: audio),
        failsWith('Unsupported audio format'),
      );
    });

    test('maps 400 to the server detail when present', () async {
      final api = apiWith(
        (_) async =>
            _json({'status': 400, 'detail': 'Track title must not be blank'}, 400),
      );

      expect(
        () => api.uploadTrack(title: 'T', filename: 'a.mp3', bytes: audio),
        failsWith('Track title must not be blank'),
      );
    });

    test('maps 400 without a body to "Invalid upload"', () async {
      final api = apiWith((_) async => http.Response('', 400));

      expect(
        () => api.uploadTrack(title: 'T', filename: 'a.mp3', bytes: audio),
        failsWith('Invalid upload'),
      );
    });

    test('maps 413 to the size message', () async {
      final api = apiWith((_) async => _json({'status': 413}, 413));

      expect(
        () => api.uploadTrack(title: 'T', filename: 'a.mp3', bytes: audio),
        failsWith('File too large (max 50 MB)'),
      );
    });

    test('maps other statuses to a generic server error', () async {
      final api = apiWith((_) async => _json({'status': 500}, 500));

      expect(
        () => api.uploadTrack(title: 'T', filename: 'a.mp3', bytes: audio),
        failsWith('Server error (500)'),
      );
    });

    test('maps a stalled upload to "Upload timed out"', () async {
      final api = TrackApi(
        baseUrl: 'http://api.test',
        uploadTimeout: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return created();
        }),
      );

      expect(
        () => api.uploadTrack(title: 'T', filename: 'a.mp3', bytes: audio),
        failsWith('Upload timed out'),
      );
    });

    test('maps a network failure to a generic connection message', () async {
      final api = apiWith((_) async => throw http.ClientException('boom'));

      expect(
        () => api.uploadTrack(title: 'T', filename: 'a.mp3', bytes: audio),
        failsWith('Cannot reach the server'),
      );
    });

    group('client-side validation (nothing is sent)', () {
      late int calls;
      late TrackApi api;

      setUp(() {
        calls = 0;
        api = apiWith((_) async {
          calls++;
          return created();
        });
      });

      tearDown(() => expect(calls, 0));

      test('rejects a blank title', () {
        expect(
          () => api.uploadTrack(title: '   ', filename: 'a.mp3', bytes: audio),
          failsWith('Enter a title'),
        );
      });

      test('rejects an empty file', () {
        expect(
          () => api.uploadTrack(
            title: 'T',
            filename: 'a.mp3',
            bytes: Uint8List(0),
          ),
          failsWith('File is empty'),
        );
      });

      test('rejects an unsupported extension', () {
        expect(
          () => api.uploadTrack(title: 'T', filename: 'notes.txt', bytes: audio),
          failsWith('Only MP3 and WAV files are supported'),
        );
      });

      test('rejects a file larger than the 50 MB limit', () {
        expect(
          () => api.uploadTrack(
            title: 'T',
            filename: 'a.mp3',
            bytes: Uint8List(maxUploadBytes + 1),
          ),
          failsWith('File too large (max 50 MB)'),
        );
      });
    });
  });
}
