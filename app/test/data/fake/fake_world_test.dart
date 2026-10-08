import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/text/fold_accents.dart';
import 'package:lasono_app/data/fake/fake_world.dart';

final _now = DateTime.utc(2026, 10, 8, 12);

FakeWorld _world() => FakeWorld(clock: () => _now);

void main() {
  group('the data', () {
    test('has 8 users and 30 tracks', () {
      final world = _world();
      expect(world.users.length, 8);
      expect(world.tracks.length, 30);
    });

    test('every id is fake, so it can be told from a real one, and no id is used twice', () {
      final world = _world();
      final ids = [...world.users.map((u) => u.id), ...world.tracks.map((t) => t.id)];
      expect(ids.every(FakeWorld.isFake), isTrue);
      expect(ids.toSet().length, ids.length);
      expect(FakeWorld.isFake('0c1f2a3b-4c5d-4e6f-8a9b-0c1d2e3f4a5b'), isFalse);
    });

    test('every track belongs to a user of the world', () {
      final world = _world();
      for (final track in world.tracks) {
        expect(world.user(track.ownerId), isNotNull, reason: track.title);
      }
    });

    test('has names in Vietnamese and in English', () {
      final world = _world();
      final titles = world.tracks.map((t) => t.title).toList();
      expect(titles, containsAll(['Nắng ấm xa dần', 'Midnight Drive']));
      expect(world.users.map((u) => u.displayName), containsAll(['Sơn Tùng', 'Đen Vâu', 'Luna Park']));
    });

    test('is the same every time it is made', () {
      final a = _world();
      final b = _world();
      expect(a.tracks.map((t) => t.title), b.tracks.map((t) => t.title));
      expect(a.tracks.map((t) => t.waveform), b.tracks.map((t) => t.waveform));
      expect(a.commentsOf(a.tracks.first.id).map((c) => c.text), b.commentsOf(b.tracks.first.id).map((c) => c.text));
    });

    test('the tracks are listed newest first, with a spread from minutes to weeks', () {
      final world = _world();
      final times = world.tracks.map((t) => t.createdAt!).toList();
      for (var i = 1; i < times.length; i++) {
        expect(times[i].isBefore(times[i - 1]), isTrue);
      }
      expect(_now.difference(times.first), lessThan(const Duration(hours: 1)));
      expect(_now.difference(times.last), greaterThan(const Duration(days: 14)));
    });

    test('neighbours in the list are by different authors', () {
      final world = _world();
      for (var i = 1; i < 28; i++) {
        expect(world.tracks[i].ownerId, isNot(world.tracks[i - 1].ownerId), reason: 'at $i');
      }
    });

    test('a ready track has a length (45 to 90 s) and 200 peaks between 0 and 1; the others have neither', () {
      final world = _world();
      for (final track in world.tracks) {
        if (track.isReady) {
          expect(track.durationSeconds, inInclusiveRange(45, 90), reason: track.title);
          expect(track.waveform!.length, 200);
          expect(track.waveform!.every((p) => p >= 0 && p <= 1), isTrue);
        } else {
          expect(track.durationSeconds, isNull);
          expect(track.waveform, isNull);
        }
      }
    });

    test('one track is still processing and one failed, so those states can be seen', () {
      final world = _world();
      expect(world.tracks.where((t) => t.status == 'PROCESSING').length, 1);
      expect(world.tracks.where((t) => t.status == 'FAILED').length, 1);
      expect(world.tracks.where((t) => t.isReady).length, 28);
    });

    test('the waveforms of different tracks are different', () {
      final world = _world();
      expect(world.tracks[0].waveform, isNot(world.tracks[1].waveform));
    });

    test('searching without marks has something to find: "son tung" folds to the name of a user', () {
      final world = _world();
      expect(world.users.map((u) => foldAccents(u.displayName)), contains('son tung'));
    });
  });

  group('comments', () {
    test('are spread along the waveform and never go past the end of their track', () {
      final world = _world();
      var total = 0;
      for (final track in world.tracks.where((t) => t.isReady)) {
        final comments = world.commentsOf(track.id);
        total += comments.length;
        for (final c in comments) {
          expect(c.positionMs, inInclusiveRange(0, track.durationMs!), reason: '${track.title}: ${c.text}');
          expect(c.trackId, track.id);
          expect(world.user(c.authorId), isNotNull);
          expect(c.createdAt!.isAfter(track.createdAt!), isTrue);
        }
        expect(track.commentCount, comments.length);
      }
      expect(total, greaterThan(60));
    });

    test('a track that is not ready has none', () {
      final world = _world();
      final processing = world.tracks.firstWhere((t) => t.status == 'PROCESSING');
      expect(world.commentsOf(processing.id), isEmpty);
    });

    test('a comment can be added and then removed, and the count follows', () {
      final world = _world();
      final id = world.tracks.first.id;
      final before = world.commentCountOf(id);

      final comment = world.addComment(id, 'someone', 1000, 'Hay quá');
      expect(world.commentCountOf(id), before + 1);
      expect(world.comment(id, comment.id)!.text, 'Hay quá');
      expect(comment.createdAt, _now);

      expect(world.removeComment(id, comment.id), isTrue);
      expect(world.removeComment(id, comment.id), isFalse);
      expect(world.commentCountOf(id), before);
    });
  });

  group('follows', () {
    test('one user follows nobody', () {
      final world = _world();
      expect(world.users.where((u) => world.followingCountOf(u.id) == 0).map((u) => u.displayName), ['Minh Anh']);
    });

    test('the follower counts add the made-up base to the real edges', () {
      final world = _world();
      final sonTung = world.users.first;
      expect(world.followerCountOf(sonTung.id), sonTung.baseFollowers + world.followersOf(sonTung.id).length);
      expect(world.followerCountOf(sonTung.id), greaterThan(1000));
    });

    test('a viewer starts out following three users, once', () {
      final world = _world();
      world.ensureViewer('real-user');
      expect(world.followingOf('real-user').length, 3);

      world.unfollow('real-user', world.users.first.id);
      world.ensureViewer('real-user');
      expect(world.followingOf('real-user').length, 2, reason: 'the start is not applied again');
    });

    test('follow and unfollow say whether they changed anything', () {
      final world = _world()..ensureViewer('v');
      final target = world.users[7].id;

      expect(world.follow('v', target), isTrue);
      expect(world.follow('v', target), isFalse);
      expect(world.isFollowing('v', target), isTrue);
      expect(world.unfollow('v', target), isTrue);
      expect(world.unfollow('v', target), isFalse);
      expect(world.isFollowing('v', target), isFalse);
    });

    test('nobody is following themselves, and an anonymous viewer follows nobody', () {
      final world = _world();
      expect(world.isFollowing('v', 'v'), isFalse);
      expect(world.isFollowing(null, world.users.first.id), isFalse);
    });

    test('followers are listed newest first', () {
      final world = _world()..ensureViewer('v');
      world.follow('v', world.users[7].id);
      expect(world.followersOf(world.users[7].id).first.key, 'v');
    });
  });

  group('likes', () {
    test('the count is the made-up base plus the likes of the viewers', () {
      final world = _world();
      final id = world.tracks.first.id;
      final base = world.likeCountOf(id);

      expect(world.like('v', id), isTrue);
      expect(world.likeCountOf(id), base + 1);
      expect(world.like('v', id), isFalse);
      expect(world.likeCountOf(id), base + 1);
      expect(world.isLiked('v', id), isTrue);
      expect(world.isLiked('other', id), isFalse);

      expect(world.unlike('v', id), isTrue);
      expect(world.unlike('v', id), isFalse);
      expect(world.likeCountOf(id), base);
    });

    test('likedBy lists the most recent like first', () {
      final world = _world();
      world.like('v', 'track-a');
      world.like('v', 'track-b');
      world.like('v', 'track-c');
      world.unlike('v', 'track-b');
      expect(world.likedBy('v'), ['track-c', 'track-a']);
    });

    test('a track the world does not know starts with no likes', () {
      expect(_world().likeCountOf('a-real-track-id'), 0);
    });
  });

  group('putting the state on a track', () {
    test('overlays the likes and the comments, and the viewer\'s own like', () {
      final world = _world();
      final track = world.tracks.first;
      world.like('v', track.id);

      final shown = world.withSocial(track, viewerId: 'v');

      expect(shown.likeCount, world.likeCountOf(track.id));
      expect(shown.isLikedByMe, isTrue);
      expect(world.withSocial(track, viewerId: 'someone-else').isLikedByMe, isFalse);
      expect(world.withSocial(track).isLikedByMe, isFalse);
    });

    test('leaves out the part that is not asked for, so a real count can stay', () {
      final world = _world();
      final real = world.tracks.first.copyWith(likeCount: 99, commentCount: 7);

      final onlyLikes = world.withSocial(real, comments: false);
      expect(onlyLikes.commentCount, 7);

      final onlyComments = world.withSocial(real, likes: false);
      expect(onlyComments.likeCount, 99);
      expect(onlyComments.commentCount, world.commentCountOf(real.id));
    });
  });
}
