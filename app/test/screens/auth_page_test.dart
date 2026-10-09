import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:lasono_app/auth/session_controller.dart';
import 'package:lasono_app/core/theme/theme.dart';
import 'package:lasono_app/screens/auth_page.dart';

import '../fake_auth_server.dart';
import '../support/test_harness.dart';

http.Response _problem(int status, String detail) => http.Response(
      jsonEncode({'detail': detail}),
      status,
      headers: {'content-type': 'application/json'},
    );

Future<void> _fill(WidgetTester tester, {String email = 'ann@example.com', String password = 'secret pass', String? name}) async {
  await tester.enterText(find.byKey(const Key('emailField')), email);
  if (name != null) await tester.enterText(find.byKey(const Key('displayNameField')), name);
  await tester.enterText(find.byKey(const Key('passwordField')), password);
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('submitButton')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('describeAuthError', () {
    test('puts a message of the server under the field it is about, in Vietnamese', () {
      expect(describeAuthError('Email is not valid').field, AuthField.email);
      expect(describeAuthError('Email must be at most 254 characters'), (field: AuthField.email, text: 'Email tối đa 254 ký tự.'));
      expect(describeAuthError('Display name must not be blank').field, AuthField.displayName);
      expect(describeAuthError('Display name must be at most 50 characters').text, 'Tên hiển thị tối đa 50 ký tự.');
      expect(describeAuthError('Password must be at least 8 characters').text, 'Mật khẩu cần ít nhất 8 ký tự.');
      expect(describeAuthError('Password must be at most 72 bytes').field, AuthField.password);
      expect(describeAuthError('This email is already registered').field, AuthField.email);
    });

    test('a failure that is about no field goes to the form', () {
      expect(describeAuthError('Wrong email or password').field, AuthField.form);
      expect(describeAuthError('Cannot reach the server').field, AuthField.form);
      expect(describeAuthError('Server error (500)').field, AuthField.form);
    });

    test('a message it does not know is shown as it is, on the form', () {
      expect(describeAuthError('Something new'), (field: AuthField.form, text: 'Something new'));
    });
  });

  group('AuthPage in the app', () {
    late TestEnv env;

    setUp(() async {
      env = await TestEnv.create();
    });

    testWidgets('/login shows a login form with an email and a password only', (tester) async {
      TestEnv.window(tester, width: 1280);
      await tester.pumpWidget(env.app(location: '/login'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('authTitle')), findsOneWidget);
      expect(find.byKey(const Key('emailField')), findsOneWidget);
      expect(find.byKey(const Key('passwordField')), findsOneWidget);
      expect(find.byKey(const Key('displayNameField')), findsNothing);
    });

    testWidgets('/register asks for a name as well', (tester) async {
      TestEnv.window(tester, width: 1280);
      await tester.pumpWidget(env.app(location: '/register'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('displayNameField')), findsOneWidget);
    });

    testWidgets('the link under the form moves between the two modes', (tester) async {
      TestEnv.window(tester, width: 1280);
      await tester.pumpWidget(env.app(location: '/login'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('switchModeButton')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('displayNameField')), findsOneWidget);

      await tester.tap(find.byKey(const Key('switchModeButton')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('displayNameField')), findsNothing);
    });
  });

  group('AuthPage on its own', () {
    late FakeAuthServer server;
    late SessionController session;
    late GoRouter router;
    String? wentTo() => router.routeInformationProvider.value.uri.toString() == '/auth' ? null : router.routeInformationProvider.value.uri.toString();

    setUp(() async {
      server = FakeAuthServer();
      session = await server.signedOutSession();
      server.requests.clear();
    });

    Future<void> open(WidgetTester tester, {bool registering = false, String? from, double width = 1280}) async {
      TestEnv.window(tester, width: width, height: 900);
      router = GoRouter(
        initialLocation: '/auth',
        routes: [
          GoRoute(path: '/auth', builder: (_, _) => AuthPage(session: session, registering: registering, from: from)),
          GoRoute(path: '/', builder: (_, _) => const Text('home')),
          GoRoute(path: '/tracks/:id', builder: (_, _) => const Text('track')),
          GoRoute(path: '/login', builder: (_, _) => const Text('login')),
          GoRoute(path: '/register', builder: (_, _) => const Text('register')),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router, theme: AppTheme.dark));
      await tester.pump();
    }

    testWidgets('asks the browser not to fill the fields in (autofill broke editing the password in the browser)', (tester) async {
      await open(tester, registering: true);

      for (final key in const ['emailField', 'displayNameField', 'passwordField']) {
        final field = tester.widget<TextField>(find.byKey(Key(key)));
        expect(field.autofillHints, isEmpty, reason: key);
        expect(field.enableSuggestions, isFalse, reason: key);
        expect(field.autocorrect, isFalse, reason: key);
      }
      expect(find.byType(AutofillGroup), findsNothing);
    });

    testWidgets('hides the password, and the eye button shows it', (tester) async {
      await open(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('passwordField'))).obscureText, isTrue);

      await tester.tap(find.byKey(const Key('togglePassword')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('passwordField'))).obscureText, isFalse);
    });

    testWidgets('sends the email and the password, signs in and goes home', (tester) async {
      await open(tester);
      await _fill(tester);
      await _submit(tester);

      expect(server.bodies['POST /api/v1/auth/login'], {'email': 'ann@example.com', 'password': 'secret pass'});
      expect(session.status, SessionStatus.signedIn);
      expect(wentTo(), '/');
    });

    testWidgets('goes back to where the user came from', (tester) async {
      await open(tester, from: '/tracks/abc');
      await _fill(tester);
      await _submit(tester);
      expect(wentTo(), '/tracks/abc');
    });

    testWidgets('does not go to a place outside the app', (tester) async {
      await open(tester, from: '//evil.example');
      await _fill(tester);
      await _submit(tester);
      expect(wentTo(), '/');
    });

    testWidgets('a wrong password is said on the form, not under a field', (tester) async {
      server.onLogin = () => http.Response('', 401);
      await open(tester);
      await _fill(tester);
      await _submit(tester);

      expect(find.byKey(const Key('formError')), findsOneWidget);
      expect(find.text('Email hoặc mật khẩu không đúng.'), findsOneWidget);
      expect(session.status, SessionStatus.signedOut);
      expect(wentTo(), isNull);
    });

    testWidgets('empty fields are said under the fields and nothing is sent', (tester) async {
      await open(tester);
      await _fill(tester, email: '  ', password: '');
      await _submit(tester);

      expect(find.text('Hãy nhập email.'), findsOneWidget);
      expect(find.text('Hãy nhập mật khẩu.'), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('sends one request even if the button is pressed twice', (tester) async {
      final answer = Completer<http.Response>();
      server.onLogin = () => answer.future;
      await open(tester);
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
      await tester.pump(const Duration(milliseconds: 50));

      expect(server.count('POST /api/v1/auth/login'), 1);
    });

    testWidgets('tries again after a failure with the same form', (tester) async {
      server.onLogin = () => http.Response('', 401);
      await open(tester);
      await _fill(tester);
      await _submit(tester);

      server.onLogin = null;
      await _submit(tester);

      expect(find.byKey(const Key('formError')), findsNothing);
      expect(session.status, SessionStatus.signedIn);
    });

    group('creating an account', () {
      testWidgets('registers, then signs in with the same details', (tester) async {
        await open(tester, registering: true);
        await _fill(tester, name: 'Ann');
        await _submit(tester);

        expect(server.bodies['POST /api/v1/auth/register'], {
          'email': 'ann@example.com',
          'displayName': 'Ann',
          'password': 'secret pass',
        });
        expect(session.status, SessionStatus.signedIn);
        expect(wentTo(), '/');
      });

      testWidgets('a taken email is said under the email field', (tester) async {
        server.onRegister = () => http.Response('', 409);
        await open(tester, registering: true);
        await _fill(tester, name: 'Ann');
        await _submit(tester);

        expect(find.text('Email này đã được đăng ký. Hãy đăng nhập.'), findsOneWidget);
        expect(find.byKey(const Key('formError')), findsNothing);
        expect(session.status, SessionStatus.signedOut);
      });

      testWidgets('a short password and a missing name are caught before asking the server', (tester) async {
        await open(tester, registering: true);
        await _fill(tester, name: ' ', password: 'short');
        await _submit(tester);

        expect(find.text('Hãy nhập tên hiển thị.'), findsOneWidget);
        expect(find.text('Mật khẩu cần ít nhất 8 ký tự.'), findsOneWidget);
        expect(server.requests, isEmpty);
      });

      testWidgets('a problem the server finds is put under the field it is about', (tester) async {
        server.onRegister = () => _problem(400, 'Display name must be at most 50 characters');
        await open(tester, registering: true);
        await _fill(tester, name: 'Ann');
        await _submit(tester);

        expect(find.text('Tên hiển thị tối đa 50 ký tự.'), findsOneWidget);
        expect(find.byKey(const Key('formError')), findsNothing);
      });
    });

    testWidgets('on a wide window the brand panel is beside the form, on a phone it is not', (tester) async {
      await open(tester, width: 1280);
      expect(find.byKey(const Key('brandPanel')), findsOneWidget);

      await open(tester, width: 390);
      await tester.pump();
      expect(find.byKey(const Key('brandPanel')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a very narrow window without overflow', (tester) async {
      await open(tester, registering: true, width: 320);
      expect(tester.takeException(), isNull);
    });
  });
}
