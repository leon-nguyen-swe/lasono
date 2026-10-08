import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/data/fake/fake_world.dart';
import 'package:lasono_app/models/track.dart';

import '../support/test_harness.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A real track as the server sends it. The viewer in the tests (Ann) is `u-1`.
Map<String, Object?> _real(String id, {String status = 'READY', String ownerId = 'u-1', String visibility = 'PUBLIC', String title = 'Bài của tôi'}) => {
      'id': id,
      'title': title,
      'description': 'Một mô tả',
      'status': status,
      'ownerId': ownerId,
      'visibility': visibility,
      'mimeType': 'audio/mpeg',
      'durationSeconds': 100.0,
      'waveform': status == 'READY' ? [for (var i = 0; i < 50; i++) 0.2 + (i % 5) * 0.1] : null,
      'createdAt': '2026-10-07T12:00:00Z',
    };

/// The track routes of the backend for one real track whose answers a test can change.
class _Backend {
  Map<String, Object?> track = _real('real-1');
  int status = 200;
  final requests = <String>[];
  final patches = <Map<String, dynamic>>[];

  late final MockClient client = MockClient((request) async {
    final path = request.url.path;
    requests.add('${request.method} $path');
    if (path == '/api/v1/tracks/real-1' || path == '/api/v1/tracks/new-track-1') {
      if (status != 200) return http.Response('', status);
      switch (request.method) {
        case 'GET':
          return _json(track);
        case 'PATCH':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          patches.add(body);
          track = {...track, ...body};
          return _json(track);
        case 'DELETE':
          return http.Response('', 204);
      }
    }
    if (path.endsWith('/stream-url')) return _json({'url': '/api/v1/tracks/real-1/stream'});
    if (path == '/api/v1/tracks') return _json({'items': [], 'nextCursor': null});
    return http.Response('', 404);
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the menu of the owner and presses an entry. A menu or a dialog needs one frame to appear and one more to finish.
Future<void> _pressMenuEntry(WidgetTester tester, String entryKey) async {
  await tester.tap(find.byKey(const Key('trackMenu')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.tap(find.byKey(Key(entryKey)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  late _Backend backend;
  setUp(() => backend = _Backend());

  Future<TestEnv> open(WidgetTester tester, String id, {bool signedIn = true, double width = 1280}) async {
    TestEnv.window(tester, width: width, height: 1600);
    final env = await TestEnv.create(signedIn: signedIn, client: backend.client);
    await tester.pumpWidget(env.app(location: '/tracks/$id'));
    await _settle(tester);
    return env;
  }

  Track fakeWithComments(TestEnv env) =>
      env.world.tracks.firstWhere((t) => t.isReady && env.world.commentsOf(t.id).length >= 3 && t.ownerId != 'u-1');

  group('what the page shows', () {
    testWidgets('a track that is still loading shows a skeleton, then the track', (tester) async {
      TestEnv.window(tester, width: 1280, height: 1600);
      final gate = Completer<void>();
      final slow = MockClient((request) async {
        await gate.future;
        return backend.client.get(request.url);
      });
      final env = await TestEnv.create(client: slow);
      await tester.pumpWidget(env.app(location: '/tracks/real-1'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('trackLoading')), findsOneWidget);

      gate.complete();
      await _settle(tester);
      expect(find.byKey(const Key('trackLoading')), findsNothing);
      expect(find.byKey(const Key('trackTitle')), findsOneWidget);
    });

    testWidgets('shows the title, the author, the description and the age of a real track', (tester) async {
      await open(tester, 'real-1');

      expect(find.text('Bài của tôi'), findsOneWidget);
      expect(find.byKey(const Key('trackAuthor')), findsOneWidget);
      expect(find.text('Một mô tả'), findsOneWidget);
      expect(find.byKey(const Key('trackAge')), findsOneWidget);
      expect(find.byKey(const Key('trackWaveform')), findsOneWidget);
    });

    testWidgets('shows a fake track of the made-up world with its author name', (tester) async {
      final env = await TestEnv.create(client: backend.client);
      final track = fakeWithComments(env);
      TestEnv.window(tester, width: 1280, height: 1600);
      await tester.pumpWidget(env.app(location: '/tracks/${track.id}'));
      await _settle(tester);

      expect(find.text(track.title), findsOneWidget);
      final owner = env.world.user(track.ownerId)!;
      expect(find.text(owner.displayName), findsWidgets);
    });

    testWidgets('a private track is marked', (tester) async {
      backend.track = _real('real-1', visibility: 'PRIVATE');
      await open(tester, 'real-1');
      expect(find.byKey(const Key('privateChip')), findsOneWidget);
    });

    testWidgets('a track being processed says so instead of showing a waveform', (tester) async {
      backend.track = _real('real-1', status: 'PROCESSING');
      await open(tester, 'real-1');

      expect(find.byKey(const Key('trackProcessing')), findsOneWidget);
      expect(find.byKey(const Key('trackWaveform')), findsNothing);
      expect(tester.widget<InkWell>(find.byKey(const Key('trackPlayButton'))).onTap, isNull);
    });

    testWidgets('a track that failed says so', (tester) async {
      backend.track = _real('real-1', status: 'FAILED');
      await open(tester, 'real-1');
      expect(find.byKey(const Key('trackFailed')), findsOneWidget);
    });

    testWidgets('a track that does not exist shows a friendly page, and the button goes home', (tester) async {
      backend.status = 404;
      await open(tester, 'real-1');

      expect(find.byKey(const Key('trackNotFound')), findsOneWidget);
      expect(find.text('Không tìm thấy bài hát'), findsOneWidget);
      await tester.tap(find.byKey(const Key('goHomeButton')));
      await _settle(tester);
      expect(find.byKey(const Key('homeTitle')), findsOneWidget);
    });

    testWidgets('a server error shows an error with a retry that works', (tester) async {
      backend.status = 500;
      await open(tester, 'real-1');
      expect(find.byKey(const Key('trackError')), findsOneWidget);
      expect(find.byKey(const Key('trackNotFound')), findsNothing);

      backend.status = 200;
      await tester.tap(find.byKey(const Key('retryButton')));
      await _settle(tester);
      expect(find.byKey(const Key('trackTitle')), findsOneWidget);
    });
  });

  group('processing', () {
    testWidgets('the page asks again by itself and shows the track once it is ready', (tester) async {
      backend.track = _real('real-1', status: 'PROCESSING');
      await open(tester, 'real-1');
      expect(find.byKey(const Key('trackProcessing')), findsOneWidget);

      backend.track = _real('real-1');
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);

      expect(find.byKey(const Key('trackProcessing')), findsNothing);
      expect(find.byKey(const Key('trackWaveform')), findsOneWidget);
      expect(tester.widget<InkWell>(find.byKey(const Key('trackPlayButton'))).onTap, isNotNull);
    });

    testWidgets('it stops asking once the track is ready', (tester) async {
      backend.track = _real('real-1', status: 'PROCESSING');
      await open(tester, 'real-1');
      backend.track = _real('real-1');
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      final asked = backend.requests.where((r) => r == 'GET /api/v1/tracks/real-1').length;

      await tester.pump(const Duration(seconds: 12));
      expect(backend.requests.where((r) => r == 'GET /api/v1/tracks/real-1').length, asked);
    });

    testWidgets('a failure while asking again is not shown to the user', (tester) async {
      backend.track = _real('real-1', status: 'PROCESSING');
      await open(tester, 'real-1');
      backend.status = 500;
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);

      expect(find.byKey(const Key('trackProcessing')), findsOneWidget);
      expect(find.byKey(const Key('trackError')), findsNothing);
    });
  });

  group('playing', () {
    testWidgets('the big button plays the track, the player bar shows it, and the button pauses it', (tester) async {
      final env = await open(tester, 'real-1');

      await tester.tap(find.byKey(const Key('trackPlayButton')));
      await _settle(tester);
      expect(env.player.playCalls, 1);
      expect(find.descendant(of: find.byKey(const Key('playerBar')), matching: find.text('Bài của tôi')), findsOneWidget);

      await tester.tap(find.byKey(const Key('trackPlayButton')));
      await _settle(tester);
      expect(env.player.pauseCalls, 1);
    });

    testWidgets('pressing the time of a comment plays the track from that moment', (tester) async {
      final env = await TestEnv.create(client: backend.client);
      final track = fakeWithComments(env);
      TestEnv.window(tester, width: 1280, height: 1600);
      await tester.pumpWidget(env.app(location: '/tracks/${track.id}'));
      await _settle(tester);

      final target = env.world.commentsOf(track.id).reduce((a, b) => a.createdAt!.isAfter(b.createdAt!) ? a : b);
      await tester.tap(find.descendant(of: find.byKey(Key('comment-${target.id}')), matching: find.byKey(const Key('commentTime'))));
      await _settle(tester);

      expect(env.player.playCalls, 1);
      expect(env.player.seeks, [Duration(milliseconds: target.positionMs)]);
    });
  });

  group('comments', () {
    testWidgets('lists the comments of a track, newest first, with how many there are', (tester) async {
      final env = await TestEnv.create(client: backend.client);
      final track = fakeWithComments(env);
      TestEnv.window(tester, width: 1280, height: 1600);
      await tester.pumpWidget(env.app(location: '/tracks/${track.id}'));
      await _settle(tester);

      final all = env.world.commentsOf(track.id);
      for (final comment in all.take(3)) {
        expect(find.byKey(Key('comment-${comment.id}')), findsOneWidget);
      }
      final newest = all.reduce((a, b) => a.createdAt!.isAfter(b.createdAt!) ? a : b);
      final oldest = all.reduce((a, b) => a.createdAt!.isBefore(b.createdAt!) ? a : b);
      expect(
        tester.getTopLeft(find.byKey(Key('comment-${newest.id}'))).dy,
        lessThan(tester.getTopLeft(find.byKey(Key('comment-${oldest.id}'))).dy),
      );
    });

    testWidgets('a track with no comment says so', (tester) async {
      await open(tester, 'real-1');
      expect(find.byKey(const Key('commentsEmpty')), findsOneWidget);
    });

    testWidgets('writing a comment adds it at the top and counts it', (tester) async {
      await open(tester, 'real-1');
      expect(find.text('Bình luận (0)'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('commentField')), 'Hay quá đi');
      await tester.pump();
      await tester.tap(find.byKey(const Key('sendComment')));
      await _settle(tester);

      expect(find.text('Hay quá đi'), findsOneWidget);
      expect(find.text('Bình luận (1)'), findsOneWidget);
      expect(find.byKey(const Key('commentsEmpty')), findsNothing);
    });

    testWidgets('a visitor who is not logged in cannot write, and pressing the box leads to the login page', (tester) async {
      await open(tester, 'real-1', signedIn: false);
      expect(tester.widget<TextField>(find.byKey(const Key('commentField'))).decoration!.hintText, 'Đăng nhập để bình luận');

      await tester.tap(find.byKey(const Key('commentField')));
      await _settle(tester);
      expect(find.byKey(const Key('emailField')), findsOneWidget);
    });

    testWidgets('the author of a comment can delete it after confirming', (tester) async {
      await open(tester, 'real-1');
      await tester.enterText(find.byKey(const Key('commentField')), 'Sẽ xoá cái này');
      await tester.pump();
      await tester.tap(find.byKey(const Key('sendComment')));
      await _settle(tester);
      expect(find.text('Sẽ xoá cái này'), findsOneWidget);

      await tester.tap(find.byKey(const Key('deleteComment')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.byKey(const Key('confirmButton')));
      await _settle(tester);

      expect(find.text('Sẽ xoá cái này'), findsNothing);
      expect(find.byKey(const Key('commentsEmpty')), findsOneWidget);
      expect(find.text('Bình luận (0)'), findsOneWidget);
    });
  });

  group('likes', () {
    testWidgets('pressing the heart likes the track and counts it', (tester) async {
      final env = await TestEnv.create(signedIn: true, client: backend.client);
      final track = fakeWithComments(env);
      TestEnv.window(tester, width: 1280, height: 1600);
      await tester.pumpWidget(env.app(location: '/tracks/${track.id}'));
      await _settle(tester);
      final before = tester.widget<Text>(find.byKey(const Key('likeCount'))).data;

      await tester.tap(find.byKey(const Key('likeButton')));
      await _settle(tester);

      expect(tester.widget<Text>(find.byKey(const Key('likeCount'))).data, isNot(before));
    });
  });

  group('the owner', () {
    testWidgets('the menu is there for the owner, and not for somebody else', (tester) async {
      await open(tester, 'real-1');
      expect(find.byKey(const Key('trackMenu')), findsOneWidget);

      backend.track = _real('real-1', ownerId: 'somebody-else');
      await tester.pumpWidget(const SizedBox());
      await open(tester, 'real-1');
      expect(find.byKey(const Key('trackMenu')), findsNothing);
    });

    testWidgets('the menu makes a public track private, and says so', (tester) async {
      await open(tester, 'real-1');
      await _pressMenuEntry(tester, 'visibilityAction');
      await _settle(tester);

      expect(backend.patches, [
        {'visibility': 'PRIVATE'}
      ]);
      expect(find.byKey(const Key('privateChip')), findsOneWidget);
    });

    testWidgets('the menu edits the title', (tester) async {
      await open(tester, 'real-1');
      await _pressMenuEntry(tester, 'editAction');
      await tester.enterText(find.byKey(const Key('editTitleField')), 'Tên mới');
      await tester.tap(find.byKey(const Key('saveEditButton')));
      await _settle(tester);

      expect(backend.patches, [
        {'title': 'Tên mới'}
      ]);
      expect(find.text('Tên mới'), findsWidgets);
    });

    testWidgets('the menu deletes the track after the user confirms, and the page goes home', (tester) async {
      await open(tester, 'real-1');
      await _pressMenuEntry(tester, 'deleteAction');
      await tester.tap(find.byKey(const Key('confirmButton')));
      await _settle(tester);

      expect(backend.requests, contains('DELETE /api/v1/tracks/real-1'));
      expect(find.byKey(const Key('homeTitle')), findsOneWidget);
    });

    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      await open(tester, 'real-1');
      await _pressMenuEntry(tester, 'deleteAction');
      await tester.tap(find.byKey(const Key('cancelButton')));
      await _settle(tester);

      expect(backend.requests, isNot(contains('DELETE /api/v1/tracks/real-1')));
      expect(find.byKey(const Key('trackTitle')), findsOneWidget);
    });
  });

  testWidgets('moving to another track shows that track, not the one before', (tester) async {
    final env = await open(tester, 'real-1');
    final other = env.world.tracks.first;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(env.app(location: '/tracks/${other.id}'));
    await _settle(tester);
    expect(find.text(other.title), findsOneWidget);
    expect(find.text('Bài của tôi'), findsNothing);
  });

  testWidgets('fits a phone without overflow', (tester) async {
    await open(tester, 'real-1', width: 390);
    expect(tester.takeException(), isNull);
    expect(FakeWorld.isFake('real-1'), isFalse);
  });
}
