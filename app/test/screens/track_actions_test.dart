import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/data/fake_flags.dart';

import '../support/test_harness.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

Map<String, Object?> _track(String status) => {
      'id': 't-1',
      'title': 'Bài mới',
      'description': '',
      'status': status,
      'ownerId': 'u-1',
      'visibility': 'PUBLIC',
      'mimeType': status == 'READY' ? 'audio/mpeg' : null,
      'durationSeconds': status == 'READY' ? 61.0 : null,
      'createdAt': '2026-10-08T12:00:00Z',
    };

/// A server where one track of the list is still being processed, and is ready from the second look at it.
class _Backend {
  int looks = 0;

  late final MockClient client = MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/v1/tracks') return _json({'items': [_track('PROCESSING')], 'nextCursor': null});
    if (path == '/api/v1/tracks/t-1') {
      looks++;
      return _json(_track(looks >= 2 ? 'READY' : 'PROCESSING'));
    }
    return http.Response('', 404);
  });
}

void main() {
  testWidgets('a track of a list that is being processed updates itself when it is ready, and then stops asking', (tester) async {
    TestEnv.window(tester, width: 1280, height: 1400);
    final backend = _Backend();
    final env = await TestEnv.create(signedIn: true, client: backend.client, flags: const FakeFlags());
    await tester.pumpWidget(env.app(location: '/'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('trackProcessing')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // first look: still being processed
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('trackProcessing')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // second look: ready
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('trackProcessing')), findsNothing);
    final looksWhenReady = backend.looks; // the two looks of the tile, and the one of the waveform that came with it

    await tester.pump(const Duration(seconds: 9));
    expect(backend.looks, looksWhenReady, reason: 'a ready track is not asked about again');
  });

  testWidgets('a failed look is not shown to the user, and the next one asks again', (tester) async {
    TestEnv.window(tester, width: 1280, height: 1400);
    var calls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/tracks') return _json({'items': [_track('PROCESSING')], 'nextCursor': null});
      if (request.url.path != '/api/v1/tracks/t-1') return http.Response('', 404);
      calls++;
      return calls == 1 ? http.Response('', 500) : _json(_track('READY'));
    });
    final env = await TestEnv.create(signedIn: true, client: client, flags: const FakeFlags());
    await tester.pumpWidget(env.app(location: '/'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('trackProcessing')), findsOneWidget);
    expect(find.byKey(const Key('pagedError')), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('trackProcessing')), findsNothing);
  });
}
