import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lasono_app/app_router.dart';
import 'package:lasono_app/auth/session_controller.dart';

import 'fake_auth_server.dart';
import 'support/test_harness.dart';

String? _go(SessionStatus status, String location, {bool debug = true}) =>
    redirectFor(status: status, location: Uri.parse(location), debug: debug);

/// The app has a spinner on some pages, which never stops turning, so pumpAndSettle would never come back.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  group('the route guard', () {
    test('while the login is being looked for, everything waits on the splash page and remembers where it was', () {
      expect(_go(SessionStatus.restoring, '/'), '/splash?from=%2F');
      expect(_go(SessionStatus.restoring, '/search?q=son'), '/splash?from=%2Fsearch%3Fq%3Dson');
      expect(_go(SessionStatus.restoring, '/splash?from=%2F'), isNull, reason: 'already there');
    });

    test('once the answer is known the splash page leads back to where the user was', () {
      expect(_go(SessionStatus.signedOut, '/splash?from=%2Ffeed'), '/feed');
      expect(_go(SessionStatus.signedIn, '/splash?from=%2Fsearch%3Fq%3Dson'), '/search?q=son');
      expect(_go(SessionStatus.signedOut, '/splash'), '/');
    });

    test('a place outside the app cannot be returned to', () {
      expect(_go(SessionStatus.signedOut, '/splash?from=https%3A%2F%2Fevil.test'), '/');
      expect(_go(SessionStatus.signedOut, '/splash?from=%2F%2Fevil.test'), '/');
      expect(_go(SessionStatus.signedIn, '/login?from=https%3A%2F%2Fevil.test'), '/');
    });

    test('without a login, a page that needs one leads to the login and back', () {
      expect(_go(SessionStatus.signedOut, '/upload'), '/login?from=%2Fupload');
      expect(_go(SessionStatus.signedOut, '/feed'), '/login?from=%2Ffeed');
    });

    test('pages that anyone may see stay where they are', () {
      for (final path in ['/', '/search', '/search?q=son', '/login', '/register', '/dev/gallery']) {
        expect(_go(SessionStatus.signedOut, path), isNull, reason: path);
      }
    });

    test('with a login, the pages that need one stay, and the login pages lead back', () {
      expect(_go(SessionStatus.signedIn, '/upload'), isNull);
      expect(_go(SessionStatus.signedIn, '/feed'), isNull);
      expect(_go(SessionStatus.signedIn, '/login?from=%2Fupload'), '/upload');
      expect(_go(SessionStatus.signedIn, '/register'), '/');
    });

    test('the design system page exists only while developing', () {
      expect(_go(SessionStatus.signedOut, '/dev/gallery', debug: false), '/');
      expect(_go(SessionStatus.signedOut, '/dev/gallery', debug: true), isNull);
    });
  });

  group('the app', () {
    testWidgets('opens on the home page of the new frame', (tester) async {
      TestEnv.window(tester, width: 1280);
      final env = await TestEnv.create();

      await tester.pumpWidget(env.app());
      await _settle(tester);

      expect(find.byKey(const Key('loginButton')), findsOneWidget);
      expect(find.byKey(const Key('uploadButton')), findsOneWidget);
      expect(find.byKey(const Key('homeEmpty')), findsOneWidget);
    });

    testWidgets('waits on the splash page until the login is looked for, then shows the list', (tester) async {
      TestEnv.window(tester, width: 1280);
      final server = FakeAuthServer();
      final answer = Completer<http.Response>();
      server.onRefresh = () => answer.future;
      final env = await TestEnv.create(authServer: server, restore: false);

      await tester.pumpWidget(env.app());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('LaSono'), findsOneWidget);
      expect(find.byKey(const Key('loginButton')), findsNothing);

      answer.complete(http.Response('', 401));
      await _settle(tester);

      expect(find.byKey(const Key('loginButton')), findsOneWidget);
    });

    testWidgets('an unknown address shows the 404 page, and the button leads home', (tester) async {
      TestEnv.window(tester, width: 1280);
      final env = await TestEnv.create();

      await tester.pumpWidget(env.app(location: '/nothing/here'));
      await _settle(tester);

      expect(find.byKey(const Key('notFoundCode')), findsOneWidget);
      expect(find.text('Không tìm thấy trang này.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('notFoundHome')));
      await _settle(tester);
      expect(find.byKey(const Key('loginButton')), findsOneWidget);
    });

    testWidgets('the login page opens on "Log in", the register page on "Create account"', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();

      await tester.pumpWidget(env.app(location: '/login'));
      await _settle(tester);
      expect(find.byKey(const Key('emailField')), findsOneWidget);
      expect(find.byKey(const Key('displayNameField')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(env.app(location: '/register'));
      await _settle(tester);
      expect(find.byKey(const Key('displayNameField')), findsOneWidget);
    });

    testWidgets('a page that needs a login sends a visitor to the login, and after the login they arrive on it', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();

      await tester.pumpWidget(env.app(location: '/upload'));
      await _settle(tester);
      expect(find.byKey(const Key('emailField')), findsOneWidget, reason: 'the login page, not the upload form');
      expect(find.byKey(const Key('chooseFileButton')), findsNothing);

      await tester.enterText(find.byKey(const Key('emailField')), 'ann@example.com');
      await tester.enterText(find.byKey(const Key('passwordField')), 'secret pass');
      await tester.tap(find.byKey(const Key('submitButton')));
      await _settle(tester);

      expect(find.byKey(const Key('chooseFileButton')), findsOneWidget, reason: 'the upload form the user asked for');
      expect(env.server.count('POST /api/v1/auth/login'), 1);
    });

    testWidgets('a user who is logged in goes straight to the page that needs a login', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create(signedIn: true);

      await tester.pumpWidget(env.app(location: '/upload'));
      await _settle(tester);

      expect(find.byKey(const Key('chooseFileButton')), findsOneWidget);
    });

    testWidgets('the upload page has a way back to the list', (tester) async {
      TestEnv.window(tester, width: 1280);
      final env = await TestEnv.create(signedIn: true);
      await tester.pumpWidget(env.app(location: '/upload'));
      await _settle(tester);

      await tester.tap(find.byType(BackButton));
      await _settle(tester);

      expect(find.byKey(const Key('homeTitle')), findsOneWidget);
    });
  });

  group('the shell around the pages', () {
    testWidgets('a page in the shell has the top bar, and the design system page has the player controls', (tester) async {
      TestEnv.window(tester, height: 6000);
      final env = await TestEnv.create();

      await tester.pumpWidget(env.app(location: '/dev/gallery'));
      await _settle(tester);

      expect(find.byKey(const Key('searchField')), findsOneWidget);
      expect(find.byKey(const Key('uploadButton')), findsOneWidget);
      expect(find.text('Design system'), findsWidgets);
      expect(find.byKey(const Key('playFakeQueue')), findsOneWidget);
      expect(find.byKey(const Key('playerBar')), findsNothing, reason: 'nothing plays yet');
    });

    testWidgets('pressing play shows the player bar, and the music goes on when the page changes', (tester) async {
      TestEnv.window(tester, height: 6000);
      final env = await TestEnv.create(signedIn: true);
      await tester.pumpWidget(env.app(location: '/dev/gallery'));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('playFakeQueue')));
      await _settle(tester);
      expect(find.byKey(const Key('playerBar')), findsOneWidget);
      expect(env.player.playCalls, 1);
      final playing = env.world.tracks.firstWhere((t) => t.isReady);
      Finder inBar() => find.descendant(of: find.byKey(const Key('playerBar')), matching: find.text(playing.title));
      expect(inBar(), findsOneWidget);

      await tester.tap(find.byKey(const Key('navFeed')));
      await _settle(tester);

      expect(find.text('Trang này đang được xây dựng.'), findsOneWidget, reason: 'the Feed page of the shell');
      expect(find.byKey(const Key('playerBar')), findsOneWidget, reason: 'the bar stays on the new page');
      expect(inBar(), findsOneWidget);
      expect(env.player.stopCalls, 0, reason: 'the music was not stopped by changing page');
      expect(env.player.loaded.length, 1, reason: 'and the track was not loaded again');
    });

    testWidgets('Feed needs a login: a visitor who presses it ends up on the login page', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      await tester.pumpWidget(env.app(location: '/dev/gallery'));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('navFeed')));
      await _settle(tester);

      expect(find.byKey(const Key('emailField')), findsOneWidget);
    });

    testWidgets('searching from the top bar opens the search page with the text in its address', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      await tester.pumpWidget(env.app(location: '/dev/gallery'));
      await _settle(tester);

      await tester.enterText(find.byKey(const Key('searchField')), 'son tung');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _settle(tester);

      expect(find.text('Tìm kiếm'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('searchField'))).controller!.text, 'son tung');
    });

    testWidgets('the account menu changes the theme of the whole app', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create(signedIn: true);
      await tester.pumpWidget(env.app(location: '/dev/gallery'));
      await _settle(tester);
      expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.dark);

      await tester.tap(find.byKey(const Key('accountMenu')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('themeAction')));
      await _settle(tester);

      expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.light);
    });

    testWidgets('signing in as another user forgets the names kept for the first', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      await tester.pumpWidget(env.app());
      await _settle(tester);
      await env.repositories.directory.profile(env.world.users.first.id);
      expect(env.repositories.directory.cached(env.world.users.first.id), isNotNull);

      await env.session.login(email: 'ann@example.com', password: 'secret pass');
      await _settle(tester);

      expect(env.repositories.directory.cached(env.world.users.first.id), isNull);
    });
  });
}
