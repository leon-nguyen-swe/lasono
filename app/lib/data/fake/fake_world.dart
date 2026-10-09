import 'dart:math';

import '../../api/profile_api.dart';
import '../../models/comment.dart';
import '../../models/track.dart';

class FakeUser {
  const FakeUser({required this.id, required this.displayName, required this.baseFollowers});

  final String id;
  final String displayName;

  /// Followers this user has besides the ones in the fake follow graph, so the numbers look like a real service.
  final int baseFollowers;
}

/// The data behind the fake repositories: a small made-up service with 8 users and 30 tracks, and the state that
/// changes while the app runs (who liked what, who follows whom, the comments).
///
/// Everything is made from fixed numbers, so two runs (and the tests) see the same world. Its ids all start with
/// [idPrefix], so any id can be told apart from a real one with [isFake]; that is how the app keeps fake and real
/// data side by side.
class FakeWorld {
  /// [newViewerFollowsSome]: a logged-in person starts out following [viewerStartsFollowing] (handy for tests and for
  /// seeing a full feed). The app turns it off, because a new account on the real backend follows nobody.
  FakeWorld({DateTime Function()? clock, this.newViewerFollowsSome = true}) : _clock = clock ?? (() => DateTime.now().toUtc()) {
    _seed();
  }

  final bool newViewerFollowsSome;

  static const idPrefix = 'f4e00000-';

  static bool isFake(String id) => id.startsWith(idPrefix);

  static String userId(int n) => 'f4e00000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
  static String trackId(int n) => 'f4e00000-0000-4000-9000-${n.toString().padLeft(12, '0')}';
  static String _commentId(int n) => 'f4e00000-0000-4000-a000-${n.toString().padLeft(12, '0')}';

  final DateTime Function() _clock;

  DateTime now() => _clock();

  late final List<FakeUser> users;

  /// Newest first.
  late final List<Track> tracks;

  final Map<String, int> _baseLikes = {};

  // trackId -> the users who liked it
  final Map<String, Set<String>> _likers = {};
  // userId -> the tracks they liked, oldest first (the last one is the most recent)
  final Map<String, List<String>> _likeLog = {};
  // trackId -> comments, in the order they were made
  final Map<String, List<Comment>> _comments = {};
  // followerId -> {followeeId: when}
  final Map<String, Map<String, DateTime>> _follows = {};
  final Set<String> _viewersSeen = {};
  int _commentCounter = 0;

  /// The users a logged-in person follows the first time the fake world sees them, so the feed is not empty.
  /// (One user, Minh Anh, follows nobody, to see that case.)
  static const viewerStartsFollowing = [0, 1, 5];

  static const _owners = <(int, List<String>)>[
    (0, ['Nắng ấm xa dần', 'Lạc trôi', 'Hãy trao cho anh', 'Em của ngày hôm qua']),
    (1, ['Đi về nhà', 'Lối nhỏ', 'Bài này chill phết', 'Mang tiền về cho mẹ']),
    (2, ['Bùa yêu', 'Đi đu đưa đi', 'Bao giờ lấy chồng']),
    (3, ['Tháng Tư là lời nói dối của em', 'Nếu những tháng ngày ấy', 'Người ở lại']),
    (4, ['Sài Gòn hôm nay mưa', 'Mùa hè của em', 'Hạ trắng', 'Bản tình ca cuối']),
    (5, ['Midnight Drive', 'Neon Rain', 'Lo-fi for Rainy Days', 'Sunrise Over Hanoi']),
    (6, ['Tokyo Nights', 'Cherry Blossom Beat', 'Skyline', 'Gió']),
    (7, ['Coffee Shop Jazz', 'Paper Planes', 'Acoustic Sunday', 'Piano Dreams']),
  ];

  static const _commentTexts = [
    'Đoạn này hay quá!',
    'Nghe đi nghe lại mãi không chán',
    'Beat drop chỗ này đỉnh thật',
    'Love this part ❤️',
    'Giọng hát nghe thích quá',
    'Ai đang nghe lúc nửa đêm giống mình không?',
    'This one hits different',
    'Cho mình xin tên bài nhạc nền được không?',
    'Hay lắm bạn ơi, cố lên!',
    'Đoạn guitar này mê quá',
    'Replay lần thứ 10 rồi 😅',
    'Chill cực kỳ',
  ];

  void _seed() {
    final base = _clock();
    users = const [
      ('Sơn Tùng', 1280),
      ('Đen Vâu', 2415),
      ('Bích Phương', 960),
      ('Hà Anh Tuấn', 1830),
      ('Minh Anh', 42),
      ('Luna Park', 318),
      ('DJ Kaito', 207),
      ('Maya Chen', 129),
    ].indexed.map((e) => FakeUser(id: userId(e.$1 + 1), displayName: e.$2.$1, baseFollowers: e.$2.$2)).toList();

    // Take one track of each owner in turn, so neighbours in the list have different authors.
    final queues = [for (final (owner, titles) in _owners) (owner, [...titles])];
    final ordered = <(int, String)>[];
    while (queues.any((q) => q.$2.isNotEmpty)) {
      for (final queue in queues) {
        if (queue.$2.isNotEmpty) ordered.add((queue.$1, queue.$2.removeAt(0)));
      }
    }

    final built = <Track>[];
    for (final (i, (ownerIndex, title)) in ordered.indexed) {
      final id = trackId(i + 1);
      final owner = users[ownerIndex];
      final status = switch (title) { 'Hạ trắng' => 'PROCESSING', 'Bản tình ca cuối' => 'FAILED', _ => 'READY' };
      final ready = status == 'READY';
      final seconds = 45 + (i * 13) % 46;
      final createdAt = base.subtract(Duration(minutes: 25 + i * i * 37));

      _baseLikes[id] = ready ? (i * 7 + 3) % 120 : 0;
      final comments = ready ? _seedComments(i, id, seconds * 1000, createdAt) : <Comment>[];
      _comments[id] = comments;
      built.add(Track(
        id: id,
        title: title,
        description: i % 3 == 0 ? 'Một bản thu thử, nghe cho vui.' : '',
        status: status,
        ownerId: owner.id,
        mimeType: ready ? 'audio/mpeg' : null,
        durationSeconds: ready ? seconds.toDouble() : null,
        waveform: ready ? _waveform(i) : null,
        createdAt: createdAt,
        likeCount: _baseLikes[id]!,
        commentCount: comments.length,
      ));
    }
    tracks = List.unmodifiable(built);

    // Who follows whom among the fake users. Minh Anh (index 4) follows nobody.
    const graph = {0: [1], 1: [0, 5], 2: [0], 3: [1, 2], 5: [0, 6], 6: [5, 7], 7: [0, 5, 6]};
    graph.forEach((follower, followees) {
      for (final (n, followee) in followees.indexed) {
        _follows.putIfAbsent(users[follower].id, () => {})[users[followee].id] =
            base.subtract(Duration(days: 3 + follower + n));
      }
    });
  }

  List<Comment> _seedComments(int trackIndex, String trackId, int durationMs, DateTime createdAt) {
    final count = (trackIndex * 5) % 11;
    return [
      for (var j = 0; j < count; j++)
        Comment(
          id: _commentId(++_commentCounter),
          trackId: trackId,
          authorId: users[(trackIndex + j * 3 + 1) % users.length].id,
          positionMs: (durationMs * ((j * 37 + trackIndex * 11) % 100) / 100).round(),
          text: _commentTexts[(trackIndex + j) % _commentTexts.length],
          createdAt: createdAt.add(Duration(minutes: 10 + j * 47)),
        ),
    ];
  }

  // 200 peaks that rise and fall like a song: a slow swell plus some roughness, the same for the same seed.
  static List<double> _waveform(int seed) {
    final random = Random(seed + 1);
    return [
      for (var i = 0; i < 200; i++)
        (0.18 + 0.55 * (0.5 + 0.5 * sin(i * 0.09 + seed)) * (0.6 + 0.4 * random.nextDouble()) + 0.2 * random.nextDouble())
            .clamp(0.05, 1.0),
    ];
  }

  // -- users and tracks ---------------------------------------------------------------------------------------

  FakeUser? user(String id) {
    for (final user in users) {
      if (user.id == id) return user;
    }
    return null;
  }

  Track? track(String id) {
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  // -- the viewer ---------------------------------------------------------------------------------------------

  /// Call with the id of the logged-in user before reading or changing anything for them. The first time, they
  /// start out following [viewerStartsFollowing].
  void ensureViewer(String? viewerId) {
    if (viewerId == null || isFake(viewerId) || !_viewersSeen.add(viewerId)) return;
    if (!newViewerFollowsSome) return;
    final start = _clock();
    for (final (n, index) in viewerStartsFollowing.indexed) {
      _follows.putIfAbsent(viewerId, () => {})[users[index].id] = start.subtract(Duration(days: 2 + n));
    }
  }

  // -- follows ------------------------------------------------------------------------------------------------

  /// People who follow [userId], newest first.
  List<MapEntry<String, DateTime>> followersOf(String userId) {
    final found = <MapEntry<String, DateTime>>[];
    _follows.forEach((follower, followees) {
      final since = followees[userId];
      if (since != null) found.add(MapEntry(follower, since));
    });
    return found..sort((a, b) => b.value.compareTo(a.value));
  }

  /// People [userId] follows, newest first.
  List<MapEntry<String, DateTime>> followingOf(String userId) =>
      (_follows[userId]?.entries.toList() ?? [])..sort((a, b) => b.value.compareTo(a.value));

  int followerCountOf(String userId) => (user(userId)?.baseFollowers ?? 0) + followersOf(userId).length;

  int followingCountOf(String userId) => _follows[userId]?.length ?? 0;

  bool isFollowing(String? viewerId, String userId) =>
      viewerId != null && viewerId != userId && (_follows[viewerId]?.containsKey(userId) ?? false);

  /// True when the follow is new, false when it was there already.
  bool follow(String viewerId, String userId) {
    final followees = _follows.putIfAbsent(viewerId, () => {});
    if (followees.containsKey(userId)) return false;
    followees[userId] = _clock();
    return true;
  }

  bool unfollow(String viewerId, String userId) => _follows[viewerId]?.remove(userId) != null;

  Profile profileOf(FakeUser user, {String? viewerId}) => Profile(
        userId: user.id,
        displayName: user.displayName,
        followerCount: followerCountOf(user.id),
        followingCount: followingCountOf(user.id),
        isFollowedByMe: isFollowing(viewerId, user.id),
      );

  // -- likes --------------------------------------------------------------------------------------------------

  int likeCountOf(String trackId) => (_baseLikes[trackId] ?? 0) + (_likers[trackId]?.length ?? 0);

  bool isLiked(String? viewerId, String trackId) => viewerId != null && (_likers[trackId]?.contains(viewerId) ?? false);

  /// True when the like is new.
  bool like(String viewerId, String trackId) {
    if (!_likers.putIfAbsent(trackId, () => {}).add(viewerId)) return false;
    _likeLog.putIfAbsent(viewerId, () => []).add(trackId);
    return true;
  }

  /// True when a like was removed.
  bool unlike(String viewerId, String trackId) {
    final removed = _likers[trackId]?.remove(viewerId) ?? false;
    if (removed) _likeLog[viewerId]?.remove(trackId);
    return removed;
  }

  /// The ids of the tracks [userId] liked, the most recently liked first.
  List<String> likedBy(String userId) => (_likeLog[userId] ?? const <String>[]).reversed.toList();

  // -- comments -----------------------------------------------------------------------------------------------

  List<Comment> commentsOf(String trackId) => List.unmodifiable(_comments[trackId] ?? const <Comment>[]);

  int commentCountOf(String trackId) => _comments[trackId]?.length ?? 0;

  Comment addComment(String trackId, String authorId, int positionMs, String text) {
    final comment = Comment(
      id: _commentId(++_commentCounter),
      trackId: trackId,
      authorId: authorId,
      positionMs: positionMs,
      text: text,
      createdAt: _clock(),
    );
    _comments.putIfAbsent(trackId, () => []).add(comment);
    return comment;
  }

  Comment? comment(String trackId, String commentId) {
    for (final comment in _comments[trackId] ?? const <Comment>[]) {
      if (comment.id == commentId) return comment;
    }
    return null;
  }

  bool removeComment(String trackId, String commentId) {
    final list = _comments[trackId];
    if (list == null) return false;
    final before = list.length;
    list.removeWhere((c) => c.id == commentId);
    return list.length < before;
  }

  // -- putting the state on a track ---------------------------------------------------------------------------

  /// [track] with the fake likes and comments on it: the counts, and whether [viewerId] liked it. Each part is
  /// applied only when asked, so a screen can have fake likes and real comments.
  Track withSocial(Track track, {String? viewerId, bool likes = true, bool comments = true}) => track.copyWith(
        likeCount: likes ? likeCountOf(track.id) : null,
        isLikedByMe: likes ? isLiked(viewerId, track.id) : null,
        commentCount: comments ? commentCountOf(track.id) : null,
      );
}
