import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/api/auth_api.dart';
import 'package:lasono_app/api/profile_api.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/data/user_directory.dart';
import 'package:lasono_app/data/user_repository.dart';

/// A user repository that knows a few users, counts how it was asked, and can be told to wait or to fail.
class _Users implements UserRepository {
  _Users(Iterable<String> ids) : known = {for (final id in ids) id: Profile(userId: id, displayName: 'User $id')};

  final Map<String, Profile> known;
  final List<List<String>> asked = [];
  Completer<void>? gate;
  Object? failure;

  @override
  Future<List<Profile>> getProfiles(Iterable<String> userIds) async {
    asked.add(userIds.toList());
    await gate?.future;
    if (failure != null) throw failure!;
    return [for (final id in userIds) ?known[id]];
  }

  @override
  Future<Profile> getProfile(String userId) => throw UnimplementedError();

  @override
  Future<Account> changeDisplayName(String displayName) => throw UnimplementedError();
}

void main() {
  test('asks for all the ids it does not have in one request', () async {
    final users = _Users(['a', 'b', 'c']);
    final directory = UserDirectory(users);

    final profiles = await directory.profiles(['a', 'b', 'c']);

    expect(users.asked, hasLength(1));
    expect(users.asked.single.toSet(), {'a', 'b', 'c'});
    expect(profiles.keys.toSet(), {'a', 'b', 'c'});
    expect(profiles['a']!.displayName, 'User a');
  });

  test('does not ask again for what it already knows', () async {
    final users = _Users(['a', 'b']);
    final directory = UserDirectory(users);

    await directory.profiles(['a']);
    await directory.profiles(['a', 'b']);
    await directory.profile('a');

    expect(users.asked, [
      ['a'],
      ['b'],
    ]);
  });

  test('two asks for the same id at the same moment make one request', () async {
    final users = _Users(['a']);
    users.gate = Completer<void>();
    final directory = UserDirectory(users);

    final first = directory.profile('a');
    final second = directory.profile('a');
    users.gate!.complete();

    expect((await first)!.userId, 'a');
    expect((await second)!.userId, 'a');
    expect(users.asked, hasLength(1));
  });

  test('overlapping asks send only the new ids, and both get everything they asked for', () async {
    final users = _Users(['a', 'b', 'c']);
    users.gate = Completer<void>();
    final directory = UserDirectory(users);

    final first = directory.profiles(['a', 'b']);
    final second = directory.profiles(['b', 'c']);
    users.gate!.complete();

    expect((await first).keys.toSet(), {'a', 'b'});
    expect((await second).keys.toSet(), {'b', 'c'});
    expect(users.asked.map((ids) => ids.toSet()), [
      {'a', 'b'},
      {'c'},
    ]);
  });

  test('a user nobody has is left out, and is not asked for again', () async {
    final users = _Users(['a']);
    final directory = UserDirectory(users);

    expect(await directory.profile('ghost'), isNull);
    expect(await directory.profile('ghost'), isNull);

    expect(users.asked, hasLength(1));
    expect((await directory.profiles(['a', 'ghost'])).keys, ['a']);
  });

  test('an empty id is never asked for, and no ids is no request', () async {
    final users = _Users(['a']);
    final directory = UserDirectory(users);

    expect(await directory.profiles(['']), isEmpty);
    expect(await directory.profiles(const []), isEmpty);
    expect(users.asked, isEmpty);
  });

  group('when the request fails', () {
    test('every caller gets the error, and nothing is remembered, so the next ask tries again', () async {
      final users = _Users(['a'])..failure = const RepositoryException('down', kind: RepositoryErrorKind.network);
      final directory = UserDirectory(users);

      await expectLater(directory.profile('a'), throwsA(isA<RepositoryException>()));
      expect(directory.cached('a'), isNull);

      users.failure = null;
      expect((await directory.profile('a'))!.userId, 'a');
      expect(users.asked, hasLength(2));
    });

    test('two callers waiting on the same failing request both get the error', () async {
      final users = _Users(['a'])
        ..failure = const RepositoryException('down', kind: RepositoryErrorKind.network)
        ..gate = Completer<void>();
      final directory = UserDirectory(users);

      final first = directory.profile('a');
      final second = directory.profile('a');
      users.gate!.complete();

      await expectLater(first, throwsA(isA<RepositoryException>()));
      await expectLater(second, throwsA(isA<RepositoryException>()));
      expect(users.asked, hasLength(1));
    });
  });

  group('what is known', () {
    test('can be read without asking, and nameOf gives a fallback until the profile has arrived', () async {
      final users = _Users(['a']);
      final directory = UserDirectory(users);
      expect(directory.cached('a'), isNull);
      expect(directory.nameOf('a', fallback: '…'), '…');

      await directory.profile('a');

      expect(directory.cached('a')!.displayName, 'User a');
      expect(directory.nameOf('a', fallback: '…'), 'User a');
    });

    test('put() replaces a profile and tells the listeners; arriving profiles tell them too', () async {
      final directory = UserDirectory(_Users(['a']));
      var notified = 0;
      directory.addListener(() => notified++);

      await directory.profile('a');
      expect(notified, 1);

      directory.put(const Profile(userId: 'a', displayName: 'Renamed', followerCount: 7));
      expect(notified, 2);
      expect(directory.cached('a')!.displayName, 'Renamed');
      expect(directory.cached('a')!.followerCount, 7);
    });

    test('put() also brings back a user that had been taken for missing', () async {
      final directory = UserDirectory(_Users([]));
      expect(await directory.profile('new'), isNull);

      directory.put(const Profile(userId: 'new', displayName: 'Mới'));

      expect((await directory.profile('new'))!.displayName, 'Mới');
    });

    test('invalidate forgets one user, clear forgets everybody', () async {
      final users = _Users(['a', 'b']);
      final directory = UserDirectory(users);
      await directory.profiles(['a', 'b']);

      directory.invalidate('a');
      expect(directory.cached('a'), isNull);
      expect(directory.cached('b'), isNotNull);

      await directory.profile('a');
      expect(users.asked.length, 2);

      directory.clear();
      expect(directory.cached('b'), isNull);
    });
  });
}
