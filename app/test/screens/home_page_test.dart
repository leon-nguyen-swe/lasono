import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/data/fake_flags.dart';

import '../fake_auth_server.dart';
import '../support/test_harness.dart';

Map<String, Object?> _track(String id, String title) => {
      'id': id,
      'title': title,
      'description': '',
      'status': 'READY',
      'ownerId': 'owner-1',
      'visibility': 'PUBLIC',
      'mimeType': 'audio/mpeg',
      'durationSeconds': 120.0,
      'createdAt': '2026-10-07T12:00:00Z',
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// The track list of the backend, in pages: the first has [a] and [b] and points to a second with [c].
class _Backend {
  final listRequests = <String?>[];
  Completer<void>? secondPageGate;
  bool failList = false;
  bool empty = false;

  late final MockClient client = MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/v1/tracks') {
      final cursor = request.url.queryParameters['cursor'];
      listRequests.add(cursor);
      if (failList) return http.Response('', 500);
      if (empty) return _json({'items': [], 'nextCursor': null});
      if (cursor == null) {
        return _json({
          'items': [_track('t-a', 'Bài A'), _track('t-b', 'Bài B')],
          'nextCursor': 'second',
        });
      }
      await secondPageGate?.future;
      return _json({'items': [_track('t-c', 'Bài C')], 'nextCursor': null});
    }
    if (path.endsWith('/stream-url')) {
      return _json({'url': '/api/v1/tracks/x/stream'});
    }
    return http.Response('', 404);
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late _Backend backend;

  Future<TestEnv> open(WidgetTester tester, {bool signedIn = false, double width = 1280, double height = 1400}) async {
    TestEnv.window(tester, width: width, height: height);
    final env = await TestEnv.create(signedIn: signedIn, client: backend.client, flags: const FakeFlags());
    await tester.pumpWidget(env.app(location: '/'));
    await _settle(tester);
    return env;
  }

  setUp(() => backend = _Backend());

  testWidgets('shows skeletons while the first page is on its way, then the tracks', (tester) async {
    TestEnv.window(tester, width: 1280, height: 1400);
    final gate = Completer<void>();
    final slow = MockClient((request) async {
      await gate.future;
      return backend.client.get(request.url);
    });
    final env = await TestEnv.create(client: slow, flags: const FakeFlags());
    await tester.pumpWidget(env.app(location: '/'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('trackCardSkeleton')), findsWidgets);
    expect(find.text('Bài A'), findsNothing);

    gate.complete();
    await _settle(tester);

    expect(find.byKey(const Key('trackCardSkeleton')), findsNothing);
    expect(find.text('Bài A'), findsOneWidget);
    expect(find.text('Bài B'), findsOneWidget);
  });

  testWidgets('shows the tracks in the order the server gave them', (tester) async {
    await open(tester);

    expect(find.byKey(const Key('homeTitle')), findsOneWidget);
    final a = tester.getTopLeft(find.text('Bài A')).dy;
    final b = tester.getTopLeft(find.text('Bài B')).dy;
    expect(a, lessThan(b));
  });

  testWidgets('asks for the next page by itself when the first one does not fill the window, and shows all', (tester) async {
    await open(tester);

    expect(backend.listRequests, [null, 'second']);
    expect(find.text('Bài C'), findsOneWidget);
  });

  testWidgets('a list with no track shows the empty state, and its button leads to the upload page', (tester) async {
    backend.empty = true;
    await open(tester, signedIn: true);

    expect(find.byKey(const Key('homeEmpty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('uploadFromEmpty')));
    await _settle(tester);
    expect(find.byKey(const Key('homeEmpty')), findsNothing);
  });

  testWidgets('a failure shows an error, and the retry button asks again and shows the tracks', (tester) async {
    backend.failList = true;
    await open(tester);
    expect(find.byKey(const Key('pagedError')), findsOneWidget);
    expect(find.text('Bài A'), findsNothing);

    backend.failList = false;
    await tester.tap(find.byKey(const Key('retryButton')));
    await _settle(tester);

    expect(find.byKey(const Key('pagedError')), findsNothing);
    expect(find.text('Bài A'), findsOneWidget);
  });

  testWidgets('playing a track makes the list the queue, and a page loaded afterwards joins it', (tester) async {
    backend.secondPageGate = Completer<void>();
    await open(tester);
    expect(find.text('Bài C'), findsNothing, reason: 'the second page is still on its way');

    await tester.tap(find.byKey(const Key('trackPlayButton')).first);
    await _settle(tester);
    expect(find.descendant(of: find.byKey(const Key('playerBar')), matching: find.text('Bài A')), findsOneWidget);

    backend.secondPageGate!.complete();
    await _settle(tester);
    await tester.tap(find.byKey(const Key('nextButton')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('nextButton')));
    await _settle(tester);

    expect(find.descendant(of: find.byKey(const Key('playerBar')), matching: find.text('Bài C')), findsOneWidget);
  });

  testWidgets('the list is read again when somebody logs in, because they may see more', (tester) async {
    final env = await (() async {
      TestEnv.window(tester, width: 1280, height: 1400);
      final server = FakeAuthServer();
      final env = await TestEnv.create(authServer: server, client: backend.client, flags: const FakeFlags());
      await tester.pumpWidget(env.app(location: '/'));
      await _settle(tester);
      return env;
    })();
    final before = backend.listRequests.length;

    await env.session.login(email: 'ann@example.com', password: 'secret pass');
    await _settle(tester);

    expect(backend.listRequests.length, greaterThan(before));
    expect(backend.listRequests.where((c) => c == null).length, 2, reason: 'the first page twice');
  });

  testWidgets('fits a phone without overflow', (tester) async {
    await open(tester, width: 390, height: 800);
    expect(tester.takeException(), isNull);
  });
}
