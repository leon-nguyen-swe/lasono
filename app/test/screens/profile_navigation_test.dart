import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/profile_api.dart';
import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/screens/profile_screen.dart';
import 'package:lasono_app/screens/track_list_screen.dart';

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

/// One list with a track of Bob (u-2), and the profile pages of Ann and Bob.
final _client = MockClient((request) async {
  final path = request.url.path;
  switch (path) {
    case '/api/v1/tracks':
      return _json({'items': [_track('b1', 'u-2')], 'nextCursor': null}, 200);
    case '/api/v1/users/u-1':
      return _json({'userId': 'u-1', 'displayName': 'Ann'}, 200);
    case '/api/v1/users/u-2':
      return _json({'userId': 'u-2', 'displayName': 'Bob'}, 200);
    case '/api/v1/users/u-1/tracks':
    case '/api/v1/users/u-2/tracks':
      return _json({'items': [], 'nextCursor': null}, 200);
  }
  return _json(_track(request.url.pathSegments.last, 'u-2'), 200);
});

Future<void> _pump(WidgetTester tester, {required bool signedIn}) async {
  final auth = FakeAuthServer();
  final session = signedIn ? await auth.signedInSession() : await auth.signedOutSession();
  await tester.pumpWidget(MaterialApp(
    home: TrackListScreen(
      session: session,
      api: TrackApi(baseUrl: 'http://api.test', client: _client),
      profileApi: ProfileApi(baseUrl: 'http://api.test', client: _client),
      player: FakePlayerService(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the account menu opens the profile of the logged-in user',
      (tester) async {
    await _pump(tester, signedIn: true);

    await tester.tap(find.byKey(const Key('accountMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profileAction')));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Ann'), findsOneWidget);
    // It is Ann's own page, so she can change her name.
    expect(find.byKey(const Key('renameAction')), findsOneWidget);
  });

  testWidgets('the player of a track links to the profile of its owner',
      (tester) async {
    await _pump(tester, signedIn: false);

    await tester.tap(find.text('Song b1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ownerProfileAction')));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Bob'), findsOneWidget);
    expect(find.byKey(const Key('renameAction')), findsNothing);
  });
}
