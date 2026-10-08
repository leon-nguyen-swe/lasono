import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/auth/session_controller.dart';
import 'package:lasono_app/screens/auth_screen.dart';
import 'package:lasono_app/screens/track_list_screen.dart';

import '../fake_auth_server.dart';
import '../fake_player_service.dart';

/// A track list that is always empty, and counts how often it was asked for.
class _Tracks {
  int listCalls = 0;

  late final TrackApi api = TrackApi(
    baseUrl: 'http://api.test',
    client: MockClient((request) async {
      listCalls++;
      return http.Response(
        jsonEncode({'items': [], 'nextCursor': null}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Tracks tracks,
  SessionController session,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TrackListScreen(
        session: session,
        api: tracks.api,
        player: FakePlayerService(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _logIn(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('emailField')), 'ann@example.com');
  await tester.enterText(find.byKey(const Key('passwordField')), 'secret pass');
  await tester.tap(find.byKey(const Key('submitButton')));
  await tester.pumpAndSettle();
}

void main() {
  late FakeAuthServer server;
  late _Tracks tracks;

  setUp(() {
    server = FakeAuthServer();
    tracks = _Tracks();
  });

  group('when nobody is logged in', () {
    testWidgets('offers to log in and has no account menu', (tester) async {
      await _pump(tester, tracks, await server.signedOutSession());

      expect(find.byKey(const Key('loginAction')), findsOneWidget);
      expect(find.byKey(const Key('accountMenu')), findsNothing);
    });

    testWidgets('the login action opens the login screen', (tester) async {
      await _pump(tester, tracks, await server.signedOutSession());

      await tester.tap(find.byKey(const Key('loginAction')));
      await tester.pumpAndSettle();

      expect(find.byType(AuthScreen), findsOneWidget);
    });

    testWidgets('after logging in it shows the name, and loads the list again',
        (tester) async {
      await _pump(tester, tracks, await server.signedOutSession());
      expect(tracks.listCalls, 1);

      await tester.tap(find.byKey(const Key('loginAction')));
      await tester.pumpAndSettle();
      await _logIn(tester);

      expect(find.byKey(const Key('loginAction')), findsNothing);
      expect(find.descendant(
        of: find.byKey(const Key('accountMenu')),
        matching: find.text('Ann'),
      ), findsOneWidget);
      expect(tracks.listCalls, 2);
    });

    testWidgets('the upload action asks to log in first, then opens the form',
        (tester) async {
      await _pump(tester, tracks, await server.signedOutSession());

      await tester.tap(find.byKey(const Key('uploadAction')));
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.byKey(const Key('chooseFileButton')), findsNothing);

      await _logIn(tester);

      expect(find.byKey(const Key('chooseFileButton')), findsOneWidget);
    });

    testWidgets('leaving the login screen without logging in opens no upload form',
        (tester) async {
      await _pump(tester, tracks, await server.signedOutSession());

      await tester.tap(find.byKey(const Key('uploadAction')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(AuthScreen), findsNothing);
      expect(find.byKey(const Key('chooseFileButton')), findsNothing);
    });
  });

  group('when someone is logged in', () {
    testWidgets('shows the name and no login action', (tester) async {
      await _pump(tester, tracks, await server.signedInSession());

      expect(find.byKey(const Key('loginAction')), findsNothing);
      expect(find.descendant(
        of: find.byKey(const Key('accountMenu')),
        matching: find.text('Ann'),
      ), findsOneWidget);
    });

    testWidgets('logging out offers to log in again, and loads the list again',
        (tester) async {
      final session = await server.signedInSession();
      await _pump(tester, tracks, session);
      expect(tracks.listCalls, 1);

      await tester.tap(find.byKey(const Key('accountMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logoutAction')));
      await tester.pumpAndSettle();

      expect(session.status, SessionStatus.signedOut);
      expect(server.count('POST /api/v1/auth/logout'), 1);
      expect(find.byKey(const Key('loginAction')), findsOneWidget);
      expect(find.byKey(const Key('accountMenu')), findsNothing);
      expect(tracks.listCalls, 2);
    });

    testWidgets('the upload action opens the form at once', (tester) async {
      await _pump(tester, tracks, await server.signedInSession());

      await tester.tap(find.byKey(const Key('uploadAction')));
      await tester.pumpAndSettle();

      expect(find.byType(AuthScreen), findsNothing);
      expect(find.byKey(const Key('chooseFileButton')), findsOneWidget);
    });

    testWidgets('a new access token alone does not reload the list',
        (tester) async {
      final session = await server.signedInSession();
      server.hasSession = true;
      await _pump(tester, tracks, session);

      await session.refreshAccessToken();
      await tester.pumpAndSettle();

      expect(tracks.listCalls, 1);
    });
  });
}
