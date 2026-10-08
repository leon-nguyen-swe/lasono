import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/data/http/api_client.dart';
import 'package:lasono_app/data/http/http_feed_repository.dart';
import 'package:lasono_app/data/http/http_search_repository.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/models/search_results.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _track = {
  'id': 't1',
  'ownerId': 'u1',
  'title': 'Sơn Tùng M-TP',
  'description': '',
  'visibility': 'PUBLIC',
  'status': 'READY',
  'durationSeconds': 200.0,
  'createdAt': '2026-10-08T12:34:56Z',
  'likeCount': 2,
  'commentCount': 1,
  'isLikedByMe': true,
};

(ApiClient, List<http.Request>) _api(http.Response Function(http.Request) answer) {
  final calls = <http.Request>[];
  return (
    ApiClient(
      baseUrl: 'http://api.test',
      client: MockClient((r) async {
        calls.add(r);
        return answer(r);
      }),
    ),
    calls,
  );
}

void main() {
  group('feed', () {
    test('asks for /feed and reads the tracks with their social fields', () async {
      final (api, calls) = _api((r) => _json({'items': [_track], 'nextCursor': 'n'}));

      final page = await HttpFeedRepository(api).feed(cursor: 'c', limit: 10);

      expect(calls.single.url.path, '/api/v1/feed');
      expect(calls.single.url.queryParameters, {'cursor': 'c', 'limit': '10'});
      expect(page.items.single.isLikedByMe, isTrue);
      expect(page.items.single.likeCount, 2);
      expect(page.nextCursor, 'n');
    });

    test('an empty feed is a page with no items, not an error', () async {
      final (api, _) = _api((r) => _json({'items': [], 'nextCursor': null}));
      final page = await HttpFeedRepository(api).feed();
      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
    });

    test('without a login the feed asks to log in', () async {
      final (api, _) = _api((r) => _json({}, 401));
      await expectLater(
        HttpFeedRepository(api).feed(),
        throwsA(isA<RepositoryException>().having((e) => e.needsLogin, 'needsLogin', isTrue)),
      );
    });

    test('a bad cursor is an "invalid" error with the reason', () async {
      final (api, _) = _api((r) => _json({'detail': 'Invalid cursor'}, 400));
      await expectLater(
        HttpFeedRepository(api).feed(cursor: 'abc'),
        throwsA(isA<RepositoryException>().having((e) => e.message, 'message', 'Invalid cursor')),
      );
    });
  });

  group('liked tracks', () {
    test('GET /users/{id}/likes gives a page of tracks', () async {
      final (api, calls) = _api((r) => _json({'items': [_track], 'nextCursor': null}));

      final page = await HttpFeedRepository(api).likedTracks('u9', limit: 5);

      expect(calls.single.url.path, '/api/v1/users/u9/likes');
      expect(calls.single.url.queryParameters, {'limit': '5'});
      expect(page.items.single.id, 't1');
    });

    test('an unknown user is "User not found"', () async {
      final (api, _) = _api((r) => _json({}, 404));
      await expectLater(
        HttpFeedRepository(api).likedTracks('x'),
        throwsA(isA<RepositoryException>().having((e) => e.message, 'message', 'User not found')),
      );
    });
  });

  group('search', () {
    test('sends the trimmed text, the type and the limit', () async {
      final (api, calls) = _api((r) => _json({'tracks': [], 'users': []}));

      await HttpSearchRepository(api).search('  son tung ', type: SearchType.users, limit: 10);

      expect(calls.single.url.path, '/api/v1/search');
      expect(calls.single.url.queryParameters, {'q': 'son tung', 'type': 'users', 'limit': '10'});
    });

    test('Vietnamese text goes through the address and the answer unharmed', () async {
      final (api, calls) = _api(
        (r) => _json({
          'tracks': [_track],
          'users': [
            {'userId': 'u1', 'displayName': 'Sơn Tùng', 'followerCount': 120, 'isFollowedByMe': false},
          ],
        }),
      );

      final results = await HttpSearchRepository(api).search('Sơn Tùng');

      expect(calls.single.url.queryParameters['q'], 'Sơn Tùng');
      expect(results.tracks.single.title, 'Sơn Tùng M-TP');
      expect(results.users.single.displayName, 'Sơn Tùng');
      expect(results.users.single.followerCount, 120);
    });

    test('the type defaults to all and the limit is left out', () async {
      final (api, calls) = _api((r) => _json({}));
      await HttpSearchRepository(api).search('abc');
      expect(calls.single.url.queryParameters, {'q': 'abc', 'type': 'all'});
    });

    test('a query the server refuses is an "invalid" error', () async {
      final (api, _) = _api((r) => _json({'detail': 'q must have 2 to 100 characters'}, 400));
      await expectLater(
        HttpSearchRepository(api).search('a'),
        throwsA(isA<RepositoryException>()
            .having((e) => e.kind, 'kind', RepositoryErrorKind.invalid)
            .having((e) => e.message, 'message', 'q must have 2 to 100 characters')),
      );
    });
  });
}
