import 'package:flutter_test/flutter_test.dart';

import 'package:lasono_app/models/track.dart';

void main() {
  group('Track.fromJson', () {
    test('maps every field of the GET /api/v1/tracks/{id} response', () {
      final track = Track.fromJson({
        'id': '3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10',
        'title': 'Vietnamese',
        'description': 'A demo track',
        'status': 'PROCESSING',
        'mimeType': 'audio/mpeg',
        'durationSeconds': 12.5,
      });

      expect(track.id, '3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10');
      expect(track.title, 'Vietnamese');
      expect(track.description, 'A demo track');
      expect(track.status, 'PROCESSING');
      expect(track.mimeType, 'audio/mpeg');
      expect(track.durationSeconds, 12.5);
    });

    test('accepts null durationSeconds and mimeType', () {
      final track = Track.fromJson({
        'id': 'abc',
        'title': 'No audio yet',
        'description': '',
        'status': 'PROCESSING',
        'mimeType': null,
        'durationSeconds': null,
      });

      expect(track.mimeType, isNull);
      expect(track.durationSeconds, isNull);
    });

    test('accepts an integer durationSeconds', () {
      final track = Track.fromJson({
        'id': 'abc',
        'title': 'Whole seconds',
        'description': '',
        'status': 'READY',
        'mimeType': 'audio/wav',
        'durationSeconds': 42,
      });

      expect(track.durationSeconds, 42.0);
    });

    test('treats a missing description as empty', () {
      final track = Track.fromJson({
        'id': 'abc',
        'title': 'No description',
        'status': 'PROCESSING',
      });

      expect(track.description, '');
    });
  });
}
