import '../../models/search_results.dart';
import '../search_repository.dart';
import 'api_client.dart';

/// Search over HTTP (`docs/api-contract.md` B5).
///
/// TODO(guide 06): the route does not exist in the backend yet; run the app with `FAKE_SEARCH` until it does.
class HttpSearchRepository implements SearchRepository {
  HttpSearchRepository(this._api);

  final ApiClient _api;

  @override
  Future<SearchResults> search(String query, {SearchType type = SearchType.all, int? limit}) async {
    final response = await _api.get(
      '/search',
      query: {'q': query.trim(), 'type': type.wireName, 'limit': limit?.toString()},
    );
    if (response.status == 200) return SearchResults.fromJson(response.object);
    throw response.failure();
  }
}
