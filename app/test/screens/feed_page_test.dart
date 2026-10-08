import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/fake/fake_world.dart';

import '../support/test_harness.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<TestEnv> open(WidgetTester tester, {bool unfollowAll = false, bool failFirst = false, double width = 1280}) async {
    TestEnv.window(tester, width: width, height: 1600);
    final env = await TestEnv.create(signedIn: true);
    if (unfollowAll) {
      for (final index in FakeWorld.viewerStartsFollowing) {
        await env.repositories.social.unfollowUser(env.world.users[index].id);
      }
    }
    if (failFirst) env.repositories.fakeBehavior!.failNext();
    await tester.pumpWidget(env.app(location: '/feed'));
    await _settle(tester);
    return env;
  }

  testWidgets('shows the new tracks of the people the user follows, and only those', (tester) async {
    final env = await open(tester);
    final followed = FakeWorld.viewerStartsFollowing.map((i) => env.world.users[i].id).toSet();
    final inFeed = env.world.tracks.where((t) => followed.contains(t.ownerId) && t.isReady && !t.isPrivate).toList();
    final others = env.world.tracks.where((t) => !followed.contains(t.ownerId) && t.isReady).toList();

    expect(find.byKey(const Key('feedTitle')), findsOneWidget);
    expect(inFeed, isNotEmpty);
    expect(find.text(inFeed.first.title), findsOneWidget);
    expect(find.text(others.first.title), findsNothing);
  });

  testWidgets('a user who follows nobody sees how to start, and the button leads to the home page', (tester) async {
    await open(tester, unfollowAll: true);

    expect(find.byKey(const Key('feedEmpty')), findsOneWidget);
    expect(find.text('Bảng tin của bạn đang trống'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discoverButton')));
    await _settle(tester);
    expect(find.byKey(const Key('homeTitle')), findsOneWidget);
  });

  testWidgets('a failure shows an error, and the retry button shows the feed', (tester) async {
    await open(tester, failFirst: true);
    expect(find.byKey(const Key('pagedError')), findsOneWidget);

    await tester.tap(find.byKey(const Key('retryButton')));
    await _settle(tester);
    expect(find.byKey(const Key('pagedError')), findsNothing);
    expect(find.byKey(const Key('trackPlayButton')), findsWidgets);
  });

  testWidgets('playing a track makes the feed the queue: next goes to the next track of the feed', (tester) async {
    final env = await open(tester);
    final followed = FakeWorld.viewerStartsFollowing.map((i) => env.world.users[i].id).toSet();
    final inFeed = env.world.tracks.where((t) => followed.contains(t.ownerId) && t.isReady && !t.isPrivate).toList();
    // The feed is newest first.
    inFeed.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));

    await tester.tap(find.byKey(const Key('trackPlayButton')).first);
    await _settle(tester);
    Finder inBar(String title) => find.descendant(of: find.byKey(const Key('playerBar')), matching: find.text(title));
    expect(inBar(inFeed[0].title), findsOneWidget);

    await tester.tap(find.byKey(const Key('nextButton')));
    await _settle(tester);
    expect(inBar(inFeed[1].title), findsOneWidget);
  });

  testWidgets('a visitor is sent to the login page and comes back to the feed after logging in', (tester) async {
    TestEnv.window(tester, width: 1280, height: 1600);
    final env = await TestEnv.create();
    await tester.pumpWidget(env.app(location: '/feed'));
    await _settle(tester);
    expect(find.byKey(const Key('emailField')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('emailField')), 'ann@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret pass');
    await tester.tap(find.byKey(const Key('submitButton')));
    await _settle(tester);
    expect(find.byKey(const Key('feedTitle')), findsOneWidget);
  });

  testWidgets('fits a phone without overflow', (tester) async {
    await open(tester, width: 390);
    expect(tester.takeException(), isNull);
  });
}
