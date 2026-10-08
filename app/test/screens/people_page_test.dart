import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/data/fake/fake_world.dart';

import '../support/test_harness.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// The viewer, Ann (`u-1`), is the only real user; everything else is made up.
final _backend = MockClient((request) async {
  if (request.url.path == '/api/v1/users/u-1') {
    return _json({'userId': 'u-1', 'displayName': 'Ann', 'followerCount': 0, 'followingCount': 3});
  }
  return http.Response('', 404);
});

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<TestEnv> open(WidgetTester tester, String Function(TestEnv env) location, {bool signedIn = true, double width = 1280}) async {
    TestEnv.window(tester, width: width, height: 1400);
    final env = await TestEnv.create(signedIn: signedIn, client: _backend);
    await tester.pumpWidget(env.app(location: location(env)));
    await _settle(tester);
    return env;
  }

  group('following', () {
    testWidgets('lists the people the user follows, with a button that says they are followed', (tester) async {
      final env = await open(tester, (env) => '/users/u-1/following');

      expect(find.byKey(const Key('peopleTitle')), findsOneWidget);
      expect(find.text('Đang theo dõi'), findsWidgets);
      for (final index in FakeWorld.viewerStartsFollowing) {
        expect(find.text(env.world.users[index].displayName), findsOneWidget);
      }
      expect(find.byKey(const Key('followButton')), findsNWidgets(FakeWorld.viewerStartsFollowing.length));
    });

    testWidgets('the button unfollows, and the row stays', (tester) async {
      final env = await open(tester, (env) => '/users/u-1/following');
      final first = env.world.users[FakeWorld.viewerStartsFollowing.first];

      await tester.tap(find.byKey(const Key('followButton')).first);
      await _settle(tester);

      expect(env.world.isFollowing('u-1', first.id), isFalse);
      expect(find.text(first.displayName), findsOneWidget);
    });

    testWidgets('pressing a row opens that profile', (tester) async {
      final env = await open(tester, (env) => '/users/u-1/following');
      final first = env.world.users[FakeWorld.viewerStartsFollowing.first];

      await tester.tap(find.text(first.displayName));
      await _settle(tester);

      expect(find.byKey(const Key('profileName')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('profileName'))).data, first.displayName);
    });

    testWidgets('a user who follows nobody shows the empty state', (tester) async {
      await open(tester, (env) => '/users/${env.world.users[4].id}/following');
      expect(find.byKey(const Key('peopleEmpty')), findsOneWidget);
      expect(find.text('Chưa theo dõi ai'), findsOneWidget);
    });
  });

  group('followers', () {
    testWidgets('lists who follows a user, and has no follow button on the row of the viewer', (tester) async {
      final env = await open(tester, (env) => '/users/${env.world.users[FakeWorld.viewerStartsFollowing.first].id}/followers');

      final user = env.world.users[FakeWorld.viewerStartsFollowing.first];
      final followers = env.world.followersOf(user.id);
      expect(find.text('Người theo dõi'), findsWidgets);
      expect(find.text('Ann'), findsOneWidget, reason: 'the viewer follows this user, so is among the followers');
      expect(find.byKey(const Key('followButton')), findsNWidgets(followers.length - 1), reason: 'one for each row but the viewer own');
    });

    testWidgets('a user nobody follows shows the empty state', (tester) async {
      await open(tester, (env) => '/users/${env.world.users[4].id}/followers');
      expect(find.byKey(const Key('peopleEmpty')), findsOneWidget);
      expect(find.text('Chưa có ai theo dõi'), findsOneWidget);
    });

    testWidgets('the arrow at the top leads back to the profile', (tester) async {
      await open(tester, (env) => '/users/${env.world.users[4].id}/followers');
      await tester.tap(find.byKey(const Key('backToProfile')));
      await _settle(tester);
      expect(find.byKey(const Key('profileName')), findsOneWidget);
    });
  });

  testWidgets('a failure shows an error with a retry that works', (tester) async {
    TestEnv.window(tester, width: 1280, height: 1400);
    final env = await TestEnv.create(signedIn: true, client: _backend);
    env.repositories.fakeBehavior!.failNext();
    await tester.pumpWidget(env.app(location: '/users/u-1/following'));
    await _settle(tester);
    expect(find.byKey(const Key('pagedError')), findsOneWidget);

    await tester.tap(find.byKey(const Key('retryButton')));
    await _settle(tester);
    expect(find.byKey(const Key('pagedError')), findsNothing);
    expect(find.text(env.world.users[FakeWorld.viewerStartsFollowing.first].displayName), findsOneWidget);
  });

  testWidgets('the numbers on a profile lead to these lists', (tester) async {
    await open(tester, (env) => '/users/${env.world.users[0].id}');
    await tester.tap(find.byKey(const Key('statFollowers')));
    await _settle(tester);
    expect(find.byKey(const Key('peopleTitle')), findsOneWidget);
    expect(find.text('Người theo dõi'), findsWidgets);

    await tester.tap(find.byKey(const Key('backToProfile')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('statFollowing')));
    await _settle(tester);
    expect(find.text('Đang theo dõi'), findsWidgets);
    expect(find.byKey(const Key('peopleTitle')), findsOneWidget);
  });

  testWidgets('a visitor who presses a follow button is sent to the login page', (tester) async {
    await open(tester, (env) => '/users/${env.world.users[0].id}/followers', signedIn: false);
    expect(find.byKey(const Key('followButton')), findsWidgets);

    await tester.tap(find.byKey(const Key('followButton')).first);
    await _settle(tester);
    expect(find.byKey(const Key('emailField')), findsOneWidget);
  });

  testWidgets('fits a phone without overflow', (tester) async {
    await open(tester, (env) => '/users/u-1/following', width: 390);
    expect(tester.takeException(), isNull);
  });
}
