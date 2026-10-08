import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lasono_app/screens/player_controls.dart';
import 'package:lasono_app/screens/waveform_view.dart';

import '../fake_player_service.dart';

const _peaks = [0.2, 0.8, 0.5, 1.0];

late FakePlayerService _player;

Future<void> _pump(WidgetTester tester, {List<double>? waveform}) {
  _player = FakePlayerService();
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: PlayerControls(
            player: _player,
            streamUrl: () async => Uri.parse('http://api.test/stream'),
            waveform: waveform,
          ),
        ),
      ),
    ),
  );
}

/// Presses Play, so the player is loaded, and tells it the track is 10 seconds long.
Future<void> _startPlaying(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('playButton')));
  await tester.pumpAndSettle();
  _player.emitDuration(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

WaveformView _view(WidgetTester tester) => tester.widget<WaveformView>(find.byType(WaveformView));

void main() {
  testWidgets('shows no waveform for a track that has none', (WidgetTester tester) async {
    await _pump(tester);

    expect(find.byType(WaveformView), findsNothing);
  });

  testWidgets('shows the waveform of the track', (WidgetTester tester) async {
    await _pump(tester, waveform: _peaks);

    expect(_view(tester).peaks, _peaks);
    expect(_view(tester).progress, 0);
  });

  testWidgets('the played part follows the playback position', (WidgetTester tester) async {
    await _pump(tester, waveform: _peaks);
    await _startPlaying(tester);

    _player.emitPosition(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(_view(tester).progress, closeTo(0.5, 0.001));
  });

  testWidgets('tapping the waveform seeks to that part of the track', (WidgetTester tester) async {
    await _pump(tester, waveform: _peaks);
    await _startPlaying(tester);
    final box = tester.getRect(find.byType(WaveformView));

    await tester.tapAt(Offset(box.left + box.width * 0.25, box.center.dy));
    await tester.pumpAndSettle();

    expect(_player.seeks, [const Duration(milliseconds: 2500)]);
  });

  testWidgets('tapping does nothing before the player knows how long the track is',
      (WidgetTester tester) async {
    await _pump(tester, waveform: _peaks);
    final box = tester.getRect(find.byType(WaveformView));

    await tester.tapAt(Offset(box.left + box.width * 0.25, box.center.dy));
    await tester.pumpAndSettle();

    expect(_player.seeks, isEmpty);
  });
}
