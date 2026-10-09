import 'dart:async';

import 'package:lasono_app/player_service.dart';

/// In-memory [PlayerService] so widget tests do not need the browser plugin.
///
/// Like just_audio, the position/duration/playing streams replay their latest
/// value to every new listener, so stale state from a previous track is visible.
class FakePlayerService implements PlayerService {
  final loaded = <Uri>[];
  var playCalls = 0;
  var pauseCalls = 0;
  var stopCalls = 0;
  final seeks = <Duration>[];
  final volumes = <double>[];

  /// When set, [load] throws it.
  Object? loadError;

  /// When set, [load] waits for it before finishing.
  Completer<void>? loadGate;

  /// Duration the player reports once a [load] finishes (null = unknown).
  Duration? durationOnLoad;

  Duration _lastPosition = Duration.zero;
  Duration? _lastDuration;
  bool _lastPlaying = false;

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();

  void emitPosition(Duration value) {
    _lastPosition = value;
    _position.add(value);
  }

  void emitDuration(Duration? value) {
    _lastDuration = value;
    _duration.add(value);
  }

  void emitCompleted() => _completed.add(null);

  void _setPlaying(bool value) {
    _lastPlaying = value;
    _playing.add(value);
  }

  static Stream<T> _replaying<T>(T Function() latest, Stream<T> live) {
    return Stream.multi((controller) {
      controller.add(latest());
      final subscription = live.listen(controller.add);
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Stream<Duration> get positionStream =>
      _replaying(() => _lastPosition, _position.stream);

  @override
  Stream<Duration?> get durationStream =>
      _replaying(() => _lastDuration, _duration.stream);

  @override
  Stream<bool> get playingStream =>
      _replaying(() => _lastPlaying, _playing.stream);

  @override
  Stream<void> get completedStream => _completed.stream;

  @override
  Future<void> load(Uri url) async {
    loaded.add(url);
    final gate = loadGate;
    if (gate != null) await gate.future;
    final error = loadError;
    if (error != null) throw error;
    emitDuration(durationOnLoad);
    emitPosition(Duration.zero);
  }

  @override
  Future<void> play() async {
    playCalls++;
    _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _setPlaying(false);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _setPlaying(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _completed.close();
  }
}
