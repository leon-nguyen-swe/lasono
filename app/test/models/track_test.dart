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

    test('maps the owner and the visibility', () {
      final track = Track.fromJson({
        'id': 'abc',
        'ownerId': 'u-1',
        'title': 'Mine',
        'description': '',
        'visibility': 'PRIVATE',
        'status': 'READY',
      });

      expect(track.ownerId, 'u-1');
      expect(track.visibility, 'PRIVATE');
    });

    test('takes a track without these fields as public', () {
      final track = Track.fromJson({
        'id': 'abc',
        'title': 'Old',
        'description': '',
        'status': 'READY',
      });

      expect(track.visibility, 'PUBLIC');
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

    test('maps the waveform peaks of a READY track', () {
      final track = Track.fromJson({
        'id': 'abc',
        'title': 'Ready',
        'description': '',
        'status': 'READY',
        'mimeType': 'audio/mpeg',
        'durationSeconds': 3.5,
        'waveform': [0.1, 0.5, 1],
      });

      expect(track.waveform, [0.1, 0.5, 1.0]);
    });

    test('has no waveform while the track is processing', () {
      final track = Track.fromJson({
        'id': 'abc',
        'title': 'Processing',
        'description': '',
        'status': 'PROCESSING',
        'waveform': null,
      });

      expect(track.waveform, isNull);
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
