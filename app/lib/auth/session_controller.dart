import 'package:flutter/foundation.dart';

import '../api/access_tokens.dart';
import '../api/auth_api.dart';

enum SessionStatus { restoring, signedOut, signedIn }

/// Who is signed in. The access token lives only in memory, so a script on the
/// page cannot read it from storage; a reload gets it back from the refresh
/// cookie (see [restore]).
class SessionController extends ChangeNotifier implements AccessTokens {
  SessionController(this._api);

  final AuthApi _api;

  SessionStatus _status = SessionStatus.restoring;
  Account? _account;
  String? _accessToken;

  // Bumped each time the user signs in or out, so an answer that arrives for
  // an older session is thrown away instead of signing the user in again.
  int _generation = 0;
  Future<String?>? _refreshing;

  SessionStatus get status => _status;
  Account? get account => _account;

  @override
  String? get accessToken => _accessToken;

  /// Looks for a session when the app opens, using the refresh cookie. It never
  /// throws: no session, or a server that does not answer, both mean "signed out".
  Future<void> restore() async {
    final generation = _generation;
    try {
      final tokens = await _api.refresh();
      if (tokens != null && generation == _generation) {
        await _signIn(tokens);
        return;
      }
    } on AuthApiException {
      // Not reachable: show the signed-out app; the user can try again.
    }
    if (generation == _generation) _signOut();
  }

  Future<void> login({required String email, required String password}) async {
    await _signIn(await _api.login(email: email, password: password));
  }

  Future<void> register({
    required String email,
    required String displayName,
    required String password,
  }) async {
    await _api.register(
      email: email,
      displayName: displayName,
      password: password,
    );
    await login(email: email, password: password);
  }

  /// The account was changed on the server (for example the display name), so
  /// the one shown is replaced. Nothing happens when nobody is logged in, or
  /// when it is another user's account.
  void accountChanged(Account account) {
    if (_status != SessionStatus.signedIn || account.userId != _account?.userId) {
      return;
    }
    _account = account;
    notifyListeners();
  }

  Future<void> logout() async {
    _signOut();
    await _api.logout();
  }

  /// Many requests can be refused at once when the token runs out. The backend
  /// rotates the refresh token, so a second refresh with the old cookie looks
  /// like a stolen token and ends the session. Everyone who asks while one
  /// refresh is running therefore waits for that same one.
  @override
  Future<String?> refreshAccessToken() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _refresh() async {
    final generation = _generation;
    final AuthTokens? tokens;
    try {
      tokens = await _api.refresh();
    } on AuthApiException {
      return null;
    }
    if (generation != _generation) return null;
    if (tokens == null) {
      _signOut();
      return null;
    }
    _accessToken = tokens.accessToken;
    notifyListeners();
    return _accessToken;
  }

  Future<void> _signIn(AuthTokens tokens) async {
    final account = await _api.currentUser(tokens.accessToken);
    _generation++;
    _accessToken = tokens.accessToken;
    _account = account;
    _status = SessionStatus.signedIn;
    notifyListeners();
  }

  void _signOut() {
    _generation++;
    _accessToken = null;
    _account = null;
    _status = SessionStatus.signedOut;
    notifyListeners();
  }
}
