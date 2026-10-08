/// Why a repository call failed, in the terms a screen cares about.
enum RepositoryErrorKind {
  /// The server could not be reached, or did not answer in time.
  network,

  /// Not logged in, or the login ran out (HTTP 401).
  unauthorized,

  /// The user may see it but may not do this (HTTP 403).
  forbidden,

  /// There is no such thing, or the user may not know that there is (HTTP 404).
  notFound,

  /// The thing is in the wrong state for this, for example a track that is still processing (HTTP 409).
  conflict,

  /// The request itself is wrong, and the server says why (HTTP 400, 413, 415).
  invalid,

  /// The server failed (HTTP 5xx).
  server,

  other,
}

/// What every repository throws. Screens catch this one type and decide what to show from [kind]; [message]
/// is a sentence for the user or, for [RepositoryErrorKind.invalid], the reason the server gave.
class RepositoryException implements Exception {
  const RepositoryException(this.message, {this.kind = RepositoryErrorKind.other});

  final String message;
  final RepositoryErrorKind kind;

  /// True when logging in again (or for the first time) would help.
  bool get needsLogin => kind == RepositoryErrorKind.unauthorized;

  @override
  String toString() => message;
}
