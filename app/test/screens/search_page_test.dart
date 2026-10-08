import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/theme/theme.dart';
import 'package:lasono_app/data/app_repositories.dart';
import 'package:lasono_app/data/search_repository.dart';
import 'package:lasono_app/models/search_results.dart';
import 'package:lasono_app/playback/playback_controller.dart';
import 'package:lasono_app/screens/search_page.dart';
import 'package:lasono_app/shell/app_context.dart';

import '../support/test_harness.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Answers each search by hand, so a test decides which one comes back first.
class _ManualSearch implements SearchRepository {
  final asked = <String>[];
  final answers = <String, Completer<SearchResults>>{};

  @override
  Future<SearchResults> search(String query, {SearchType type = SearchType.all, int? limit}) {
    asked.add(query);
    return (answers[query] = Completer<SearchResults>()).future;
  }
}

void main() {
  Future<TestEnv> open(WidgetTester tester, String query, {double width = 1280, bool failFirst = false}) async {
    TestEnv.window(tester, width: width, height: 1600);
    final env = await TestEnv.create(signedIn: true);
    if (failFirst) env.repositories.fakeBehavior!.failNext();
    await tester.pumpWidget(env.app(location: '/search?q=${Uri.encodeQueryComponent(query)}'));
    await _settle(tester);
    return env;
  }

  testWidgets('with nothing typed it explains what to do', (tester) async {
    await open(tester, '');
    expect(find.byKey(const Key('searchIdle')), findsOneWidget);
    expect(find.byKey(const Key('searchTabs')), findsNothing);
  });

  testWidgets('one letter is too short, and no tabs are shown', (tester) async {
    await open(tester, 's');
    expect(find.byKey(const Key('searchTooShort')), findsOneWidget);
    expect(find.byKey(const Key('searchTabs')), findsNothing);
  });

  testWidgets('finds a person without the accents, and shows their name', (tester) async {
    final env = await open(tester, 'son tung');
    final person = env.world.users.firstWhere((u) => u.displayName == 'Sơn Tùng');

    expect(find.byKey(const Key('usersHeading')), findsOneWidget);
    expect(find.byKey(ValueKey('user-${person.id}')), findsOneWidget);
    expect(find.byKey(const Key('searchTitle')), findsOneWidget);
  });

  testWidgets('finds a track by its title', (tester) async {
    final env = await open(tester, 'bua yeu');
    final track = env.world.tracks.firstWhere((t) => t.title == 'Bùa yêu');

    expect(find.byKey(const Key('tracksHeading')), findsOneWidget);
    expect(find.byKey(ValueKey('track-${track.id}')), findsOneWidget);
  });

  testWidgets('a word nobody has shows that there is no result', (tester) async {
    await open(tester, 'zzzqqq');
    expect(find.byKey(const Key('searchEmpty')), findsOneWidget);
    expect(find.byKey(const Key('searchTabs')), findsOneWidget);
  });

  testWidgets('the tabs choose between people and tracks', (tester) async {
    await open(tester, 'son tung');
    expect(find.byKey(const Key('usersHeading')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tabTracks')));
    await _settle(tester);
    expect(find.byKey(const Key('usersHeading')), findsNothing);
    expect(find.byKey(const Key('searchEmpty')), findsOneWidget);
    expect(find.text('Không có bài hát nào khớp “son tung”'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tabUsers')));
    await _settle(tester);
    expect(find.byKey(const Key('usersHeading')), findsOneWidget);
    expect(find.byKey(const Key('searchEmpty')), findsNothing);
  });

  testWidgets('a failure shows an error, and the retry button searches again', (tester) async {
    await open(tester, 'son tung', failFirst: true);
    expect(find.byKey(const Key('searchError')), findsOneWidget);

    await tester.tap(find.byKey(const Key('retryButton')));
    await _settle(tester);
    expect(find.byKey(const Key('searchError')), findsNothing);
    expect(find.byKey(const Key('usersHeading')), findsOneWidget);
  });

  testWidgets('typing in the top bar goes to the search page after a short pause, and not before', (tester) async {
    TestEnv.window(tester);
    final env = await TestEnv.create(signedIn: true);
    await tester.pumpWidget(env.app(location: '/'));
    await _settle(tester);

    await tester.enterText(find.byKey(const Key('searchField')), 'son');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('searchTitle')), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    await _settle(tester);
    expect(find.text('Kết quả cho “son”'), findsOneWidget);
  });

  testWidgets('a slow answer to an older word does not replace the answer to the newer one', (tester) async {
    TestEnv.window(tester, width: 1280, height: 1600);
    final env = await TestEnv.create(signedIn: true);
    final search = _ManualSearch();
    final repositories = AppRepositories(
      tracks: env.repositories.tracks,
      users: env.repositories.users,
      social: env.repositories.social,
      feed: env.repositories.feed,
      search: search,
    );
    final query = ValueNotifier('luna');
    await tester.pumpWidget(
      SessionScope(
        session: env.session,
        child: RepositoriesScope(
          repositories: repositories,
          child: PlaybackScope(
            read: env.newPlayback,
            child: MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: ValueListenableBuilder<String>(valueListenable: query, builder: (_, q, _) => SearchPage(query: q)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    query.value = 'kaito';
    await tester.pump();
    expect(search.asked, ['luna', 'kaito']);

    final luna = await env.repositories.users.getProfile(env.world.users.firstWhere((u) => u.displayName == 'Luna Park').id);
    final kaito = await env.repositories.users.getProfile(env.world.users.firstWhere((u) => u.displayName == 'DJ Kaito').id);
    search.answers['kaito']!.complete(SearchResults(users: [kaito]));
    await tester.pump(const Duration(milliseconds: 50));
    search.answers['luna']!.complete(SearchResults(users: [luna]));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(ValueKey('user-${kaito.userId}')), findsOneWidget);
    expect(find.byKey(ValueKey('user-${luna.userId}')), findsNothing);
  });

  testWidgets('fits a phone without overflow', (tester) async {
    await open(tester, 'an', width: 390);
    expect(tester.takeException(), isNull);
  });
}
