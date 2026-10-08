import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/models/track.dart';
import 'package:lasono_app/playback/playback_controller.dart';
import 'package:lasono_app/widgets/track_card.dart';
import 'package:lasono_app/widgets/waveform_view.dart';

import '../support/test_harness.dart';

final _clock = DateTime.utc(2026, 10, 8, 12);

class _Rig {
  _Rig(this.env) : playback = env.newPlayback();

  final TestEnv env;
  final PlaybackController playback;

  int plays = 0;
  int opens = 0;
  int loginRequests = 0;
  final openedUsers = <String>[];
  final changes = <Track>[];
  final menu = <String>[];

  List<Track> get tracks => env.world.tracks;
  Track get first => tracks.firstWhere((t) => t.isReady);
  Track get second => tracks.where((t) => t.isReady).elementAt(1);

  static Future<_Rig> create({bool signedIn = true}) async => _Rig(await TestEnv.create(signedIn: signedIn));

  String? get viewer => env.session.account?.userId;

  Widget card(
    Track track, {
    String? viewerId,
    bool withMenu = false,
    List<Track>? queue,
  }) {
    final list = queue ?? tracks;
    return themed(
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: TrackCard(
          track: track,
          playback: playback,
          directory: env.repositories.directory,
          waveforms: env.repositories.waveforms,
          social: env.repositories.social,
          viewerId: viewerId ?? viewer,
          clock: () => _clock,
          onPlay: () async {
            plays++;
            await playback.playQueue(list, startIndex: list.indexWhere((t) => t.id == track.id), sourceId: 'test');
          },
          onOpen: () => opens++,
          onOpenUser: openedUsers.add,
          onNeedLogin: () => loginRequests++,
          onChanged: changes.add,
          onEdit: withMenu ? () => menu.add('edit') : null,
          onToggleVisibility: withMenu ? () => menu.add('visibility') : null,
          onDelete: withMenu ? () => menu.add('delete') : null,
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Icon _playIcon(WidgetTester tester) => tester.widget<Icon>(find.descendant(of: find.byKey(const Key('trackPlayButton')), matching: find.byType(Icon)));

void main() {
  group('what it shows', () {
    testWidgets('the title, the author, how long ago, the length, the likes and the comments', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final track = rig.first;

      await tester.pumpWidget(rig.card(track));
      await rig.settle(tester);

      expect(find.text(track.title), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('trackAuthor')), matching: find.text(rig.env.world.user(track.ownerId)!.displayName)), findsOneWidget);
      final age = tester.widget<Text>(find.byKey(const Key('trackAge'))).data!;
      expect(age, endsWith('trước'));
      expect(tester.widget<Text>(find.byKey(const Key('trackDuration'))).data, '0:${track.durationSeconds!.round()}');
      expect(find.byKey(const Key('likeButton')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('commentCount'))).data, formatCountOf(track.commentCount));
      expect(find.byKey(const Key('trackCover')), findsOneWidget);
    });

    testWidgets('draws its waveform, with no skeleton, when the track carries the peaks', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      await tester.pumpWidget(rig.card(rig.first));
      await rig.settle(tester);

      expect(find.byType(WaveformView), findsOneWidget);
      expect(find.byKey(const Key('waveformSkeleton')), findsNothing);
    });

    testWidgets('a list item has no peaks: it shows a skeleton and then reads its own waveform', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final real = rig.first;
      final fromAList = Track(
        id: real.id,
        title: real.title,
        description: '',
        status: 'READY',
        ownerId: real.ownerId,
        durationSeconds: real.durationSeconds,
        createdAt: real.createdAt,
      );

      await tester.pumpWidget(rig.card(fromAList));
      expect(find.byKey(const Key('waveformSkeleton')), findsOneWidget);
      await rig.settle(tester);

      expect(find.byKey(const Key('waveformSkeleton')), findsNothing);
      expect(find.byType(WaveformView), findsOneWidget);
      expect(rig.env.repositories.waveforms.cached(fromAList), isNotNull, reason: 'kept for the next time');
    });

    testWidgets('a private track is marked', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      await tester.pumpWidget(rig.card(rig.first.copyWith(visibility: 'PRIVATE')));
      expect(find.byKey(const Key('privateChip')), findsOneWidget);
      expect(find.text('Riêng tư'), findsOneWidget);

      await tester.pumpWidget(rig.card(rig.first));
      expect(find.byKey(const Key('privateChip')), findsNothing);
    });

    testWidgets('a track without a date has no "ago"', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final undated = Track(id: rig.first.id, title: 'Không ngày', description: '', status: 'READY', ownerId: rig.first.ownerId, waveform: rig.first.waveform);
      await tester.pumpWidget(rig.card(undated));
      expect(find.byKey(const Key('trackAge')), findsNothing);
    });
  });

  group('a track that cannot be played', () {
    testWidgets('while it is processing it says so, shows no waveform, and the play button does nothing', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final processing = rig.tracks.firstWhere((t) => t.status == 'PROCESSING');
      await tester.pumpWidget(rig.card(processing));
      await rig.settle(tester);

      expect(find.byKey(const Key('trackProcessing')), findsOneWidget);
      expect(find.byType(WaveformView), findsNothing);

      await tester.tap(find.byKey(const Key('trackPlayButton')), warnIfMissed: false);
      expect(rig.plays, 0);
      expect(tester.widget<InkWell>(find.byKey(const Key('trackPlayButton'))).onTap, isNull);
    });

    testWidgets('when it failed it says so in the colour of an error', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final failed = rig.tracks.firstWhere((t) => t.status == 'FAILED');
      await tester.pumpWidget(rig.card(failed));

      expect(find.byKey(const Key('trackFailed')), findsOneWidget);
      expect(find.byType(WaveformView), findsNothing);
      expect(find.textContaining('thất bại'), findsOneWidget);
    });

    testWidgets('a track that cannot be played can still be liked and opened', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      await tester.pumpWidget(rig.card(rig.tracks.firstWhere((t) => t.status == 'PROCESSING')));
      await tester.tap(find.byKey(const Key('trackTitle')));
      expect(rig.opens, 1);
    });
  });

  group('playing', () {
    testWidgets('pressing play asks the list to start this track, and the card then shows pause', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      await tester.pumpWidget(rig.card(rig.second));
      expect(_playIcon(tester).icon, Icons.play_arrow_rounded);

      await tester.tap(find.byKey(const Key('trackPlayButton')));
      await rig.settle(tester);

      expect(rig.plays, 1);
      expect(rig.playback.current!.id, rig.second.id);
      expect(rig.playback.queue.length, rig.tracks.length, reason: 'the whole list became the queue');
      expect(_playIcon(tester).icon, Icons.pause_rounded);
    });

    testWidgets('pressing again pauses, and again plays: it does not start the list a second time', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      await tester.pumpWidget(rig.card(rig.first));
      await tester.tap(find.byKey(const Key('trackPlayButton')));
      await rig.settle(tester);

      await tester.tap(find.byKey(const Key('trackPlayButton')));
      await rig.settle(tester);
      expect(_playIcon(tester).icon, Icons.play_arrow_rounded);

      await tester.tap(find.byKey(const Key('trackPlayButton')));
      await rig.settle(tester);
      expect(_playIcon(tester).icon, Icons.pause_rounded);
      expect(rig.plays, 1);
    });

    testWidgets('when another track plays, this card shows play again', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      await tester.pumpWidget(rig.card(rig.first));
      await rig.playback.playQueue([rig.second]);
      await rig.settle(tester);

      expect(_playIcon(tester).icon, Icons.play_arrow_rounded);
      expect(find.byKey(const Key('trackPosition')), findsNothing, reason: 'only the playing card shows the time played');
    });

    testWidgets('the playing card shows the time played and its waveform follows the playing', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final track = rig.first;
      await tester.pumpWidget(rig.card(track));
      await tester.tap(find.byKey(const Key('trackPlayButton')));
      await rig.settle(tester);

      rig.env.player.emitDuration(Duration(milliseconds: track.durationMs!));
      rig.env.player.emitPosition(Duration(milliseconds: track.durationMs! ~/ 2));
      await rig.settle(tester);

      expect(tester.widget<Text>(find.byKey(const Key('trackPosition'))).data, isNotEmpty);
      expect(tester.widget<WaveformView>(find.byType(WaveformView)).progress, closeTo(0.5, 0.01));
    });

    testWidgets('a card that is not playing has an empty waveform', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      await tester.pumpWidget(rig.card(rig.first));
      await rig.settle(tester);
      expect(tester.widget<WaveformView>(find.byType(WaveformView)).progress, 0);
    });

    testWidgets('shows why the track cannot be played, when it is the current one and failed', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      const unknown = Track(id: 'f4e00000-0000-4000-9000-999999999999', title: 'Bài không có', description: '', status: 'READY', ownerId: 'x', waveform: [0.5, 0.5]);
      await tester.pumpWidget(rig.card(unknown, queue: [unknown]));

      await tester.tap(find.byKey(const Key('trackPlayButton')));
      await rig.settle(tester);

      expect(find.byKey(const Key('trackError')), findsOneWidget);
    });
  });

  group('pressing the waveform', () {
    testWidgets('on a track that is not playing starts it and jumps to the place pressed', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final track = rig.first;
      await tester.pumpWidget(rig.card(track));
      await rig.settle(tester);
      final box = tester.getRect(find.byKey(const Key('waveformPaint')));

      await tester.tapAt(Offset(box.left + box.width * 0.5, box.center.dy));
      await rig.settle(tester);

      expect(rig.plays, 1);
      expect(rig.playback.current!.id, track.id);
      expect(rig.env.player.seeks.last.inMilliseconds, closeTo(track.durationMs! * 0.5, track.durationMs! * 0.03));
    });

    testWidgets('on the playing track only seeks, and does not start the list again', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final track = rig.first;
      await tester.pumpWidget(rig.card(track));
      await tester.tap(find.byKey(const Key('trackPlayButton')));
      await rig.settle(tester);
      final box = tester.getRect(find.byKey(const Key('waveformPaint')));

      await tester.tapAt(Offset(box.left + box.width * 0.25, box.center.dy));
      await rig.settle(tester);

      expect(rig.plays, 1);
      expect(rig.env.player.seeks.last.inMilliseconds, closeTo(track.durationMs! * 0.25, track.durationMs! * 0.03));
    });
  });

  group('opening things', () {
    testWidgets('the title and the cover open the track, the author opens the user, the comments open the track', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      await tester.pumpWidget(rig.card(rig.first));
      await rig.settle(tester);

      await tester.tap(find.byKey(const Key('trackTitle')));
      await tester.tap(find.byKey(const Key('trackCover')));
      await tester.tap(find.byKey(const Key('commentCountButton')));
      await tester.tap(find.byKey(const Key('trackAuthor')));

      expect(rig.opens, 3);
      expect(rig.openedUsers, [rig.first.ownerId]);
    });
  });

  group('liking', () {
    testWidgets('pressing the heart likes the track and tells the list the new copy of it', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final track = rig.first;
      await tester.pumpWidget(rig.card(track));
      await rig.settle(tester);

      await tester.tap(find.byKey(const Key('likeButton')));
      await rig.settle(tester);

      expect(rig.changes.single.id, track.id);
      expect(rig.changes.single.isLikedByMe, isTrue);
      expect(rig.changes.single.likeCount, track.likeCount + 1);
      expect(rig.changes.single.title, track.title, reason: 'the rest of the track is the same');
    });

    testWidgets('without a login a press asks to log in', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create(signedIn: false);
      await tester.pumpWidget(rig.card(rig.first));
      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pump();
      expect(rig.loginRequests, 1);
      expect(rig.changes, isEmpty);
    });
  });

  group('the menu of the owner', () {
    testWidgets('is there for the owner when the actions are given, and calls them', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final track = rig.first;
      await tester.pumpWidget(rig.card(track, viewerId: track.ownerId, withMenu: true));

      for (final (key, expected) in [('editAction', 'edit'), ('visibilityAction', 'visibility'), ('deleteAction', 'delete')]) {
        await tester.tap(find.byKey(const Key('trackMenu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(rig.menu.last, expected);
      }
    });

    testWidgets('offers to make a public track private, and a private track public', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final track = rig.first;

      await tester.pumpWidget(rig.card(track, viewerId: track.ownerId, withMenu: true));
      await tester.tap(find.byKey(const Key('trackMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Chuyển sang riêng tư'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.pumpWidget(rig.card(track.copyWith(visibility: 'PRIVATE'), viewerId: track.ownerId, withMenu: true));
      await tester.tap(find.byKey(const Key('trackMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Chuyển sang công khai'), findsOneWidget);
    });

    testWidgets('is not there for anyone else, or when no action is given', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      final track = rig.first;

      await tester.pumpWidget(rig.card(track, viewerId: 'someone-else', withMenu: true));
      expect(find.byKey(const Key('trackMenu')), findsNothing);

      await tester.pumpWidget(rig.card(track, viewerId: track.ownerId));
      expect(find.byKey(const Key('trackMenu')), findsNothing);
    });
  });

  group('hover', () {
    Color? cardColor(WidgetTester tester) {
      final box = tester.widget<AnimatedContainer>(find.byKey(const Key('trackCardBody')));
      return (box.decoration as BoxDecoration?)?.color;
    }

    testWidgets('the card lifts a little under the mouse, and goes back when the mouse leaves', (tester) async {
      TestEnv.window(tester);
      final rig = await _Rig.create();
      await tester.pumpWidget(rig.card(rig.first));
      await rig.settle(tester);
      final resting = cardColor(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(const Key('trackCardBody'))));
      await rig.settle(tester);
      expect(cardColor(tester), isNot(resting));

      await mouse.moveTo(const Offset(1, 1));
      await rig.settle(tester);
      expect(cardColor(tester), resting);
    });
  });

  group('on a phone', () {
    testWidgets('puts the waveform under the title, keeps everything, and does not overflow', (tester) async {
      TestEnv.window(tester, width: 390, height: 900);
      final rig = await _Rig.create();
      final track = rig.first.copyWith(title: 'Một cái tên bài hát rất rất dài ' * 5);
      await tester.pumpWidget(rig.card(track, viewerId: track.ownerId, withMenu: true));
      await rig.settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('trackPlayButton')), findsOneWidget);
      expect(find.byType(WaveformView), findsOneWidget);
      expect(find.byKey(const Key('likeButton')), findsOneWidget);
      expect(find.byKey(const Key('trackMenu')), findsOneWidget);
      final cover = tester.getRect(find.byKey(const Key('trackCover')));
      final waveform = tester.getRect(find.byType(WaveformView));
      expect(waveform.top, greaterThan(cover.bottom), reason: 'under the cover, spanning the card');
    });

    testWidgets('fits 320 px', (tester) async {
      TestEnv.window(tester, width: 320, height: 900);
      final rig = await _Rig.create();
      await tester.pumpWidget(rig.card(rig.first.copyWith(visibility: 'PRIVATE', title: 'Tên dài ' * 20)));
      await rig.settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a card for another track takes its own waveform when the list gives it a new track', (tester) async {
    TestEnv.window(tester);
    final rig = await _Rig.create();
    await tester.pumpWidget(rig.card(rig.first));
    await rig.settle(tester);

    await tester.pumpWidget(rig.card(rig.second));
    await rig.settle(tester);

    expect(find.text(rig.second.title), findsOneWidget);
    expect(find.text(rig.first.title), findsNothing);
  });
}

String formatCountOf(int n) => n < 1000 ? '$n' : '${(n / 1000).toStringAsFixed(1).replaceAll('.', ',')}K';
