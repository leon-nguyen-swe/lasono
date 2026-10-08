import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/screens/player_controls.dart';

import '../fake_player_service.dart';

Future<void> _pump(
  WidgetTester tester,
  FakePlayerService player,
  Future<Uri> Function() streamUrl,
) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerControls(player: player, streamUrl: streamUrl),
        ),
      ),
    );

void main() {
  testWidgets('asks for the address only when Play is pressed, and only once',
      (tester) async {
    final player = FakePlayerService();
    var asked = 0;
    await _pump(tester, player, () async {
      asked++;
      return Uri.parse('http://api.test/stream?signature=s');
    });
    expect(asked, 0);

    await tester.tap(find.byKey(const Key('playButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playButton'))); // pause
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playButton'))); // play again
    await tester.pumpAndSettle();

    expect(asked, 1);
    expect(player.loaded, [Uri.parse('http://api.test/stream?signature=s')]);
  });

  testWidgets('shows why the address could not be had, and does not play',
      (tester) async {
    final player = FakePlayerService();
    await _pump(tester, player,
        () async => throw const TrackApiException('Track not found'));

    await tester.tap(find.byKey(const Key('playButton')));
    await tester.pumpAndSettle();

    expect(find.text('Track not found'), findsOneWidget);
    expect(player.loaded, isEmpty);
    expect(player.playCalls, 0);
    expect(find.byKey(const Key('playerLoading')), findsNothing);
  });

  testWidgets('tries to ask again at the next Play after a failure',
      (tester) async {
    final player = FakePlayerService();
    var fail = true;
    await _pump(tester, player, () async {
      if (fail) throw const TrackApiException('Cannot reach the server');
      return Uri.parse('http://api.test/stream?signature=s');
    });
    await tester.tap(find.byKey(const Key('playButton')));
    await tester.pumpAndSettle();

    fail = false;
    await tester.tap(find.byKey(const Key('playButton')));
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach the server'), findsNothing);
    expect(player.playCalls, 1);
  });
}
