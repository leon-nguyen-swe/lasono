import 'package:flutter_test/flutter_test.dart';

import 'package:lasono_app/models/track_page.dart';

void main() {
  group('TrackPage.fromJson', () {
    test('maps the items and the cursor of GET /api/v1/tracks', () {
      final page = TrackPage.fromJson({
        'items': [
          {
            'id': '3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10',
            'title': 'Vietnamese',
            'description': 'A demo track',
            'status': 'PROCESSING',
          },
          {
            'id': '9a1c2d3e-0000-4000-8000-000000000001',
            'title': 'Second',
            'description': '',
            'status': 'READY',
          },
        ],
        'nextCursor': 'abc123',
      });

      expect(page.items.map((track) => track.title), ['Vietnamese', 'Second']);
      expect(page.items.first.id, '3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10');
      expect(page.items.first.description, 'A demo track');
      expect(page.items.last.status, 'READY');
      expect(page.nextCursor, 'abc123');
    });

    test('has no next cursor on the last page', () {
      final page = TrackPage.fromJson({
        'items': [
          {'id': 'abc', 'title': 'Only one', 'description': '', 'status': 'PROCESSING'},
        ],
        'nextCursor': null,
      });

      expect(page.nextCursor, isNull);
    });

    test('accepts an empty page', () {
      final page = TrackPage.fromJson({'items': [], 'nextCursor': null});

      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
    });

    test('list items carry no mime type or duration', () {
      final page = TrackPage.fromJson({
        'items': [
          {'id': 'abc', 'title': 'Listed', 'description': '', 'status': 'PROCESSING'},
        ],
        'nextCursor': null,
      });

      expect(page.items.single.mimeType, isNull);
      expect(page.items.single.durationSeconds, isNull);
    });
  });
}
