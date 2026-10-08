import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/screens/track_list_screen.dart';

import '../fake_auth_server.dart';
import '../fake_player_service.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

const _mine = {
  'id': 't1',
  'ownerId': 'u-1',
  'title': 'Mine',
  'description': '',
  'visibility': 'PUBLIC',
  'status': 'READY',
  'durationSeconds': 3.0,
  'waveform': [0.2, 0.8],
};

/// A list with one track of the fake account. After a DELETE the list is empty.
class _Tracks {
  int listCalls = 0;
  bool deleted = false;

  late final TrackApi api = TrackApi(
    baseUrl: 'http://api.test',
    client: MockClient((request) async {
      if (request.method == 'DELETE') {
        deleted = true;
        return http.Response('', 204);
      }
      if (request.url.path == '/api/v1/tracks') {
        listCalls++;
        return _json({'items': deleted ? [] : [_mine], 'nextCursor': null}, 200);
      }
      return _json(_mine, 200);
    }),
  );
}

void main() {
  testWidgets('loads the list again after the owner deleted a track in the player',
      (tester) async {
    final tracks = _Tracks();
    final session = await FakeAuthServer().signedInSession();
    await tester.pumpWidget(MaterialApp(
      home: TrackListScreen(session: session, api: tracks.api, player: FakePlayerService()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mine'), findsOneWidget);

    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteAction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeleteButton')));
    await tester.pumpAndSettle();

    expect(tracks.listCalls, 2);
    expect(find.text('Mine'), findsNothing);
    expect(find.text('No tracks yet'), findsOneWidget);
  });

  testWidgets('does not load the list again when the player is left without a change',
      (tester) async {
    final tracks = _Tracks();
    final session = await FakeAuthServer().signedInSession();
    await tester.pumpWidget(MaterialApp(
      home: TrackListScreen(session: session, api: tracks.api, player: FakePlayerService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(tracks.listCalls, 1);
  });
}
