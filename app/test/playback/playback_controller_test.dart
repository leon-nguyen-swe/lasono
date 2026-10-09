import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/models/track.dart';
import 'package:lasono_app/player_service.dart';
import 'package:lasono_app/playback/playback_controller.dart';

import '../fake_player_service.dart';

Track _track(String id, {String status = 'READY', double seconds = 60}) => Track(
      id: id,
      title: 'Track $id',
      description: '',
      status: status,
      ownerId: 'owner',
      durationSeconds: status == 'READY' ? seconds : null,
    );

class _Harness {
  _Harness() : player = FakePlayerService() {
    controller = PlaybackController(
      player: player,
      streamUrl: (id) async {
        asked.add(id);
        final failure = streamFailure;
        if (failure != null) throw failure;
        return Uri.parse('http://stream.test/$id');
      },
    );
  }

  final FakePlayerService player;
  late final PlaybackController controller;
  final asked = <String>[];
  Object? streamFailure;

  /// Lets the streams of the fake player deliver what was emitted.
  Future<void> settle() => pumpEventQueue();
}

void main() {
  group('playing a queue', () {
    test('loads the address of the track pressed, plays it, and asks for no other', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b'), _track('c')], startIndex: 1);
      await h.settle();

      expect(h.asked, ['b']);
      expect(h.player.loaded, [Uri.parse('http://stream.test/b')]);
      expect(h.player.playCalls, 1);
      expect(h.controller.current!.id, 'b');
      expect(h.controller.index, 1);
      expect(h.controller.playing, isTrue);
      expect(h.controller.loading, isFalse);
      expect(h.controller.error, isNull);
      expect(h.controller.queue.map((t) => t.id), ['a', 'b', 'c']);
    });

    test('shows the length from the track at once, and the length the player reports when it knows it', () async {
      final h = _Harness();
      h.player.durationOnLoad = const Duration(seconds: 61);

      final started = h.controller.playQueue([_track('a', seconds: 60)]);
      expect(h.controller.duration.value, const Duration(seconds: 60));
      await started;
      await h.settle();

      expect(h.controller.duration.value, const Duration(seconds: 61));
    });

    test('is loading until the audio is ready', () async {
      final h = _Harness();
      h.player.loadGate = Completer<void>();

      final started = h.controller.playQueue([_track('a')]);
      await h.settle();
      expect(h.controller.loading, isTrue);
      expect(h.player.playCalls, 0);

      h.player.loadGate!.complete();
      await started;
      expect(h.controller.loading, isFalse);
      expect(h.player.playCalls, 1);
    });

    test('plays one track on its own with play()', () async {
      final h = _Harness();
      await h.controller.play(_track('solo'));
      expect(h.controller.queue.map((t) => t.id), ['solo']);
      expect(h.controller.hasNext, isFalse);
    });

    test('an empty list does nothing', () async {
      final h = _Harness();
      await h.controller.playQueue(const []);
      expect(h.controller.current, isNull);
      expect(h.asked, isEmpty);
    });

    test('a start index out of range is kept inside the list', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b')], startIndex: 99);
      expect(h.controller.current!.id, 'b');
      await h.controller.playQueue([_track('a'), _track('b')], startIndex: -3);
      expect(h.controller.current!.id, 'a');
    });

    test('a track that is not ready is skipped for the next one that can be played', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a', status: 'PROCESSING'), _track('b', status: 'FAILED'), _track('c')]);
      expect(h.controller.current!.id, 'c');
      expect(h.asked, ['c']);
    });

    test('when nothing in the list can be played, it says so and loads nothing', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a', status: 'PROCESSING'), _track('b', status: 'FAILED')]);
      expect(h.controller.error, 'No track in this list can be played');
      expect(h.asked, isEmpty);
      expect(h.controller.playing, isFalse);
    });

    test('a track pressed while the one before is still loading wins; the first is never played', () async {
      final h = _Harness();
      h.player.loadGate = Completer<void>();

      final first = h.controller.playQueue([_track('a')]);
      await h.settle();
      final second = h.controller.playQueue([_track('b')]);
      await h.settle();
      h.player.loadGate!.complete();
      await Future.wait([first, second]);
      await h.settle();

      expect(h.controller.current!.id, 'b');
      expect(h.controller.loading, isFalse);
      expect(h.player.playCalls, 1, reason: 'only the track pressed last starts');
    });
  });

  group('next and previous', () {
    test('next goes to the following track and plays it; at the end there is no next', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b')]);

      expect(h.controller.hasNext, isTrue);
      await h.controller.next();
      expect(h.controller.current!.id, 'b');
      expect(h.controller.hasNext, isFalse);

      await h.controller.next();
      expect(h.controller.current!.id, 'b');
      expect(h.asked, ['a', 'b']);
    });

    test('next skips tracks that cannot be played', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b', status: 'PROCESSING'), _track('c')]);
      await h.controller.next();
      expect(h.controller.current!.id, 'c');
    });

    test('previous goes back to the track before when the track has hardly played', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b')], startIndex: 1);
      h.player.emitPosition(const Duration(seconds: 2));
      await h.settle();

      await h.controller.previous();

      expect(h.controller.current!.id, 'a');
    });

    test('previous starts the same track again when it has played for more than 3 seconds', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b')], startIndex: 1);
      h.player.emitPosition(const Duration(seconds: 10));
      await h.settle();

      await h.controller.previous();

      expect(h.controller.current!.id, 'b');
      expect(h.player.seeks, [Duration.zero]);
    });

    test('previous on the first track starts it again', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b')]);
      expect(h.controller.hasPrevious, isFalse);

      await h.controller.previous();

      expect(h.controller.current!.id, 'a');
      expect(h.player.seeks, [Duration.zero]);
    });
  });

  group('the end of a track', () {
    test('goes on to the next track by itself', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b')]);

      h.player.emitCompleted();
      await h.settle();

      expect(h.controller.current!.id, 'b');
      expect(h.asked, ['a', 'b']);
      expect(h.controller.playing, isTrue);
    });

    test('at the end of the queue it stops on the last track, back at its start', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b')], startIndex: 1);
      h.player.emitPosition(const Duration(seconds: 59));
      await h.settle();

      h.player.emitCompleted();
      await h.settle();

      expect(h.controller.current!.id, 'b');
      expect(h.controller.playing, isFalse);
      expect(h.controller.position.value, Duration.zero);
      expect(h.player.pauseCalls, 1);
      expect(h.player.seeks.last, Duration.zero);
    });

    test('and play can then start that track again', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a')]);
      h.player.emitCompleted();
      await h.settle();

      await h.controller.togglePlay();

      expect(h.controller.playing, isTrue);
      expect(h.player.playCalls, 2);
      expect(h.player.loaded.length, 1, reason: 'the track is still loaded, it is not asked for again');
    });
  });

  group('play and pause', () {
    test('toggle pauses and resumes the loaded track', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a')]);

      await h.controller.togglePlay();
      await h.settle();
      expect(h.controller.playing, isFalse);

      await h.controller.togglePlay();
      await h.settle();
      expect(h.controller.playing, isTrue);
      expect(h.player.loaded.length, 1);
    });

    test('with nothing to play it does nothing', () async {
      final h = _Harness();
      await h.controller.togglePlay();
      expect(h.player.playCalls, 0);
    });

    test('pause() only pauses when playing', () async {
      final h = _Harness();
      await h.controller.pause();
      expect(h.player.pauseCalls, 0);
      await h.controller.playQueue([_track('a')]);
      await h.controller.pause();
      expect(h.player.pauseCalls, 1);
    });
  });

  group('when something goes wrong', () {
    test('an address that cannot be had is shown as the error, and nothing plays', () async {
      final h = _Harness();
      h.streamFailure = const RepositoryException('Track not found', kind: RepositoryErrorKind.notFound);

      await h.controller.playQueue([_track('a')]);

      expect(h.controller.error, 'Track not found');
      expect(h.controller.loading, isFalse);
      expect(h.controller.playing, isFalse);
      expect(h.player.playCalls, 0);
    });

    test('audio that cannot be loaded says so', () async {
      final h = _Harness();
      h.player.loadError = const PlaybackException('boom');

      await h.controller.playQueue([_track('a')]);

      expect(h.controller.error, 'Cannot play this track');
      expect(h.controller.playing, isFalse);
    });

    test('pressing play again after a failure tries again', () async {
      final h = _Harness();
      h.streamFailure = const RepositoryException('Cannot reach the server', kind: RepositoryErrorKind.network);
      await h.controller.playQueue([_track('a')]);
      expect(h.controller.error, isNotNull);

      h.streamFailure = null;
      await h.controller.togglePlay();

      expect(h.controller.error, isNull);
      expect(h.controller.playing, isTrue);
      expect(h.asked, ['a', 'a']);
    });

    test('a failed track does not stop the user from going on to the next', () async {
      final h = _Harness();
      h.streamFailure = const RepositoryException('x');
      await h.controller.playQueue([_track('a'), _track('b')]);

      h.streamFailure = null;
      await h.controller.next();

      expect(h.controller.current!.id, 'b');
      expect(h.controller.error, isNull);
    });
  });

  group('seeking', () {
    test('jumps to the asked position, and the bar moves at once', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a', seconds: 60)]);

      await h.controller.seek(const Duration(seconds: 30));

      expect(h.player.seeks, [const Duration(seconds: 30)]);
      expect(h.controller.position.value, const Duration(seconds: 30));
    });

    test('is kept inside the track: before the start and past the end', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a', seconds: 60)]);

      await h.controller.seek(const Duration(seconds: -5));
      await h.controller.seek(const Duration(seconds: 500));

      expect(h.player.seeks, [Duration.zero, const Duration(seconds: 60)]);
    });

    test('a fraction of the length: tapping the middle of the bar', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a', seconds: 60)]);

      await h.controller.seekFraction(0.5);
      await h.controller.seekFraction(2);

      expect(h.player.seeks, [const Duration(seconds: 30), const Duration(seconds: 60)]);
    });

    test('before anything is loaded, a seek is ignored', () async {
      final h = _Harness();
      await h.controller.seek(const Duration(seconds: 5));
      expect(h.player.seeks, isEmpty);
    });

    test('the position follows the player', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a')]);

      h.player.emitPosition(const Duration(seconds: 12));
      await h.settle();

      expect(h.controller.position.value, const Duration(seconds: 12));
    });
  });

  group('volume', () {
    test('is passed to the player and kept between 0 and 1', () async {
      final h = _Harness();
      await h.controller.setVolume(0.4);
      await h.controller.setVolume(3);
      await h.controller.setVolume(-1);
      expect(h.player.volumes, [0.4, 1.0, 0.0]);
    });

    test('mute silences and unmute brings back the volume from before', () async {
      final h = _Harness();
      await h.controller.setVolume(0.6);

      await h.controller.toggleMute();
      expect(h.controller.muted, isTrue);
      expect(h.controller.volume, 0);

      await h.controller.toggleMute();
      expect(h.controller.volume, 0.6);
      expect(h.controller.muted, isFalse);
    });

    test('unmuting from a volume that was dragged to zero gives full volume, not silence', () async {
      final h = _Harness();
      await h.controller.setVolume(0);
      await h.controller.toggleMute();
      expect(h.controller.volume, 1);
    });
  });

  group('the queue changes', () {
    test('a list that grew adds its new tracks at the end, once', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b')], sourceId: 'home');

      h.controller.extendQueue('home', [_track('b'), _track('c'), _track('d')]);

      expect(h.controller.queue.map((t) => t.id), ['a', 'b', 'c', 'd']);
    });

    test('a different list, or a queue without a list, is left alone', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a')], sourceId: 'home');
      h.controller.extendQueue('feed', [_track('z')]);
      expect(h.controller.queue.map((t) => t.id), ['a']);

      await h.controller.playQueue([_track('a')]);
      h.controller.extendQueue('home', [_track('z')]);
      expect(h.controller.queue.map((t) => t.id), ['a']);
    });

    test('a newer version of a track replaces it in the queue, also the current one', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b')]);

      h.controller.replaceTrack(_track('a').copyWith(likeCount: 9, isLikedByMe: true));

      expect(h.controller.current!.likeCount, 9);
      expect(h.controller.current!.isLikedByMe, isTrue);
      expect(h.controller.queue.last.likeCount, 0);

      h.controller.replaceTrack(_track('unknown'));
      expect(h.controller.queue.length, 2);
    });

    test('stop empties the queue and silences the player', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a'), _track('b')]);

      await h.controller.stop();
      await h.settle();

      expect(h.controller.current, isNull);
      expect(h.controller.queue, isEmpty);
      expect(h.controller.playing, isFalse);
      expect(h.player.stopCalls, 1);
    });

    test('a track still loading when stop is called is not played afterwards', () async {
      final h = _Harness();
      h.player.loadGate = Completer<void>();
      final started = h.controller.playQueue([_track('a')]);
      await h.settle();

      await h.controller.stop();
      h.player.loadGate!.complete();
      await started;
      await h.settle();

      expect(h.player.playCalls, 0);
      expect(h.controller.current, isNull);
    });
  });

  group('telling the screen', () {
    test('listeners hear about a new track, but not about every tick of the position', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a')]);
      await h.settle();
      var notified = 0;
      h.controller.addListener(() => notified++);

      for (var i = 1; i <= 20; i++) {
        h.player.emitPosition(Duration(seconds: i));
      }
      await h.settle();
      expect(notified, 0);

      await h.controller.togglePlay();
      await h.settle();
      expect(notified, greaterThan(0));
    });

    test('after dispose the player can still send events without a crash', () async {
      final h = _Harness();
      await h.controller.playQueue([_track('a')]);
      h.controller.dispose();

      h.player.emitPosition(const Duration(seconds: 1));
      h.player.emitCompleted();
      await h.settle();
    });
  });
}
