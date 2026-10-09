/// The answer to liking or unliking a track: the new state and the count after the change.
class LikeState {
  const LikeState({required this.trackId, required this.liked, required this.likeCount});

  factory LikeState.fromJson(Map<String, dynamic> json) => LikeState(
        trackId: json['trackId'] as String,
        liked: json['liked'] as bool,
        likeCount: (json['likeCount'] as num).toInt(),
      );

  final String trackId;
  final bool liked;
  final int likeCount;
}

/// The answer to following or unfollowing a user.
class FollowState {
  const FollowState({required this.userId, required this.following, required this.followerCount});

  factory FollowState.fromJson(Map<String, dynamic> json) => FollowState(
        userId: json['userId'] as String,
        following: json['following'] as bool,
        followerCount: (json['followerCount'] as num).toInt(),
      );

  final String userId;
  final bool following;
  final int followerCount;
}

/// One entry of a followers or following list. Only an id: names come from the user directory.
class FollowEdge {
  const FollowEdge({required this.userId, this.followedAt});

  factory FollowEdge.fromJson(Map<String, dynamic> json) => FollowEdge(
        userId: json['userId'] as String,
        followedAt: DateTime.tryParse(json['followedAt'] as String? ?? ''),
      );

  final String userId;
  final DateTime? followedAt;
}

/// A page of anything that is listed with a cursor. [nextCursor] is null on the last page.
class CursorPage<T> {
  const CursorPage({required this.items, this.nextCursor});

  factory CursorPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> item) parse,
  ) =>
      CursorPage(
        items: (json['items'] as List<dynamic>).map((e) => parse(e as Map<String, dynamic>)).toList(),
        nextCursor: json['nextCursor'] as String?,
      );

  final List<T> items;
  final String? nextCursor;
}
