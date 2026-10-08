import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../core/theme/theme.dart';
import '../data/user_directory.dart';
import '../models/track.dart';
import '../playback/playback_controller.dart';
import 'player_bar.dart';
import 'top_bar.dart';

/// The frame of the app: the top bar, the page, and the player bar at the bottom. The router keeps one of these
/// alive while the page inside it changes, which is why the music does not stop when the user moves around.
///
/// It does not know the router either: [onGo] takes a location (`/feed`, `/users/…`) and the app moves there.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.child,
    required this.location,
    required this.session,
    required this.themeController,
    required this.playback,
    required this.directory,
    required this.onGo,
  });

  /// The page.
  final Widget child;

  /// Where the app is now, with its query (`/search?q=son`).
  final String location;

  final SessionController session;
  final ThemeController themeController;
  final PlaybackController playback;
  final UserDirectory directory;
  final ValueChanged<String> onGo;

  String? get _searchQuery {
    final uri = Uri.parse(location);
    return uri.path == '/search' ? (uri.queryParameters['q'] ?? '') : null;
  }

  String _withReturn(String path) => '$path?from=${Uri.encodeQueryComponent(location)}';

  Future<void> _logout() async {
    // What was playing may be private to this user, so it stops with the login.
    await playback.stop();
    await session.logout();
    onGo('/');
  }

  @override
  Widget build(BuildContext context) {
    final path = Uri.parse(location).path;
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: Column(
        children: [
          TopBar(
            session: session,
            themeController: themeController,
            location: path,
            searchQuery: _searchQuery,
            onHome: () => onGo('/'),
            onFeed: () => onGo('/feed'),
            onUpload: () => onGo('/upload'),
            onSearch: (query) => onGo(query.isEmpty ? '/search' : '/search?q=${Uri.encodeQueryComponent(query)}'),
            onLogin: () => onGo(_withReturn('/login')),
            onRegister: () => onGo(_withReturn('/register')),
            onProfile: (userId) => onGo('/users/${Uri.encodeComponent(userId)}'),
            onLogout: _logout,
          ),
          Expanded(child: child),
          PlayerBar(
            playback: playback,
            directory: directory,
            onOpenTrack: (Track track) => onGo('/tracks/${Uri.encodeComponent(track.id)}'),
            onOpenUser: (userId) => onGo('/users/${Uri.encodeComponent(userId)}'),
          ),
        ],
      ),
    );
  }
}

/// Puts a page in the middle of the window, no wider than the design allows, with the side margins of its
/// screen size. Every page of the shell uses it, so they all line up under the top bar.
class PageContainer extends StatelessWidget {
  const PageContainer({super.key, required this.child, this.padding});

  final Widget child;

  /// Replaces the vertical padding; the sides always follow the screen size.
  final EdgeInsets? padding;

  static double sideMargin(ScreenSize size) => switch (size) {
        ScreenSize.compact => AppSpacing.lg,
        ScreenSize.medium => AppSpacing.xl,
        ScreenSize.expanded => AppSpacing.xxl,
      };

  @override
  Widget build(BuildContext context) {
    final side = sideMargin(context.screenSize);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, padding?.top ?? AppSpacing.xl, side, padding?.bottom ?? AppSpacing.xl),
          child: child,
        ),
      ),
    );
  }
}
