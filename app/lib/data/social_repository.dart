import '../models/comment.dart';
import '../models/engagement.dart';

/// Likes, follows and comments: what people do with tracks and with each other (Phase 5 of the backend).
/// Every method that changes something needs a login and throws a [RepositoryException] of kind
/// `unauthorized` without one.
abstract class SocialRepository {
  /// Idempotent: liking a track that is already liked changes nothing and still answers with the state.
  Future<LikeState> likeTrack(String trackId);
  Future<LikeState> unlikeTrack(String trackId);

  /// Idempotent. Following oneself is refused (`invalid`).
  Future<FollowState> followUser(String userId);
  Future<FollowState> unfollowUser(String userId);

  /// The people who follow [userId], newest first. Only ids: ask the user directory for the names.
  Future<CursorPage<FollowEdge>> followers(String userId, {String? cursor, int? limit});

  /// The people [userId] follows, newest first.
  Future<CursorPage<FollowEdge>> following(String userId, {String? cursor, int? limit});

  Future<CursorPage<Comment>> comments(
    String trackId, {
    CommentOrder order = CommentOrder.position,
    String? cursor,
    int? limit,
  });

  /// Pins a comment at [positionMs] of the track. The position must be inside the track.
  Future<Comment> postComment(String trackId, {required int positionMs, required String text});

  /// Allowed for the author of the comment and for the owner of the track.
  Future<void> deleteComment(String trackId, String commentId);
}
