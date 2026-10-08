/// Where the API clients get the access token of the signed-in user.
abstract class AccessTokens {
  /// The token to send now, or null when nobody is signed in.
  String? get accessToken;

  /// Gets a new token after the server refused the current one, and returns it.
  /// Null means there is none: the session is over, or the server is not reachable.
  Future<String?> refreshAccessToken();
}
