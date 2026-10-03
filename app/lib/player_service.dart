import 'dart:async';

import 'package:just_audio/just_audio.dart';

class PlaybackException implements Exception {
  const PlaybackException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class PlayerService {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;

  /// Prepares [url] for playback. Throws [PlaybackException] if it cannot load.
  Future<void> load(Uri url);

  /// Starts playback and returns immediately (does not wait for the track to end).
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioPlayerService implements PlayerService {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Future<void> load(Uri url) async {
    try {
      await _player.setUrl(url.toString());
    } on PlayerException catch (e) {
      throw PlaybackException('$e');
    } on PlayerInterruptedException catch (e) {
      throw PlaybackException('$e');
    }
  }

  // AudioPlayer.play() only completes when playback ends or is paused, so it
  // must not be awaited here.
  @override
  Future<void> play() async {
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
