import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/api/profile_api.dart';
import 'package:lasono_app/models/comment.dart';
import 'package:lasono_app/models/engagement.dart';
import 'package:lasono_app/models/search_results.dart';
import 'package:lasono_app/models/track.dart';
import 'package:lasono_app/models/track_page.dart';

const _phase4Track = {
  'id': 't1',
  'ownerId': 'u1',
  'title': 'Nắng ấm xa dần',
  'description': '',
  'visibility': 'PUBLIC',
  'status': 'READY',
  'durationSeconds': 213.4,
};

void main() {
  group('Track', () {
    test('a track from the Phase 1-4 backend (no Phase 5 fields) gets neutral values', () {
      final track = Track.fromJson(_phase4Track);

      expect(track.createdAt, isNull);
      expect(track.likeCount, 0);
      expect(track.commentCount, 0);
      expect(track.isLikedByMe, isFalse);
      expect(track.coverUrl, isNull);
    });

    test('reads the Phase 5 fields when the server sends them', () {
      final track = Track.fromJson({
        ..._phase4Track,
        'createdAt': '2026-10-08T12:34:56.789012Z',
        'likeCount': 12,
        'commentCount': 3,
        'isLikedByMe': true,
        'coverUrl': '/covers/t1.jpg',
      });

      expect(track.createdAt, DateTime.utc(2026, 10, 8, 12, 34, 56, 789, 12));
      expect(track.likeCount, 12);
      expect(track.commentCount, 3);
      expect(track.isLikedByMe, isTrue);
      expect(track.coverUrl, '/covers/t1.jpg');
    });

    test('a createdAt that is not a date is ignored, not a crash', () {
      expect(Track.fromJson({..._phase4Track, 'createdAt': 'yesterday'}).createdAt, isNull);
    });

    test('the length in milliseconds is rounded, not cut: 213.4 s is 213400 ms', () {
      expect(Track.fromJson(_phase4Track).durationMs, 213400);
      expect(Track.fromJson({..._phase4Track, 'durationSeconds': 0.0005}).durationMs, 1);
      expect(Track.fromJson({..._phase4Track, 'durationSeconds': null}).durationMs, isNull);
    });

    test('isReady and isPrivate follow the status and the visibility', () {
      expect(Track.fromJson(_phase4Track).isReady, isTrue);
      expect(Track.fromJson({..._phase4Track, 'status': 'PROCESSING'}).isReady, isFalse);
      expect(Track.fromJson({..._phase4Track, 'visibility': 'PRIVATE'}).isPrivate, isTrue);
    });

    test('copyWith changes only what it is given and keeps the owner, the date and the cover', () {
      final track = Track.fromJson({
        ..._phase4Track,
        'createdAt': '2026-10-08T12:34:56Z',
        'coverUrl': '/c.jpg',
      });

      final liked = track.copyWith(isLikedByMe: true, likeCount: 5);

      expect(liked.isLikedByMe, isTrue);
      expect(liked.likeCount, 5);
      expect(liked.title, track.title);
      expect(liked.ownerId, 'u1');
      expect(liked.createdAt, track.createdAt);
      expect(liked.coverUrl, '/c.jpg');
    });
  });

  group('TrackPage', () {
    test('has no total count unless the server sends one', () {
      final page = TrackPage.fromJson({'items': [_phase4Track], 'nextCursor': null});
      expect(page.totalCount, isNull);
      expect(page.items.single.id, 't1');
    });

    test('reads the total count of the tracks of a user', () {
      final page = TrackPage.fromJson({'items': [], 'nextCursor': 'c', 'totalCount': 14});
      expect(page.totalCount, 14);
      expect(page.nextCursor, 'c');
    });
  });

  group('Profile', () {
    test('a Phase 4 profile (name only) has zero counts and is not followed', () {
      final profile = Profile.fromJson({'userId': 'u1', 'displayName': 'Alice'});

      expect(profile.followerCount, 0);
      expect(profile.followingCount, 0);
      expect(profile.isFollowedByMe, isFalse);
      expect(profile.avatarUrl, isNull);
    });

    test('reads the counts and the follow state', () {
      final profile = Profile.fromJson({
        'userId': 'u1',
        'displayName': 'Alice',
        'followerCount': 5,
        'followingCount': 2,
        'isFollowedByMe': true,
      });

      expect(profile.followerCount, 5);
      expect(profile.followingCount, 2);
      expect(profile.isFollowedByMe, isTrue);
    });

    test('copyWith keeps the id', () {
      const profile = Profile(userId: 'u1', displayName: 'Alice');
      final renamed = profile.copyWith(displayName: 'Alice B.', followerCount: 3);
      expect(renamed.userId, 'u1');
      expect(renamed.displayName, 'Alice B.');
      expect(renamed.followerCount, 3);
    });
  });

  group('Comment, LikeState, FollowState, FollowEdge', () {
    test('a comment is read with its position in milliseconds', () {
      final comment = Comment.fromJson({
        'id': 'c1',
        'trackId': 't1',
        'authorId': 'u2',
        'positionMs': 83000,
        'text': 'Đoạn này hay quá!',
        'createdAt': '2026-10-08T12:40:00Z',
      });

      expect(comment.positionMs, 83000);
      expect(comment.text, 'Đoạn này hay quá!');
      expect(comment.authorId, 'u2');
      expect(comment.createdAt, DateTime.utc(2026, 10, 8, 12, 40));
    });

    test('the two orders of a comment list are named as the server expects', () {
      expect(CommentOrder.position.wireName, 'position');
      expect(CommentOrder.recent.wireName, 'recent');
    });

    test('a like state and a follow state are read', () {
      final like = LikeState.fromJson({'trackId': 't1', 'liked': true, 'likeCount': 13});
      expect((like.liked, like.likeCount), (true, 13));
      final follow = FollowState.fromJson({'userId': 'u1', 'following': false, 'followerCount': 5});
      expect((follow.following, follow.followerCount), (false, 5));
    });

    test('a follow edge has an id and a time', () {
      final edge = FollowEdge.fromJson({'userId': 'u7', 'followedAt': '2026-10-01T08:00:00Z'});
      expect(edge.userId, 'u7');
      expect(edge.followedAt, DateTime.utc(2026, 10, 1, 8));
    });

    test('a page of anything reads its items and its cursor', () {
      final page = CursorPage.fromJson(
        {
          'items': [
            {'userId': 'a'},
            {'userId': 'b'},
          ],
          'nextCursor': 'next',
        },
        FollowEdge.fromJson,
      );
      expect(page.items.map((e) => e.userId), ['a', 'b']);
      expect(page.nextCursor, 'next');
    });
  });

  group('SearchResults', () {
    test('reads tracks and users, and tolerates a missing list', () {
      final results = SearchResults.fromJson({
        'tracks': [_phase4Track],
        'users': [
          {'userId': 'u9', 'displayName': 'Sơn Tùng', 'followerCount': 120, 'isFollowedByMe': false},
        ],
      });
      expect(results.tracks.single.title, 'Nắng ấm xa dần');
      expect(results.users.single.displayName, 'Sơn Tùng');
      expect(results.users.single.followerCount, 120);
      expect(results.isEmpty, isFalse);

      final onlyTracks = SearchResults.fromJson({'tracks': [_phase4Track]});
      expect(onlyTracks.users, isEmpty);
      expect(SearchResults.fromJson({}).isEmpty, isTrue);
    });

    test('the types are named as the server expects', () {
      expect(SearchType.values.map((t) => t.wireName), ['all', 'tracks', 'users']);
    });
  });
}
