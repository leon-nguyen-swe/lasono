import 'dart:typed_data';

import '../../api/auth_api.dart';
import '../../api/profile_api.dart';
import '../../models/comment.dart';
import '../../models/engagement.dart';
import '../../models/search_results.dart';
import '../../models/track.dart';
import '../../models/track_page.dart';
import '../feed_repository.dart';
import '../search_repository.dart';
import '../social_repository.dart';
import '../track_repository.dart';
import '../user_repository.dart';
import 'fake_repositories.dart';
import 'fake_world.dart';

// When part of the backend is not built yet, some data is real and some is made up, and both can be on one screen.
// These repositories choose, for every call, where it goes:
//
//  - an id that belongs to the fake world (it starts with `f4e00000-`) always goes to the fake repository,
//    because the real backend has never heard of it;
//  - any other id goes to the real repository, unless the switch of that feature says it is fake.
//
// When no switch is on, none of this is used: the real repositories are used as they are.

/// Tracks. The real ones come from the real backend; the likes and comments of a real track are replaced by the
/// fake ones when those switches are on, so a screen shows what the fake social repository holds.
class RoutingTrackRepository implements TrackRepository {
  RoutingTrackRepository({
    required this.real,
    required this.fake,
    required this.world,
    required this.viewerId,
    required this.fakeLikes,
    required this.fakeComments,
  });

  final TrackRepository real;
  final FakeTrackRepository fake;
  final FakeWorld world;
  final ViewerId viewerId;
  final bool fakeLikes;
  final bool fakeComments;

  Track _shown(Track track) => fakeLikes || fakeComments
      ? world.withSocial(track, viewerId: viewerId(), likes: fakeLikes, comments: fakeComments)
      : track;

  TrackPage _shownPage(TrackPage page) => TrackPage(
        items: page.items.map(_shown).toList(),
        nextCursor: page.nextCursor,
        totalCount: page.totalCount,
      );

  @override
  Future<Track> getTrack(String id) =>
      FakeWorld.isFake(id) ? fake.getTrack(id) : real.getTrack(id).then(_shown);

  @override
  Future<TrackPage> listTracks({String? cursor, int? limit}) =>
      real.listTracks(cursor: cursor, limit: limit).then(_shownPage);

  @override
  Future<TrackPage> listUserTracks(String userId, {String? cursor, int? limit}) => FakeWorld.isFake(userId)
      ? fake.listUserTracks(userId, cursor: cursor, limit: limit)
      : real.listUserTracks(userId, cursor: cursor, limit: limit).then(_shownPage);

  @override
  Future<Uri> fetchStreamUrl(String id) => FakeWorld.isFake(id) ? fake.fetchStreamUrl(id) : real.fetchStreamUrl(id);

  @override
  Future<Track> updateTrack(String id, {String? title, String? description, String? visibility}) =>
      FakeWorld.isFake(id)
          ? fake.updateTrack(id, title: title, description: description, visibility: visibility)
          : real.updateTrack(id, title: title, description: description, visibility: visibility).then(_shown);

  @override
  Future<void> deleteTrack(String id) => FakeWorld.isFake(id) ? fake.deleteTrack(id) : real.deleteTrack(id);

  @override
  Future<String> uploadTrack({
    required String title,
    String description = '',
    String visibility = 'PUBLIC',
    required String filename,
    required Uint8List bytes,
  }) =>
      real.uploadTrack(
        title: title,
        description: description,
        visibility: visibility,
        filename: filename,
        bytes: bytes,
      );
}

/// Users. A real user's counts and "followed by me" are the fake ones when the follows switch is on.
class RoutingUserRepository implements UserRepository {
  RoutingUserRepository({
    required this.real,
    required this.fake,
    required this.world,
    required this.viewerId,
    required this.fakeFollows,
  });

  final UserRepository real;
  final FakeUserRepository fake;
  final FakeWorld world;
  final ViewerId viewerId;
  final bool fakeFollows;

  Profile _shown(Profile profile) {
    if (!fakeFollows) return profile;
    final viewer = viewerId();
    world.ensureViewer(viewer);
    return profile.copyWith(
      followerCount: world.followerCountOf(profile.userId),
      followingCount: world.followingCountOf(profile.userId),
      isFollowedByMe: world.isFollowing(viewer, profile.userId),
    );
  }

  @override
  Future<Profile> getProfile(String userId) =>
      FakeWorld.isFake(userId) ? fake.getProfile(userId) : real.getProfile(userId).then(_shown);

  @override
  Future<List<Profile>> getProfiles(Iterable<String> userIds) async {
    final ids = userIds.toSet();
    final fakeIds = ids.where(FakeWorld.isFake).toList();
    final realIds = ids.where((id) => !FakeWorld.isFake(id)).toList();
    final found = await Future.wait([
      if (fakeIds.isNotEmpty) fake.getProfiles(fakeIds),
      if (realIds.isNotEmpty) real.getProfiles(realIds).then((list) => list.map(_shown).toList()),
    ]);
    return [for (final list in found) ...list];
  }

  @override
  Future<Account> changeDisplayName(String displayName) => real.changeDisplayName(displayName);
}

/// Likes, follows and comments: each kind has its own switch.
class RoutingSocialRepository implements SocialRepository {
  RoutingSocialRepository({
    required this.real,
    required this.fake,
    required this.fakeLikes,
    required this.fakeFollows,
    required this.fakeComments,
  });

  final SocialRepository real;
  final SocialRepository fake;
  final bool fakeLikes;
  final bool fakeFollows;
  final bool fakeComments;

  SocialRepository _likes(String trackId) => fakeLikes || FakeWorld.isFake(trackId) ? fake : real;
  SocialRepository _follows(String userId) => fakeFollows || FakeWorld.isFake(userId) ? fake : real;
  SocialRepository _comments(String trackId) => fakeComments || FakeWorld.isFake(trackId) ? fake : real;

  @override
  Future<LikeState> likeTrack(String trackId) => _likes(trackId).likeTrack(trackId);

  @override
  Future<LikeState> unlikeTrack(String trackId) => _likes(trackId).unlikeTrack(trackId);

  @override
  Future<FollowState> followUser(String userId) => _follows(userId).followUser(userId);

  @override
  Future<FollowState> unfollowUser(String userId) => _follows(userId).unfollowUser(userId);

  @override
  Future<CursorPage<FollowEdge>> followers(String userId, {String? cursor, int? limit}) =>
      _follows(userId).followers(userId, cursor: cursor, limit: limit);

  @override
  Future<CursorPage<FollowEdge>> following(String userId, {String? cursor, int? limit}) =>
      _follows(userId).following(userId, cursor: cursor, limit: limit);

  @override
  Future<CursorPage<Comment>> comments(
    String trackId, {
    CommentOrder order = CommentOrder.position,
    String? cursor,
    int? limit,
  }) =>
      _comments(trackId).comments(trackId, order: order, cursor: cursor, limit: limit);

  @override
  Future<Comment> postComment(String trackId, {required int positionMs, required String text}) =>
      _comments(trackId).postComment(trackId, positionMs: positionMs, text: text);

  @override
  Future<void> deleteComment(String trackId, String commentId) =>
      _comments(trackId).deleteComment(trackId, commentId);
}

class RoutingFeedRepository implements FeedRepository {
  RoutingFeedRepository({required this.real, required this.fake, required this.fakeFeed});

  final FeedRepository real;
  final FeedRepository fake;
  final bool fakeFeed;

  @override
  Future<TrackPage> feed({String? cursor, int? limit}) =>
      (fakeFeed ? fake : real).feed(cursor: cursor, limit: limit);

  @override
  Future<TrackPage> likedTracks(String userId, {String? cursor, int? limit}) =>
      (fakeFeed || FakeWorld.isFake(userId) ? fake : real).likedTracks(userId, cursor: cursor, limit: limit);
}

class RoutingSearchRepository implements SearchRepository {
  RoutingSearchRepository({required this.real, required this.fake, required this.fakeSearch});

  final SearchRepository real;
  final SearchRepository fake;
  final bool fakeSearch;

  @override
  Future<SearchResults> search(String query, {SearchType type = SearchType.all, int? limit}) =>
      (fakeSearch ? fake : real).search(query, type: type, limit: limit);
}
