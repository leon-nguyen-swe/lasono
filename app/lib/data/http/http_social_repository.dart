import '../../models/comment.dart';
import '../../models/engagement.dart';
import '../social_repository.dart';
import 'api_client.dart';

/// Likes, follows and comments over HTTP, written to `docs/api-contract.md` Part B.
///
/// TODO(guide 02, 03, 04): none of these routes exist in the backend yet. Until each guide is done, run the app
/// with `FAKE_LIKES`, `FAKE_FOLLOWS` and `FAKE_COMMENTS` (see docs/backend-guide/00-how-to-use.md).
class HttpSocialRepository implements SocialRepository {
  HttpSocialRepository(this._api);

  final ApiClient _api;

  static const _trackGone = {404: 'Track not found', 409: 'This track is not ready yet'};
  static const _userGone = {404: 'User not found'};

  @override
  Future<LikeState> likeTrack(String trackId) => _like('PUT', trackId);

  @override
  Future<LikeState> unlikeTrack(String trackId) => _like('DELETE', trackId);

  Future<LikeState> _like(String method, String trackId) async {
    final response = await _api.send(method, '/tracks/${Uri.encodeComponent(trackId)}/like');
    if (response.status == 200) return LikeState.fromJson(response.object);
    throw response.failure(messages: _trackGone);
  }

  @override
  Future<FollowState> followUser(String userId) => _follow('PUT', userId);

  @override
  Future<FollowState> unfollowUser(String userId) => _follow('DELETE', userId);

  Future<FollowState> _follow(String method, String userId) async {
    final response = await _api.send(method, '/users/${Uri.encodeComponent(userId)}/follow');
    if (response.status == 200) return FollowState.fromJson(response.object);
    throw response.failure(messages: _userGone);
  }

  @override
  Future<CursorPage<FollowEdge>> followers(String userId, {String? cursor, int? limit}) =>
      _edges(userId, 'followers', cursor, limit);

  @override
  Future<CursorPage<FollowEdge>> following(String userId, {String? cursor, int? limit}) =>
      _edges(userId, 'following', cursor, limit);

  Future<CursorPage<FollowEdge>> _edges(String userId, String kind, String? cursor, int? limit) async {
    final response = await _api.get(
      '/users/${Uri.encodeComponent(userId)}/$kind',
      query: {'cursor': cursor, 'limit': limit?.toString()},
    );
    if (response.status == 200) return CursorPage.fromJson(response.object, FollowEdge.fromJson);
    throw response.failure(messages: _userGone);
  }

  @override
  Future<CursorPage<Comment>> comments(
    String trackId, {
    CommentOrder order = CommentOrder.position,
    String? cursor,
    int? limit,
  }) async {
    final response = await _api.get(
      '/tracks/${Uri.encodeComponent(trackId)}/comments',
      query: {'order': order.wireName, 'cursor': cursor, 'limit': limit?.toString()},
    );
    if (response.status == 200) return CursorPage.fromJson(response.object, Comment.fromJson);
    throw response.failure(messages: _trackGone);
  }

  @override
  Future<Comment> postComment(String trackId, {required int positionMs, required String text}) async {
    final response = await _api.send(
      'POST',
      '/tracks/${Uri.encodeComponent(trackId)}/comments',
      jsonBody: {'positionMs': positionMs, 'text': text},
    );
    if (response.status == 201 || response.status == 200) return Comment.fromJson(response.object);
    throw response.failure(messages: _trackGone);
  }

  @override
  Future<void> deleteComment(String trackId, String commentId) async {
    final response = await _api.send(
      'DELETE',
      '/tracks/${Uri.encodeComponent(trackId)}/comments/${Uri.encodeComponent(commentId)}',
    );
    if (response.status == 204 || response.status == 200) return;
    throw response.failure(
      messages: const {403: 'Only the author or the owner of the track can delete this comment', 404: 'Comment not found'},
    );
  }
}
