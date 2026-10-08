import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/fake/fake_behavior.dart';
import 'package:lasono_app/data/fake/fake_repositories.dart';
import 'package:lasono_app/data/fake/fake_world.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/models/search_results.dart';
import 'package:lasono_app/models/track.dart';

class _Fixture {
  _Fixture({this.viewer = 'viewer-1', TrackResolver? resolver})
      : world = FakeWorld(clock: () => DateTime.utc(2026, 10, 8, 12)),
        behavior = FakeBehavior.instant() {
    feed = FakeFeedRepository(world, behavior, () => viewer, resolveTrack: resolver);
    search = FakeSearchRepository(world, behavior, () => viewer);
  }

  final FakeWorld world;
  final FakeBehavior behavior;
  late final FakeFeedRepository feed;
  late final FakeSearchRepository search;
  String? viewer;
}

Matcher _fails(RepositoryErrorKind kind, [String? message]) {
  var matcher = isA<RepositoryException>().having((e) => e.kind, 'kind', kind);
  if (message != null) matcher = matcher.having((e) => e.message, 'message', message);
  return throwsA(matcher);
}

void main() {
  group('feed', () {
    test('needs a login', () async {
      final f = _Fixture(viewer: null);
      await expectLater(f.feed.feed(), _fails(RepositoryErrorKind.unauthorized));
    });

    test('a new viewer sees the ready tracks of the three users they start out following, newest first', () async {
      final f = _Fixture();
      final page = await f.feed.feed(limit: 50);
      final followed = {FakeWorld.userId(1), FakeWorld.userId(2), FakeWorld.userId(6)};

      expect(page.items, isNotEmpty);
      expect(page.items.every((t) => followed.contains(t.ownerId)), isTrue);
      expect(page.items.every((t) => t.isReady), isTrue);
      final times = page.items.map((t) => t.createdAt!).toList();
      for (var i = 1; i < times.length; i++) {
        expect(times[i].isBefore(times[i - 1]), isTrue);
      }
      expect(page.items.length, f.world.tracks.where((t) => followed.contains(t.ownerId) && t.isReady).length);
    });

    test('the pages put together are the whole feed, with nobody twice', () async {
      final f = _Fixture();
      final whole = (await f.feed.feed(limit: 50)).items.map((t) => t.id).toList();

      final paged = <String>[];
      String? cursor;
      do {
        final page = await f.feed.feed(cursor: cursor, limit: 4);
        expect(page.items.length, lessThanOrEqualTo(4));
        paged.addAll(page.items.map((t) => t.id));
        cursor = page.nextCursor;
      } while (cursor != null);

      expect(paged, whole);
      expect(paged.toSet().length, paged.length);
    });

    test('the default page is 20 tracks at most', () async {
      final f = _Fixture();
      // Follow everybody, so there are more than 20 tracks.
      for (final user in f.world.users) {
        f.world.follow('viewer-1', user.id);
      }
      final page = await f.feed.feed();
      expect(page.items.length, 20);
      expect(page.nextCursor, isNotNull);
    });

    test('someone who follows nobody has an empty feed, not an error', () async {
      final f = _Fixture();
      f.world.ensureViewer('viewer-1');
      for (final user in f.world.users) {
        f.world.unfollow('viewer-1', user.id);
      }

      final page = await f.feed.feed();

      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
    });

    test('a track that is processing or failed never appears, even from someone who is followed', () async {
      final f = _Fixture();
      for (final user in f.world.users) {
        f.world.follow('viewer-1', user.id);
      }
      final page = await f.feed.feed(limit: 50);
      expect(page.items.map((t) => t.status).toSet(), {'READY'});
    });

    test('shows the like of the viewer on the tracks', () async {
      final f = _Fixture();
      final first = (await f.feed.feed()).items.first;
      f.world.like('viewer-1', first.id);

      final again = (await f.feed.feed()).items.first;

      expect(again.isLikedByMe, isTrue);
      expect(again.likeCount, first.likeCount + 1);
    });

    test('a limit below 1 is refused', () async {
      await expectLater(_Fixture().feed.feed(limit: 0), _fails(RepositoryErrorKind.invalid));
    });
  });

  group('liked tracks', () {
    test('are listed most recently liked first', () async {
      final f = _Fixture();
      final ids = f.world.tracks.where((t) => t.isReady).take(3).map((t) => t.id).toList();
      for (final id in ids) {
        f.world.like('viewer-1', id);
      }

      final page = await f.feed.likedTracks('viewer-1');

      expect(page.items.map((t) => t.id), ids.reversed.toList());
      expect(page.items.every((t) => t.isLikedByMe), isTrue);
    });

    test('include a real track, which the resolver finds', () async {
      Track real(String id) => Track(id: id, title: 'Bài thật', description: '', status: 'READY', ownerId: 'u');
      final f = _Fixture(resolver: (id) async => id == 'real-1' ? real(id) : null);
      f.world.like('viewer-1', f.world.tracks.first.id);
      f.world.like('viewer-1', 'real-1');
      f.world.like('viewer-1', 'real-gone');

      final page = await f.feed.likedTracks('viewer-1');

      expect(page.items.map((t) => t.title), ['Bài thật', f.world.tracks.first.title]);
      expect(page.items.first.isLikedByMe, isTrue);
    });

    test('a user who liked nothing has an empty list, and an unknown fake user is not found', () async {
      final f = _Fixture();
      expect((await f.feed.likedTracks('someone')).items, isEmpty);
      await expectLater(f.feed.likedTracks(FakeWorld.userId(99)), _fails(RepositoryErrorKind.notFound));
    });

    test('are paged', () async {
      final f = _Fixture();
      for (final track in f.world.tracks.where((t) => t.isReady).take(5)) {
        f.world.like('viewer-1', track.id);
      }
      final first = await f.feed.likedTracks('viewer-1', limit: 2);
      final second = await f.feed.likedTracks('viewer-1', limit: 2, cursor: first.nextCursor);
      expect(first.items.length, 2);
      expect(second.items.length, 2);
      expect({...first.items.map((t) => t.id), ...second.items.map((t) => t.id)}.length, 4);
    });
  });

  group('search', () {
    test('finds a user without the marks and without the capitals, the same as with them', () async {
      final f = _Fixture();
      final plain = await f.search.search('son tung');
      final shouted = await f.search.search('SON TUNG');
      final marked = await f.search.search('Sơn Tùng');

      expect(plain.users.first.displayName, 'Sơn Tùng');
      expect(shouted.users.map((u) => u.userId), plain.users.map((u) => u.userId));
      expect(marked.users.map((u) => u.userId), plain.users.map((u) => u.userId));
    });

    test('finds a track by its title without the marks', () async {
      final results = await _Fixture().search.search('nang am');
      expect(results.tracks.first.title, 'Nắng ấm xa dần');
    });

    test('a short word that is only part of a name is found', () async {
      final results = await _Fixture().search.search('son');
      expect(results.users.map((u) => u.displayName), contains('Sơn Tùng'));
    });

    test('a small typo still finds it, like the trigram search of the backend', () async {
      final results = await _Fixture().search.search('son tuhg');
      expect(results.users.map((u) => u.displayName), contains('Sơn Tùng'));
    });

    test('a title that starts with the query comes before one that only contains it', () async {
      final f = _Fixture();
      final results = await f.search.search('nang');
      // "Nắng ấm xa dần" starts with it; a title that merely contains "nang" would come after.
      expect(results.tracks.first.title, startsWith('Nắng'));
    });

    test('only the kind that is asked for is searched', () async {
      final f = _Fixture();
      expect((await f.search.search('son', type: SearchType.users)).tracks, isEmpty);
      expect((await f.search.search('nang', type: SearchType.tracks)).users, isEmpty);
      expect((await f.search.search('nang', type: SearchType.tracks)).tracks, isNotEmpty);
    });

    test('the limit is applied to each kind', () async {
      final f = _Fixture();
      final results = await f.search.search('an', limit: 2);
      expect(results.tracks.length, lessThanOrEqualTo(2));
      expect(results.users.length, lessThanOrEqualTo(2));
    });

    test('a track that is processing or failed is not found, because it cannot be played', () async {
      final f = _Fixture();
      expect((await f.search.search('ha trang')).tracks, isEmpty);
      expect((await f.search.search('ban tinh ca')).tracks, isEmpty);
    });

    test('nothing alike gives an empty answer, not an error', () async {
      expect((await _Fixture().search.search('zzzzzz')).isEmpty, isTrue);
    });

    test('a query that is too short or too long is refused, spaces do not count', () async {
      final f = _Fixture();
      await expectLater(f.search.search('a'), _fails(RepositoryErrorKind.invalid));
      await expectLater(f.search.search('  a  '), _fails(RepositoryErrorKind.invalid));
      await expectLater(f.search.search(''), _fails(RepositoryErrorKind.invalid));
      await expectLater(f.search.search('a' * 101), _fails(RepositoryErrorKind.invalid));
      await f.search.search('ab');
      await f.search.search('a' * 100);
    });

    test('says whether the viewer follows each user found', () async {
      final f = _Fixture();
      final results = await f.search.search('son tung');
      expect(results.users.first.isFollowedByMe, isTrue, reason: 'a new viewer starts out following Sơn Tùng');

      final other = await f.search.search('maya');
      expect(other.users.first.isFollowedByMe, isFalse);
    });

    test('matches what the guide of the backend worked out by hand', () {
      // docs/backend-guide/06-search-vietnamese.md, trace-through: 9 shared pieces of 13 in all.
      expect(FakeSearchRepository.similarityForTest('Sơn Tùng M-TP', 'son tung'), closeTo(9 / 13, 0.0001));
      expect(FakeSearchRepository.similarityForTest('Sơn Tùng M-TP', 'son tuhg'), closeTo(6 / 16, 0.0001));
      expect(FakeSearchRepository.similarityForTest('Nắng ấm xa dần', 'nang am'), closeTo(8 / 15, 0.0001));
    });
  });
}
