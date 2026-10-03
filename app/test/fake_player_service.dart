import 'dart:async';

import 'package:lasono_app/player_service.dart';

/// In-memory [PlayerService] so widget tests do not need the browser plugin.
class FakePlayerService implements PlayerService {
  final loaded = <Uri>[];
  var playCalls = 0;
  var pauseCalls = 0;
  var stopCalls = 0;

  /// When set, [load] throws it.
  Object? loadError;

  /// When set, [load] waits for it before finishing.
  Completer<void>? loadGate;

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _playing = StreamController<bool>.broadcast();

  void emitPosition(Duration value) => _position.add(value);
  void emitDuration(Duration? value) => _duration.add(value);

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<void> load(Uri url) async {
    loaded.add(url);
    final gate = loadGate;
    if (gate != null) await gate.future;
    final error = loadError;
    if (error != null) throw error;
  }

  @override
  Future<void> play() async {
    playCalls++;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _playing.add(false);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _playing.add(false);
  }

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _playing.close();
  }
}
