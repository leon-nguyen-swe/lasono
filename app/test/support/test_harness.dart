import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lasono_app/api/track_api.dart';
import 'package:lasono_app/audio_picker.dart';
import 'package:lasono_app/auth/session_controller.dart';
import 'package:lasono_app/core/theme/theme.dart';
import 'package:lasono_app/data/app_repositories.dart';
import 'package:lasono_app/data/fake/fake_behavior.dart';
import 'package:lasono_app/data/fake/fake_world.dart';
import 'package:lasono_app/data/fake_flags.dart';
import 'package:lasono_app/main.dart';
import 'package:lasono_app/playback/playback_controller.dart';

import '../fake_auth_server.dart';
import '../fake_player_service.dart';

/// Everything a test of the app needs, with nothing real: a login server that answers by itself, a player that
/// plays nothing, and the made-up world for every kind of data (so a made-up track can be played and liked).
class TestEnv {
  TestEnv._({
    required this.server,
    required this.session,
    required this.player,
    required this.world,
    required this.repositories,
  });

  final FakeAuthServer server;
  final SessionController session;
  final FakePlayerService player;
  final FakeWorld world;
  final AppRepositories repositories;

  /// [client] answers the real backend's routes of the data (tracks, users); the login has its own [authServer].
  /// [restore] false leaves the login "being looked for" (the session has not asked the server yet).
  static Future<TestEnv> create({
    bool signedIn = false,
    bool restore = true,
    FakeAuthServer? authServer,
    FakeFlags flags = const FakeFlags(likes: true, follows: true, comments: true, feed: true, search: true),
    http.Client? client,
  }) async {
    final server = authServer ?? FakeAuthServer();
    final session = !restore
        ? server.session()
        : (signedIn ? await server.signedInSession() : await server.signedOutSession());
    final world = FakeWorld(clock: () => DateTime.utc(2026, 10, 8, 12));
    final repositories = AppRepositories.create(
      session: session,
      flags: flags,
      baseUrl: 'http://api.test',
      client: client ?? MockClient((request) async => http.Response('{"items": [], "nextCursor": null}', 200)),
      world: world,
      behavior: FakeBehavior.instant(),
      routeFakeIds: true,
    );
    return TestEnv._(server: server, session: session, player: FakePlayerService(), world: world, repositories: repositories);
  }

  /// A playback controller on the fake player, asking the made-up repositories for the address of a track.
  PlaybackController newPlayback() => PlaybackController(player: player, streamUrl: repositories.tracks.fetchStreamUrl);

  /// The whole app, opened at [location].
  Widget app({String location = '/', ThemeController? theme, AudioPicker? pickAudio}) => LasonoApp(
        session: session,
        repositories: repositories,
        player: player,
        themeController: theme,
        pickAudio: pickAudio,
        initialLocation: location,
        api: TrackApi(
          baseUrl: 'http://api.test',
          client: MockClient((request) async => http.Response('{"items": [], "nextCursor": null}', 200)),
        ),
      );

  /// Gives the test a window of this size (and puts it back afterwards).
  static void window(WidgetTester tester, {double width = 1280, double height = 900}) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
}

/// A material app in the LaSono theme around a widget under test.
Widget themed(Widget child, {ThemeData? theme}) => MaterialApp(theme: theme ?? AppTheme.dark, home: Scaffold(body: child));
