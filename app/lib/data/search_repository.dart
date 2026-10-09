import '../models/search_results.dart';

/// Search over tracks and users (Phase 6 of the backend).
abstract class SearchRepository {
  /// Finds tracks by title and users by name, ignoring accents and case (`son tung` finds `Sơn Tùng`).
  /// A query shorter than 2 characters is refused (`invalid`). There is no paging: the best [limit] of each kind.
  Future<SearchResults> search(String query, {SearchType type = SearchType.all, int? limit});
}
