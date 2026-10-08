import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/auth/session_controller.dart';
import 'package:lasono_app/player_service.dart';
import 'package:lasono_app/screens/track_list_screen.dart';
import 'package:lasono_app/screens/waveform_view.dart';

import '../fake_auth_server.dart';
import '../fake_player_service.dart';

Map<String, dynamic> _item(int i) => {
      'id': 'id-$i',
      'title': 'Track $i',
      'description': '',
      'status': 'READY',
    };

http.Response _page(Iterable<int> ids, {String? next}) => http.Response(
      jsonEncode({'items': ids.map(_item).toList(), 'nextCursor': next}),
      200,
      headers: {'content-type': 'application/json'},
    );

typedef _Route = FutureOr<http.Response> Function();

/// A fake server: answers GET /api/v1/tracks from [routes], keyed by the
/// request's cursor (null for the first page), and records every cursor asked for.
class _Server {
  _Server(this.routes);

  final Map<String?, _Route> routes;
  final cursors = <String?>[];

  /// The ids asked for with GET /api/v1/tracks/{id}, which also carries the waveform.
  final details = <String>[];

  late final TrackApi api = TrackApi(
    baseUrl: 'http://api.test',
    client: MockClient((request) async {
      if (request.url.pathSegments.length > 3) {
        final id = request.url.pathSegments.last;
        details.add(id);
        return http.Response(
          jsonEncode({
            'id': id,
            'title': 'Track',
            'description': '',
            'status': 'READY',
            'mimeType': 'audio/mpeg',
            'durationSeconds': 3.0,
            'waveform': [0.2, 0.8, 0.5],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final cursor = request.url.queryParameters['cursor'];
      cursors.add(cursor);
      return routes[cursor]!();
    }),
  );
}

/// Shows the list. The user is logged in unless a test passes another session.
Future<void> _pump(
  WidgetTester tester,
  _Server server, {
  PlayerService? player,
  SessionController? session,
}) async {
  final signedIn = session ?? await FakeAuthServer().signedInSession();
  await tester.pumpWidget(
    MaterialApp(
      home: TrackListScreen(session: signedIn, api: server.api, player: player),
    ),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) =>
    tester.dragUntilVisible(finder, find.byType(ListView), const Offset(0, -300));

/// How many rows the list has, built or not (tracks plus an optional footer).
int _rowCount(WidgetTester tester) {
  final list = tester.widget<ListView>(find.byType(ListView));
  return (list.childrenDelegate as SliverChildBuilderDelegate).estimatedChildCount!;
}

void main() {
  group('first page', () {
    testWidgets('shows a spinner while it loads, then the tracks',
        (WidgetTester tester) async {
      final gate = Completer<http.Response>();
      final server = _Server({null: () => gate.future});

      await _pump(tester, server);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete(_page([0, 1, 2]));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Track 0'), findsOneWidget);
      expect(find.text('Track 2'), findsOneWidget);
    });

    testWidgets('asks for the first page without a cursor',
        (WidgetTester tester) async {
      final server = _Server({null: () => _page([0, 1, 2])});

      await _pump(tester, server);
      await tester.pumpAndSettle();

      expect(server.cursors, [null]);
    });

    testWidgets('shows a message when there are no tracks',
        (WidgetTester tester) async {
      final server = _Server({null: () => _page([])});

      await _pump(tester, server);
      await tester.pumpAndSettle();

      expect(find.text('No tracks yet'), findsOneWidget);
    });

    testWidgets('shows the error and a Retry button when it fails, and Retry loads it',
        (WidgetTester tester) async {
      var failures = 1;
      final server = _Server({
        null: () {
          if (failures-- > 0) throw http.ClientException('boom');
          return _page([0, 1, 2]);
        },
      });

      await _pump(tester, server);
      await tester.pumpAndSettle();

      expect(find.text('Cannot reach the server'), findsOneWidget);

      await tester.tap(find.byKey(const Key('retryButton')));
      await tester.pumpAndSettle();

      expect(find.text('Track 0'), findsOneWidget);
      expect(find.text('Cannot reach the server'), findsNothing);
      expect(server.cursors, [null, null]);
    });

    testWidgets('shows the duration of a ready track and dashes while it is processing',
        (WidgetTester tester) async {
      final server = _Server({
        null: () => http.Response(
              jsonEncode({
                'items': [
                  {..._item(0), 'status': 'READY', 'durationSeconds': 185.0},
                  {..._item(1), 'status': 'PROCESSING', 'durationSeconds': null},
                ],
                'nextCursor': null,
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
      });

      await _pump(tester, server);
      await tester.pumpAndSettle();

      expect(find.text('3:05'), findsOneWidget);
      expect(find.text('--:--'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget,
          reason: 'only the processing track has an hourglass');
    });
  });

  group('next pages', () {
    final firstPage = List.generate(30, (i) => i);

    testWidgets('scrolling to the end loads the next page with the cursor and appends it',
        (WidgetTester tester) async {
      final server = _Server({
        null: () => _page(firstPage, next: 'c1'),
        'c1': () => _page([30, 31, 32, 33, 34]),
      });
      await _pump(tester, server);
      await tester.pumpAndSettle();
      expect(server.cursors, [null]);

      await _scrollTo(tester, find.text('Track 34'));
      await tester.pumpAndSettle();

      expect(server.cursors, [null, 'c1']);
      expect(find.text('Track 34'), findsOneWidget);
      expect(_rowCount(tester), 35);
    });

    testWidgets('does not ask for more once the last page has been loaded',
        (WidgetTester tester) async {
      final server = _Server({null: () => _page(firstPage)});
      await _pump(tester, server);
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('Track 29'));
      await tester.pumpAndSettle();

      expect(server.cursors, [null]);
    });

    testWidgets('does not ask for the same page twice while it is loading',
        (WidgetTester tester) async {
      final gate = Completer<http.Response>();
      final server = _Server({
        null: () => _page(firstPage, next: 'c1'),
        'c1': () => gate.future,
      });
      await _pump(tester, server);
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('Track 29'));
      // Keep scrolling at the bottom while page 2 is still loading.
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pump();
      }
      expect(server.cursors, [null, 'c1']);

      gate.complete(_page([30, 31]));
      await tester.pumpAndSettle();

      expect(server.cursors, [null, 'c1']);
      expect(_rowCount(tester), 32);
    });

    testWidgets('a failing page keeps the loaded tracks and Retry loads it again',
        (WidgetTester tester) async {
      var failures = 1;
      final server = _Server({
        null: () => _page(firstPage, next: 'c1'),
        'c1': () {
          if (failures-- > 0) throw http.ClientException('boom');
          return _page([30, 31]);
        },
      });
      await _pump(tester, server);
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.byKey(const Key('retryButton')));
      await tester.pumpAndSettle();

      expect(find.text('Cannot reach the server'), findsOneWidget);
      expect(find.text('Track 29'), findsOneWidget);

      await tester.tap(find.byKey(const Key('retryButton')));
      await tester.pumpAndSettle();

      expect(server.cursors, [null, 'c1', 'c1']);
      expect(find.text('Cannot reach the server'), findsNothing);
      expect(_rowCount(tester), 32);
    });

    testWidgets('ignores tracks that are already in the list',
        (WidgetTester tester) async {
      final server = _Server({
        null: () => _page(firstPage, next: 'c1'),
        'c1': () => _page([29, 30, 31]),
      });
      await _pump(tester, server);
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('Track 31'));
      await tester.pumpAndSettle();

      expect(_rowCount(tester), 32);
    });

    testWidgets('keeps loading pages until the list fills the screen',
        (WidgetTester tester) async {
      // Four short rows do not fill the screen, so there is nothing to scroll.
      final server = _Server({
        null: () => _page([0, 1, 2, 3], next: 'c1'),
        'c1': () => _page([4, 5, 6, 7], next: 'c2'),
        'c2': () => _page([8, 9, 10, 11]),
      });

      await _pump(tester, server);
      await tester.pumpAndSettle();

      expect(server.cursors, [null, 'c1', 'c2']);
      expect(find.text('Track 0'), findsOneWidget);
    });
  });

  group('navigation', () {
    final firstPage = List.generate(30, (i) => i);

    testWidgets('tapping a track opens its player, which streams from the API',
        (WidgetTester tester) async {
      final player = FakePlayerService();
      final server = _Server({null: () => _page([0, 1, 2])});
      await _pump(tester, server, player: player);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Track 1'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Track 1'), findsOneWidget);
      // The list does not carry the waveform, so the player fetches the track once to draw it.
      expect(server.details, ['id-1']);
      expect(find.byType(WaveformView), findsOneWidget);

      await tester.tap(find.byKey(const Key('playButton')));
      await tester.pumpAndSettle();

      expect(
        player.loaded,
        [Uri.parse('http://api.test/api/v1/tracks/id-1/stream')],
      );
    });

    testWidgets('going back keeps the list and its scroll position without asking the server again',
        (WidgetTester tester) async {
      final server = _Server({
        null: () => _page(firstPage, next: 'c1'),
        'c1': () => _page([30, 31]),
      });
      await _pump(tester, server, player: FakePlayerService());
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('Track 12'));
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('Track 12'));

      await tester.tap(find.text('Track 12'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('Track 12')), before);
      expect(server.cursors, [null]);
    });

    testWidgets('leaving the player stops playback', (WidgetTester tester) async {
      final player = FakePlayerService();
      final server = _Server({null: () => _page([0, 1, 2])});
      await _pump(tester, server, player: player);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Track 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playButton')));
      await tester.pumpAndSettle();
      final stopsBefore = player.stopCalls;

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(player.stopCalls, greaterThan(stopsBefore));
    });

    testWidgets('the upload action opens the upload form',
        (WidgetTester tester) async {
      final server = _Server({null: () => _page([0, 1, 2])});
      await _pump(tester, server, player: FakePlayerService());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('uploadAction')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chooseFileButton')), findsOneWidget);
    });

    testWidgets('returning from the upload form reloads the list from the first page',
        (WidgetTester tester) async {
      var loads = 0;
      final server = _Server({
        null: () => loads++ == 0 ? _page([0, 1]) : _page([99, 0, 1]),
      });
      await _pump(tester, server, player: FakePlayerService());
      await tester.pumpAndSettle();
      expect(find.text('Track 99'), findsNothing);

      await tester.tap(find.byKey(const Key('uploadAction')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(server.cursors, [null, null]);
      expect(find.text('Track 99'), findsOneWidget);
    });
  });
}
