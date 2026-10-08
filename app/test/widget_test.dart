import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/test_harness.dart';

/// A server whose track list is one page with these titles.
MockClient _listClient(List<String> titles) => MockClient(
      (_) async => http.Response(
        jsonEncode({
          'items': [
            for (final (index, title) in titles.indexed)
              {
                'id': 'id-$index',
                'title': title,
                'description': '',
                'status': 'PROCESSING',
              },
          ],
          'nextCursor': null,
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

Future<void> _open(WidgetTester tester, {List<String> titles = const []}) async {
  TestEnv.window(tester, width: 1280, height: 1000);
  final env = await TestEnv.create(client: _listClient(titles));
  await tester.pumpWidget(env.app());
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('shows the LaSono name in the top bar', (WidgetTester tester) async {
    await _open(tester);

    expect(find.text('LaSono'), findsWidgets);
  });

  testWidgets('does not ship the counter demo', (WidgetTester tester) async {
    await _open(tester);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('opens on the list of tracks', (WidgetTester tester) async {
    await _open(tester, titles: ['Vietnamese', 'Second']);

    expect(find.text('Vietnamese'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.byKey(const Key('uploadButton')), findsOneWidget);
  });
}
