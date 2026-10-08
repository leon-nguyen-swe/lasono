/// Which parts of the backend are not built yet, so the app uses made-up data for them. One switch per feature, set
/// when the app is started: `--dart-define=FAKE_LIKES=true`. Turn a switch off when the backend of that feature is
/// done (docs/backend-guide/00-how-to-use.md).
///
/// | Switch | What it stands in for |
/// |---|---|
/// | `FAKE_LIKES` | like and unlike, `likeCount`, `isLikedByMe` |
/// | `FAKE_FOLLOWS` | follow and unfollow, followers and following, the counts of a profile |
/// | `FAKE_COMMENTS` | comments on the waveform, `commentCount` |
/// | `FAKE_SOCIAL` | all three of the above at once |
/// | `FAKE_FEED` | the feed and the list of the tracks a user liked |
/// | `FAKE_SEARCH` | search |
///
/// A switch of its own wins over `FAKE_SOCIAL`: `FAKE_SOCIAL=true FAKE_LIKES=false` is fake follows and comments
/// with real likes.
class FakeFlags {
  const FakeFlags({
    this.likes = false,
    this.follows = false,
    this.comments = false,
    this.feed = false,
    this.search = false,
  });

  /// Reads the switches the app was started with.
  static const environment = FakeFlags(
    likes: bool.hasEnvironment('FAKE_LIKES') ? bool.fromEnvironment('FAKE_LIKES') : bool.fromEnvironment('FAKE_SOCIAL'),
    follows:
        bool.hasEnvironment('FAKE_FOLLOWS') ? bool.fromEnvironment('FAKE_FOLLOWS') : bool.fromEnvironment('FAKE_SOCIAL'),
    comments: bool.hasEnvironment('FAKE_COMMENTS')
        ? bool.fromEnvironment('FAKE_COMMENTS')
        : bool.fromEnvironment('FAKE_SOCIAL'),
    feed: bool.fromEnvironment('FAKE_FEED'),
    search: bool.fromEnvironment('FAKE_SEARCH'),
  );

  /// The same rule as [environment], for values that are not known when the app is built (tests).
  /// A value that is given (not null) for one feature wins over [social].
  factory FakeFlags.resolve({
    bool social = false,
    bool? likes,
    bool? follows,
    bool? comments,
    bool feed = false,
    bool search = false,
  }) =>
      FakeFlags(
        likes: likes ?? social,
        follows: follows ?? social,
        comments: comments ?? social,
        feed: feed,
        search: search,
      );

  final bool likes;
  final bool follows;
  final bool comments;
  final bool feed;
  final bool search;

  /// True when anything is made up. Then fake and real ids can both turn up on a screen.
  bool get any => likes || follows || comments || feed || search;

  /// A short description of what is fake, for the console and for the gallery page.
  String get description {
    final names = [
      if (likes) 'likes',
      if (follows) 'follows',
      if (comments) 'comments',
      if (feed) 'feed',
      if (search) 'search',
    ];
    return names.isEmpty ? 'nothing is fake' : 'fake: ${names.join(', ')}';
  }
}
