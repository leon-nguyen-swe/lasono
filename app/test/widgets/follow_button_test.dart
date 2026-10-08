import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/fake/fake_behavior.dart';
import 'package:lasono_app/data/fake/fake_repositories.dart';
import 'package:lasono_app/data/fake/fake_world.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/models/engagement.dart';
import 'package:lasono_app/widgets/follow_button.dart';

import '../support/test_harness.dart';

class _Social extends FakeSocialRepository {
  _Social(super.world, super.behavior, super.viewerId);

  Completer<void>? gate;
  int follows = 0;
  int unfollows = 0;
  Object? failure;

  @override
  Future<FollowState> followUser(String userId) async {
    follows++;
    await gate?.future;
    if (failure != null) throw failure!;
    return super.followUser(userId);
  }

  @override
  Future<FollowState> unfollowUser(String userId) async {
    unfollows++;
    await gate?.future;
    if (failure != null) throw failure!;
    return super.unfollowUser(userId);
  }
}

class _Rig {
  _Rig({this.viewer = 'viewer-1'}) : world = FakeWorld(clock: () => DateTime.utc(2026, 10, 8, 12)) {
    social = _Social(world, FakeBehavior.instant(), () => viewer);
  }

  final FakeWorld world;
  final String? viewer;
  late final _Social social;
  int loginRequests = 0;
  final changes = <FollowState>[];

  // Maya Chen: a new viewer does not follow her.
  String get target => FakeWorld.userId(8);

  Widget button({bool following = false, String? userId, bool compact = false}) => themed(
        Center(
          child: FollowButton(
            userId: userId ?? target,
            following: following,
            social: social,
            viewerId: viewer,
            onNeedLogin: () => loginRequests++,
            onChanged: changes.add,
            compact: compact,
          ),
        ),
      );
}

void main() {
  testWidgets('offers "Theo dõi" to someone who is not followed, and "Đang theo dõi" to someone who is', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.button());
    expect(find.text('Theo dõi'), findsOneWidget);

    await tester.pumpWidget(rig.button(following: true));
    expect(find.text('Đang theo dõi'), findsOneWidget);
  });

  testWidgets('is not shown on the page of the logged-in user themselves', (tester) async {
    final rig = _Rig(viewer: 'me');
    await tester.pumpWidget(rig.button(userId: 'me'));
    expect(find.byKey(const Key('followButton')), findsNothing);
  });

  testWidgets('is shown to a visitor who is not logged in', (tester) async {
    final rig = _Rig(viewer: null);
    await tester.pumpWidget(rig.button());
    expect(find.byKey(const Key('followButton')), findsOneWidget);
  });

  group('pressing it', () {
    testWidgets('changes the button at once and the server confirms it', (tester) async {
      final rig = _Rig();
      rig.social.gate = Completer<void>();
      await tester.pumpWidget(rig.button());

      await tester.tap(find.byKey(const Key('followButton')));
      await tester.pump();
      expect(find.text('Đang theo dõi'), findsOneWidget);
      expect(rig.changes, isEmpty);

      rig.social.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Đang theo dõi'), findsOneWidget);
      expect(rig.changes.single.following, isTrue);
      expect(rig.world.isFollowing('viewer-1', rig.target), isTrue);
    });

    testWidgets('a followed user is unfollowed with a second press', (tester) async {
      final rig = _Rig();
      rig.world.ensureViewer('viewer-1');
      rig.world.follow('viewer-1', rig.target);
      await tester.pumpWidget(rig.button(following: true));

      await tester.tap(find.byKey(const Key('followButton')));
      await tester.pumpAndSettle();

      expect(find.text('Theo dõi'), findsOneWidget);
      expect(rig.social.unfollows, 1);
      expect(rig.changes.single.following, isFalse);
    });

    testWidgets('a quick double press sends one request', (tester) async {
      final rig = _Rig();
      rig.social.gate = Completer<void>();
      await tester.pumpWidget(rig.button());

      await tester.tap(find.byKey(const Key('followButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('followButton')));
      await tester.tap(find.byKey(const Key('followButton')));
      await tester.pump();

      expect(rig.social.follows, 1);
      expect(rig.social.unfollows, 0);

      rig.social.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a failure puts the button back and says why', (tester) async {
      final rig = _Rig();
      rig.social.failure = const RepositoryException('x', kind: RepositoryErrorKind.network);
      await tester.pumpWidget(rig.button());

      await tester.tap(find.byKey(const Key('followButton')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Theo dõi'), findsOneWidget);
      expect(find.textContaining('kết nối'), findsOneWidget);
      expect(rig.changes, isEmpty);
    });

    testWidgets('a user who is not found is reported', (tester) async {
      final rig = _Rig();
      rig.social.failure = const RepositoryException('x', kind: RepositoryErrorKind.notFound);
      await tester.pumpWidget(rig.button());
      await tester.tap(find.byKey(const Key('followButton')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Không tìm thấy'), findsOneWidget);
      expect(find.text('Theo dõi'), findsOneWidget);
    });

    testWidgets('when the login ran out, the button goes back and the user is asked to log in', (tester) async {
      final rig = _Rig();
      rig.social.failure = const RepositoryException('x', kind: RepositoryErrorKind.unauthorized);
      await tester.pumpWidget(rig.button());
      await tester.tap(find.byKey(const Key('followButton')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Theo dõi'), findsOneWidget);
      expect(rig.loginRequests, 1);
    });

    testWidgets('without a login nothing is sent, and the user is asked to log in', (tester) async {
      final rig = _Rig(viewer: null);
      await tester.pumpWidget(rig.button());

      await tester.tap(find.byKey(const Key('followButton')));
      await tester.pump();

      expect(rig.loginRequests, 1);
      expect(rig.social.follows, 0);
      expect(find.text('Theo dõi'), findsOneWidget);
    });
  });

  testWidgets('under the pointer a followed user shows "Bỏ theo dõi", the way to undo it', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.button(following: true));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byKey(const Key('followButton'))));
    await tester.pump();

    expect(find.text('Bỏ theo dõi'), findsOneWidget);

    await gesture.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(find.text('Đang theo dõi'), findsOneWidget);
  });

  testWidgets('follows the values of the screen when it is not busy', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.button());
    await tester.pumpWidget(rig.button(following: true));
    expect(find.text('Đang theo dõi'), findsOneWidget);
  });

  testWidgets('the compact button is lower than the normal one', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.button());
    final normal = tester.getSize(find.byKey(const Key('followButton'))).height;
    await tester.pumpWidget(rig.button(compact: true));
    expect(tester.getSize(find.byKey(const Key('followButton'))).height, lessThan(normal));
  });
}
