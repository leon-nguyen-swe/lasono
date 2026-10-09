import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/api/access_tokens.dart';
import 'package:lasono_app/api/profile_api.dart';
import 'package:lasono_app/data/http/api_client.dart';
import 'package:lasono_app/data/http/http_user_repository.dart';
import 'package:lasono_app/data/repository_exception.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

class _Tokens implements AccessTokens {
  _Tokens(this.accessToken);

  @override
  String? accessToken;

  @override
  Future<String?> refreshAccessToken() async => null;
}

Map<String, dynamic> _profile(String id, {bool followed = false}) =>
    {'userId': id, 'displayName': 'User $id', 'followerCount': 1, 'followingCount': 2, 'isFollowedByMe': followed};

class _Fixture {
  _Fixture(http.Response Function(http.Request) answer, {AccessTokens? auth}) {
    final client = MockClient((r) async {
      calls.add(r);
      return answer(r);
    });
    final api = ApiClient(baseUrl: 'http://api.test', client: client, auth: auth);
    repo = HttpUserRepository(api, profileApi: ProfileApi(baseUrl: 'http://api.test', client: client, auth: auth));
  }

  final calls = <http.Request>[];
  late final HttpUserRepository repo;
}

void main() {
  group('getProfile', () {
    test('reads the profile with the counts and sends the login, so isFollowedByMe is about the viewer', () async {
      final f = _Fixture((r) => _json(_profile('u1', followed: true)), auth: _Tokens('tok'));

      final profile = await f.repo.getProfile('u1');

      expect(f.calls.single.url.path, '/api/v1/users/u1');
      expect(f.calls.single.headers['authorization'], 'Bearer tok');
      expect(profile.isFollowedByMe, isTrue);
      expect(profile.followerCount, 1);
    });

    test('works when nobody is logged in', () async {
      final f = _Fixture((r) => _json(_profile('u1')));
      expect((await f.repo.getProfile('u1')).displayName, 'User u1');
      expect(f.calls.single.headers.containsKey('authorization'), isFalse);
    });

    test('when the server refuses a login that cannot be renewed, reads the public profile without it', () async {
      final f = _Fixture(
        (r) => r.headers.containsKey('authorization') ? _json({}, 401) : _json(_profile('u1')),
        auth: _Tokens('expired'),
      );

      final profile = await f.repo.getProfile('u1');

      expect(profile.userId, 'u1');
      expect(f.calls.length, 2);
      expect(f.calls.last.headers.containsKey('authorization'), isFalse);
    });

    test('an unknown user is "User not found"', () async {
      final f = _Fixture((r) => _json({}, 404));
      await expectLater(
        f.repo.getProfile('x'),
        throwsA(isA<RepositoryException>()
            .having((e) => e.kind, 'kind', RepositoryErrorKind.notFound)
            .having((e) => e.message, 'message', 'User not found')),
      );
    });
  });

  group('getProfiles with the batch route', () {
    test('asks for the ids at once and reads the items', () async {
      final f = _Fixture((r) => _json({'items': [_profile('a'), _profile('b')]}));

      final profiles = await f.repo.getProfiles(['a', 'b']);

      expect(f.calls.single.url.path, '/api/v1/users');
      expect(f.calls.single.url.queryParameters['ids'], 'a,b');
      expect(profiles.map((p) => p.userId), ['a', 'b']);
    });

    test('asks nothing for no ids and once for an id given twice', () async {
      final f = _Fixture((r) => _json({'items': [_profile('a')]}));

      expect(await f.repo.getProfiles(const []), isEmpty);
      expect(f.calls, isEmpty);

      await f.repo.getProfiles(['a', 'a', 'a']);
      expect(f.calls.single.url.queryParameters['ids'], 'a');
    });

    test('120 ids are asked for in three requests of at most 50', () async {
      final ids = [for (var i = 0; i < 120; i++) 'u$i'];
      final f = _Fixture((r) {
        final asked = r.url.queryParameters['ids']!.split(',');
        return _json({'items': [for (final id in asked) _profile(id)]});
      });

      final profiles = await f.repo.getProfiles(ids);

      expect(f.calls.length, 3);
      expect(f.calls.map((c) => c.url.queryParameters['ids']!.split(',').length), [50, 50, 20]);
      expect(profiles.length, 120);
    });

    test('a server error is not hidden by the fall back', () async {
      final f = _Fixture((r) => _json({}, 500));
      await expectLater(
        f.repo.getProfiles(['a']),
        throwsA(isA<RepositoryException>().having((e) => e.kind, 'kind', RepositoryErrorKind.server)),
      );
    });
  });

  group('getProfiles before the backend has the batch route', () {
    // Until guide 03 is done, GET /users?ids= is not a route: the server answers 404 (or 401 without a login).
    http.Response oneByOne(http.Request r) {
      if (r.url.path == '/api/v1/users') return _json({}, 404);
      final id = r.url.pathSegments.last;
      return id == 'ghost' ? _json({}, 404) : _json(_profile(id));
    }

    test('falls back to one request per user and skips the ones nobody has', () async {
      final f = _Fixture(oneByOne);

      final profiles = await f.repo.getProfiles(['a', 'ghost', 'b']);

      expect(profiles.map((p) => p.userId).toSet(), {'a', 'b'});
      expect(f.calls.where((c) => c.url.path.startsWith('/api/v1/users/')).length, 3);
    });

    test('remembers that the route is missing and does not ask for it again', () async {
      final f = _Fixture(oneByOne);

      await f.repo.getProfiles(['a']);
      f.calls.clear();
      await f.repo.getProfiles(['b']);

      expect(f.calls.single.url.path, '/api/v1/users/b');
    });

    test('also falls back on 401, which is what the batch route gives without a login today', () async {
      final f = _Fixture((r) => r.url.path == '/api/v1/users' ? _json({}, 401) : _json(_profile(r.url.pathSegments.last)));
      expect((await f.repo.getProfiles(['a'])).single.userId, 'a');
    });
  });

  test('changing the display name goes through the Phase 4 profile API', () async {
    final f = _Fixture(
      (r) => _json({'userId': 'u1', 'email': 'a@x.com', 'displayName': 'Alice B.'}),
      auth: _Tokens('tok'),
    );

    final account = await f.repo.changeDisplayName('Alice B.');

    expect(f.calls.single.method, 'PATCH');
    expect(f.calls.single.url.path, '/api/v1/users/me');
    expect(account.displayName, 'Alice B.');
  });
}
