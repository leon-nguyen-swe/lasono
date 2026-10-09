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

  /// Emits each time playback reaches the end of the track.
  Stream<void> get completedStream;

  /// Prepares [url] for playback. Throws [PlaybackException] if it cannot load.
  Future<void> load(Uri url);

  /// Starts playback and returns immediately (does not wait for the track to end).
  Future<void> play();
  Future<void> pause();
  Future<void> stop();

  /// Jumps to [position]. In the browser this makes the audio element issue a
  /// new `Range` request to the stream endpoint.
  Future<void> seek(Duration position);

  /// Sets the loudness, from 0 (silent) to 1 (full). It stays for the next tracks.
  Future<void> setVolume(double volume);
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

  // just_audio keeps `playing == true` after the end of the track, so without
  // reacting to this the player stays "playing" and later seeks are silent.
  @override
  Stream<void> get completedStream => _player.processingStateStream
      .where((state) => state == ProcessingState.completed);

  @override
  Future<void> load(Uri url) async {
    try {
      // A new track on a player that is playing another one: in the browser the audio element kept the old
      // source and no request for the new one was made (the old track went on playing under the new title).
      // Stopping first makes just_audio build a fresh platform player for the new address.
      await _player.stop();
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
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> dispose() => _player.dispose();
}
