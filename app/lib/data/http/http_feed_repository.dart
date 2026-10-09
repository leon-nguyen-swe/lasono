import '../../models/track_page.dart';
import '../feed_repository.dart';
import 'api_client.dart';

/// The feed and the tracks a user liked, over HTTP (`docs/api-contract.md` B1 and B4).
///
/// TODO(guide 05): neither route exists in the backend yet; run the app with `FAKE_FEED` until it does.
class HttpFeedRepository implements FeedRepository {
  HttpFeedRepository(this._api);

  final ApiClient _api;

  @override
  Future<TrackPage> feed({String? cursor, int? limit}) async {
    final response = await _api.get('/feed', query: {'cursor': cursor, 'limit': limit?.toString()});
    if (response.status == 200) return TrackPage.fromJson(response.object);
    throw response.failure();
  }

  @override
  Future<TrackPage> likedTracks(String userId, {String? cursor, int? limit}) async {
    final response = await _api.get(
      '/users/${Uri.encodeComponent(userId)}/likes',
      query: {'cursor': cursor, 'limit': limit?.toString()},
    );
    if (response.status == 200) return TrackPage.fromJson(response.object);
    throw response.failure(messages: const {404: 'User not found'});
  }
}
