import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/main.dart';

const _trackId = '3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10';

TrackApi _api(MockClientHandler handler) =>
    TrackApi(baseUrl: 'http://api.test', client: MockClient(handler));

void main() {
  testWidgets('shows the LaSono title screen', (WidgetTester tester) async {
    await tester.pumpWidget(const LasonoApp());

    expect(find.text('LaSono'), findsOneWidget);
  });

  testWidgets('does not ship the counter demo', (WidgetTester tester) async {
    await tester.pumpWidget(const LasonoApp());

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('Load fetches the trimmed id and shows the track metadata',
      (WidgetTester tester) async {
    late Uri requested;
    final api = _api((request) async {
      requested = request.url;
      return http.Response(
        jsonEncode({
          'id': _trackId,
          'title': 'Vietnamese',
          'description': 'A demo track',
          'status': 'PROCESSING',
          'mimeType': 'audio/mpeg',
          'durationSeconds': null,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    await tester.pumpWidget(LasonoApp(api: api));

    await tester.enterText(
      find.byKey(const Key('trackIdField')),
      '  $_trackId  ',
    );
    await tester.tap(find.byKey(const Key('loadButton')));
    await tester.pumpAndSettle();

    expect(requested.path, '/api/v1/tracks/$_trackId');
    expect(find.text('Vietnamese'), findsOneWidget);
    expect(find.text('A demo track'), findsOneWidget);
    expect(find.text('PROCESSING'), findsOneWidget);
  });

  testWidgets('shows "Track not found" on a 404', (WidgetTester tester) async {
    final api = _api((_) async => http.Response('{"status":404}', 404));
    await tester.pumpWidget(LasonoApp(api: api));

    await tester.enterText(find.byKey(const Key('trackIdField')), _trackId);
    await tester.tap(find.byKey(const Key('loadButton')));
    await tester.pumpAndSettle();

    expect(find.text('Track not found'), findsOneWidget);
  });

  testWidgets('asks for an id without calling the API when the field is empty',
      (WidgetTester tester) async {
    var calls = 0;
    final api = _api((_) async {
      calls++;
      return http.Response('{}', 200);
    });
    await tester.pumpWidget(LasonoApp(api: api));

    await tester.tap(find.byKey(const Key('loadButton')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a track id'), findsOneWidget);
    expect(calls, 0);
  });
}
