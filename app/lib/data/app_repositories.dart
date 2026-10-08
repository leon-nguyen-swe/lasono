import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../api/profile_api.dart';
import '../api/track_api.dart';
import '../auth/session_controller.dart';
import 'fake/fake_behavior.dart';
import 'fake/fake_repositories.dart';
import 'fake/fake_world.dart';
import 'fake/routing_repositories.dart';
import 'fake_flags.dart';
import 'feed_repository.dart';
import 'http/api_client.dart';
import 'http/http_feed_repository.dart';
import 'http/http_search_repository.dart';
import 'http/http_social_repository.dart';
import 'http/http_user_repository.dart';
import 'search_repository.dart';
import 'social_repository.dart';
import 'track_repository.dart';
import 'user_directory.dart';
import 'user_repository.dart';
import 'waveform_cache.dart';

/// Everything a screen may ask for, behind interfaces: a screen never makes an HTTP call itself, and does not
/// know whether the answer is real or made up.
class AppRepositories {
  AppRepositories({
    required this.tracks,
    required this.users,
    required this.social,
    required this.feed,
    required this.search,
    this.flags = const FakeFlags(),
    this.fakeWorld,
    this.fakeBehavior,
  })  : directory = UserDirectory(users),
        waveforms = WaveformCache(tracks);

  final TrackRepository tracks;
  final UserRepository users;
  final SocialRepository social;
  final FeedRepository feed;
  final SearchRepository search;

  /// The names of users, shared by every screen.
  final UserDirectory directory;

  /// The waveforms of the tracks shown in lists, which carry none themselves.
  final WaveformCache waveforms;

  /// Which parts are made up (see [FakeFlags]).
  final FakeFlags flags;

  /// The made-up data and the switch for its latency and failures; null when nothing is fake.
  final FakeWorld? fakeWorld;
  final FakeBehavior? fakeBehavior;

  /// The real backend, with made-up data where [flags] say the backend is not built yet.
  ///
  /// Without any flag the real repositories are used as they are. With one, every call is routed by id (see
  /// `routing_repositories.dart`), because fake and real ids can then be on one screen. [routeFakeIds] does the
  /// same routing with no flag on, so that fake ids (the design system page plays fake tracks) work too; a real
  /// id still goes to the real backend untouched.
  factory AppRepositories.create({
    required SessionController session,
    FakeFlags flags = FakeFlags.environment,
    String baseUrl = defaultApiBaseUrl,
    http.Client? client,
    FakeWorld? world,
    FakeBehavior? behavior,
    bool routeFakeIds = false,
  }) {
    final trackApi = TrackApi(baseUrl: baseUrl, client: client, auth: session);
    final api = ApiClient(baseUrl: baseUrl, client: client, auth: session);
    final realUsers = HttpUserRepository(
      api,
      profileApi: ProfileApi(baseUrl: baseUrl, client: client, auth: session),
    );
    final realSocial = HttpSocialRepository(api);
    final realFeed = HttpFeedRepository(api);
    final realSearch = HttpSearchRepository(api);

    if (!flags.any && !routeFakeIds) {
      return AppRepositories(
        tracks: trackApi,
        users: realUsers,
        social: realSocial,
        feed: realFeed,
        search: realSearch,
        flags: flags,
      );
    }

    final fakeWorld = world ?? FakeWorld();
    final fakeBehavior = behavior ?? FakeBehavior();
    String? viewerId() => session.account?.userId;

    final fakeTracks = FakeTrackRepository(fakeWorld, fakeBehavior, viewerId);
    return AppRepositories(
      tracks: RoutingTrackRepository(
        real: trackApi,
        fake: fakeTracks,
        world: fakeWorld,
        viewerId: viewerId,
        fakeLikes: flags.likes,
        fakeComments: flags.comments,
      ),
      users: RoutingUserRepository(
        real: realUsers,
        fake: FakeUserRepository(fakeWorld, fakeBehavior, viewerId),
        world: fakeWorld,
        viewerId: viewerId,
        fakeFollows: flags.follows,
      ),
      social: RoutingSocialRepository(
        real: realSocial,
        fake: FakeSocialRepository(fakeWorld, fakeBehavior, viewerId),
        fakeLikes: flags.likes,
        fakeFollows: flags.follows,
        fakeComments: flags.comments,
      ),
      feed: RoutingFeedRepository(
        real: realFeed,
        fake: FakeFeedRepository(
          fakeWorld,
          fakeBehavior,
          viewerId,
          // A real track a user liked is looked up in the real backend.
          resolveTrack: (id) async {
            try {
              return await trackApi.getTrack(id);
            } on TrackApiException {
              return null;
            }
          },
        ),
        fakeFeed: flags.feed,
      ),
      search: RoutingSearchRepository(
        real: realSearch,
        fake: FakeSearchRepository(fakeWorld, fakeBehavior, viewerId),
        fakeSearch: flags.search,
      ),
      flags: flags,
      fakeWorld: fakeWorld,
      fakeBehavior: fakeBehavior,
    );
  }
}

/// Gives the screens below it the repositories: `RepositoriesScope.of(context).tracks`.
class RepositoriesScope extends InheritedWidget {
  const RepositoriesScope({super.key, required this.repositories, required super.child});

  final AppRepositories repositories;

  /// Null when there is no scope above (the design system page is also shown on its own in tests).
  static AppRepositories? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RepositoriesScope>()?.repositories;

  static AppRepositories of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RepositoriesScope>();
    assert(scope != null, 'No RepositoriesScope above this widget: wrap the app in one');
    return scope!.repositories;
  }

  @override
  bool updateShouldNotify(RepositoriesScope oldWidget) => repositories != oldWidget.repositories;
}
