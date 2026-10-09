import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/data/http/api_client.dart';
import 'package:lasono_app/data/http/http_social_repository.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/models/comment.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

class _Call {
  _Call(this.request);
  final http.Request request;
  String get method => request.method;
  String get path => request.url.path;
  Map<String, String> get query => request.url.queryParameters;
}

(HttpSocialRepository, List<_Call>) _repo(http.Response Function(http.Request) answer) {
  final calls = <_Call>[];
  final api = ApiClient(
    baseUrl: 'http://api.test',
    client: MockClient((r) async {
      calls.add(_Call(r));
      return answer(r);
    }),
  );
  return (HttpSocialRepository(api), calls);
}

Matcher _kind(RepositoryErrorKind kind, [String? message]) {
  var matcher = isA<RepositoryException>().having((e) => e.kind, 'kind', kind);
  if (message != null) matcher = matcher.having((e) => e.message, 'message', message);
  return throwsA(matcher);
}

void main() {
  group('likes', () {
    test('PUT /tracks/{id}/like gives the new state', () async {
      final (repo, calls) = _repo((r) => _json({'trackId': 't1', 'liked': true, 'likeCount': 13}));

      final state = await repo.likeTrack('t1');

      expect((calls.single.method, calls.single.path), ('PUT', '/api/v1/tracks/t1/like'));
      expect(state.liked, isTrue);
      expect(state.likeCount, 13);
    });

    test('DELETE /tracks/{id}/like gives the state without the like', () async {
      final (repo, calls) = _repo((r) => _json({'trackId': 't1', 'liked': false, 'likeCount': 12}));

      final state = await repo.unlikeTrack('t1');

      expect((calls.single.method, calls.single.path), ('DELETE', '/api/v1/tracks/t1/like'));
      expect(state.liked, isFalse);
    });

    test('an id is escaped in the path', () async {
      final (repo, calls) = _repo((r) => _json({'trackId': 'a/b', 'liked': true, 'likeCount': 1}));
      await repo.likeTrack('a/b');
      expect(calls.single.request.url.toString(), contains('/tracks/a%2Fb/like'));
    });

    test('without a login it asks to log in', () async {
      final (repo, _) = _repo((r) => _json({}, 401));
      await expectLater(repo.likeTrack('t1'), _kind(RepositoryErrorKind.unauthorized));
    });

    test('a track that is private to someone else (or missing) is "not found"', () async {
      final (repo, _) = _repo((r) => _json({}, 404));
      await expectLater(repo.likeTrack('t1'), _kind(RepositoryErrorKind.notFound, 'Track not found'));
    });

    test('a track that is not ready is a conflict with a clear message', () async {
      final (repo, _) = _repo((r) => _json({}, 409));
      await expectLater(repo.likeTrack('t1'), _kind(RepositoryErrorKind.conflict, 'This track is not ready yet'));
    });
  });

  group('follows', () {
    test('PUT /users/{id}/follow gives the new state', () async {
      final (repo, calls) = _repo((r) => _json({'userId': 'u2', 'following': true, 'followerCount': 6}));

      final state = await repo.followUser('u2');

      expect((calls.single.method, calls.single.path), ('PUT', '/api/v1/users/u2/follow'));
      expect((state.following, state.followerCount), (true, 6));
    });

    test('DELETE /users/{id}/follow', () async {
      final (repo, calls) = _repo((r) => _json({'userId': 'u2', 'following': false, 'followerCount': 5}));
      final state = await repo.unfollowUser('u2');
      expect(calls.single.method, 'DELETE');
      expect(state.following, isFalse);
    });

    test('following yourself is refused with the reason of the server', () async {
      final (repo, _) = _repo((r) => _json({'detail': 'You cannot follow yourself'}, 400));
      await expectLater(repo.followUser('me'), _kind(RepositoryErrorKind.invalid, 'You cannot follow yourself'));
    });

    test('an unknown user is "User not found"', () async {
      final (repo, _) = _repo((r) => _json({}, 404));
      await expectLater(repo.followUser('x'), _kind(RepositoryErrorKind.notFound, 'User not found'));
    });

    test('followers are listed with the cursor and the limit', () async {
      final (repo, calls) = _repo(
        (r) => _json({
          'items': [
            {'userId': 'u7', 'followedAt': '2026-10-01T08:00:00Z'},
          ],
          'nextCursor': 'next',
        }),
      );

      final page = await repo.followers('u1', cursor: 'abc', limit: 20);

      expect(calls.single.path, '/api/v1/users/u1/followers');
      expect(calls.single.query, {'cursor': 'abc', 'limit': '20'});
      expect(page.items.single.userId, 'u7');
      expect(page.nextCursor, 'next');
    });

    test('following uses its own path and sends no query when there is none', () async {
      final (repo, calls) = _repo((r) => _json({'items': [], 'nextCursor': null}));

      final page = await repo.following('u1');

      expect(calls.single.path, '/api/v1/users/u1/following');
      expect(calls.single.query, isEmpty);
      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
    });
  });

  group('comments', () {
    const commentJson = {
      'id': 'c1',
      'trackId': 't1',
      'authorId': 'u2',
      'positionMs': 83000,
      'text': 'Đoạn này hay quá!',
      'createdAt': '2026-10-08T12:40:00Z',
    };

    test('are listed by position unless asked otherwise', () async {
      final (repo, calls) = _repo((r) => _json({'items': [commentJson], 'nextCursor': null}));

      final page = await repo.comments('t1');

      expect(calls.single.path, '/api/v1/tracks/t1/comments');
      expect(calls.single.query, {'order': 'position'});
      expect(page.items.single.positionMs, 83000);
    });

    test('can be listed newest first, with a cursor and a limit', () async {
      final (repo, calls) = _repo((r) => _json({'items': [], 'nextCursor': null}));

      await repo.comments('t1', order: CommentOrder.recent, cursor: 'c', limit: 200);

      expect(calls.single.query, {'order': 'recent', 'cursor': 'c', 'limit': '200'});
    });

    test('a comment is posted as JSON and read back from the 201', () async {
      final (repo, calls) = _repo((r) => _json(commentJson, 201));

      final comment = await repo.postComment('t1', positionMs: 83000, text: 'Đoạn này hay quá!');

      expect((calls.single.method, calls.single.path), ('POST', '/api/v1/tracks/t1/comments'));
      expect(jsonDecode(calls.single.request.body), {'positionMs': 83000, 'text': 'Đoạn này hay quá!'});
      expect(comment.id, 'c1');
    });

    test('a position outside the track is refused with the reason of the server', () async {
      final (repo, _) = _repo((r) => _json({'detail': 'positionMs must be between 0 and 213400'}, 400));
      await expectLater(
        repo.postComment('t1', positionMs: 999999, text: 'x'),
        _kind(RepositoryErrorKind.invalid, 'positionMs must be between 0 and 213400'),
      );
    });

    test('commenting on a track that is not ready is a conflict', () async {
      final (repo, _) = _repo((r) => _json({}, 409));
      await expectLater(repo.postComment('t1', positionMs: 0, text: 'x'), _kind(RepositoryErrorKind.conflict));
    });

    test('a comment is deleted with 204 and nothing is read from the body', () async {
      final (repo, calls) = _repo((r) => http.Response('', 204));

      await repo.deleteComment('t1', 'c1');

      expect((calls.single.method, calls.single.path), ('DELETE', '/api/v1/tracks/t1/comments/c1'));
    });

    test('someone who may not delete it gets "forbidden", a comment that is gone gets "not found"', () async {
      final (forbidden, _) = _repo((r) => _json({}, 403));
      await expectLater(forbidden.deleteComment('t1', 'c1'), _kind(RepositoryErrorKind.forbidden));

      final (gone, _) = _repo((r) => _json({}, 404));
      await expectLater(gone.deleteComment('t1', 'c1'), _kind(RepositoryErrorKind.notFound, 'Comment not found'));
    });
  });

  test('a server error is reported as such', () async {
    final (repo, _) = _repo((r) => _json({}, 500));
    await expectLater(repo.likeTrack('t1'), _kind(RepositoryErrorKind.server, 'Server error (500)'));
  });
}
