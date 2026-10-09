import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/fake_flags.dart';

void main() {
  group('resolve', () {
    test('nothing is fake unless something is asked for', () {
      final flags = FakeFlags.resolve();
      expect(flags.any, isFalse);
      expect(flags.description, 'nothing is fake');
    });

    test('FAKE_SOCIAL switches on likes, follows and comments together, and nothing else', () {
      final flags = FakeFlags.resolve(social: true);
      expect((flags.likes, flags.follows, flags.comments), (true, true, true));
      expect((flags.feed, flags.search), (false, false));
    });

    test('a feature switch of its own wins over FAKE_SOCIAL, in both directions', () {
      final realLikes = FakeFlags.resolve(social: true, likes: false);
      expect((realLikes.likes, realLikes.follows, realLikes.comments), (false, true, true));

      final onlyLikes = FakeFlags.resolve(likes: true);
      expect((onlyLikes.likes, onlyLikes.follows, onlyLikes.comments), (true, false, false));
    });

    test('the feed and the search have their own switches', () {
      final flags = FakeFlags.resolve(feed: true);
      expect((flags.feed, flags.search, flags.likes), (true, false, false));
      expect(FakeFlags.resolve(search: true).search, isTrue);
    });

    test('any is true when a single thing is fake', () {
      expect(FakeFlags.resolve(comments: true).any, isTrue);
      expect(FakeFlags.resolve(search: true).any, isTrue);
    });

    test('describes what is fake, so the console and the gallery can say it', () {
      expect(FakeFlags.resolve(social: true, search: true).description, 'fake: likes, follows, comments, search');
    });
  });

  test('without any --dart-define the app starts with the real backend for everything', () {
    // This test runs without --dart-define, like the app run in production. With FAKE_* set when starting
    // the tests the expectation would be different on purpose.
    const flags = FakeFlags.environment;
    expect(flags.any, isFalse);
  });
}
