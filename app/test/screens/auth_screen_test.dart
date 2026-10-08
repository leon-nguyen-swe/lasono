import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:lasono_app/auth/session_controller.dart';
import 'package:lasono_app/screens/auth_screen.dart';

import '../fake_auth_server.dart';

Future<void> _openAuthScreen(WidgetTester tester, SessionController session) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const Key('open'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => AuthScreen(session: session)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

Future<void> _fill(
  WidgetTester tester, {
  String email = 'ann@example.com',
  String password = 'secret pass',
  String? displayName,
}) async {
  await tester.enterText(find.byKey(const Key('emailField')), email);
  await tester.enterText(find.byKey(const Key('passwordField')), password);
  if (displayName != null) {
    await tester.enterText(find.byKey(const Key('displayNameField')), displayName);
  }
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('submitButton')));
  await tester.pumpAndSettle();
}

void main() {
  late FakeAuthServer server;
  late SessionController session;

  setUp(() async {
    server = FakeAuthServer();
    session = await server.signedOutSession();
    server.requests.clear();
  });

  testWidgets('starts as a login form with an email and a password only',
      (tester) async {
    await _openAuthScreen(tester, session);

    expect(find.byKey(const Key('emailField')), findsOneWidget);
    expect(find.byKey(const Key('passwordField')), findsOneWidget);
    expect(find.byKey(const Key('displayNameField')), findsNothing);
  });

  testWidgets('hides what is typed in the password field', (tester) async {
    await _openAuthScreen(tester, session);

    final field = tester.widget<TextField>(find.byKey(const Key('passwordField')));
    expect(field.obscureText, isTrue);
  });

  group('logging in', () {
    testWidgets('sends the email and the password, signs in and closes the screen',
        (tester) async {
      await _openAuthScreen(tester, session);

      await _fill(tester, email: 'ann@example.com', password: 'secret pass');
      await _submit(tester);

      expect(server.bodies['POST /api/v1/auth/login'],
          {'email': 'ann@example.com', 'password': 'secret pass'});
      expect(session.status, SessionStatus.signedIn);
      expect(find.byType(AuthScreen), findsNothing);
    });

    testWidgets('shows the reason and stays on the screen when it fails',
        (tester) async {
      server.onLogin = () => http.Response('', 401);
      await _openAuthScreen(tester, session);

      await _fill(tester);
      await _submit(tester);

      expect(find.text('Wrong email or password'), findsOneWidget);
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(session.status, SessionStatus.signedOut);
    });

    testWidgets('asks to fill in the fields instead of sending an empty form',
        (tester) async {
      await _openAuthScreen(tester, session);

      await _fill(tester, email: '  ', password: '');
      await _submit(tester);

      expect(find.text('Fill in every field'), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('takes the same form once more after a failure', (tester) async {
      server.onLogin = () => http.Response('', 401);
      await _openAuthScreen(tester, session);
      await _fill(tester);
      await _submit(tester);

      server.onLogin = null;
      await _submit(tester);

      expect(find.text('Wrong email or password'), findsNothing);
      expect(session.status, SessionStatus.signedIn);
    });

    testWidgets('sends one request even if the button is pressed twice',
        (tester) async {
      final answer = Completer<http.Response>();
      server.onLogin = () => answer.future;
      await _openAuthScreen(tester, session);
      await _fill(tester);

      await tester.tap(find.byKey(const Key('submitButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submitButton')), warnIfMissed: false);
      await tester.pump();
      answer.complete(http.Response(
        jsonEncode({'accessToken': 'a', 'tokenType': 'Bearer', 'expiresIn': 900}),
        200,
        headers: {'content-type': 'application/json'},
      ));
      await tester.pumpAndSettle();

      expect(server.count('POST /api/v1/auth/login'), 1);
    });
  });

  group('creating an account', () {
    Future<void> switchToRegister(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('switchModeButton')));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for a name as well', (tester) async {
      await _openAuthScreen(tester, session);

      await switchToRegister(tester);

      expect(find.byKey(const Key('displayNameField')), findsOneWidget);
    });

    testWidgets('registers, then signs in with the same details, and closes',
        (tester) async {
      await _openAuthScreen(tester, session);
      await switchToRegister(tester);

      await _fill(tester, displayName: 'Ann');
      await _submit(tester);

      expect(server.bodies['POST /api/v1/auth/register'], {
        'email': 'ann@example.com',
        'displayName': 'Ann',
        'password': 'secret pass',
      });
      expect(session.status, SessionStatus.signedIn);
      expect(find.byType(AuthScreen), findsNothing);
    });

    testWidgets('tells that the email is taken', (tester) async {
      server.onRegister = () => http.Response('', 409);
      await _openAuthScreen(tester, session);
      await switchToRegister(tester);

      await _fill(tester, displayName: 'Ann');
      await _submit(tester);

      expect(find.text('This email is already registered'), findsOneWidget);
      expect(session.status, SessionStatus.signedOut);
    });

    testWidgets('needs the name too', (tester) async {
      await _openAuthScreen(tester, session);
      await switchToRegister(tester);

      await _fill(tester, displayName: ' ');
      await _submit(tester);

      expect(find.text('Fill in every field'), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('goes back to the login form, and clears the old error',
        (tester) async {
      server.onLogin = () => http.Response('', 401);
      await _openAuthScreen(tester, session);
      await _fill(tester);
      await _submit(tester);
      expect(find.text('Wrong email or password'), findsOneWidget);

      await switchToRegister(tester);
      expect(find.text('Wrong email or password'), findsNothing);
      await switchToRegister(tester);

      expect(find.byKey(const Key('displayNameField')), findsNothing);
    });
  });
}
