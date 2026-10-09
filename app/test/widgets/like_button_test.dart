import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/fake/fake_behavior.dart';
import 'package:lasono_app/data/fake/fake_repositories.dart';
import 'package:lasono_app/data/fake/fake_world.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/models/engagement.dart';
import 'package:lasono_app/widgets/like_button.dart';

import '../support/test_harness.dart';

/// A social repository whose answer a test can hold back, and which counts the requests it gets.
class _Social extends FakeSocialRepository {
  _Social(super.world, super.behavior, super.viewerId);

  Completer<void>? gate;
  int likes = 0;
  int unlikes = 0;
  Object? failure;

  @override
  Future<LikeState> likeTrack(String trackId) async {
    likes++;
    await gate?.future;
    if (failure != null) throw failure!;
    return super.likeTrack(trackId);
  }

  @override
  Future<LikeState> unlikeTrack(String trackId) async {
    unlikes++;
    await gate?.future;
    if (failure != null) throw failure!;
    return super.unlikeTrack(trackId);
  }
}

class _Rig {
  _Rig({bool signedIn = true})
      : world = FakeWorld(clock: () => DateTime.utc(2026, 10, 8, 12)),
        viewer = signedIn ? 'viewer-1' : null {
    social = _Social(world, FakeBehavior.instant(), () => viewer);
  }

  final FakeWorld world;
  final String? viewer;
  late final _Social social;
  int loginRequests = 0;
  final changes = <LikeState>[];

  String get trackId => world.tracks.firstWhere((t) => t.isReady).id;

  Widget button({bool liked = false, int count = 5, bool showCount = true, String? id}) => themed(
        Center(
          child: LikeButton(
            trackId: id ?? trackId,
            liked: liked,
            count: count,
            social: social,
            signedIn: viewer != null,
            onNeedLogin: () => loginRequests++,
            onChanged: changes.add,
            showCount: showCount,
          ),
        ),
      );
}

String _count(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('likeCount'))).data!;

void main() {
  testWidgets('shows an empty heart and the count, or a full heart when the track is liked', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.button(count: 5));
    expect(find.byKey(const Key('unlikedIcon')), findsOneWidget);
    expect(_count(tester), '5');

    await tester.pumpWidget(rig.button(liked: true, count: 6));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('likedIcon')), findsOneWidget);
    expect(_count(tester), '6');
  });

  testWidgets('writes a big count in short form', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.button(count: 1234));
    expect(_count(tester), '1,2K');
  });

  testWidgets('can leave the count out', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.button(showCount: false));
    expect(find.byKey(const Key('likeCount')), findsNothing);
  });

  group('pressing it', () {
    testWidgets('fills the heart and adds one at once, before the server has answered', (tester) async {
      final rig = _Rig();
      rig.social.gate = Completer<void>();
      await tester.pumpWidget(rig.button(count: 5));

      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump();

      expect(find.byKey(const Key('likedIcon')), findsOneWidget);
      expect(_count(tester), '6');
      expect(rig.social.likes, 1);
      expect(rig.changes, isEmpty, reason: 'nothing is confirmed yet');

      rig.social.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('and then takes the exact count from the server, and tells the screen', (tester) async {
      final rig = _Rig();
      final id = rig.trackId;
      final base = rig.world.likeCountOf(id);
      await tester.pumpWidget(rig.button(count: base, id: id));

      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pumpAndSettle();

      expect(_count(tester), '${base + 1}');
      expect(rig.changes.single.liked, isTrue);
      expect(rig.changes.single.likeCount, base + 1);
      expect(rig.world.isLiked('viewer-1', id), isTrue);
    });

    testWidgets('a second press unlikes: the heart empties and the count goes down', (tester) async {
      final rig = _Rig();
      final id = rig.trackId;
      rig.world.like('viewer-1', id);
      final count = rig.world.likeCountOf(id);
      await tester.pumpWidget(rig.button(liked: true, count: count, id: id));

      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unlikedIcon')), findsOneWidget);
      expect(_count(tester), '${count - 1}');
      expect(rig.social.unlikes, 1);
    });

    testWidgets('a second press while the first is still on its way is ignored', (tester) async {
      final rig = _Rig();
      rig.social.gate = Completer<void>();
      await tester.pumpWidget(rig.button(count: 5));

      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump();

      expect(rig.social.likes, 1);
      expect(rig.social.unlikes, 0);
      expect(_count(tester), '6');

      rig.social.gate!.complete();
      await tester.pumpAndSettle();
      // And after the answer, the button works again.
      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pumpAndSettle();
      expect(rig.social.unlikes, 1);
    });

    testWidgets('when the server cannot be reached the heart goes back and a message says why', (tester) async {
      final rig = _Rig();
      rig.social.failure = const RepositoryException('x', kind: RepositoryErrorKind.network);
      rig.social.gate = Completer<void>();
      await tester.pumpWidget(rig.button(count: 5));

      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump();
      expect(_count(tester), '6', reason: 'it changed at once, before the server answered');

      rig.social.gate!.complete(); // ... and then the answer is a failure
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('unlikedIcon')), findsOneWidget);
      expect(_count(tester), '5');
      expect(find.textContaining('kết nối'), findsOneWidget);
      expect(rig.changes, isEmpty);
      expect(rig.loginRequests, 0);
    });

    testWidgets('and the button can be pressed again after a failure', (tester) async {
      final rig = _Rig();
      rig.social.failure = const RepositoryException('x', kind: RepositoryErrorKind.server);
      await tester.pumpWidget(rig.button(count: 5));
      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump(const Duration(milliseconds: 300));

      rig.social.failure = null;
      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pumpAndSettle();

      expect(rig.social.likes, 2);
      expect(find.byKey(const Key('likedIcon')), findsOneWidget);
    });

    testWidgets('when the login ran out, the heart goes back and the user is asked to log in again', (tester) async {
      final rig = _Rig();
      rig.social.failure = const RepositoryException('x', kind: RepositoryErrorKind.unauthorized);
      await tester.pumpWidget(rig.button(count: 5));

      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('unlikedIcon')), findsOneWidget);
      expect(rig.loginRequests, 1);
    });

    testWidgets('without a login nothing is sent, and the user is asked to log in', (tester) async {
      final rig = _Rig(signedIn: false);
      await tester.pumpWidget(rig.button(count: 5));

      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump();

      expect(rig.loginRequests, 1);
      expect(rig.social.likes, 0);
      expect(find.byKey(const Key('unlikedIcon')), findsOneWidget);
      expect(_count(tester), '5');
    });

    testWidgets('the count never goes below zero', (tester) async {
      final rig = _Rig();
      final id = 'f4e00000-0000-4000-9000-999999999999'; // a track nobody has liked
      rig.social.gate = Completer<void>();
      await tester.pumpWidget(rig.button(liked: true, count: 0, id: id));

      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump();

      expect(_count(tester), '0');
      rig.social.gate!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('when the screen gives it new values', () {
    testWidgets('it follows them (a list was reloaded)', (tester) async {
      final rig = _Rig();
      await tester.pumpWidget(rig.button(count: 5));

      await tester.pumpWidget(rig.button(liked: true, count: 9));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('likedIcon')), findsOneWidget);
      expect(_count(tester), '9');
    });

    testWidgets('but not while its own request is on its way: the answer of the server decides', (tester) async {
      final rig = _Rig();
      rig.social.gate = Completer<void>();
      await tester.pumpWidget(rig.button(count: 5));
      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump();

      await tester.pumpWidget(rig.button(count: 5)); // the screen still holds the old track
      expect(_count(tester), '6');

      rig.social.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a button taken off the screen while its request runs does not crash', (tester) async {
      final rig = _Rig();
      rig.social.gate = Completer<void>();
      await tester.pumpWidget(rig.button());
      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump();

      await tester.pumpWidget(themed(const SizedBox()));
      rig.social.gate!.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('is announced as a toggle with its state', (tester) async {
    final rig = _Rig();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(rig.button(liked: true));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Bỏ thích'), findsOneWidget);
    handle.dispose();
  });
}
