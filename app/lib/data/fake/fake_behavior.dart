import 'dart:async';
import 'dart:math';

import '../repository_exception.dart';

/// How the fake repositories behave: how long they take to answer, and whether they fail. One instance can be
/// shared by all of them, so a single switch makes the whole app fail (to see the error states) or answer at once.
class FakeBehavior {
  FakeBehavior({
    this.minLatency = const Duration(milliseconds: 200),
    this.maxLatency = const Duration(milliseconds: 600),
    int seed = 11,
    this.failing = false,
  }) : _random = Random(seed);

  /// Answers at once, for tests.
  FakeBehavior.instant() : this(minLatency: Duration.zero, maxLatency: Duration.zero);

  final Duration minLatency;
  final Duration maxLatency;
  final Random _random;

  /// While true every call fails with a network error. Switch it on to see the error states of the screens.
  bool failing;

  int _failNext = 0;

  /// The next [count] calls fail, then everything works again: to test one failure and its retry.
  void failNext([int count = 1]) => _failNext = count;

  /// How long the next call takes: somewhere between [minLatency] and [maxLatency].
  Duration nextLatency() {
    final span = maxLatency.inMilliseconds - minLatency.inMilliseconds;
    if (span <= 0) return minLatency;
    return minLatency + Duration(milliseconds: _random.nextInt(span + 1));
  }

  /// Waits for the latency, fails if told to, otherwise runs [body].
  Future<T> run<T>(FutureOr<T> Function() body) async {
    final wait = nextLatency();
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (failing || _failNext > 0) {
      if (_failNext > 0) _failNext--;
      throw const RepositoryException('Simulated network failure', kind: RepositoryErrorKind.network);
    }
    return body();
  }
}
