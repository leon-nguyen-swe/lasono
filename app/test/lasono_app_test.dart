import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/main.dart';

void main() {
  testWidgets('does not show the debug banner in the corner', (WidgetTester tester) async {
    final api = TrackApi(
      baseUrl: 'http://api.test',
      client: MockClient(
        (_) async => http.Response('{"items": [], "nextCursor": null}', 200),
      ),
    );

    await tester.pumpWidget(LasonoApp(api: api));
    await tester.pumpAndSettle();

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).debugShowCheckedModeBanner, isFalse);
  });
}
