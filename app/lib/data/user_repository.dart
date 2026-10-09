import '../api/auth_api.dart';
import '../api/profile_api.dart';

/// Users: what anyone may know about them, and the logged-in user's own name.
abstract class UserRepository {
  Future<Profile> getProfile(String userId);

  /// Profiles of several users in as few requests as possible. A user nobody has is left out of the answer
  /// (no error), and the order of the answer is not the order of [userIds].
  Future<List<Profile>> getProfiles(Iterable<String> userIds);

  /// Changes the display name of the logged-in user.
  Future<Account> changeDisplayName(String displayName);
}
