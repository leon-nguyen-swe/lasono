import 'package:http/http.dart' as http;

/// Where the API clients get the access token of the signed-in user.
abstract class AccessTokens {
  /// The token to send now, or null when nobody is signed in.
  String? get accessToken;

  /// Gets a new token after the server refused the current one, and returns it.
  /// Null means there is none: the session is over, or the server is not reachable.
  Future<String?> refreshAccessToken();
}

/// Sends a request with the access token of the logged-in user.
///
/// The server refuses a token that has run out, also on the routes anyone may
/// read. A new token is asked for once and the request is sent once more; a
/// second refusal is the answer. Without a token there is nothing to renew.
Future<http.Response> sendWithToken(
  AccessTokens? auth,
  Future<http.Response> Function(String? token) send,
) async {
  final token = auth?.accessToken;
  final response = await send(token);
  if (response.statusCode != 401 || auth == null || token == null) {
    return response;
  }
  final renewed = await auth.refreshAccessToken();
  return renewed == null ? response : send(renewed);
}
