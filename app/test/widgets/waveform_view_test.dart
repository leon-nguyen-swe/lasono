import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/theme/theme.dart';
import 'package:lasono_app/widgets/waveform_view.dart';

import '../support/test_harness.dart';

final _c = AppColors.dark;

Widget _wrap(Widget child, {double width = 400}) => themed(Center(child: SizedBox(width: width, child: child)));

RenderObject _paint(WidgetTester tester) => tester.renderObject(find.byKey(const Key('waveformPaint')));

const _markers = [
  WaveformMarker(id: 'm1', positionMs: 10000, authorId: 'u1', authorName: 'Sơn Tùng', text: 'Đoạn này hay quá!'),
  WaveformMarker(id: 'm2', positionMs: 50000, authorId: 'u2', authorName: 'Đen Vâu', text: 'Beat drop đỉnh thật'),
];

Future<TestGesture> _mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(1, 1));
  addTearDown(gesture.removePointer);
  return gesture;
}

void main() {
  group('the bars', () {
    testWidgets('are drawn one for each peak', (tester) async {
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.2, 0.8, 0.5, 1.0, 0.1])));
      expect(_paint(tester), paintsExactlyCountTimes(#drawRRect, 5));
    });

    testWidgets('up to the progress are in the played colour, and the rest in the other', (tester) async {
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.2, 0.8, 0.5, 1.0], progress: 0.5)));

      expect(
        _paint(tester),
        paints
          ..rrect(color: _c.waveformPlayed)
          ..rrect(color: _c.waveformPlayed)
          ..rrect(color: _c.waveformUnplayed)
          ..rrect(color: _c.waveformUnplayed),
      );
    });

    testWidgets('nothing is drawn for a track without peaks', (tester) async {
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [])));
      expect(_paint(tester), paintsNothing);
    });

    test('a loud peak is a taller bar than a quiet one, a silent one is still a thin line, and none is taller than the view', () {
      final painter = WaveformBarsPainter(
        peaks: const [0.0, 0.1, 1.0, 5.0],
        progress: 0,
        playedColor: _c.waveformPlayed,
        restColor: _c.waveformUnplayed,
        hoverColor: _c.waveformHover,
        lineColor: _c.textPrimary,
      );
      final canvas = TestRecordingCanvas();

      painter.paint(canvas, const Size(400, 100));

      final bars = canvas.invocations
          .map((call) => call.invocation)
          .where((call) => call.memberName == #drawRRect)
          .map((call) => call.positionalArguments.first as RRect)
          .toList();
      expect(bars, hasLength(4));
      expect(bars[2].height, greaterThan(bars[1].height));
      expect(bars[0].height, WaveformBarsPainter.minBarHeight);
      expect(bars.every((b) => b.height <= 100), isTrue);
    });

    testWidgets('keep the colour they had when the theme is light', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Center(child: SizedBox(width: 400, child: WaveformView(peaks: [0.5, 0.5], progress: 0.5)))),
        ),
      );
      expect(_paint(tester), paints..rrect(color: AppColors.light.waveformPlayed)..rrect(color: AppColors.light.waveformUnplayed));
    });
  });

  group('pressing', () {
    testWidgets('asks to seek to that fraction of the width', (tester) async {
      final seeks = <double>[];
      await tester.pumpWidget(_wrap(WaveformView(peaks: const [0.5, 0.5, 0.5, 0.5], onSeek: seeks.add)));
      final box = tester.getRect(find.byKey(const Key('waveformPaint')));

      await tester.tapAt(Offset(box.left + box.width * 0.25, box.center.dy));

      expect(seeks.single, closeTo(0.25, 0.01));
    });

    testWidgets('without a seek callback the view is read only', (tester) async {
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5])));
      await tester.tap(find.byKey(const Key('waveformPaint')));
      expect(tester.takeException(), isNull);
    });
  });

  group('the pointer', () {
    testWidgets('shows the time a press would jump to, and a line', (tester) async {
      final mouse = await _mouse(tester);
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5, 0.5, 0.5], durationMs: 60000)));
      final box = tester.getRect(find.byKey(const Key('waveformPaint')));

      await mouse.moveTo(Offset(box.left + box.width * 0.5, box.center.dy));
      await tester.pump();

      expect(find.byKey(const Key('hoverTime')), findsOneWidget);
      expect(find.text('0:30'), findsOneWidget);
      expect(_paint(tester), paints..line());

      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(find.byKey(const Key('hoverTime')), findsNothing);
    });

    testWidgets('colours the stretch between the playing and the pointer, when the pointer is ahead', (tester) async {
      final mouse = await _mouse(tester);
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5, 0.5, 0.5], progress: 0.25, durationMs: 40000)));
      final box = tester.getRect(find.byKey(const Key('waveformPaint')));

      await mouse.moveTo(Offset(box.left + box.width * 0.76, box.center.dy));
      await tester.pump();

      expect(
        _paint(tester),
        paints
          ..rrect(color: _c.waveformPlayed)
          ..rrect(color: _c.waveformHover)
          ..rrect(color: _c.waveformHover)
          ..rrect(color: _c.waveformUnplayed),
      );
    });

    testWidgets('shows no time when the length is not known', (tester) async {
      final mouse = await _mouse(tester);
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5])));
      await mouse.moveTo(tester.getCenter(find.byKey(const Key('waveformPaint'))));
      await tester.pump();
      expect(find.byKey(const Key('hoverTime')), findsNothing);
    });
  });

  group('the comments', () {
    testWidgets('are avatars under the bars, each at its place in the track', (tester) async {
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5, 0.5, 0.5], durationMs: 100000, markers: _markers)));
      final box = tester.getRect(find.byKey(const Key('waveformPaint')));

      final first = tester.getCenter(find.byKey(const Key('marker-m1')));
      final second = tester.getCenter(find.byKey(const Key('marker-m2')));

      expect(first.dx, closeTo(box.left + box.width * 0.10, 12));
      expect(second.dx, closeTo(box.left + box.width * 0.50, 12));
      expect(first.dy, greaterThan(box.bottom), reason: 'below the bars');
    });

    testWidgets('are not shown when the length of the track is not known: there is no place for them', (tester) async {
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5], markers: _markers)));
      expect(find.byKey(const Key('marker-m1')), findsNothing);
    });

    testWidgets('a comment at the very start or the very end stays inside the view', (tester) async {
      const edge = [
        WaveformMarker(id: 'a', positionMs: 0, authorId: 'u1', authorName: 'A', text: 'đầu'),
        WaveformMarker(id: 'b', positionMs: 100000, authorId: 'u2', authorName: 'B', text: 'cuối'),
      ];
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5], durationMs: 100000, markers: edge)));
      final box = tester.getRect(find.byType(WaveformView));

      expect(tester.getTopLeft(find.byKey(const Key('marker-a'))).dx, greaterThanOrEqualTo(box.left));
      expect(tester.getTopRight(find.byKey(const Key('marker-b'))).dx, lessThanOrEqualTo(box.right + 0.5));
    });

    testWidgets('close together they become one avatar with how many more there are', (tester) async {
      const crowded = [
        WaveformMarker(id: 'a', positionMs: 10000, authorId: 'u1', authorName: 'A', text: 'một'),
        WaveformMarker(id: 'b', positionMs: 11000, authorId: 'u2', authorName: 'B', text: 'hai'),
        WaveformMarker(id: 'c', positionMs: 11500, authorId: 'u3', authorName: 'C', text: 'ba'),
        WaveformMarker(id: 'd', positionMs: 80000, authorId: 'u4', authorName: 'D', text: 'xa'),
      ];
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5], durationMs: 100000, markers: crowded)));

      expect(find.byKey(const Key('marker-a')), findsOneWidget);
      expect(find.byKey(const Key('marker-b')), findsNothing);
      expect(find.byKey(const Key('marker-d')), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('show their text when the pointer is on the avatar, and hide it when it leaves', (tester) async {
      final mouse = await _mouse(tester);
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5], durationMs: 100000, markers: _markers)));
      expect(find.byKey(const Key('markerBubble')), findsNothing);

      await mouse.moveTo(tester.getCenter(find.byKey(const Key('marker-m2'))));
      await tester.pump();

      expect(find.byKey(const Key('markerBubble')), findsOneWidget);
      expect(find.textContaining('Đen Vâu'), findsWidgets);
      expect(find.textContaining('Beat drop đỉnh thật'), findsOneWidget);
      expect(find.textContaining('0:50'), findsOneWidget);

      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(find.byKey(const Key('markerBubble')), findsNothing);
    });

    testWidgets('show their text by themselves when the playing reaches them, and not when it is far away', (tester) async {
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5], durationMs: 100000, markers: _markers, progress: 0.101)));
      expect(find.textContaining('Đoạn này hay quá!'), findsOneWidget, reason: 'at 10.1 s, a comment at 10 s');

      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5], durationMs: 100000, markers: _markers, progress: 0.30)));
      expect(find.byKey(const Key('markerBubble')), findsNothing);

      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5], durationMs: 100000, markers: _markers, progress: 0)));
      expect(find.byKey(const Key('markerBubble')), findsNothing, reason: 'nothing has played yet');
    });

    testWidgets('pressing an avatar reports its comment, and does not seek', (tester) async {
      final tapped = <String>[];
      final seeks = <double>[];
      await tester.pumpWidget(_wrap(WaveformView(
        peaks: const [0.5, 0.5],
        durationMs: 100000,
        markers: _markers,
        onSeek: seeks.add,
        onMarkerTap: (m) => tapped.add(m.id),
      )));

      await tester.tap(find.byKey(const Key('marker-m1')));

      expect(tapped, ['m1']);
      expect(seeks, isEmpty);
    });

    testWidgets('the room for them is only taken when there are some', (tester) async {
      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5], height: 80)));
      expect(tester.getSize(find.byType(WaveformView)).height, 80);

      await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5], height: 80, durationMs: 1000, markers: _markers)));
      expect(tester.getSize(find.byType(WaveformView)).height, greaterThan(80));
    });
  });

  testWidgets('says how far it is, for a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(const WaveformView(peaks: [0.5, 0.5], progress: 0.42)));
    expect(find.bySemanticsLabel('Dạng sóng của bài hát'), findsOneWidget);
    expect(tester.getSemantics(find.byType(WaveformView)).value, '42%');
    handle.dispose();
  });
}
