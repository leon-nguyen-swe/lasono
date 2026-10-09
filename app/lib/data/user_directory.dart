import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/profile_api.dart';
import 'user_repository.dart';

/// The names of users, kept in memory.
///
/// A list of tracks, comments or followers holds only the ids of the users in it (the backend modules do not
/// know each other's data). Every card needs a name, so each asks this directory. It asks the repository for all the
/// ids it does not have yet **in one request**, never asks twice for the same id while the first answer is on
/// its way, and keeps what it learned, so scrolling a list does not ask again.
///
/// It is a [ChangeNotifier]: a widget that shows a name can listen, and redraws when the profile arrives or changes
/// (after a follow, a rename).
class UserDirectory extends ChangeNotifier {
  UserDirectory(this._users);

  final UserRepository _users;

  final Map<String, Profile> _known = {};
  final Set<String> _missing = {};
  final Map<String, Completer<Profile?>> _inFlight = {};

  /// What is known now, without asking. Null when the profile has not arrived (or there is none).
  Profile? cached(String userId) => _known[userId];

  /// A name to show right now: the display name if it is known, otherwise [fallback].
  String nameOf(String userId, {String fallback = ''}) => _known[userId]?.displayName ?? fallback;

  /// The profile of one user, or null when nobody has that id.
  Future<Profile?> profile(String userId) async => (await profiles([userId]))[userId];

  /// The profiles of [userIds], in one request for the ones not known yet. Ids nobody has are left out of the answer.
  Future<Map<String, Profile>> profiles(Iterable<String> userIds) async {
    final wanted = userIds.where((id) => id.isNotEmpty).toSet();

    final toAsk = <String>[
      for (final id in wanted)
        if (!_known.containsKey(id) && !_missing.contains(id) && !_inFlight.containsKey(id)) id,
    ];
    final waiting = <Future<Profile?>>[];
    if (toAsk.isNotEmpty) {
      final completers = {for (final id in toAsk) id: Completer<Profile?>()};
      _inFlight.addAll(completers);
      // Anybody who asks for these ids meanwhile waits on the same completers.
      for (final completer in completers.values) {
        // An error is reported to the caller below; this keeps a completer nobody waits for from being "unhandled".
        completer.future.then((_) {}, onError: (_) {});
      }
      unawaited(_load(toAsk, completers));
    }
    waiting.addAll([for (final id in wanted) ?_inFlight[id]?.future]);
    await Future.wait(waiting);

    return {for (final id in wanted) id: ?_known[id]};
  }

  Future<void> _load(List<String> ids, Map<String, Completer<Profile?>> completers) async {
    try {
      final found = await _users.getProfiles(ids);
      final byId = {for (final profile in found) profile.userId: profile};
      var changed = false;
      for (final id in ids) {
        final profile = byId[id];
        if (profile == null) {
          _missing.add(id);
        } else {
          _known[id] = profile;
          changed = true;
        }
        _inFlight.remove(id)?.complete(profile);
      }
      if (changed) notifyListeners();
    } catch (error, stack) {
      // Nothing is remembered about a failure, so the next ask tries again.
      for (final id in ids) {
        _inFlight.remove(id)?.completeError(error, stack);
      }
    }
  }

  /// Puts a profile that is known to be right (the answer to a follow, a rename) in place of the old one.
  void put(Profile profile) {
    _known[profile.userId] = profile;
    _missing.remove(profile.userId);
    notifyListeners();
  }

  /// Remembers profiles that came with another answer (the people a search found), so no card asks for them again.
  void cachedAll(Iterable<Profile> profiles) {
    var changed = false;
    for (final profile in profiles) {
      _known[profile.userId] = profile;
      _missing.remove(profile.userId);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Forgets one user, so the next ask goes to the repository.
  void invalidate(String userId) {
    _known.remove(userId);
    _missing.remove(userId);
  }

  /// Forgets everyone, for example when somebody else logs in (what is shown about "followed by me" is theirs).
  void clear() {
    _known.clear();
    _missing.clear();
    notifyListeners();
  }
}
