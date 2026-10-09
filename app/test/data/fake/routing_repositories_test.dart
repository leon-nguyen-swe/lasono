import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/api/auth_api.dart';
import 'package:lasono_app/api/profile_api.dart';
import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/auth/session_controller.dart';
import 'package:lasono_app/data/app_repositories.dart';
import 'package:lasono_app/data/fake/fake_behavior.dart';
import 'package:lasono_app/data/fake/fake_repositories.dart';
import 'package:lasono_app/data/fake/fake_world.dart';
import 'package:lasono_app/data/fake/routing_repositories.dart';
import 'package:lasono_app/data/fake_flags.dart';
import 'package:lasono_app/data/feed_repository.dart';
import 'package:lasono_app/data/search_repository.dart';
import 'package:lasono_app/data/social_repository.dart';
import 'package:lasono_app/data/track_repository.dart';
import 'package:lasono_app/data/user_repository.dart';
import 'package:lasono_app/models/comment.dart';
import 'package:lasono_app/models/engagement.dart';
import 'package:lasono_app/models/search_results.dart';
import 'package:lasono_app/models/track.dart';
import 'package:lasono_app/models/track_page.dart';

const _realTrackId = '0c1f2a3b-4c5d-4e6f-8a9b-0c1d2e3f4a5b';
const _realUserId = '5b0c2d4e-1111-4222-8333-944455566677';

// "Real" repositories that only remember how they were called and answer with a fixed value.

class _RealTracks implements TrackRepository {
  final calls = <String>[];

  Track _track(String id) => Track(id: id, title: 'Real $id', description: '', status: 'READY', ownerId: _realUserId);

  @override
  Future<Track> getTrack(String id) async {
    calls.add('getTrack:$id');
    return _track(id);
  }

  @override
  Future<TrackPage> listTracks({String? cursor, int? limit}) async {
    calls.add('listTracks');
    return TrackPage(items: [_track(_realTrackId)], nextCursor: 'next');
  }

  @override
  Future<TrackPage> listUserTracks(String userId, {String? cursor, int? limit}) async {
    calls.add('listUserTracks:$userId');
    return TrackPage(items: [_track(_realTrackId)], totalCount: 1);
  }

  @override
  Future<Uri> fetchStreamUrl(String id) async {
    calls.add('fetchStreamUrl:$id');
    return Uri.parse('http://real/stream');
  }

  @override
  Future<Track> updateTrack(String id, {String? title, String? description, String? visibility}) async {
    calls.add('updateTrack:$id');
    return _track(id);
  }

  @override
  Future<void> deleteTrack(String id) async => calls.add('deleteTrack:$id');

  @override
  Future<String> uploadTrack({
    required String title,
    String description = '',
    String visibility = 'PUBLIC',
    required String filename,
    required Uint8List bytes,
  }) async {
    calls.add('uploadTrack:$title');
    return _realTrackId;
  }
}

class _RealUsers implements UserRepository {
  final calls = <String>[];

  Profile _profile(String id) => Profile(userId: id, displayName: 'Real $id');

  @override
  Future<Profile> getProfile(String userId) async {
    calls.add('getProfile:$userId');
    return _profile(userId);
  }

  @override
  Future<List<Profile>> getProfiles(Iterable<String> userIds) async {
    calls.add('getProfiles:${userIds.join(',')}');
    return userIds.map(_profile).toList();
  }

  @override
  Future<Account> changeDisplayName(String displayName) async {
    calls.add('changeDisplayName');
    return Account(userId: _realUserId, email: 'a@x.com', displayName: displayName);
  }
}

class _RealSocial implements SocialRepository {
  final calls = <String>[];

  @override
  Future<LikeState> likeTrack(String trackId) async {
    calls.add('like:$trackId');
    return LikeState(trackId: trackId, liked: true, likeCount: 41);
  }

  @override
  Future<LikeState> unlikeTrack(String trackId) async {
    calls.add('unlike:$trackId');
    return LikeState(trackId: trackId, liked: false, likeCount: 40);
  }

  @override
  Future<FollowState> followUser(String userId) async {
    calls.add('follow:$userId');
    return FollowState(userId: userId, following: true, followerCount: 9);
  }

  @override
  Future<FollowState> unfollowUser(String userId) async {
    calls.add('unfollow:$userId');
    return FollowState(userId: userId, following: false, followerCount: 8);
  }

  @override
  Future<CursorPage<FollowEdge>> followers(String userId, {String? cursor, int? limit}) async {
    calls.add('followers:$userId');
    return const CursorPage(items: []);
  }

  @override
  Future<CursorPage<FollowEdge>> following(String userId, {String? cursor, int? limit}) async {
    calls.add('following:$userId');
    return const CursorPage(items: []);
  }

  @override
  Future<CursorPage<Comment>> comments(
    String trackId, {
    CommentOrder order = CommentOrder.position,
    String? cursor,
    int? limit,
  }) async {
    calls.add('comments:$trackId');
    return const CursorPage(items: []);
  }

  @override
  Future<Comment> postComment(String trackId, {required int positionMs, required String text}) async {
    calls.add('postComment:$trackId');
    return Comment(id: 'real-c', trackId: trackId, authorId: 'a', positionMs: positionMs, text: text);
  }

  @override
  Future<void> deleteComment(String trackId, String commentId) async => calls.add('deleteComment:$trackId');
}

class _RealFeed implements FeedRepository {
  final calls = <String>[];

  @override
  Future<TrackPage> feed({String? cursor, int? limit}) async {
    calls.add('feed');
    return const TrackPage(items: []);
  }

  @override
  Future<TrackPage> likedTracks(String userId, {String? cursor, int? limit}) async {
    calls.add('likedTracks:$userId');
    return const TrackPage(items: []);
  }
}

class _RealSearch implements SearchRepository {
  final calls = <String>[];

  @override
  Future<SearchResults> search(String query, {SearchType type = SearchType.all, int? limit}) async {
    calls.add('search:$query');
    return const SearchResults();
  }
}

class _Rig {
  _Rig({
    bool likes = false,
    bool follows = false,
    bool comments = false,
    bool feedFake = false,
    bool searchFake = false,
  })  : world = FakeWorld(clock: () => DateTime.utc(2026, 10, 8, 12)),
        behavior = FakeBehavior.instant(),
        flags = FakeFlags(likes: likes, follows: follows, comments: comments, feed: feedFake, search: searchFake) {
    final fakeTracks = FakeTrackRepository(world, behavior, () => viewer);
    final fakeUsers = FakeUserRepository(world, behavior, () => viewer);
    final fakeSocial = FakeSocialRepository(world, behavior, () => viewer);
    tracks = RoutingTrackRepository(
      real: realTracks,
      fake: fakeTracks,
      world: world,
      viewerId: () => viewer,
      fakeLikes: likes,
      fakeComments: comments,
    );
    users = RoutingUserRepository(
      real: realUsers,
      fake: fakeUsers,
      world: world,
      viewerId: () => viewer,
      fakeFollows: follows,
    );
    social = RoutingSocialRepository(
      real: realSocial,
      fake: fakeSocial,
      fakeLikes: likes,
      fakeFollows: follows,
      fakeComments: comments,
    );
    feed = RoutingFeedRepository(
      real: realFeed,
      fake: FakeFeedRepository(world, behavior, () => viewer),
      fakeFeed: feedFake,
    );
    search = RoutingSearchRepository(
      real: realSearch,
      fake: FakeSearchRepository(world, behavior, () => viewer),
      fakeSearch: searchFake,
    );
  }

  final FakeWorld world;
  final FakeBehavior behavior;
  final FakeFlags flags;
  String? viewer = 'viewer-1';

  final realTracks = _RealTracks();
  final realUsers = _RealUsers();
  final realSocial = _RealSocial();
  final realFeed = _RealFeed();
  final realSearch = _RealSearch();

  late final RoutingTrackRepository tracks;
  late final RoutingUserRepository users;
  late final RoutingSocialRepository social;
  late final RoutingFeedRepository feed;
  late final RoutingSearchRepository search;

  String get fakeTrack => world.tracks.firstWhere((t) => t.isReady).id;
  String get fakeUser => FakeWorld.userId(1);
}

void main() {
  group('tracks', () {
    test('a fake id goes to the fake repository, a real id to the real one', () async {
      final r = _Rig();
      expect((await r.tracks.getTrack(r.fakeTrack)).ownerId, startsWith(FakeWorld.idPrefix));
      expect((await r.tracks.getTrack(_realTrackId)).title, 'Real $_realTrackId');
      expect(r.realTracks.calls, ['getTrack:$_realTrackId']);
    });

    test('the stream address of a fake track is made in memory; a real one comes from the server', () async {
      final r = _Rig();
      expect((await r.tracks.fetchStreamUrl(r.fakeTrack)).scheme, 'data');
      expect((await r.tracks.fetchStreamUrl(_realTrackId)).host, 'real');
    });

    test('the list is the real list; the tracks of a fake user are the fake ones', () async {
      final r = _Rig();
      expect((await r.tracks.listTracks()).items.single.id, _realTrackId);
      expect((await r.tracks.listUserTracks(r.fakeUser)).totalCount, greaterThan(0));
      await r.tracks.listUserTracks(_realUserId);
      expect(r.realTracks.calls, ['listTracks', 'listUserTracks:$_realUserId']);
    });

    test('an upload always goes to the real backend', () async {
      final r = _Rig(likes: true, comments: true, follows: true, feedFake: true, searchFake: true);
      await r.tracks.uploadTrack(title: 'Mới', filename: 'a.mp3', bytes: Uint8List(1));
      expect(r.realTracks.calls, ['uploadTrack:Mới']);
    });

    test('changing or deleting a fake track is refused by the fake, never sent to the server', () async {
      final r = _Rig();
      await expectLater(r.tracks.deleteTrack(r.fakeTrack), throwsA(anything));
      await expectLater(r.tracks.updateTrack(r.fakeTrack, title: 'x'), throwsA(anything));
      expect(r.realTracks.calls, isEmpty);
      await r.tracks.deleteTrack(_realTrackId);
      expect(r.realTracks.calls, ['deleteTrack:$_realTrackId']);
    });

    test('with the likes switch on, a real track shows the fake like count and the like of the viewer', () async {
      final r = _Rig(likes: true);
      await r.social.likeTrack(_realTrackId);

      final track = await r.tracks.getTrack(_realTrackId);

      expect(track.likeCount, 1);
      expect(track.isLikedByMe, isTrue);
      final listed = (await r.tracks.listTracks()).items.single;
      expect(listed.likeCount, 1);
    });

    test('with the switches off, a real track is shown exactly as the server sent it', () async {
      final r = _Rig();
      r.world.like('viewer-1', _realTrackId);
      final track = await r.tracks.getTrack(_realTrackId);
      expect((track.likeCount, track.isLikedByMe), (0, false));
    });

    test('the likes and the comments are overlaid separately', () async {
      final r = _Rig(comments: true);
      r.world.addComment(_realTrackId, 'viewer-1', 0, 'hi');
      r.world.like('viewer-1', _realTrackId);

      final track = await r.tracks.getTrack(_realTrackId);

      expect(track.commentCount, 1);
      expect(track.likeCount, 0, reason: 'likes are not fake in this rig');
    });
  });

  group('users', () {
    test('a fake id goes to the fake repository, a real id to the real one', () async {
      final r = _Rig();
      expect((await r.users.getProfile(r.fakeUser)).displayName, 'Sơn Tùng');
      expect((await r.users.getProfile(_realUserId)).displayName, 'Real $_realUserId');
      expect(r.realUsers.calls, ['getProfile:$_realUserId']);
    });

    test('several profiles are split by kind, asked in one request each, and put together', () async {
      final r = _Rig();
      final profiles = await r.users.getProfiles([r.fakeUser, _realUserId, FakeWorld.userId(2)]);

      expect(profiles.map((p) => p.userId).toSet(), {r.fakeUser, _realUserId, FakeWorld.userId(2)});
      expect(r.realUsers.calls, ['getProfiles:$_realUserId']);
    });

    test('with the follows switch on, a real user has the fake counts and follow state', () async {
      final r = _Rig(follows: true);
      await r.social.followUser(_realUserId);

      final profile = await r.users.getProfile(_realUserId);

      expect(profile.isFollowedByMe, isTrue);
      expect(profile.followerCount, 1);
      expect((await r.users.getProfiles([_realUserId])).single.isFollowedByMe, isTrue);
    });

    test('with it off, a real profile is as the server sent it', () async {
      final r = _Rig();
      r.world.ensureViewer('viewer-1');
      r.world.follow('viewer-1', _realUserId);
      expect((await r.users.getProfile(_realUserId)).isFollowedByMe, isFalse);
    });

    test('renaming goes to the real backend', () async {
      final r = _Rig();
      await r.users.changeDisplayName('Mới');
      expect(r.realUsers.calls, ['changeDisplayName']);
    });
  });

  group('social', () {
    test('a fake id is always fake, even when its switch is off', () async {
      final r = _Rig();
      await r.social.likeTrack(r.fakeTrack);
      await r.social.followUser(r.fakeUser);
      await r.social.comments(r.fakeTrack);
      expect(r.realSocial.calls, isEmpty);
    });

    test('a real id goes to the real backend when its switch is off', () async {
      final r = _Rig();
      await r.social.likeTrack(_realTrackId);
      await r.social.followUser(_realUserId);
      await r.social.postComment(_realTrackId, positionMs: 1, text: 'x');
      expect(r.realSocial.calls, ['like:$_realTrackId', 'follow:$_realUserId', 'postComment:$_realTrackId']);
    });

    test('each feature has its own switch: fake likes with real follows and comments', () async {
      final r = _Rig(likes: true);

      final liked = await r.social.likeTrack(_realTrackId);
      await r.social.followUser(_realUserId);
      await r.social.comments(_realTrackId);

      expect(liked.likeCount, 1, reason: 'the fake count, not the 41 of the real backend');
      expect(r.realSocial.calls, ['follow:$_realUserId', 'comments:$_realTrackId']);
    });

    test('with all switches on nothing reaches the real backend', () async {
      final r = _Rig(likes: true, follows: true, comments: true);
      await r.social.likeTrack(_realTrackId);
      await r.social.unlikeTrack(_realTrackId);
      await r.social.followUser(_realUserId);
      await r.social.unfollowUser(_realUserId);
      await r.social.followers(_realUserId);
      await r.social.following(_realUserId);
      await r.social.comments(_realTrackId);
      final comment = await r.social.postComment(_realTrackId, positionMs: 5, text: 'hay');
      await r.social.deleteComment(_realTrackId, comment.id);
      expect(r.realSocial.calls, isEmpty);
    });
  });

  group('feed and search', () {
    test('the feed is real unless its switch is on', () async {
      final real = _Rig();
      await real.feed.feed();
      expect(real.realFeed.calls, ['feed']);

      final fake = _Rig(feedFake: true);
      expect((await fake.feed.feed()).items, isNotEmpty);
      expect(fake.realFeed.calls, isEmpty);
    });

    test('the likes of a fake user are fake even when the feed is real', () async {
      final r = _Rig();
      await r.feed.likedTracks(r.fakeUser);
      await r.feed.likedTracks(_realUserId);
      expect(r.realFeed.calls, ['likedTracks:$_realUserId']);
    });

    test('search is real unless its switch is on', () async {
      final real = _Rig();
      await real.search.search('son tung');
      expect(real.realSearch.calls, ['search:son tung']);

      final fake = _Rig(searchFake: true);
      expect((await fake.search.search('son tung')).users.first.displayName, 'Sơn Tùng');
      expect(fake.realSearch.calls, isEmpty);
    });
  });

  group('AppRepositories.create', () {
    SessionController session() =>
        SessionController(AuthApi(baseUrl: 'http://api.test', client: MockClient((r) async => http.Response('{}', 401))));

    test('without a switch the real repositories are used as they are, with nothing fake around', () {
      final repositories = AppRepositories.create(session: session(), flags: const FakeFlags());

      expect(repositories.tracks, isA<TrackApi>());
      expect(repositories.users, isNot(isA<RoutingUserRepository>()));
      expect(repositories.social, isNot(isA<RoutingSocialRepository>()));
      expect(repositories.fakeWorld, isNull);
      expect(repositories.flags.any, isFalse);
    });

    test('with a switch every repository routes by id, and the fake world exists', () {
      final repositories = AppRepositories.create(session: session(), flags: const FakeFlags(search: true));

      expect(repositories.tracks, isA<RoutingTrackRepository>());
      expect(repositories.users, isA<RoutingUserRepository>());
      expect(repositories.social, isA<RoutingSocialRepository>());
      expect(repositories.feed, isA<RoutingFeedRepository>());
      expect(repositories.search, isA<RoutingSearchRepository>());
      expect(repositories.fakeWorld, isNotNull);
      expect(repositories.fakeBehavior, isNotNull);
    });

    test('the user directory asks the users repository of the same set', () async {
      final repositories = AppRepositories.create(
        session: session(),
        flags: const FakeFlags(follows: true),
        behavior: FakeBehavior.instant(),
      );
      final profile = await repositories.directory.profile(FakeWorld.userId(1));
      expect(profile!.displayName, 'Sơn Tùng');
    });

    testWidgets('RepositoriesScope hands the repositories to the widgets below it', (tester) async {
      final repositories = AppRepositories.create(session: session(), flags: const FakeFlags());
      late AppRepositories seen;

      await tester.pumpWidget(
        RepositoriesScope(
          repositories: repositories,
          child: Builder(
            builder: (context) {
              seen = RepositoriesScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(seen, same(repositories));
    });
  });
}
