import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'api/auth_api.dart';
import 'api/profile_api.dart';
import 'api/track_api.dart';
import 'app_router.dart';
import 'audio_picker.dart';
import 'auth/session_controller.dart';
import 'core/theme/theme.dart';
import 'data/app_repositories.dart';
import 'data/fake_flags.dart';
import 'player_service.dart';
import 'playback/playback_controller.dart';
import 'screens/track_list_screen.dart';
import 'screens/track_screen.dart';

void main() {
  // Addresses like /users/42 instead of /#/users/42. The server must answer every such address with the app
  // (`flutter run` does; see docs/backend-guide/07-phase7-proof-and-release.md for the Caddyfile).
  usePathUrlStrategy();

  // The track API sends the access token of whoever is logged in, so both
  // are made here and share the session.
  final session = SessionController(AuthApi());
  final repositories = AppRepositories.create(
    session: session,
    flags: FakeFlags.environment,
    // While developing, the made-up tracks of the design system page can be played even with no switch on.
    routeFakeIds: kDebugMode,
  );
  if (kDebugMode) debugPrint('LaSono: ${repositories.flags.description}');
  runApp(
    LasonoApp(
      session: session,
      api: TrackApi(auth: session),
      profileApi: ProfileApi(auth: session),
      repositories: repositories,
    ),
  );
}

class LasonoApp extends StatefulWidget {
  const LasonoApp({
    super.key,
    required this.session,
    this.api,
    this.profileApi,
    this.pickAudio,
    this.player,
    this.themeController,
    this.repositories,
    this.initialLocation = AppRoutes.home,
  });

  final SessionController session;

  /// The track API of the old screens, which are still in use until their new versions exist.
  final TrackApi? api;
  final ProfileApi? profileApi;
  final AudioPicker? pickAudio;
  final PlayerService? player;

  /// Which theme is shown; dark unless it is changed. Tests may pass their own.
  final ThemeController? themeController;

  /// Where the data comes from. Without it the real backend is used.
  final AppRepositories? repositories;

  /// The page the app opens on (a browser opens on the address in its bar instead).
  final String initialLocation;

  @override
  State<LasonoApp> createState() => _LasonoAppState();
}

class _LasonoAppState extends State<LasonoApp> {
  late final ThemeController _theme = widget.themeController ?? ThemeController();
  late final AppRepositories _repositories =
      widget.repositories ?? AppRepositories.create(session: widget.session, flags: const FakeFlags());

  // The audio player needs the browser, so the controller is made when the first page that plays something asks.
  PlaybackController? _playbackInstance;
  PlaybackController get _playback => _playbackInstance ??= PlaybackController(
        player: widget.player ?? JustAudioPlayerService(),
        streamUrl: _repositories.tracks.fetchStreamUrl,
      );

  late final GoRouter _router = createRouter(
    RouterDependencies(
      session: widget.session,
      themeController: _theme,
      repositories: _repositories,
      playback: () => _playback,
      legacyHome: (context) => TrackListScreen(
        session: widget.session,
        api: widget.api,
        profileApi: widget.profileApi,
        pickAudio: widget.pickAudio,
        player: widget.player,
      ),
      legacyUpload: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('Upload'),
          leading: BackButton(onPressed: () => context.go(AppRoutes.home)),
        ),
        body: TrackScreen(api: widget.api, pickAudio: widget.pickAudio, player: widget.player),
      ),
    ),
    initialLocation: widget.initialLocation,
  );

  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = widget.session.account?.userId;
    widget.session.addListener(_onSessionChanged);
    // A reload of the page loses the access token, which lives in memory only.
    // The refresh cookie gets it back, before anything is asked for the user.
    if (widget.session.status == SessionStatus.restoring) {
      unawaited(widget.session.restore());
    }
  }

  // What a profile says about "followed by me" belongs to whoever is logged in, so another user starts from nothing.
  void _onSessionChanged() {
    final userId = widget.session.account?.userId;
    if (userId == _userId) return;
    _userId = userId;
    _repositories.directory.clear();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _router.dispose();
    _playbackInstance?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) => MaterialApp.router(
        title: 'LaSono',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _theme.mode,
        routerConfig: _router,
        builder: (context, child) => RepositoriesScope(
          repositories: _repositories,
          child: PlaybackScope(read: () => _playback, child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
