import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/auth/session_controller.dart';
import 'package:lasono_app/models/track.dart';
import 'package:lasono_app/screens/track_player_screen.dart';

import '../fake_auth_server.dart';
import '../fake_player_service.dart';

// The fake account is 'u-1'.
Track _track({String ownerId = 'u-1', String visibility = 'PUBLIC'}) => Track(
      id: 'abc',
      ownerId: ownerId,
      title: 'My Song',
      description: 'Old text',
      visibility: visibility,
      status: 'READY',
      durationSeconds: 5,
      waveform: const [0.2, 0.8],
    );

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// A server for one track that remembers the PATCH and DELETE it got.
class _Tracks {
  final requests = <http.Request>[];
  http.Response Function(http.Request request)? onPatch;
  http.Response Function(http.Request request)? onDelete;

  late final TrackApi api = TrackApi(
    baseUrl: 'http://api.test',
    client: MockClient((request) async {
      requests.add(request);
      if (request.method == 'PATCH') {
        return onPatch?.call(request) ?? _json(_after(request), 200);
      }
      if (request.method == 'DELETE') {
        return onDelete?.call(request) ?? http.Response('', 204);
      }
      return http.Response('', 404);
    }),
  );

  Map<String, dynamic> _after(http.Request request) {
    final changes = jsonDecode(request.body) as Map<String, dynamic>;
    return {
      'id': 'abc',
      'ownerId': 'u-1',
      'title': changes['title'] ?? 'My Song',
      'description': changes['description'] ?? 'Old text',
      'visibility': changes['visibility'] ?? 'PUBLIC',
      'status': 'READY',
      'durationSeconds': 5.0,
      'waveform': [0.2, 0.8],
    };
  }

  List<http.Request> of(String method) =>
      requests.where((r) => r.method == method).toList();
}

late int _changed;

/// Opens the player screen from a first page, so that a screen can close itself.
Future<void> _open(
  WidgetTester tester,
  _Tracks tracks,
  SessionController session,
  Track track,
) async {
  _changed = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const Key('open'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => TrackPlayerScreen(
                  track: track,
                  api: tracks.api,
                  player: FakePlayerService(),
                  session: session,
                  onChanged: () => _changed++,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

void main() {
  late FakeAuthServer server;
  late _Tracks tracks;

  setUp(() {
    server = FakeAuthServer();
    tracks = _Tracks();
  });

  group('who sees the buttons', () {
    testWidgets('the owner sees Edit and Delete', (tester) async {
      await _open(tester, tracks, await server.signedInSession(), _track());

      expect(find.byKey(const Key('editAction')), findsOneWidget);
      expect(find.byKey(const Key('deleteAction')), findsOneWidget);
    });

    testWidgets('someone else does not', (tester) async {
      await _open(tester, tracks, await server.signedInSession(),
          _track(ownerId: 'someone-else'));

      expect(find.byKey(const Key('editAction')), findsNothing);
      expect(find.byKey(const Key('deleteAction')), findsNothing);
    });

    testWidgets('nobody who is not logged in does', (tester) async {
      await _open(tester, tracks, await server.signedOutSession(), _track());

      expect(find.byKey(const Key('editAction')), findsNothing);
      expect(find.byKey(const Key('deleteAction')), findsNothing);
    });

    testWidgets('a track whose owner is unknown is nobody\'s to change',
        (tester) async {
      await _open(tester, tracks, await server.signedInSession(),
          _track(ownerId: ''));

      expect(find.byKey(const Key('editAction')), findsNothing);
    });
  });

  group('editing', () {
    Future<void> openEditor(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('editAction')));
      await tester.pumpAndSettle();
    }

    testWidgets('starts from what the track has now', (tester) async {
      await _open(tester, tracks, await server.signedInSession(),
          _track(visibility: 'PRIVATE'));

      await openEditor(tester);

      expect(find.widgetWithText(TextField, 'My Song'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Old text'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('editPrivateSwitch'))).value,
        isTrue,
      );
    });

    testWidgets('saves the new text and visibility and shows them', (tester) async {
      await _open(tester, tracks, await server.signedInSession(), _track());
      await openEditor(tester);

      await tester.enterText(find.byKey(const Key('editTitleField')), 'New title');
      await tester.enterText(find.byKey(const Key('editDescriptionField')), 'New text');
      await tester.tap(find.byKey(const Key('editPrivateSwitch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveEditButton')));
      await tester.pumpAndSettle();

      expect(jsonDecode(tracks.of('PATCH').single.body), {
        'title': 'New title',
        'description': 'New text',
        'visibility': 'PRIVATE',
      });
      expect(find.widgetWithText(AppBar, 'New title'), findsOneWidget);
      expect(find.text('New text'), findsOneWidget);
      expect(find.byKey(const Key('saveEditButton')), findsNothing);
      expect(_changed, 1);
    });

    testWidgets('sends only what was changed, and nothing when nothing was',
        (tester) async {
      await _open(tester, tracks, await server.signedInSession(), _track());
      await openEditor(tester);

      await tester.tap(find.byKey(const Key('saveEditButton')));
      await tester.pumpAndSettle();
      expect(tracks.of('PATCH'), isEmpty);
      expect(find.byKey(const Key('saveEditButton')), findsNothing);
      expect(_changed, 0);

      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('editDescriptionField')), 'Only this');
      await tester.tap(find.byKey(const Key('saveEditButton')));
      await tester.pumpAndSettle();

      expect(jsonDecode(tracks.of('PATCH').single.body), {'description': 'Only this'});
    });

    testWidgets('keeps the form open and says why when the server refuses',
        (tester) async {
      tracks.onPatch = (_) => _json({'detail': 'Title is empty'}, 400);
      await _open(tester, tracks, await server.signedInSession(), _track());
      await openEditor(tester);

      await tester.enterText(find.byKey(const Key('editTitleField')), ' ');
      await tester.tap(find.byKey(const Key('saveEditButton')));
      await tester.pumpAndSettle();

      expect(find.text('Title is empty'), findsOneWidget);
      expect(find.byKey(const Key('saveEditButton')), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'My Song'), findsOneWidget);
      expect(_changed, 0);
    });

    testWidgets('cancel changes nothing', (tester) async {
      await _open(tester, tracks, await server.signedInSession(), _track());
      await openEditor(tester);

      await tester.enterText(find.byKey(const Key('editTitleField')), 'Other');
      await tester.tap(find.byKey(const Key('cancelEditButton')));
      await tester.pumpAndSettle();

      expect(tracks.of('PATCH'), isEmpty);
      expect(find.widgetWithText(AppBar, 'My Song'), findsOneWidget);
    });
  });

  group('deleting', () {
    Future<void> pressDelete(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('deleteAction')));
      await tester.pumpAndSettle();
    }

    testWidgets('asks first, and does nothing if the user cancels', (tester) async {
      await _open(tester, tracks, await server.signedInSession(), _track());

      await pressDelete(tester);
      expect(find.byKey(const Key('confirmDeleteButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancelDeleteButton')));
      await tester.pumpAndSettle();

      expect(tracks.of('DELETE'), isEmpty);
      expect(find.byType(TrackPlayerScreen), findsOneWidget);
    });

    testWidgets('deletes the track, closes the screen and tells the list',
        (tester) async {
      await _open(tester, tracks, await server.signedInSession(), _track());

      await pressDelete(tester);
      await tester.tap(find.byKey(const Key('confirmDeleteButton')));
      await tester.pumpAndSettle();

      expect(tracks.of('DELETE'), hasLength(1));
      expect(find.byType(TrackPlayerScreen), findsNothing);
      expect(_changed, 1);
    });

    testWidgets('stays on the screen and says why when the server refuses',
        (tester) async {
      tracks.onDelete = (_) => http.Response('', 409);
      await _open(tester, tracks, await server.signedInSession(), _track());

      await pressDelete(tester);
      await tester.tap(find.byKey(const Key('confirmDeleteButton')));
      await tester.pumpAndSettle();

      expect(find.text('This track is still being processed. Try again in a moment.'),
          findsOneWidget);
      expect(find.byType(TrackPlayerScreen), findsOneWidget);
      expect(_changed, 0);
    });
  });
}
