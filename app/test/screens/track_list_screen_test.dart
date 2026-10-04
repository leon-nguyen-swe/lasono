import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/screens/track_list_screen.dart';

Map<String, dynamic> _item(int i) => {
      'id': 'id-$i',
      'title': 'Track $i',
      'description': '',
      'status': 'PROCESSING',
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

  late final TrackApi api = TrackApi(
    baseUrl: 'http://api.test',
    client: MockClient((request) async {
      final cursor = request.url.queryParameters['cursor'];
      cursors.add(cursor);
      return routes[cursor]!();
    }),
  );
}

Future<void> _pump(WidgetTester tester, _Server server) =>
    tester.pumpWidget(MaterialApp(home: TrackListScreen(api: server.api)));

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
}
