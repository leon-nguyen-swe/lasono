import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'audio_picker.dart';
import 'auth/session_controller.dart';
import 'core/theme/theme.dart';
import 'data/app_repositories.dart';
import 'dev/gallery_screen.dart';
import 'playback/playback_controller.dart';
import 'screens/auth_page.dart';
import 'screens/home_page.dart';
import 'screens/profile_page.dart';
import 'screens/track_page.dart';
import 'screens/upload_page.dart';
import 'shell/app_shell.dart';

/// The places of the app. The routes that are not in the table yet (a page that is still the old screen) are
/// given as builders, so the router does not depend on how those screens are made.
class AppRoutes {
  static const home = '/';
  static const feed = '/feed';
  static const search = '/search';
  static const upload = '/upload';
  static const login = '/login';
  static const register = '/register';
  static const splash = '/splash';
  static const gallery = GalleryScreen.routeName;

  /// Pages that need a login. Without one the user is sent to the login page and brought back afterwards.
  static const needLogin = [upload, feed];
}

/// Everything the router needs from the app.
class RouterDependencies {
  const RouterDependencies({
    required this.session,
    required this.themeController,
    required this.repositories,
    required this.playback,
    this.pickAudio,
  });

  final SessionController session;
  final ThemeController themeController;
  final AppRepositories repositories;

  /// Made when a page of the shell first needs it (see [PlaybackScope]).
  final PlaybackController Function() playback;

  /// The file dialog of the upload page; the real one when null.
  final AudioPicker? pickAudio;
}

/// Where a login (or the start of the app) must send the user, given where they are and who they are; null means
/// "stay". This is the route guard, written as a function so it can be tested without any widget.
String? redirectFor({
  required SessionStatus status,
  required Uri location,
  bool debug = kDebugMode,
}) {
  final path = location.path;

  // The login is still being looked for (the refresh cookie): show nothing of the app yet, and come back to this
  // same place when the answer is known.
  if (status == SessionStatus.restoring) {
    return path == AppRoutes.splash ? null : '${AppRoutes.splash}?from=${Uri.encodeQueryComponent(location.toString())}';
  }
  if (path == AppRoutes.splash) return _safeFrom(location) ?? AppRoutes.home;

  final signedIn = status == SessionStatus.signedIn;
  if (!signedIn && AppRoutes.needLogin.contains(path)) {
    return '${AppRoutes.login}?from=${Uri.encodeQueryComponent(location.toString())}';
  }
  if (signedIn && (path == AppRoutes.login || path == AppRoutes.register)) {
    return _safeFrom(location) ?? AppRoutes.home;
  }
  if (!debug && path == AppRoutes.gallery) return AppRoutes.home;
  return null;
}

// Only a place inside the app may be returned to: "?from=https://elsewhere" must not send the user away.
String? _safeFrom(Uri location) {
  final from = location.queryParameters['from'];
  if (from == null || !from.startsWith('/') || from.startsWith('//')) return null;
  return from;
}

GoRouter createRouter(RouterDependencies deps, {String initialLocation = AppRoutes.home, bool debug = kDebugMode}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: deps.session,
    redirect: (context, state) =>
        redirectFor(status: deps.session.status, location: state.uri, debug: debug),
    errorBuilder: (context, state) => _NotFoundPage(location: state.uri.toString()),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (context, state) => const _SplashPage()),
            GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => AuthPage(session: deps.session, from: state.uri.queryParameters['from']),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => AuthPage(session: deps.session, registering: true, from: state.uri.queryParameters['from']),
      ),
      // The new frame. A page put in here gets the top bar and the player bar, and the music keeps playing
      // while the user moves between its pages.
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.uri.toString(),
          session: deps.session,
          themeController: deps.themeController,
          playback: deps.playback(),
          directory: deps.repositories.directory,
          onGo: (location) => GoRouter.of(context).go(location),
          child: child,
        ),
        routes: [
          if (debug) GoRoute(path: AppRoutes.gallery, builder: (context, state) => GalleryScreen(themeController: deps.themeController, embedded: true)),
          GoRoute(path: AppRoutes.home, builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/tracks/:id',
            builder: (context, state) => TrackPage(key: ValueKey(state.pathParameters['id']), trackId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/users/:id',
            builder: (context, state) => ProfilePage(key: ValueKey(state.pathParameters['id']), userId: state.pathParameters['id']!),
          ),
          GoRoute(path: AppRoutes.upload, builder: (context, state) => UploadPage(pickAudio: deps.pickAudio)),
          GoRoute(path: AppRoutes.feed, builder: (context, state) => const _ComingSoonPage(title: 'Bảng tin')),
          GoRoute(path: AppRoutes.search, builder: (context, state) => const _ComingSoonPage(title: 'Tìm kiếm')),
        ],
      ),
    ],
  );
}

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    // Same as the old app showed while it looked for a login: the name and a spinner.
    return Scaffold(
      appBar: AppBar(title: const Text('LaSono')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// A page of the shell that is not built yet.
class _ComingSoonPage extends StatelessWidget {
  const _ComingSoonPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          Text('Trang này đang được xây dựng.', style: text.bodyMedium),
        ],
      ),
    );
  }
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('404', key: const Key('notFoundCode'), style: text.displaySmall),
            const SizedBox(height: AppSpacing.sm),
            Text('Không tìm thấy trang này.', style: text.titleMedium),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              key: const Key('notFoundHome'),
              onPressed: () => GoRouter.of(context).go(AppRoutes.home),
              child: const Text('Về trang chủ'),
            ),
          ],
        ),
      ),
    );
  }
}
