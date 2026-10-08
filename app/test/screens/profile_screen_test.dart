import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/profile_api.dart';
import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/auth/session_controller.dart';
import 'package:lasono_app/screens/profile_screen.dart';
import 'package:lasono_app/screens/track_player_screen.dart';

import '../fake_auth_server.dart';
import '../fake_player_service.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _track(String id, String owner) => {
      'id': id,
      'ownerId': owner,
      'title': 'Song $id',
      'description': '',
      'visibility': 'PUBLIC',
      'status': 'READY',
      'durationSeconds': 3.0,
      'waveform': [0.2, 0.8],
    };

/// The server of the profile pages: Bob (u-2) with three tracks in two pages,
/// Ann (u-1, the fake account) with one track she may delete, and Cy (u-3) with none.
class _Server {
  final requests = <String>[];
  final bodies = <String, Object?>{};
  http.Response Function()? onProfile;
  http.Response Function()? onRename;
  bool annTrackDeleted = false;

  late final MockClient client = MockClient((request) async {
    final route = '${request.method} ${request.url.path}';
    requests.add(route);
    if (request.body.isNotEmpty) bodies[route] = jsonDecode(request.body);
    final cursor = request.url.queryParameters['cursor'];
    switch (route) {
      case 'GET /api/v1/users/u-2':
        return onProfile?.call() ?? _json({'userId': 'u-2', 'displayName': 'Bob'}, 200);
      case 'GET /api/v1/users/u-1':
        return _json({'userId': 'u-1', 'displayName': 'Ann'}, 200);
      case 'GET /api/v1/users/u-3':
        return _json({'userId': 'u-3', 'displayName': 'Cy'}, 200);
      case 'GET /api/v1/users/u-2/tracks':
        final all = [_track('b1', 'u-2'), _track('b2', 'u-2'), _track('b3', 'u-2')];
        return cursor == null
            ? _json({'items': all.take(2).toList(), 'nextCursor': 'c2'}, 200)
            : _json({'items': all.skip(2).toList(), 'nextCursor': null}, 200);
      case 'GET /api/v1/users/u-1/tracks':
        return _json({
          'items': annTrackDeleted ? [] : [_track('a1', 'u-1')],
          'nextCursor': null,
        }, 200);
      case 'GET /api/v1/users/u-3/tracks':
        return _json({'items': [], 'nextCursor': null}, 200);
      case 'PATCH /api/v1/users/me':
        return onRename?.call() ??
            _json({'userId': 'u-1', 'email': 'ann@example.com', 'displayName': 'Ann B.'}, 200);
      case 'DELETE /api/v1/tracks/a1':
        annTrackDeleted = true;
        return http.Response('', 204);
    }
    if (request.url.path.startsWith('/api/v1/tracks/')) {
      final id = request.url.pathSegments.last;
      return _json(_track(id, id.startsWith('a') ? 'u-1' : 'u-2'), 200);
    }
    return http.Response('', 404);
  });

  int count(String route) => requests.where((r) => r == route).length;

  TrackApi get trackApi => TrackApi(baseUrl: 'http://api.test', client: client);
  ProfileApi get profileApi => ProfileApi(baseUrl: 'http://api.test', client: client);
}

ProfileScreen _screen(_Server server, SessionController session, String userId) =>
    ProfileScreen(
      userId: userId,
      session: session,
      trackApi: server.trackApi,
      profileApi: server.profileApi,
      player: FakePlayerService(),
    );

Future<void> _pump(
  WidgetTester tester,
  _Server server,
  SessionController session, {
  String userId = 'u-2',
}) async {
  await tester.pumpWidget(MaterialApp(home: _screen(server, session, userId)));
  await tester.pumpAndSettle();
}

void main() {
  late FakeAuthServer auth;
  late _Server server;

  setUp(() {
    auth = FakeAuthServer();
    server = _Server();
  });

  testWidgets('shows the name and the first page of the tracks', (tester) async {
    await _pump(tester, server, await auth.signedOutSession());

    expect(find.widgetWithText(AppBar, 'Bob'), findsOneWidget);
    expect(find.text('Song b1'), findsOneWidget);
    expect(find.text('Song b2'), findsOneWidget);
    expect(find.text('Song b3'), findsNothing);
    expect(server.count('GET /api/v1/users/u-2'), 1);
    expect(server.count('GET /api/v1/users/u-2/tracks'), 1);
  });

  testWidgets('shows a spinner while it loads', (tester) async {
    final session = await auth.signedOutSession();
    await tester.pumpWidget(MaterialApp(home: _screen(server, session, 'u-2')));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('says so when the user has no tracks', (tester) async {
    await _pump(tester, server, await auth.signedOutSession(), userId: 'u-3');

    expect(find.text('No tracks yet'), findsOneWidget);
  });

  testWidgets('says why when the user is not found, and Retry asks again',
      (tester) async {
    server.onProfile = () => http.Response('', 404);
    await _pump(tester, server, await auth.signedOutSession());

    expect(find.text('User not found'), findsOneWidget);
    expect(find.text('Song b1'), findsNothing);

    server.onProfile = null;
    await tester.tap(find.byKey(const Key('retryButton')));
    await tester.pumpAndSettle();

    expect(find.text('User not found'), findsNothing);
    expect(find.text('Song b1'), findsOneWidget);
  });

  testWidgets('Load more adds the next page with the cursor, then goes away',
      (tester) async {
    await _pump(tester, server, await auth.signedOutSession());
    expect(find.byKey(const Key('loadMoreButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('loadMoreButton')));
    await tester.pumpAndSettle();

    expect(find.text('Song b3'), findsOneWidget);
    expect(find.text('Song b1'), findsOneWidget);
    expect(find.byKey(const Key('loadMoreButton')), findsNothing);
    expect(server.count('GET /api/v1/users/u-2/tracks'), 2);
  });

  testWidgets('tapping a track opens its player', (tester) async {
    await _pump(tester, server, await auth.signedOutSession());

    await tester.tap(find.text('Song b2'));
    await tester.pumpAndSettle();

    expect(find.byType(TrackPlayerScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Song b2'), findsOneWidget);
  });

  testWidgets('loads the tracks again after the owner deleted one in the player',
      (tester) async {
    await _pump(tester, server, await auth.signedInSession(), userId: 'u-1');
    expect(find.text('Song a1'), findsOneWidget);

    await tester.tap(find.text('Song a1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteAction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeleteButton')));
    await tester.pumpAndSettle();

    expect(server.count('GET /api/v1/users/u-1/tracks'), 2);
    expect(find.text('Song a1'), findsNothing);
    expect(find.text('No tracks yet'), findsOneWidget);
  });

  testWidgets('does not load the tracks again when the player is left without a change',
      (tester) async {
    await _pump(tester, server, await auth.signedOutSession());

    await tester.tap(find.text('Song b1'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(server.count('GET /api/v1/users/u-2/tracks'), 1);
  });

  group('the name', () {
    testWidgets('can be changed only on one\'s own page', (tester) async {
      await _pump(tester, server, await auth.signedInSession(), userId: 'u-2');

      expect(find.byKey(const Key('renameAction')), findsNothing);
    });

    testWidgets('cannot be changed by someone who is not logged in', (tester) async {
      await _pump(tester, server, await auth.signedOutSession(), userId: 'u-1');

      expect(find.byKey(const Key('renameAction')), findsNothing);
    });

    testWidgets('is changed through a form that starts from the current name',
        (tester) async {
      final session = await auth.signedInSession();
      await _pump(tester, server, session, userId: 'u-1');

      await tester.tap(find.byKey(const Key('renameAction')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Ann'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('renameField')), 'Ann B.');
      await tester.tap(find.byKey(const Key('saveRenameButton')));
      await tester.pumpAndSettle();

      expect(server.bodies['PATCH /api/v1/users/me'], {'displayName': 'Ann B.'});
      expect(find.widgetWithText(AppBar, 'Ann B.'), findsOneWidget);
      expect(session.account?.displayName, 'Ann B.');
      expect(find.byKey(const Key('saveRenameButton')), findsNothing);
    });

    testWidgets('keeps the form open and says why when the server refuses',
        (tester) async {
      server.onRename = () => _json({'detail': 'Name is empty'}, 400);
      await _pump(tester, server, await auth.signedInSession(), userId: 'u-1');

      await tester.tap(find.byKey(const Key('renameAction')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('renameField')), ' ');
      await tester.tap(find.byKey(const Key('saveRenameButton')));
      await tester.pumpAndSettle();

      expect(find.text('Name is empty'), findsOneWidget);
      expect(find.byKey(const Key('saveRenameButton')), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Ann'), findsOneWidget);
    });

    testWidgets('cancel changes nothing', (tester) async {
      await _pump(tester, server, await auth.signedInSession(), userId: 'u-1');

      await tester.tap(find.byKey(const Key('renameAction')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('renameField')), 'Other');
      await tester.tap(find.byKey(const Key('cancelRenameButton')));
      await tester.pumpAndSettle();

      expect(server.count('PATCH /api/v1/users/me'), 0);
      expect(find.widgetWithText(AppBar, 'Ann'), findsOneWidget);
    });
  });
}
