import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/auth/session_controller.dart';
import 'package:lasono_app/core/theme/theme.dart';
import 'package:lasono_app/shell/app_shell.dart';
import 'package:lasono_app/shell/top_bar.dart';

import '../fake_auth_server.dart';
import '../support/test_harness.dart';

class _Calls {
  final events = <String>[];
  void add(String event) => events.add(event);
}

Widget _topBar(
  _Calls calls, {
  required SessionController session,
  ThemeController? theme,
  String location = '/',
  String? searchQuery,
}) {
  return themed(
    TopBar(
      session: session,
      themeController: theme ?? ThemeController(),
      location: location,
      searchQuery: searchQuery,
      onHome: () => calls.add('home'),
      onFeed: () => calls.add('feed'),
      onUpload: () => calls.add('upload'),
      onSearch: (q) => calls.add('search:$q'),
      onLogin: () => calls.add('login'),
      onRegister: () => calls.add('register'),
      onProfile: (id) => calls.add('profile:$id'),
      onLogout: () => calls.add('logout'),
    ),
  );
}

void main() {
  group('the top bar on a wide window', () {
    testWidgets('shows the logo, Home, Feed, the search field and Upload', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();

      await tester.pumpWidget(_topBar(_Calls(), session: env.session));

      expect(find.byKey(const Key('logo')), findsOneWidget);
      expect(find.text('LaSono'), findsOneWidget, reason: 'the name, which is made of two coloured spans, reads as one text');
      expect(find.byType(LaSonoLogo), findsOneWidget);
      expect(find.byKey(const Key('navHome')), findsOneWidget);
      expect(find.byKey(const Key('navFeed')), findsOneWidget);
      expect(find.byKey(const Key('searchField')), findsOneWidget);
      expect(find.byKey(const Key('uploadButton')), findsOneWidget);
    });

    testWidgets('signed out it offers to log in or to create an account', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      final calls = _Calls();
      await tester.pumpWidget(_topBar(calls, session: env.session));

      expect(find.byKey(const Key('accountMenu')), findsNothing);
      await tester.tap(find.byKey(const Key('loginButton')));
      await tester.tap(find.byKey(const Key('registerButton')));

      expect(calls.events, ['login', 'register']);
    });

    testWidgets('while the login is still being looked for there is a grey circle, and no buttons', (tester) async {
      TestEnv.window(tester);
      final session = FakeAuthServer().session(); // never restored: still "restoring"

      await tester.pumpWidget(_topBar(_Calls(), session: session));

      expect(find.byKey(const Key('accountPlaceholder')), findsOneWidget);
      expect(find.byKey(const Key('loginButton')), findsNothing);
      expect(find.byKey(const Key('accountMenu')), findsNothing);
    });

    testWidgets('signed in it shows the avatar, and a menu with the profile, the theme and log out', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create(signedIn: true);
      final calls = _Calls();
      final theme = ThemeController();
      await tester.pumpWidget(_topBar(calls, session: env.session, theme: theme));

      expect(find.byKey(const Key('loginButton')), findsNothing);
      expect(find.text('A'), findsOneWidget, reason: 'the initial of Ann, on the avatar');

      await tester.tap(find.byKey(const Key('accountMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Ann'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profileAction')));
      await tester.pumpAndSettle();
      expect(calls.events, ['profile:u-1']);

      await tester.tap(find.byKey(const Key('accountMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Giao diện sáng'), findsOneWidget, reason: 'the app is dark: the menu offers light');
      await tester.tap(find.byKey(const Key('themeAction')));
      await tester.pumpAndSettle();
      expect(theme.mode, ThemeMode.light);

      await tester.tap(find.byKey(const Key('accountMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Giao diện tối'), findsOneWidget);
      await tester.tap(find.byKey(const Key('logoutAction')));
      await tester.pumpAndSettle();
      expect(calls.events.last, 'logout');
    });

    testWidgets('Home and Feed call their callbacks, and the logo goes home', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      final calls = _Calls();
      await tester.pumpWidget(_topBar(calls, session: env.session));

      await tester.tap(find.byKey(const Key('navFeed')));
      await tester.tap(find.byKey(const Key('navHome')));
      await tester.tap(find.byKey(const Key('logo')));
      await tester.tap(find.byKey(const Key('uploadButton')));

      expect(calls.events, ['feed', 'home', 'home', 'upload']);
    });

    testWidgets('marks the page the user is on', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_topBar(_Calls(), session: env.session, location: '/feed'));

      String selected(String key) => tester.getSemantics(find.byKey(Key(key))).flagsCollection.isSelected.toString();
      expect(selected('navFeed'), 'Tristate.isTrue');
      expect(selected('navHome'), 'Tristate.isFalse');
      handle.dispose();
    });
  });

  group('the search field', () {
    testWidgets('searches after a short pause in typing, not at every letter', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      final calls = _Calls();
      await tester.pumpWidget(_topBar(calls, session: env.session));

      await tester.enterText(find.byKey(const Key('searchField')), 'so');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(const Key('searchField')), 'son');
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls.events, isEmpty, reason: 'the pause restarted with the new letter');

      await tester.pump(const Duration(milliseconds: 150));
      expect(calls.events, ['search:son']);
    });

    testWidgets('one letter is not enough to search', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      final calls = _Calls();
      await tester.pumpWidget(_topBar(calls, session: env.session));

      await tester.enterText(find.byKey(const Key('searchField')), 's');
      await tester.pump(const Duration(seconds: 1));

      expect(calls.events, isEmpty);
    });

    testWidgets('Enter searches at once, with the spaces around the text taken off', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      final calls = _Calls();
      await tester.pumpWidget(_topBar(calls, session: env.session));

      await tester.enterText(find.byKey(const Key('searchField')), '  Sơn Tùng ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(seconds: 1));

      expect(calls.events, ['search:Sơn Tùng'], reason: 'once, not again after the pause');
    });

    testWidgets('shows the text of the page it was opened with, and empties when the page is left', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      final calls = _Calls();
      await tester.pumpWidget(_topBar(calls, session: env.session, location: '/search', searchQuery: 'nang am'));
      expect(tester.widget<TextField>(find.byKey(const Key('searchField'))).controller!.text, 'nang am');

      await tester.pumpWidget(_topBar(calls, session: env.session, location: '/', searchQuery: null));
      expect(tester.widget<TextField>(find.byKey(const Key('searchField'))).controller!.text, isEmpty);
    });
  });

  group('the top bar on a tablet', () {
    testWidgets('at 700 px it uses icons, keeps the word LaSono, and everything is inside the window', (tester) async {
      TestEnv.window(tester, width: 700, height: 800);
      final env = await TestEnv.create();
      await tester.pumpWidget(_topBar(_Calls(), session: env.session));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('searchField')), findsNothing);
      expect(find.byKey(const Key('searchIcon')), findsOneWidget);
      expect(find.byKey(const Key('uploadIcon')), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('logo'))).width, greaterThan(100), reason: 'the word LaSono is beside the bars');
      expect(tester.getTopRight(find.byKey(const Key('loginButton'))).dx, lessThanOrEqualTo(700));
    });

    testWidgets('just under the width of the full bar (899 px) it still uses icons and does not overflow', (tester) async {
      TestEnv.window(tester, width: 899, height: 800);
      final env = await TestEnv.create(signedIn: true);
      await tester.pumpWidget(_topBar(_Calls(), session: env.session));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('searchIcon')), findsOneWidget);
      expect(find.byKey(const Key('accountMenu')), findsOneWidget);
    });
  });

  group('the top bar on a phone', () {
    testWidgets('keeps the logo mark, the icons and the account; the field and the long buttons go', (tester) async {
      TestEnv.window(tester, width: 390, height: 800);
      final env = await TestEnv.create();
      final calls = _Calls();
      await tester.pumpWidget(_topBar(calls, session: env.session));

      expect(find.byKey(const Key('searchField')), findsNothing);
      expect(find.byKey(const Key('uploadButton')), findsNothing);
      expect(find.byKey(const Key('registerButton')), findsNothing);
      expect(find.byKey(const Key('searchIcon')), findsOneWidget);
      expect(find.byKey(const Key('uploadIcon')), findsOneWidget);
      expect(find.byKey(const Key('navHome')), findsNothing, reason: 'the logo is Home on a phone');
      expect(find.byKey(const Key('loginButton')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'nothing overflows at 390 px');

      await tester.tap(find.byKey(const Key('searchIcon')));
      await tester.tap(find.byKey(const Key('uploadIcon')));
      expect(calls.events, ['search:', 'upload']);
    });

    testWidgets('does not overflow at 320 px either, signed in', (tester) async {
      TestEnv.window(tester, width: 320, height: 640);
      final env = await TestEnv.create(signedIn: true);

      await tester.pumpWidget(_topBar(_Calls(), session: env.session));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('accountMenu')), findsOneWidget);
    });
  });

  group('the shell', () {
    testWidgets('puts the page between the top bar and the player bar', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      final went = <String>[];

      await tester.pumpWidget(
        themed(
          AppShell(
            location: '/feed',
            session: env.session,
            themeController: ThemeController(),
            playback: env.newPlayback(),
            directory: env.repositories.directory,
            onGo: went.add,
            child: const Center(child: Text('the page')),
          ),
        ),
      );

      expect(find.text('the page'), findsOneWidget);
      expect(find.byType(TopBar), findsOneWidget);
      // Top bar above the page.
      expect(tester.getTopLeft(find.byType(TopBar)).dy, lessThan(tester.getTopLeft(find.text('the page')).dy));
    });

    testWidgets('sends the user to the login with a way back to where they were', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      final went = <String>[];
      await tester.pumpWidget(
        themed(
          AppShell(
            location: '/search?q=son',
            session: env.session,
            themeController: ThemeController(),
            playback: env.newPlayback(),
            directory: env.repositories.directory,
            onGo: went.add,
            child: const SizedBox(),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('loginButton')));
      await tester.tap(find.byKey(const Key('registerButton')));

      expect(went, [
        '/login?from=%2Fsearch%3Fq%3Dson',
        '/register?from=%2Fsearch%3Fq%3Dson',
      ]);
    });

    testWidgets('a search becomes an address with the text encoded; an empty search is the search page', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create();
      final went = <String>[];
      await tester.pumpWidget(
        themed(
          AppShell(
            location: '/',
            session: env.session,
            themeController: ThemeController(),
            playback: env.newPlayback(),
            directory: env.repositories.directory,
            onGo: went.add,
            child: const SizedBox(),
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('searchField')), 'Sơn Tùng');
      await tester.testTextInput.receiveAction(TextInputAction.search);

      expect(went.single, '/search?q=S%C6%A1n+T%C3%B9ng');
      expect(Uri.parse(went.single).queryParameters['q'], 'Sơn Tùng');
    });

    testWidgets('log out stops what is playing before it ends the login, and goes home', (tester) async {
      TestEnv.window(tester);
      final env = await TestEnv.create(signedIn: true);
      final playback = env.newPlayback();
      await playback.playQueue(env.world.tracks.where((t) => t.isReady).toList());
      final went = <String>[];
      await tester.pumpWidget(
        themed(
          AppShell(
            location: '/',
            session: env.session,
            themeController: ThemeController(),
            playback: playback,
            directory: env.repositories.directory,
            onGo: went.add,
            child: const SizedBox(),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('accountMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logoutAction')));
      await tester.pumpAndSettle();

      expect(playback.current, isNull);
      expect(env.player.stopCalls, 1);
      expect(went, ['/']);
      expect(env.server.count('POST /api/v1/auth/logout'), 1);
    });
  });

  group('the keyboard and the tab title', () {
    Future<(TestEnv, dynamic)> open(WidgetTester tester, {Widget child = const SizedBox()}) async {
      TestEnv.window(tester);
      final env = await TestEnv.create(signedIn: true);
      final playback = env.newPlayback();
      await playback.playQueue(env.world.tracks.where((t) => t.isReady).toList());
      await tester.pumpWidget(
        themed(
          AppShell(
            location: '/',
            session: env.session,
            themeController: ThemeController(),
            playback: playback,
            directory: env.repositories.directory,
            onGo: (_) {},
            child: child,
          ),
        ),
      );
      return (env, playback);
    }

    testWidgets('Space pauses what is playing, and plays it again', (tester) async {
      final (env, playback) = await open(tester);
      await tester.pump();
      expect(playback.playing, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(playback.playing, isFalse);
      expect(env.player.pauseCalls, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(playback.playing, isTrue);
    });

    testWidgets('Space typed in a text field is a space, and does not touch the music', (tester) async {
      final (env, playback) = await open(tester, child: const Center(child: TextField(key: Key('someField'))));
      await tester.pump();

      await tester.tap(find.byKey(const Key('someField')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(playback.playing, isTrue);
      expect(env.player.pauseCalls, 0);
    });

    testWidgets('the title of the tab is the name of the app, or the track that plays', (tester) async {
      final titles = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
          titles.add((call.arguments as Map)['label'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final (env, playback) = await open(tester);
      await tester.pump();
      final track = playback.current!;
      expect(titles.last, '${track.title} · LaSono');

      await playback.stop();
      await tester.pump();
      expect(titles.last, 'LaSono');
      expect(env.player.stopCalls, 1);
    });
  });

  group('PageContainer', () {
    testWidgets('keeps a page no wider than the design, in the middle, with margins that follow the screen', (tester) async {
      TestEnv.window(tester, width: 1600);
      await tester.pumpWidget(themed(const PageContainer(child: SizedBox(key: Key('content'), width: double.infinity, height: 10))));

      final size = tester.getSize(find.byKey(const Key('content')));
      expect(size.width, AppBreakpoints.contentMaxWidth - 2 * PageContainer.sideMargin(ScreenSize.expanded));
      expect(tester.getCenter(find.byKey(const Key('content'))).dx, 800);
    });

    testWidgets('uses the whole width minus the margins on a phone', (tester) async {
      TestEnv.window(tester, width: 400);
      await tester.pumpWidget(themed(const PageContainer(child: SizedBox(key: Key('content'), width: double.infinity, height: 10))));
      expect(tester.getSize(find.byKey(const Key('content'))).width, 400 - 2 * PageContainer.sideMargin(ScreenSize.compact));
    });

    test('the side margin grows with the screen', () {
      expect(PageContainer.sideMargin(ScreenSize.compact), lessThan(PageContainer.sideMargin(ScreenSize.medium)));
      expect(PageContainer.sideMargin(ScreenSize.medium), lessThan(PageContainer.sideMargin(ScreenSize.expanded)));
    });
  });
}

