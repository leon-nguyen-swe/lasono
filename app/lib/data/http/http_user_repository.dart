import '../../api/auth_api.dart';
import '../../api/profile_api.dart';
import '../repository_exception.dart';
import '../user_repository.dart';
import 'api_client.dart';

/// Users over HTTP.
///
/// A profile is read **with** the login when there is one, because `isFollowedByMe` depends on who asks. (The
/// Phase 4 `ProfileApi.getProfile` sends none; that is why it is not used here.) If the server refuses the
/// login on this public route and it cannot be renewed, the profile is read once more without it.
class HttpUserRepository implements UserRepository {
  HttpUserRepository(this._api, {required this._profileApi});

  /// The most ids the batch route takes (api-contract.md B2).
  static const batchLimit = 50;

  final ApiClient _api;
  final ProfileApi _profileApi;

  // TODO(guide 03): GET /users?ids= does not exist until the follows guide is done. Until then every batch
  // falls back to one request per user, and this flag stops asking again.
  bool _batchAvailable = true;

  @override
  Future<Profile> getProfile(String userId) async {
    final path = '/users/${Uri.encodeComponent(userId)}';
    var response = await _api.get(path);
    if (response.status == 401) response = await _api.get(path, withLogin: false);
    if (response.status == 200) return Profile.fromJson(response.object);
    throw response.failure(messages: const {404: 'User not found'});
  }

  @override
  Future<List<Profile>> getProfiles(Iterable<String> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return const [];

    final profiles = <Profile>[];
    for (var start = 0; start < ids.length; start += batchLimit) {
      final chunk = ids.sublist(start, (start + batchLimit).clamp(0, ids.length));
      profiles.addAll(await _chunk(chunk));
    }
    return profiles;
  }

  Future<List<Profile>> _chunk(List<String> ids) async {
    if (_batchAvailable) {
      final response = await _api.get('/users', query: {'ids': ids.join(',')});
      if (response.status == 200) {
        final items = response.object['items'] as List<dynamic>? ?? const [];
        return [for (final item in items) Profile.fromJson(item as Map<String, dynamic>)];
      }
      // Not there yet (nothing answers this route), or refused: ask one by one, and remember it.
      if (const {401, 403, 404, 405}.contains(response.status)) {
        _batchAvailable = false;
      } else {
        throw response.failure();
      }
    }
    final found = await Future.wait(ids.map(_orNull));
    return [for (final profile in found) ?profile];
  }

  Future<Profile?> _orNull(String id) async {
    try {
      return await getProfile(id);
    } on RepositoryException catch (e) {
      if (e.kind == RepositoryErrorKind.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<Account> changeDisplayName(String displayName) => _profileApi.changeDisplayName(displayName);
}
