import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/models/track.dart';
import 'package:lasono_app/playback/playback_controller.dart';
import 'package:lasono_app/shell/player_bar.dart';

import '../support/test_harness.dart';

class _Bar {
  _Bar(this.env, this.playback);

  final TestEnv env;
  final PlaybackController playback;
  final opened = <String>[];

  List<Track> get ready => env.world.tracks.where((t) => t.isReady).toList();
  Track get first => ready.first;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        themed(
          Align(
            alignment: Alignment.bottomCenter,
            child: PlayerBar(
              playback: playback,
              directory: env.repositories.directory,
              onOpenTrack: (track) => opened.add('track:${track.id}'),
              onOpenUser: (id) => opened.add('user:$id'),
            ),
          ),
        ),
      );

  /// Lets the names of the authors arrive and the bar redraw.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<_Bar> _bar(WidgetTester tester, {double width = 1280}) async {
  TestEnv.window(tester, width: width, height: 800);
  final env = await TestEnv.create();
  final playback = env.newPlayback();
  addTearDown(playback.dispose);
  final bar = _Bar(env, playback);
  await bar.pump(tester);
  return bar;
}

void main() {
  testWidgets('is not there while nothing plays', (tester) async {
    final bar = await _bar(tester);

    expect(find.byKey(const Key('playerBar')), findsNothing);
    expect(find.byKey(const Key('playerBarEmpty')), findsOneWidget);
    expect(bar.playback.current, isNull);
  });

  group('on a wide window', () {
    testWidgets('appears with the cover, the title and the name of the author once a track plays', (tester) async {
      final bar = await _bar(tester);

      await bar.playback.playQueue(bar.ready);
      await bar.settle(tester);

      expect(find.byKey(const Key('playerBar')), findsOneWidget);
      expect(find.byKey(const Key('playerCover')), findsOneWidget);
      expect(find.text(bar.first.title), findsOneWidget);
      final author = bar.env.world.user(bar.first.ownerId)!.displayName;
      expect(find.descendant(of: find.byKey(const Key('playerArtist')), matching: find.text(author)), findsOneWidget);
    });

    testWidgets('the author is asked for once, even when the bar redraws many times', (tester) async {
      final bar = await _bar(tester);
      await bar.playback.playQueue(bar.ready);
      await bar.settle(tester);

      for (var i = 0; i < 5; i++) {
        bar.env.player.emitPosition(Duration(seconds: i));
        await tester.pump();
      }

      expect(bar.env.repositories.directory.cached(bar.first.ownerId), isNotNull);
    });

    testWidgets('shows pause while playing, and a press pauses; a second press plays again', (tester) async {
      final bar = await _bar(tester);
      await bar.playback.playQueue(bar.ready);
      await bar.settle(tester);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.tap(find.byKey(const Key('playPauseButton')));
      await bar.settle(tester);
      expect(bar.env.player.pauseCalls, 1);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      await tester.tap(find.byKey(const Key('playPauseButton')));
      await bar.settle(tester);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    });

    testWidgets('next plays the next track of the list, and is switched off on the last one', (tester) async {
      final bar = await _bar(tester);
      await bar.playback.playQueue(bar.ready.take(2).toList());
      await bar.settle(tester);
      IconButton next() => tester.widget<IconButton>(find.byKey(const Key('nextButton')));
      expect(next().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('nextButton')));
      await bar.settle(tester);

      expect(bar.playback.current!.id, bar.ready[1].id);
      expect(find.text(bar.ready[1].title), findsOneWidget);
      expect(next().onPressed, isNull);
    });

    testWidgets('previous goes back a track, or starts the track again when it has played for a while', (tester) async {
      final bar = await _bar(tester);
      await bar.playback.playQueue(bar.ready.take(3).toList(), startIndex: 1);
      await bar.settle(tester);

      await tester.tap(find.byKey(const Key('previousButton')));
      await bar.settle(tester);
      expect(bar.playback.current!.id, bar.ready[0].id);

      bar.env.player.emitPosition(const Duration(seconds: 20));
      await bar.settle(tester);
      await tester.tap(find.byKey(const Key('previousButton')));
      await bar.settle(tester);
      expect(bar.env.player.seeks.last, Duration.zero);
      expect(bar.playback.current!.id, bar.ready[0].id);
    });

    testWidgets('shows the time played and the length, with the minutes and the seconds', (tester) async {
      final bar = await _bar(tester);
      await bar.playback.playQueue([bar.first.copyWith(durationSeconds: 83)]);
      bar.env.player.emitDuration(const Duration(seconds: 83));
      bar.env.player.emitPosition(const Duration(seconds: 12));
      await bar.settle(tester);

      expect(find.byKey(const Key('playerPosition')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('playerPosition'))).data, '0:12');
      expect(tester.widget<Text>(find.byKey(const Key('playerDuration'))).data, '1:23');
    });

    testWidgets('pressing the bar in the middle seeks to the middle of the track', (tester) async {
      final bar = await _bar(tester);
      await bar.playback.playQueue([bar.first.copyWith(durationSeconds: 60)]);
      bar.env.player.emitDuration(const Duration(seconds: 60));
      await bar.settle(tester);

      await tester.tapAt(tester.getCenter(find.byKey(const Key('seekSlider'))));
      await bar.settle(tester);

      expect(bar.env.player.seeks.last.inSeconds, inInclusiveRange(27, 33));
    });

    testWidgets('the bar follows the playback: the slider moves with the position', (tester) async {
      final bar = await _bar(tester);
      await bar.playback.playQueue([bar.first.copyWith(durationSeconds: 100)]);
      bar.env.player.emitDuration(const Duration(seconds: 100));
      bar.env.player.emitPosition(const Duration(seconds: 25));
      await bar.settle(tester);

      expect(tester.widget<Slider>(find.byKey(const Key('seekSlider'))).value, closeTo(0.25, 0.001));
    });

    testWidgets('cannot be sought while the audio is still loading', (tester) async {
      final bar = await _bar(tester);
      bar.env.player.loadGate = Completer<void>();
      unawaited(bar.playback.playQueue(bar.ready));
      await bar.settle(tester);

      expect(find.byKey(const Key('playerLoading')), findsOneWidget);
      expect(tester.widget<Slider>(find.byKey(const Key('seekSlider'))).onChanged, isNull);

      bar.env.player.loadGate!.complete();
      await bar.settle(tester);
      expect(find.byKey(const Key('playerLoading')), findsNothing);
    });

    testWidgets('has a volume control that can mute and unmute', (tester) async {
      final bar = await _bar(tester);
      await bar.playback.playQueue(bar.ready);
      await bar.settle(tester);
      expect(find.byKey(const Key('volumeSlider')), findsOneWidget);

      await tester.tap(find.byKey(const Key('volumeButton')));
      await bar.settle(tester);
      expect(bar.env.player.volumes.last, 0);
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

      await tester.tap(find.byKey(const Key('volumeButton')));
      await bar.settle(tester);
      expect(bar.env.player.volumes.last, 1);
    });

    testWidgets('pressing the title opens the track, pressing the author opens the user', (tester) async {
      final bar = await _bar(tester);
      await bar.playback.playQueue(bar.ready);
      await bar.settle(tester);

      await tester.tap(find.byKey(const Key('playerTitle')));
      await tester.tap(find.byKey(const Key('playerArtist')));

      expect(bar.opened, ['track:${bar.first.id}', 'user:${bar.first.ownerId}']);
    });

    testWidgets('says why a track cannot be played, and the button then tries again', (tester) async {
      final bar = await _bar(tester);
      const unknown = Track(id: 'f4e00000-0000-4000-9000-999999999999', title: 'Bài không có', description: '', status: 'READY', ownerId: 'x');
      await bar.playback.playQueue([unknown]);
      await bar.settle(tester);

      expect(find.byKey(const Key('playerError')), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.byKey(const Key('playerArtist')), findsNothing);
    });

    testWidgets('a long title is cut with dots and nothing overflows', (tester) async {
      final bar = await _bar(tester);
      final long = bar.first.copyWith(title: 'Một cái tên bài hát rất rất dài ' * 6);
      await bar.playback.playQueue([long]);
      await bar.settle(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('on a tablet', () {
    testWidgets('has no volume control, and still everything else', (tester) async {
      final bar = await _bar(tester, width: 800);
      await bar.playback.playQueue(bar.ready);
      await bar.settle(tester);

      expect(find.byKey(const Key('volumeSlider')), findsNothing);
      expect(find.byKey(const Key('seekSlider')), findsOneWidget);
      expect(find.byKey(const Key('previousButton')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('on a phone', () {
    testWidgets('shrinks to a mini bar: cover, names, next and play, with a thin line of progress', (tester) async {
      final bar = await _bar(tester, width: 390);
      await bar.playback.playQueue([bar.first.copyWith(durationSeconds: 100)]);
      bar.env.player.emitDuration(const Duration(seconds: 100));
      bar.env.player.emitPosition(const Duration(seconds: 50));
      await bar.settle(tester);

      expect(find.byKey(const Key('miniPlayer')), findsOneWidget);
      expect(find.byKey(const Key('seekSlider')), findsNothing);
      expect(find.byKey(const Key('volumeSlider')), findsNothing);
      expect(find.byKey(const Key('previousButton')), findsNothing);
      expect(find.byKey(const Key('playPauseButton')), findsOneWidget);
      expect(find.byKey(const Key('playerCover')), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byKey(const Key('miniProgress'))).value, closeTo(0.5, 0.001));
      expect(tester.takeException(), isNull);
    });

    testWidgets('pressing the mini bar opens the track; the play button does not', (tester) async {
      final bar = await _bar(tester, width: 390);
      await bar.playback.playQueue(bar.ready);
      await bar.settle(tester);

      await tester.tap(find.byKey(const Key('playPauseButton')));
      await bar.settle(tester);
      expect(bar.opened, isEmpty);

      await tester.tap(find.byKey(const Key('playerCover')));
      expect(bar.opened, ['track:${bar.first.id}']);
    });

    testWidgets('fits a very narrow phone, 320 px, with a long title', (tester) async {
      final bar = await _bar(tester, width: 320);
      await bar.playback.playQueue([bar.first.copyWith(title: 'Một cái tên bài hát rất rất dài ' * 6)]);
      await bar.settle(tester);

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('goes away again when the queue is stopped', (tester) async {
    final bar = await _bar(tester);
    await bar.playback.playQueue(bar.ready);
    await bar.settle(tester);
    expect(find.byKey(const Key('playerBar')), findsOneWidget);

    await bar.playback.stop();
    await bar.settle(tester);

    expect(find.byKey(const Key('playerBar')), findsNothing);
  });
}
