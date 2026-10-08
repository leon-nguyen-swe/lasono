import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/fake/fake_behavior.dart';
import 'package:lasono_app/data/fake/fake_repositories.dart';
import 'package:lasono_app/data/fake/fake_world.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/models/comment.dart';

class _Fixture {
  _Fixture({this.viewer = 'viewer-1'})
      : world = FakeWorld(clock: () => DateTime.utc(2026, 10, 8, 12)),
        behavior = FakeBehavior.instant() {
    repo = FakeSocialRepository(world, behavior, () => viewer);
  }

  final FakeWorld world;
  final FakeBehavior behavior;
  late final FakeSocialRepository repo;
  String? viewer;

  /// A track that is ready, and its length in milliseconds.
  String get readyTrack => world.tracks.firstWhere((t) => t.isReady).id;
}

Matcher _fails(RepositoryErrorKind kind, [String? message]) {
  var matcher = isA<RepositoryException>().having((e) => e.kind, 'kind', kind);
  if (message != null) matcher = matcher.having((e) => e.message, 'message', message);
  return throwsA(matcher);
}

void main() {
  group('likes', () {
    test('a like counts once, however many times it is sent (idempotent)', () async {
      final f = _Fixture();
      final id = f.readyTrack;
      final base = f.world.likeCountOf(id);

      final first = await f.repo.likeTrack(id);
      final second = await f.repo.likeTrack(id);

      expect((first.liked, first.likeCount), (true, base + 1));
      expect((second.liked, second.likeCount), (true, base + 1));
    });

    test('an unlike takes it back, and a second unlike changes nothing', () async {
      final f = _Fixture();
      final id = f.readyTrack;
      final base = f.world.likeCountOf(id);
      await f.repo.likeTrack(id);

      final first = await f.repo.unlikeTrack(id);
      final second = await f.repo.unlikeTrack(id);

      expect((first.liked, first.likeCount), (false, base));
      expect(second.likeCount, base);
    });

    test('the likes of two people add up', () async {
      final f = _Fixture();
      final id = f.readyTrack;
      final base = f.world.likeCountOf(id);

      await f.repo.likeTrack(id);
      f.viewer = 'viewer-2';
      final state = await f.repo.likeTrack(id);

      expect(state.likeCount, base + 2);
    });

    test('without a login it asks to log in', () async {
      final f = _Fixture(viewer: null);
      await expectLater(f.repo.likeTrack(f.readyTrack), _fails(RepositoryErrorKind.unauthorized));
      await expectLater(f.repo.unlikeTrack(f.readyTrack), _fails(RepositoryErrorKind.unauthorized));
    });

    test('a track that is still processing cannot be liked', () async {
      final f = _Fixture();
      final processing = f.world.tracks.firstWhere((t) => t.status == 'PROCESSING').id;
      await expectLater(f.repo.likeTrack(processing), _fails(RepositoryErrorKind.conflict));
    });

    test('a track the fake world does not know (a real one) can be liked, starting from zero', () async {
      final f = _Fixture();
      final state = await f.repo.likeTrack('0c1f2a3b-4c5d-4e6f-8a9b-0c1d2e3f4a5b');
      expect(state.likeCount, 1);
    });

    test('when the fake network fails, so does the like, and nothing was changed', () async {
      final f = _Fixture();
      final id = f.readyTrack;
      f.behavior.failing = true;

      await expectLater(f.repo.likeTrack(id), _fails(RepositoryErrorKind.network));

      f.behavior.failing = false;
      expect(f.world.isLiked('viewer-1', id), isFalse);
    });
  });

  group('follows', () {
    final target = FakeWorld.userId(8); // Maya Chen, whom a new viewer does not follow

    test('a follow counts once and says how many followers the user has now', () async {
      final f = _Fixture();
      final base = f.world.followerCountOf(target);

      final first = await f.repo.followUser(target);
      final second = await f.repo.followUser(target);

      expect((first.following, first.followerCount), (true, base + 1));
      expect(second.followerCount, base + 1);
    });

    test('an unfollow takes it back, and doing it twice changes nothing', () async {
      final f = _Fixture();
      final base = f.world.followerCountOf(target);
      await f.repo.followUser(target);

      expect((await f.repo.unfollowUser(target)).followerCount, base);
      expect((await f.repo.unfollowUser(target)).followerCount, base);
    });

    test('following yourself is refused', () async {
      final f = _Fixture();
      await expectLater(
        f.repo.followUser('viewer-1'),
        _fails(RepositoryErrorKind.invalid, 'You cannot follow yourself'),
      );
    });

    test('a user that does not exist in the fake world is not found; one the world does not know is accepted', () async {
      final f = _Fixture();
      await expectLater(f.repo.followUser(FakeWorld.userId(99)), _fails(RepositoryErrorKind.notFound));
      expect((await f.repo.followUser('a-real-user-id')).following, isTrue);
    });

    test('without a login it asks to log in', () async {
      final f = _Fixture(viewer: null);
      await expectLater(f.repo.followUser(target), _fails(RepositoryErrorKind.unauthorized));
    });

    test('the new follower is first in the followers of the user, and the user is in the viewer\'s following', () async {
      final f = _Fixture();
      await f.repo.followUser(target);

      final followers = await f.repo.followers(target);
      final following = await f.repo.following('viewer-1');

      expect(followers.items.first.userId, 'viewer-1');
      expect(following.items.first.userId, target);
      expect(followers.items.first.followedAt, DateTime.utc(2026, 10, 8, 12));
    });

    test('a list is paged with a cursor, and the pages do not overlap', () async {
      final f = _Fixture();
      f.world.ensureViewer('viewer-1');
      final id = FakeWorld.userId(1); // Sơn Tùng has several followers in the world
      for (final who in ['a', 'b', 'c', 'd']) {
        f.world.ensureViewer(who);
        f.world.follow(who, id);
      }
      final all = f.world.followersOf(id).map((e) => e.key).toList();
      expect(all.length, greaterThan(4));

      final seen = <String>[];
      String? cursor;
      do {
        final page = await f.repo.followers(id, cursor: cursor, limit: 3);
        seen.addAll(page.items.map((e) => e.userId));
        cursor = page.nextCursor;
      } while (cursor != null);

      expect(seen, all);
    });

    test('a limit below 1 and a cursor that is not ours are refused', () async {
      final f = _Fixture();
      await expectLater(f.repo.followers(target, limit: 0), _fails(RepositoryErrorKind.invalid));
      await expectLater(f.repo.followers(target, cursor: 'abc'), _fails(RepositoryErrorKind.invalid, 'Invalid cursor'));
    });
  });

  group('comments', () {
    late _Fixture f;
    late String trackId;

    setUp(() {
      f = _Fixture();
      trackId = f.world.tracks.firstWhere((t) => f.world.commentCountOf(t.id) >= 5).id;
    });

    test('are listed by position, the earliest first', () async {
      final page = await f.repo.comments(trackId);
      final positions = page.items.map((c) => c.positionMs).toList();
      expect(positions, [...positions]..sort());
      expect(page.items.length, f.world.commentCountOf(trackId));
      expect(page.nextCursor, isNull);
    });

    test('can be listed newest first', () async {
      final page = await f.repo.comments(trackId, order: CommentOrder.recent);
      final times = page.items.map((c) => c.createdAt!).toList();
      for (var i = 1; i < times.length; i++) {
        expect(times[i].isAfter(times[i - 1]), isFalse);
      }
    });

    test('paged with a limit they come out whole and in the same order as in one go', () async {
      final whole = (await f.repo.comments(trackId)).items.map((c) => c.id).toList();

      final paged = <String>[];
      String? cursor;
      do {
        final page = await f.repo.comments(trackId, limit: 2, cursor: cursor);
        paged.addAll(page.items.map((c) => c.id));
        cursor = page.nextCursor;
      } while (cursor != null);

      expect(paged, whole);
    });

    test('a comment is posted with the text trimmed, the viewer as the author, and counted', () async {
      final before = f.world.commentCountOf(trackId);

      final comment = await f.repo.postComment(trackId, positionMs: 1500, text: '  Hay quá!  ');

      expect(comment.text, 'Hay quá!');
      expect(comment.authorId, 'viewer-1');
      expect(comment.positionMs, 1500);
      expect(comment.trackId, trackId);
      expect(f.world.commentCountOf(trackId), before + 1);
      expect((await f.repo.comments(trackId)).items.map((c) => c.id), contains(comment.id));
    });

    test('a blank text is refused', () async {
      for (final text in ['', '   ', '\n\t']) {
        await expectLater(f.repo.postComment(trackId, positionMs: 0, text: text), _fails(RepositoryErrorKind.invalid));
      }
    });

    test('500 characters are accepted and 501 are not, counting what a person sees (an emoji is one)', () async {
      await f.repo.postComment(trackId, positionMs: 0, text: 'a' * 500);
      await expectLater(f.repo.postComment(trackId, positionMs: 0, text: 'a' * 501), _fails(RepositoryErrorKind.invalid));
      await f.repo.postComment(trackId, positionMs: 0, text: '😀' * 500);
      await expectLater(f.repo.postComment(trackId, positionMs: 0, text: '😀' * 501), _fails(RepositoryErrorKind.invalid));
    });

    test('the position may be 0 and the very end, but not past it, and the message names the limit', () async {
      final durationMs = f.world.track(trackId)!.durationMs!;

      await f.repo.postComment(trackId, positionMs: 0, text: 'đầu');
      await f.repo.postComment(trackId, positionMs: durationMs, text: 'cuối');
      await expectLater(
        f.repo.postComment(trackId, positionMs: durationMs + 1, text: 'quá'),
        _fails(RepositoryErrorKind.invalid, 'positionMs must be between 0 and $durationMs'),
      );
      await expectLater(f.repo.postComment(trackId, positionMs: -1, text: 'âm'), _fails(RepositoryErrorKind.invalid));
    });

    test('a track the world does not know cannot be checked against its length: only a negative position is refused', () async {
      await f.repo.postComment('a-real-track', positionMs: 99999999, text: 'ok');
      await expectLater(f.repo.postComment('a-real-track', positionMs: -5, text: 'x'), _fails(RepositoryErrorKind.invalid));
    });

    test('a track that is not ready cannot be commented on', () async {
      final processing = f.world.tracks.firstWhere((t) => t.status == 'PROCESSING').id;
      await expectLater(f.repo.postComment(processing, positionMs: 0, text: 'x'), _fails(RepositoryErrorKind.conflict));
    });

    test('without a login it asks to log in', () async {
      f.viewer = null;
      await expectLater(f.repo.postComment(trackId, positionMs: 0, text: 'x'), _fails(RepositoryErrorKind.unauthorized));
      await expectLater(f.repo.deleteComment(trackId, 'c'), _fails(RepositoryErrorKind.unauthorized));
    });

    test('the author can delete their comment', () async {
      final comment = await f.repo.postComment(trackId, positionMs: 10, text: 'của tôi');
      final before = f.world.commentCountOf(trackId);

      await f.repo.deleteComment(trackId, comment.id);

      expect(f.world.commentCountOf(trackId), before - 1);
    });

    test('the owner of the track can delete the comment of someone else', () async {
      final comment = await f.repo.postComment(trackId, positionMs: 10, text: 'của người khác');
      f.viewer = f.world.track(trackId)!.ownerId;

      await f.repo.deleteComment(trackId, comment.id);

      expect(f.world.comment(trackId, comment.id), isNull);
    });

    test('a stranger may not delete it, and a comment that is gone is not found', () async {
      final comment = await f.repo.postComment(trackId, positionMs: 10, text: 'của tôi');
      f.viewer = 'stranger';

      await expectLater(f.repo.deleteComment(trackId, comment.id), _fails(RepositoryErrorKind.forbidden));
      await expectLater(f.repo.deleteComment(trackId, 'no-such-comment'), _fails(RepositoryErrorKind.notFound));

      f.viewer = 'viewer-1';
      await f.repo.deleteComment(trackId, comment.id);
      await expectLater(f.repo.deleteComment(trackId, comment.id), _fails(RepositoryErrorKind.notFound));
    });
  });
}
