import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/fake/fake_audio.dart';
import 'package:lasono_app/data/fake/fake_behavior.dart';
import 'package:lasono_app/data/fake/fake_repositories.dart';
import 'package:lasono_app/data/fake/fake_world.dart';
import 'package:lasono_app/data/repository_exception.dart';

class _Fixture {
  _Fixture({this.viewer = 'viewer-1'})
      : world = FakeWorld(clock: () => DateTime.utc(2026, 10, 8, 12)),
        behavior = FakeBehavior.instant() {
    tracks = FakeTrackRepository(world, behavior, () => viewer);
    users = FakeUserRepository(world, behavior, () => viewer);
  }

  final FakeWorld world;
  final FakeBehavior behavior;
  late final FakeTrackRepository tracks;
  late final FakeUserRepository users;
  String? viewer;
}

Matcher _fails(RepositoryErrorKind kind, [String? message]) {
  var matcher = isA<RepositoryException>().having((e) => e.kind, 'kind', kind);
  if (message != null) matcher = matcher.having((e) => e.message, 'message', message);
  return throwsA(matcher);
}

void main() {
  group('tracks', () {
    test('a track is read with the likes of the viewer on it', () async {
      final f = _Fixture();
      final id = f.world.tracks.first.id;
      f.world.like('viewer-1', id);

      final track = await f.tracks.getTrack(id);

      expect(track.title, f.world.tracks.first.title);
      expect(track.isLikedByMe, isTrue);
      expect(track.likeCount, f.world.likeCountOf(id));
    });

    test('an unknown track is not found', () async {
      await expectLater(_Fixture().tracks.getTrack('nope'), _fails(RepositoryErrorKind.notFound, 'Track not found'));
    });

    test('the list has 20 on the first page, then the other 10, then no cursor', () async {
      final f = _Fixture();
      final first = await f.tracks.listTracks();
      final second = await f.tracks.listTracks(cursor: first.nextCursor);

      expect(first.items.length, 20);
      expect(second.items.length, 10);
      expect(second.nextCursor, isNull);
      expect({...first.items.map((t) => t.id), ...second.items.map((t) => t.id)}.length, 30);
    });

    test('a limit above 50 is cut to 50', () async {
      final page = await _Fixture().tracks.listTracks(limit: 500);
      expect(page.items.length, 30);
      expect(page.nextCursor, isNull);
    });

    test('the tracks of a user come with how many there are in all', () async {
      final f = _Fixture();
      final owner = FakeWorld.userId(1);
      final mine = f.world.tracks.where((t) => t.ownerId == owner).length;

      final page = await f.tracks.listUserTracks(owner, limit: 2);

      expect(page.totalCount, mine);
      expect(page.items.length, 2);
      expect(page.nextCursor, isNotNull);
      expect(page.items.every((t) => t.ownerId == owner), isTrue);
    });

    test('a user with no tracks has an empty page and a total of zero', () async {
      final page = await _Fixture().tracks.listUserTracks('someone-real');
      expect(page.items, isEmpty);
      expect(page.totalCount, 0);
    });

    test('a ready track can be played: its address holds a tune as long as the track says', () async {
      final f = _Fixture();
      final track = f.world.tracks.firstWhere((t) => t.isReady);

      final uri = await f.tracks.fetchStreamUrl(track.id);

      expect(uri.scheme, 'data');
      final bytes = uri.data!.contentAsBytes();
      expect(bytes.length, FakeAudio.headerBytes + track.durationSeconds!.round() * FakeAudio.sampleRate);
    });

    test('asking again gives the same address without making the tune again', () async {
      final f = _Fixture();
      final id = f.world.tracks.firstWhere((t) => t.isReady).id;
      expect(identical(await f.tracks.fetchStreamUrl(id), await f.tracks.fetchStreamUrl(id)), isTrue);
    });

    test('a track that is processing cannot be played, and an unknown one is not found', () async {
      final f = _Fixture();
      final processing = f.world.tracks.firstWhere((t) => t.status == 'PROCESSING').id;
      await expectLater(f.tracks.fetchStreamUrl(processing), _fails(RepositoryErrorKind.conflict));
      await expectLater(f.tracks.fetchStreamUrl('nope'), _fails(RepositoryErrorKind.notFound));
    });

    test('a fake track cannot be changed, deleted or uploaded', () async {
      final f = _Fixture();
      final id = f.world.tracks.first.id;
      await expectLater(f.tracks.updateTrack(id, title: 'x'), throwsA(isA<RepositoryException>()));
      await expectLater(f.tracks.deleteTrack(id), throwsA(isA<RepositoryException>()));
      await expectLater(
        f.tracks.uploadTrack(title: 't', filename: 'a.mp3', bytes: _bytes),
        throwsA(isA<RepositoryException>()),
      );
    });
  });

  group('users', () {
    test('a profile has the counts and whether the viewer follows the user', () async {
      final f = _Fixture();
      final sonTung = FakeWorld.userId(1);

      final profile = await f.users.getProfile(sonTung);

      expect(profile.displayName, 'Sơn Tùng');
      expect(profile.followerCount, f.world.followerCountOf(sonTung));
      expect(profile.followerCount, greaterThan(1000));
      expect(profile.isFollowedByMe, isTrue, reason: 'a new viewer starts out following Sơn Tùng');
    });

    test('is not followed by someone who is not logged in', () async {
      final f = _Fixture(viewer: null);
      expect((await f.users.getProfile(FakeWorld.userId(1))).isFollowedByMe, isFalse);
    });

    test('an unknown user is not found', () async {
      await expectLater(_Fixture().users.getProfile('nope'), _fails(RepositoryErrorKind.notFound, 'User not found'));
    });

    test('several profiles come at once; the ones nobody has and the repeated ones are left out', () async {
      final f = _Fixture();
      final profiles = await f.users.getProfiles([FakeWorld.userId(1), FakeWorld.userId(2), 'ghost', FakeWorld.userId(1)]);
      expect(profiles.map((p) => p.userId).toSet(), {FakeWorld.userId(1), FakeWorld.userId(2)});
      expect(profiles.length, 2);
    });

    test('a user cannot be renamed here', () async {
      await expectLater(_Fixture().users.changeDisplayName('x'), throwsA(isA<RepositoryException>()));
    });
  });
}

final _bytes = Uint8List.fromList([1, 2, 3]);
