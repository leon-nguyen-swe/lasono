import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_auth_server.dart';
import 'support/test_harness.dart';

void main() {
  testWidgets('does not show the debug banner in the corner', (WidgetTester tester) async {
    TestEnv.window(tester, width: 1280);
    final env = await TestEnv.create();

    await tester.pumpWidget(env.app());
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).debugShowCheckedModeBanner, isFalse);
  });

  group('looking for a session when the app opens', () {
    late FakeAuthServer server;
    late int listCalls;
    late MockClient client;

    setUp(() {
      server = FakeAuthServer();
      listCalls = 0;
      client = MockClient((_) async {
        listCalls++;
        return http.Response('{"items": [], "nextCursor": null}', 200);
      });
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('waits for the answer before it asks for the tracks', (WidgetTester tester) async {
      TestEnv.window(tester, width: 1280);
      final answer = Completer<http.Response>();
      server.onRefresh = () => answer.future;
      final env = await TestEnv.create(authServer: server, restore: false, client: client);

      await tester.pumpWidget(env.app());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('LaSono'), findsOneWidget);
      expect(listCalls, 0);

      answer.complete(http.Response('', 401));
      await settle(tester);

      expect(listCalls, 1);
      expect(find.byKey(const Key('loginButton')), findsOneWidget);
    });

    testWidgets('signs the user in again when the refresh cookie is valid', (WidgetTester tester) async {
      TestEnv.window(tester, width: 1280);
      server.hasSession = true;
      final env = await TestEnv.create(authServer: server, restore: false, client: client);

      await tester.pumpWidget(env.app());
      await settle(tester);

      expect(find.byKey(const Key('accountMenu')), findsOneWidget);
      expect(find.byKey(const Key('loginButton')), findsNothing);
    });

    testWidgets('opens signed out when the server cannot be reached', (WidgetTester tester) async {
      TestEnv.window(tester, width: 1280);
      server.onRefresh = () => throw http.ClientException('down');
      final env = await TestEnv.create(authServer: server, restore: false, client: client);

      await tester.pumpWidget(env.app());
      await settle(tester);

      expect(find.byKey(const Key('loginButton')), findsOneWidget);
    });

    testWidgets('does not look again when the session is already known', (WidgetTester tester) async {
      TestEnv.window(tester, width: 1280);
      final env = await TestEnv.create(authServer: server, signedIn: true, client: client);
      server.requests.clear();

      await tester.pumpWidget(env.app());
      await settle(tester);

      expect(server.count('POST /api/v1/auth/refresh'), 0);
      expect(find.byKey(const Key('accountMenu')), findsOneWidget);
    });
  });
}
