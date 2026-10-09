import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../auth/session_controller.dart';
import '../data/app_repositories.dart';
import '../playback/playback_controller.dart';

/// Who is logged in. Widgets that read it with [SessionScope.of] are rebuilt when the login or the logout happens.
class SessionScope extends InheritedNotifier<SessionController> {
  const SessionScope({super.key, required SessionController session, required super.child}) : super(notifier: session);

  static SessionController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'No SessionScope above this widget: wrap the app in one');
    return scope!.notifier!;
  }

  /// Without listening: for a callback (a button) that needs to know the login at the moment it is pressed.
  static SessionController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'No SessionScope above this widget: wrap the app in one');
    return scope!.notifier!;
  }
}

/// What a page needs from the app, and the moves between pages, in one place.
extension AppContext on BuildContext {
  AppRepositories get repos => RepositoriesScope.of(this);
  PlaybackController get playback => PlaybackScope.of(this);

  /// The logged-in session; the widget is rebuilt when it changes.
  SessionController get session => SessionScope.of(this);

  /// The id of the logged-in user, or null. The widget is rebuilt when it changes.
  String? get viewerId => session.account?.userId;

  void openTrack(String trackId) => go('/tracks/${Uri.encodeComponent(trackId)}');
  void openUser(String userId) => go('/users/${Uri.encodeComponent(userId)}');

  /// Sends the user to the login page, which brings them back here afterwards.
  void askToLogin() {
    final here = GoRouter.of(this).routeInformationProvider.value.uri.toString();
    go('/login?from=${Uri.encodeQueryComponent(here)}');
  }

  /// Back to the page before this one when there is one, otherwise to [fallback].
  void goBackOr(String fallback) {
    final router = GoRouter.of(this);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(fallback);
    }
  }
}
