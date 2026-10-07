import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lasono_app/screens/waveform_view.dart';

const _played = Color(0xFF112233);
const _rest = Color(0xFFAABBCC);

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.light(primary: _played, outlineVariant: _rest),
      ),
      home: Scaffold(body: Center(child: SizedBox(width: 400, child: child))),
    );

RenderObject _render(WidgetTester tester) =>
    tester.renderObject(find.descendant(
      of: find.byType(WaveformView),
      matching: find.byType(CustomPaint),
    ));

void main() {
  testWidgets('draws one bar for each peak', (WidgetTester tester) async {
    await tester.pumpWidget(_app(const WaveformView(peaks: [0.2, 0.8, 0.5, 1.0, 0.1])));

    expect(_render(tester), paintsExactlyCountTimes(#drawRRect, 5));
  });

  testWidgets('draws the bars up to the progress in the played colour',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(const WaveformView(peaks: [0.2, 0.8, 0.5, 1.0], progress: 0.5)),
    );

    expect(
      _render(tester),
      paints
        ..rrect(color: _played)
        ..rrect(color: _played)
        ..rrect(color: _rest)
        ..rrect(color: _rest),
    );
  });

  test('a loud peak is a taller bar than a quiet one, and no bar is taller than the view', () {
    const painter = WaveformPainter(
      peaks: [0.1, 1.0],
      progress: 0,
      playedColor: _played,
      restColor: _rest,
    );
    final canvas = TestRecordingCanvas();

    painter.paint(canvas, const Size(400, 100));

    final bars = canvas.invocations
        .map((call) => call.invocation)
        .where((call) => call.memberName == #drawRRect)
        .map((call) => call.positionalArguments.first as RRect)
        .toList();
    expect(bars, hasLength(2));
    expect(bars[1].height, greaterThan(bars[0].height));
    expect(bars[1].height, lessThanOrEqualTo(100));
  });

  testWidgets('draws nothing for a track without peaks', (WidgetTester tester) async {
    await tester.pumpWidget(_app(const WaveformView(peaks: [])));

    expect(_render(tester), paintsNothing);
  });

  testWidgets('tapping asks to seek to that fraction of the width', (WidgetTester tester) async {
    final seeks = <double>[];
    await tester.pumpWidget(
      _app(WaveformView(peaks: const [0.5, 0.5, 0.5, 0.5], onSeek: seeks.add)),
    );
    final box = tester.getRect(find.byType(WaveformView));

    await tester.tapAt(Offset(box.left + box.width * 0.25, box.center.dy));

    expect(seeks, hasLength(1));
    expect(seeks.single, closeTo(0.25, 0.01));
  });
}
