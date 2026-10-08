import 'dart:typed_data';

import '../../api/auth_api.dart';
import '../../api/profile_api.dart';
import '../../core/text/fold_accents.dart';
import '../../models/comment.dart';
import '../../models/engagement.dart';
import '../../models/search_results.dart';
import '../../models/track.dart';
import '../../models/track_page.dart';
import '../feed_repository.dart';
import '../repository_exception.dart';
import '../search_repository.dart';
import '../social_repository.dart';
import '../track_repository.dart';
import '../user_repository.dart';
import 'fake_audio.dart';
import 'fake_behavior.dart';
import 'fake_world.dart';

/// Who is logged in right now, or null. The fake repositories ask each time, so a login or a logout is seen.
typedef ViewerId = String? Function();

RepositoryException _unauthorized() =>
    const RepositoryException('Please log in again', kind: RepositoryErrorKind.unauthorized);

RepositoryException _notFound(String what) => RepositoryException('$what not found', kind: RepositoryErrorKind.notFound);

RepositoryException _invalid(String message) => RepositoryException(message, kind: RepositoryErrorKind.invalid);

String _requireViewer(ViewerId viewerId, FakeWorld world) {
  final viewer = viewerId();
  if (viewer == null) throw _unauthorized();
  world.ensureViewer(viewer);
  return viewer;
}

/// One page of [all], the way the real server pages: a cursor (opaque to the caller), a limit that defaults to
/// [defaultLimit] and is cut at [maxLimit], and no cursor on the last page.
({List<T> items, String? nextCursor}) _page<T>(
  List<T> all,
  String? cursor,
  int? limit, {
  int defaultLimit = 20,
  int maxLimit = 50,
}) {
  if (limit != null && limit < 1) throw _invalid('limit must be at least 1');
  final size = limit == null ? defaultLimit : (limit > maxLimit ? maxLimit : limit);

  var start = 0;
  if (cursor != null && cursor.isNotEmpty) {
    final parsed = cursor.startsWith('i') ? int.tryParse(cursor.substring(1)) : null;
    if (parsed == null || parsed < 0) throw _invalid('Invalid cursor');
    start = parsed;
  }
  final end = start + size;
  return (
    items: all.skip(start).take(size).toList(),
    nextCursor: end < all.length ? 'i$end' : null,
  );
}

// ---------------------------------------------------------------------------------------------------------------

/// The fake tracks (those of [FakeWorld]) as a track repository. Read only: a fake track cannot be uploaded,
/// changed or deleted. Its audio is a short tune made in memory ([FakeAudio]), so it can be played and seeked.
class FakeTrackRepository implements TrackRepository {
  FakeTrackRepository(this.world, this.behavior, this.viewerId);

  final FakeWorld world;
  final FakeBehavior behavior;
  final ViewerId viewerId;

  final Map<String, Uri> _audio = {};

  Track _shown(Track track) => world.withSocial(track, viewerId: viewerId());

  @override
  Future<Track> getTrack(String id) => behavior.run(() {
        final track = world.track(id);
        if (track == null) throw _notFound('Track');
        return _shown(track);
      });

  @override
  Future<TrackPage> listTracks({String? cursor, int? limit}) => behavior.run(() {
        final page = _page(world.tracks, cursor, limit);
        return TrackPage(items: page.items.map(_shown).toList(), nextCursor: page.nextCursor);
      });

  @override
  Future<TrackPage> listUserTracks(String userId, {String? cursor, int? limit}) => behavior.run(() {
        final mine = world.tracks.where((t) => t.ownerId == userId).toList();
        final page = _page(mine, cursor, limit);
        return TrackPage(
          items: page.items.map(_shown).toList(),
          nextCursor: page.nextCursor,
          totalCount: mine.length,
        );
      });

  @override
  Future<Uri> fetchStreamUrl(String id) => behavior.run(() {
        final track = world.track(id);
        if (track == null) throw _notFound('Track');
        if (!track.isReady) {
          throw const RepositoryException('This track is not ready yet', kind: RepositoryErrorKind.conflict);
        }
        return _audio.putIfAbsent(
          id,
          () => FakeAudio.dataUri(track.durationSeconds!.round(), seed: world.tracks.indexOf(track)),
        );
      });

  static const _readOnly = RepositoryException('A fake track cannot be changed');

  @override
  Future<Track> updateTrack(String id, {String? title, String? description, String? visibility}) =>
      behavior.run(() => throw _readOnly);

  @override
  Future<void> deleteTrack(String id) => behavior.run(() => throw _readOnly);

  @override
  Future<String> uploadTrack({
    required String title,
    String description = '',
    String visibility = 'PUBLIC',
    required String filename,
    required Uint8List bytes,
  }) =>
      behavior.run(() => throw _readOnly);
}

// ---------------------------------------------------------------------------------------------------------------

class FakeUserRepository implements UserRepository {
  FakeUserRepository(this.world, this.behavior, this.viewerId);

  final FakeWorld world;
  final FakeBehavior behavior;
  final ViewerId viewerId;

  @override
  Future<Profile> getProfile(String userId) => behavior.run(() {
        world.ensureViewer(viewerId());
        final user = world.user(userId);
        if (user == null) throw _notFound('User');
        return world.profileOf(user, viewerId: viewerId());
      });

  @override
  Future<List<Profile>> getProfiles(Iterable<String> userIds) => behavior.run(() {
        world.ensureViewer(viewerId());
        return [
          for (final id in userIds.toSet())
            if (world.user(id) case final user?) world.profileOf(user, viewerId: viewerId()),
        ];
      });

  @override
  Future<Account> changeDisplayName(String displayName) =>
      behavior.run(() => throw const RepositoryException('A fake user cannot be renamed'));
}

// ---------------------------------------------------------------------------------------------------------------

/// Likes, follows and comments kept in memory. It works for any id, fake or real: an unknown track simply has no
/// likes and no comments yet. It cannot check a comment position against the length of a track it does not know,
/// so for those it only refuses a negative position.
class FakeSocialRepository implements SocialRepository {
  FakeSocialRepository(this.world, this.behavior, this.viewerId);

  final FakeWorld world;
  final FakeBehavior behavior;
  final ViewerId viewerId;

  static const _maxCommentLength = 500;

  void _requireReadyIfKnown(String trackId) {
    final track = world.track(trackId);
    if (track != null && !track.isReady) {
      throw const RepositoryException('This track is not ready yet', kind: RepositoryErrorKind.conflict);
    }
  }

  @override
  Future<LikeState> likeTrack(String trackId) => behavior.run(() {
        final viewer = _requireViewer(viewerId, world);
        _requireReadyIfKnown(trackId);
        world.like(viewer, trackId);
        return LikeState(trackId: trackId, liked: true, likeCount: world.likeCountOf(trackId));
      });

  @override
  Future<LikeState> unlikeTrack(String trackId) => behavior.run(() {
        final viewer = _requireViewer(viewerId, world);
        world.unlike(viewer, trackId);
        return LikeState(trackId: trackId, liked: false, likeCount: world.likeCountOf(trackId));
      });

  @override
  Future<FollowState> followUser(String userId) => behavior.run(() {
        final viewer = _requireViewer(viewerId, world);
        if (viewer == userId) throw _invalid('You cannot follow yourself');
        if (FakeWorld.isFake(userId) && world.user(userId) == null) throw _notFound('User');
        world.follow(viewer, userId);
        return FollowState(userId: userId, following: true, followerCount: world.followerCountOf(userId));
      });

  @override
  Future<FollowState> unfollowUser(String userId) => behavior.run(() {
        final viewer = _requireViewer(viewerId, world);
        if (FakeWorld.isFake(userId) && world.user(userId) == null) throw _notFound('User');
        world.unfollow(viewer, userId);
        return FollowState(userId: userId, following: false, followerCount: world.followerCountOf(userId));
      });

  @override
  Future<CursorPage<FollowEdge>> followers(String userId, {String? cursor, int? limit}) => behavior.run(() {
        world.ensureViewer(viewerId());
        return _edges(world.followersOf(userId), cursor, limit);
      });

  @override
  Future<CursorPage<FollowEdge>> following(String userId, {String? cursor, int? limit}) => behavior.run(() {
        world.ensureViewer(viewerId());
        return _edges(world.followingOf(userId), cursor, limit);
      });

  CursorPage<FollowEdge> _edges(List<MapEntry<String, DateTime>> found, String? cursor, int? limit) {
    final page = _page(found, cursor, limit);
    return CursorPage(
      items: [for (final e in page.items) FollowEdge(userId: e.key, followedAt: e.value)],
      nextCursor: page.nextCursor,
    );
  }

  @override
  Future<CursorPage<Comment>> comments(
    String trackId, {
    CommentOrder order = CommentOrder.position,
    String? cursor,
    int? limit,
  }) =>
      behavior.run(() {
        final all = [...world.commentsOf(trackId)];
        if (order == CommentOrder.position) {
          all.sort((a, b) {
            final byPosition = a.positionMs.compareTo(b.positionMs);
            return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
          });
        } else {
          all.sort((a, b) {
            final byTime = (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
            return byTime != 0 ? byTime : b.id.compareTo(a.id);
          });
        }
        final page = _page(all, cursor, limit, defaultLimit: 50, maxLimit: 200);
        return CursorPage(items: page.items, nextCursor: page.nextCursor);
      });

  @override
  Future<Comment> postComment(String trackId, {required int positionMs, required String text}) =>
      behavior.run(() {
        final viewer = _requireViewer(viewerId, world);
        _requireReadyIfKnown(trackId);

        final trimmed = text.trim();
        final length = trimmed.runes.length;
        if (length < 1 || length > _maxCommentLength) {
          throw _invalid('text must have 1 to $_maxCommentLength characters');
        }
        final track = world.track(trackId);
        final durationMs = track?.durationMs;
        if (positionMs < 0 || (durationMs != null && positionMs > durationMs)) {
          throw _invalid('positionMs must be between 0 and ${durationMs ?? 'the length of the track'}');
        }
        return world.addComment(trackId, viewer, positionMs, trimmed);
      });

  @override
  Future<void> deleteComment(String trackId, String commentId) => behavior.run(() {
        final viewer = _requireViewer(viewerId, world);
        final comment = world.comment(trackId, commentId);
        if (comment == null) throw _notFound('Comment');
        final ownerOfTrack = world.track(trackId)?.ownerId;
        if (comment.authorId != viewer && ownerOfTrack != viewer) {
          throw const RepositoryException(
            'Only the author or the owner of the track can delete this comment',
            kind: RepositoryErrorKind.forbidden,
          );
        }
        world.removeComment(trackId, commentId);
      });
}

// ---------------------------------------------------------------------------------------------------------------

/// Looks up a track that is not in the fake world (a real one a user liked). Returns null when there is none.
typedef TrackResolver = Future<Track?> Function(String id);

class FakeFeedRepository implements FeedRepository {
  FakeFeedRepository(this.world, this.behavior, this.viewerId, {this.resolveTrack});

  final FakeWorld world;
  final FakeBehavior behavior;
  final ViewerId viewerId;
  final TrackResolver? resolveTrack;

  @override
  Future<TrackPage> feed({String? cursor, int? limit}) => behavior.run(() {
        final viewer = _requireViewer(viewerId, world);
        final followed = world.followingOf(viewer).map((e) => e.key).toSet();
        final tracks = world.tracks
            .where((t) => followed.contains(t.ownerId) && t.isReady && !t.isPrivate)
            .map((t) => world.withSocial(t, viewerId: viewer))
            .toList();
        final page = _page(tracks, cursor, limit);
        return TrackPage(items: page.items, nextCursor: page.nextCursor);
      });

  @override
  Future<TrackPage> likedTracks(String userId, {String? cursor, int? limit}) async {
    final viewer = viewerId();
    world.ensureViewer(viewer);
    // The tracks are looked up before the (delayed) answer, because a real track needs a real request.
    final ids = world.likedBy(userId);
    if (FakeWorld.isFake(userId) && world.user(userId) == null) {
      return behavior.run(() => throw _notFound('User'));
    }
    final page = _page(ids, cursor, limit);
    final tracks = <Track>[];
    for (final id in page.items) {
      final track = world.track(id) ?? await resolveTrack?.call(id);
      if (track != null) tracks.add(world.withSocial(track, viewerId: viewer));
    }
    return behavior.run(() => TrackPage(items: tracks, nextCursor: page.nextCursor));
  }
}

// ---------------------------------------------------------------------------------------------------------------

class FakeSearchRepository implements SearchRepository {
  FakeSearchRepository(this.world, this.behavior, this.viewerId);

  final FakeWorld world;
  final FakeBehavior behavior;
  final ViewerId viewerId;

  // Like PostgreSQL's pg_trgm (docs/backend-guide/06-search-vietnamese.md): a text is its set of 3-letter
  // pieces, with two spaces in front of each word and one behind; two texts are alike when they share many.
  static const _threshold = 0.3;

  @override
  Future<SearchResults> search(String query, {SearchType type = SearchType.all, int? limit}) => behavior.run(() {
        final text = query.trim().replaceAll(RegExp(r'\s+'), ' ');
        final length = text.runes.length;
        if (length < 2 || length > 100) throw _invalid('q must have 2 to 100 characters');
        if (limit != null && limit < 1) throw _invalid('limit must be at least 1');
        final size = limit == null ? 20 : (limit > 50 ? 50 : limit);
        final folded = foldAccents(text);
        final viewer = viewerId();
        world.ensureViewer(viewer);

        final tracks = <(double, Track)>[];
        if (type != SearchType.users) {
          for (final track in world.tracks) {
            if (!track.isReady || track.isPrivate) continue;
            final score = _score(foldAccents(track.title), folded);
            if (score != null) tracks.add((score, world.withSocial(track, viewerId: viewer)));
          }
          tracks.sort((a, b) {
            final byScore = b.$1.compareTo(a.$1);
            return byScore != 0 ? byScore : (b.$2.createdAt ?? DateTime(0)).compareTo(a.$2.createdAt ?? DateTime(0));
          });
        }

        final users = <(double, Profile)>[];
        if (type != SearchType.tracks) {
          for (final user in world.users) {
            final score = _score(foldAccents(user.displayName), folded);
            if (score != null) users.add((score, world.profileOf(user, viewerId: viewer)));
          }
          users.sort((a, b) {
            final byScore = b.$1.compareTo(a.$1);
            return byScore != 0 ? byScore : b.$2.followerCount.compareTo(a.$2.followerCount);
          });
        }

        return SearchResults(
          tracks: tracks.take(size).map((e) => e.$2).toList(),
          users: users.take(size).map((e) => e.$2).toList(),
        );
      });

  /// How well [title] answers [query] (both folded), or null when it does not. A title that contains the query
  /// scores above one that is only alike; one that starts with it scores highest.
  static double? _score(String title, String query) {
    if (title.startsWith(query)) return 2;
    if (title.contains(query)) return 1.5;
    final similarity = _similarity(title, query);
    return similarity >= _threshold ? similarity : null;
  }

  static Set<String> _trigrams(String folded) {
    final pieces = <String>{};
    for (final match in RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(folded)) {
      final padded = '  ${match.group(0)} ';
      for (var i = 0; i + 3 <= padded.length; i++) {
        pieces.add(padded.substring(i, i + 3));
      }
    }
    return pieces;
  }

  /// The share of 3-letter pieces two texts have in common, from 0 to 1 (the `similarity` of pg_trgm).
  static double _similarity(String a, String b) {
    final ta = _trigrams(a);
    final tb = _trigrams(b);
    if (ta.isEmpty || tb.isEmpty) return 0;
    final shared = ta.intersection(tb).length;
    return shared / (ta.length + tb.length - shared);
  }

  /// Exposed for the tests, so they can pin the numbers worked out in the backend guide.
  static double similarityForTest(String a, String b) => _similarity(foldAccents(a), foldAccents(b));
}
