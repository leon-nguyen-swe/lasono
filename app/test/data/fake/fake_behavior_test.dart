import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/fake/fake_behavior.dart';
import 'package:lasono_app/data/repository_exception.dart';

void main() {
  group('latency', () {
    test('the default waits between 200 and 600 milliseconds, each time', () {
      final behavior = FakeBehavior();
      for (var i = 0; i < 200; i++) {
        final wait = behavior.nextLatency();
        expect(wait, greaterThanOrEqualTo(const Duration(milliseconds: 200)));
        expect(wait, lessThanOrEqualTo(const Duration(milliseconds: 600)));
      }
    });

    test('is not always the same, so the screens are seen with different waits', () {
      final behavior = FakeBehavior();
      final waits = {for (var i = 0; i < 30; i++) behavior.nextLatency()};
      expect(waits.length, greaterThan(5));
    });

    test('the same seed gives the same waits, so a run can be repeated', () {
      final a = FakeBehavior(seed: 5);
      final b = FakeBehavior(seed: 5);
      expect([for (var i = 0; i < 10; i++) a.nextLatency()], [for (var i = 0; i < 10; i++) b.nextLatency()]);
    });

    test('the instant behaviour has no wait at all', () {
      expect(FakeBehavior.instant().nextLatency(), Duration.zero);
    });

    test('run() really waits for the latency before it answers', () {
      fakeAsync((async) {
        var answered = false;
        FakeBehavior(minLatency: const Duration(milliseconds: 300), maxLatency: const Duration(milliseconds: 300))
            .run(() => 42)
            .then((_) => answered = true);

        async.elapse(const Duration(milliseconds: 299));
        expect(answered, isFalse);
        async.elapse(const Duration(milliseconds: 2));
        expect(answered, isTrue);
      });
    });
  });

  group('failure', () {
    Matcher networkError() => throwsA(
          isA<RepositoryException>().having((e) => e.kind, 'kind', RepositoryErrorKind.network),
        );

    test('answers with the value of the body when nothing is wrong', () async {
      expect(await FakeBehavior.instant().run(() => 'ok'), 'ok');
    });

    test('while failing is true every call is a network error, and the body is not run', () async {
      final behavior = FakeBehavior.instant()..failing = true;
      var ran = false;

      await expectLater(behavior.run(() => ran = true), networkError());
      await expectLater(behavior.run(() => 1), networkError());
      expect(ran, isFalse);

      behavior.failing = false;
      expect(await behavior.run(() => 1), 1);
    });

    test('failNext(2) fails two calls and then works again', () async {
      final behavior = FakeBehavior.instant()..failNext(2);
      await expectLater(behavior.run(() => 1), networkError());
      await expectLater(behavior.run(() => 1), networkError());
      expect(await behavior.run(() => 1), 1);
    });

    test('an error thrown by the body is passed on as it is', () async {
      await expectLater(
        FakeBehavior.instant().run<int>(() => throw const RepositoryException('nope', kind: RepositoryErrorKind.notFound)),
        throwsA(isA<RepositoryException>().having((e) => e.kind, 'kind', RepositoryErrorKind.notFound)),
      );
    });
  });
}
