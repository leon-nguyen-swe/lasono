import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/data/fake/fake_world.dart';
import 'package:lasono_app/data/fake_flags.dart';

import '../support/test_harness.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// The routes of the backend that a profile page uses, for the logged-in user Ann (`u-1`).
class _Backend {
  int profileStatus = 200;
  int tracksStatus = 200;
  List<Map<String, Object?>> tracks = [];
  String name = 'Ann';
  final patches = <Map<String, dynamic>>[];
  Map<String, Object?>? renameFailure;

  late final MockClient client = MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/v1/users/u-1' && request.method == 'GET') {
      if (profileStatus != 200) return http.Response('', profileStatus);
      return _json({'userId': 'u-1', 'displayName': name, 'followerCount': 7, 'followingCount': 3});
    }
    if (path == '/api/v1/users/u-1/tracks') {
      if (tracksStatus != 200) return http.Response('', tracksStatus);
      return _json({'items': tracks, 'nextCursor': null, 'totalCount': tracks.length});
    }
    if (path == '/api/v1/users/me' && request.method == 'PATCH') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      patches.add(body);
      final failure = renameFailure;
      if (failure != null) return _json(failure, 400);
      name = body['displayName'] as String;
      return _json({'userId': 'u-1', 'email': 'ann@example.com', 'displayName': name});
    }
    if (path == '/api/v1/users/me') return _json({'userId': 'u-1', 'email': 'ann@example.com', 'displayName': name});
    return http.Response('', 404);
  });
}

Map<String, Object?> _track(String id, String title, {String visibility = 'PUBLIC'}) => {
      'id': id,
      'title': title,
      'description': '',
      'status': 'PROCESSING',
      'ownerId': 'u-1',
      'visibility': visibility,
    };

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late _Backend backend;
  setUp(() => backend = _Backend());

  Future<TestEnv> open(WidgetTester tester, String userId, {bool signedIn = true, double width = 1280, FakeFlags? flags}) async {
    TestEnv.window(tester, width: width, height: 1600);
    final env = flags == null
        ? await TestEnv.create(signedIn: signedIn, client: backend.client)
        : await TestEnv.create(signedIn: signedIn, client: backend.client, flags: flags);
    await tester.pumpWidget(env.app(location: '/users/$userId'));
    await _settle(tester);
    return env;
  }


  group("somebody else's page", () {
    testWidgets('shows the name, the numbers, the follow button and the tracks of the user', (tester) async {
      final env = await TestEnv.create(signedIn: true, client: backend.client);
      final user = env.world.users.first;
      final tracks = env.world.tracks.where((t) => t.ownerId == user.id).toList();
      TestEnv.window(tester, width: 1280, height: 1600);
      await tester.pumpWidget(env.app(location: '/users/${user.id}'));
      await _settle(tester);

      expect(find.byKey(const Key('profileName')), findsOneWidget);
      expect(find.text(user.displayName), findsWidgets);
      expect(find.byKey(const Key('statFollowers')), findsOneWidget);
      expect(find.byKey(const Key('followButton')), findsOneWidget);
      expect(find.byKey(const Key('renameButton')), findsNothing);
      expect(find.byKey(const Key('privateNote')), findsNothing);
      expect(find.text(tracks.first.title), findsOneWidget);
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('statTracks')), matching: find.byKey(const Key('statValue')))).data, '${tracks.length}');
    });

    testWidgets('following adds one to the number of followers', (tester) async {
      final env = await TestEnv.create(signedIn: true, client: backend.client);
      // A user the viewer does not follow yet.
      final user = env.world.users.firstWhere((u) => !FakeWorld.viewerStartsFollowing.contains(env.world.users.indexOf(u)));
      TestEnv.window(tester, width: 1280, height: 1600);
      await tester.pumpWidget(env.app(location: '/users/${user.id}'));
      await _settle(tester);
      int followers() => int.parse(tester.widget<Text>(find.descendant(of: find.byKey(const Key('statFollowers')), matching: find.byKey(const Key('statValue')))).data!.replaceAll(RegExp(r'[^0-9]'), ''));
      final before = followers();

      await tester.tap(find.byKey(const Key('followButton')));
      await _settle(tester);

      expect(find.textContaining('Đang theo dõi'), findsWidgets);
      expect(followers(), before + 1);
    });

    testWidgets('a visitor who presses follow is sent to the login page', (tester) async {
      final env = await TestEnv.create(client: backend.client);
      TestEnv.window(tester, width: 1280, height: 1600);
      await tester.pumpWidget(env.app(location: '/users/${env.world.users.first.id}'));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('followButton')));
      await _settle(tester);
      expect(find.byKey(const Key('emailField')), findsOneWidget);
    });

    testWidgets('a user who does not exist shows a friendly page, and the button goes home', (tester) async {
      await open(tester, 'f4e00000-0000-4000-8000-000000009999');
      expect(find.byKey(const Key('userNotFound')), findsOneWidget);

      await tester.tap(find.byKey(const Key('goHomeButton')));
      await _settle(tester);
      expect(find.byKey(const Key('homeTitle')), findsOneWidget);
    });
  });

  group('my own page', () {
    testWidgets('has the rename button instead of follow, and says that private tracks are only mine', (tester) async {
      backend.tracks = [_track('t-1', 'Bài riêng của tôi', visibility: 'PRIVATE')];
      await open(tester, 'u-1', flags: const FakeFlags());

      expect(find.byKey(const Key('renameButton')), findsOneWidget);
      expect(find.byKey(const Key('followButton')), findsNothing);
      expect(find.byKey(const Key('privateNote')), findsOneWidget);
      expect(find.text('Bài riêng của tôi'), findsOneWidget);
      expect(find.byKey(const Key('privateChip')), findsOneWidget);
      expect(find.text('7'), findsOneWidget, reason: 'the followers');
    });

    testWidgets('with no track it says so and offers to upload', (tester) async {
      await open(tester, 'u-1');
      expect(find.byKey(const Key('tracksEmpty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('uploadFromEmpty')));
      await _settle(tester);
      expect(find.byKey(const Key('dropZone')), findsOneWidget);
    });

    testWidgets('renaming changes the name on the page and sends only the new name', (tester) async {
      await open(tester, 'u-1');
      await tester.tap(find.byKey(const Key('renameButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.enterText(find.byKey(const Key('renameField')), 'Ann Mới');
      await tester.tap(find.byKey(const Key('saveRenameButton')));
      await _settle(tester);

      expect(backend.patches, [
        {'displayName': 'Ann Mới'}
      ]);
      expect(tester.widget<Text>(find.byKey(const Key('profileName'))).data, 'Ann Mới');
      expect(find.byKey(const Key('renameField')), findsNothing);
    });

    testWidgets('an empty name is refused before asking the server, and a refusal of the server is explained', (tester) async {
      await open(tester, 'u-1');
      await tester.tap(find.byKey(const Key('renameButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      await tester.enterText(find.byKey(const Key('renameField')), '   ');
      await tester.tap(find.byKey(const Key('saveRenameButton')));
      await tester.pump();
      expect(find.text('Hãy nhập tên hiển thị.'), findsOneWidget);
      expect(backend.patches, isEmpty);

      backend.renameFailure = {'detail': 'Display name must be at most 50 characters'};
      await tester.enterText(find.byKey(const Key('renameField')), 'x' * 60);
      await tester.tap(find.byKey(const Key('saveRenameButton')));
      await _settle(tester);
      expect(find.text('Tên hiển thị tối đa 50 ký tự.'), findsOneWidget);
      expect(find.byKey(const Key('renameField')), findsOneWidget, reason: 'the dialog stays so the user can fix it');
    });

    testWidgets('the likes tab lists the tracks I liked, and says so when there are none', (tester) async {
      final env = await TestEnv.create(signedIn: true, client: backend.client);
      TestEnv.window(tester, width: 1280, height: 1600);
      await tester.pumpWidget(env.app(location: '/users/u-1'));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('tabLikes')));
      await _settle(tester);
      expect(find.byKey(const Key('likesEmpty')), findsOneWidget);

      final liked = env.world.tracks.first;
      await env.repositories.social.likeTrack(liked.id);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(env.app(location: '/users/u-1'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('tabLikes')));
      await _settle(tester);

      expect(find.text(liked.title), findsOneWidget);
      expect(find.byKey(const Key('likesEmpty')), findsNothing);
    });
  });

  group('failures', () {
    testWidgets('a server error on the profile shows an error with a retry that works', (tester) async {
      backend.profileStatus = 500;
      await open(tester, 'u-1');
      expect(find.byKey(const Key('profileError')), findsOneWidget);

      backend.profileStatus = 200;
      await tester.tap(find.byKey(const Key('retryButton')));
      await _settle(tester);
      expect(find.byKey(const Key('profileName')), findsOneWidget);
    });

    testWidgets('the profile with a failing list of tracks still shows the header, with the error in the list', (tester) async {
      backend.tracksStatus = 500;
      await open(tester, 'u-1');
      expect(find.byKey(const Key('profileName')), findsOneWidget);
      expect(find.byKey(const Key('pagedError')), findsOneWidget);
    });
  });

  testWidgets('fits a phone without overflow', (tester) async {
    backend.tracks = [_track('t-1', 'Một bài')];
    await open(tester, 'u-1', width: 390);
    expect(tester.takeException(), isNull);
  });
}
