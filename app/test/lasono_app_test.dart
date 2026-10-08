import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/main.dart';

import 'fake_auth_server.dart';

void main() {
  testWidgets('does not show the debug banner in the corner', (WidgetTester tester) async {
    final api = TrackApi(
      baseUrl: 'http://api.test',
      client: MockClient(
        (_) async => http.Response('{"items": [], "nextCursor": null}', 200),
      ),
    );

    await tester.pumpWidget(LasonoApp(session: FakeAuthServer().session(), api: api));
    await tester.pumpAndSettle();

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).debugShowCheckedModeBanner, isFalse);
  });

  group('looking for a session when the app opens', () {
    late FakeAuthServer server;
    late int listCalls;
    late TrackApi api;

    setUp(() {
      server = FakeAuthServer();
      listCalls = 0;
      api = TrackApi(
        baseUrl: 'http://api.test',
        client: MockClient((_) async {
          listCalls++;
          return http.Response('{"items": [], "nextCursor": null}', 200);
        }),
      );
    });

    testWidgets('waits for the answer before it asks for the tracks',
        (WidgetTester tester) async {
      final answer = Completer<http.Response>();
      server.onRefresh = () => answer.future;

      await tester.pumpWidget(LasonoApp(session: server.session(), api: api));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('LaSono'), findsOneWidget);
      expect(listCalls, 0);

      answer.complete(http.Response('', 401));
      await tester.pumpAndSettle();

      expect(listCalls, 1);
      expect(find.byKey(const Key('loginAction')), findsOneWidget);
    });

    testWidgets('signs the user in again when the refresh cookie is valid',
        (WidgetTester tester) async {
      server.hasSession = true;

      await tester.pumpWidget(LasonoApp(session: server.session(), api: api));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('accountMenu')), findsOneWidget);
      expect(find.text('Ann'), findsOneWidget);
      expect(find.byKey(const Key('loginAction')), findsNothing);
    });

    testWidgets('opens signed out when the server cannot be reached',
        (WidgetTester tester) async {
      server.onRefresh = () => throw http.ClientException('down');

      await tester.pumpWidget(LasonoApp(session: server.session(), api: api));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('loginAction')), findsOneWidget);
    });

    testWidgets('does not look again when the session is already known',
        (WidgetTester tester) async {
      final session = await server.signedInSession();
      server.requests.clear();

      await tester.pumpWidget(LasonoApp(session: session, api: api));
      await tester.pumpAndSettle();

      expect(server.count('POST /api/v1/auth/refresh'), 0);
      expect(find.text('Ann'), findsOneWidget);
    });
  });
}
