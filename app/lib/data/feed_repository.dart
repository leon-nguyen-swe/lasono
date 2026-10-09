import '../models/track_page.dart';

/// Lists built from several kinds of data: the feed and the tracks a user liked (Phase 6 of the backend).
abstract class FeedRepository {
  /// New tracks of the people the logged-in user follows, newest first. Needs a login.
  Future<TrackPage> feed({String? cursor, int? limit});

  /// The tracks [userId] liked, the most recently liked first. Only the ones the viewer may see.
  Future<TrackPage> likedTracks(String userId, {String? cursor, int? limit});
}
