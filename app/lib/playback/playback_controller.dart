import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/repository_exception.dart';
import '../models/track.dart';
import '../player_service.dart';

/// What plays now and what plays next, for the whole app. It lives above the router, so the music goes on while
/// the user moves from page to page, and the player bar at the bottom shows and controls it.
///
/// It does not decode or fetch audio itself: [PlayerService] does that (in the browser the audio element asks
/// the server for the bytes it needs with `Range` requests, which is also what makes seeking fast). This class
/// decides which track is loaded, when to go on to the next one, and what the user sees.
///
/// The queue is the list the user pressed play in: its tracks, in its order. A track that cannot be played
/// (still processing, or failed) stays in the queue but is skipped.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this._player,
    required this._streamUrl,
    this.restartAfter = const Duration(seconds: 3),
  }) {
    _subscriptions.addAll([
      _player.positionStream.listen((value) => position.value = value),
      _player.durationStream.listen((value) {
        // Before a track is loaded the player reports nothing, or the length of the previous one.
        if (value != null && _loadedTrackId != null) duration.value = value;
      }),
      _player.playingStream.listen(_setPlaying),
      _player.completedStream.listen((_) => unawaited(_onCompleted())),
    ]);
  }

  final PlayerService _player;
  final Future<Uri> Function(String trackId) _streamUrl;

  /// Pressing "previous" after this much of a track has played goes back to its start instead of the track before.
  final Duration restartAfter;

  final _subscriptions = <StreamSubscription<Object?>>[];

  List<Track> _queue = const [];
  int _index = 0;
  String? _sourceId;
  String? _loadedTrackId;
  bool _playing = false;
  bool _loading = false;
  String? _error;
  double _volume = 1;
  double _volumeBeforeMute = 1;
  int _loadToken = 0;
  bool _disposed = false;

  /// Where playback is, and how long the track is. They change many times a second, so they are separate
  /// notifiers: only the widgets that draw them rebuild, not everything that listens to the controller.
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);

  List<Track> get queue => _queue;
  int get index => _index;

  /// The list the queue came from (see [playQueue]), or null.
  String? get sourceId => _sourceId;

  Track? get current => _queue.isEmpty ? null : _queue[_index];

  bool get playing => _playing;

  /// True from pressing play until the audio is ready.
  bool get loading => _loading;

  /// Why the current track cannot be played, or null.
  String? get error => _error;

  double get volume => _volume;
  bool get muted => _volume == 0;

  bool get hasNext => _nextPlayable() != null;
  bool get hasPrevious => _previousPlayable() != null;

  bool _isPlayable(Track track) => track.isReady;

  // The player confirms with an event a moment after it is told to play or pause. The buttons must not wait for
  // that, so what was just asked is taken as the state at once, and the events only correct it.
  void _setPlaying(bool value) {
    if (value == _playing) return;
    _playing = value;
    notifyListeners();
  }

  int? _nextPlayable() {
    for (var i = _index + 1; i < _queue.length; i++) {
      if (_isPlayable(_queue[i])) return i;
    }
    return null;
  }

  int? _previousPlayable() {
    for (var i = _index - 1; i >= 0; i--) {
      if (_isPlayable(_queue[i])) return i;
    }
    return null;
  }

  /// Makes [tracks] the queue and plays the one at [startIndex]. If that one cannot be played, the next one that
  /// can is played. [sourceId] names the list (for [extendQueue]).
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0, String? sourceId}) async {
    if (tracks.isEmpty) return;
    _queue = List.unmodifiable(tracks);
    _sourceId = sourceId;
    var start = startIndex.clamp(0, tracks.length - 1);
    if (!_isPlayable(tracks[start])) {
      final later = tracks.indexWhere(_isPlayable, start);
      if (later == -1) {
        _index = start;
        _loadedTrackId = null;
        _error = 'No track in this list can be played';
        _loading = false;
        notifyListeners();
        return;
      }
      start = later;
    }
    _index = start;
    await _loadCurrent();
  }

  /// Plays one track on its own (a queue of one).
  Future<void> play(Track track) => playQueue([track]);

  /// Adds the tracks of a list that grew (the next page of a feed) to the end of the queue, if the queue came from
  /// that same list. Tracks that are in the queue already are not added twice.
  void extendQueue(String sourceId, List<Track> more) {
    if (_sourceId == null || _sourceId != sourceId) return;
    final known = {for (final t in _queue) t.id};
    final added = [for (final t in more) if (!known.contains(t.id)) t];
    if (added.isEmpty) return;
    _queue = List.unmodifiable([..._queue, ...added]);
    notifyListeners();
  }

  /// Puts a newer version of a track (it was liked, or renamed) in the queue, wherever it is.
  void replaceTrack(Track track) {
    if (!_queue.any((t) => t.id == track.id)) return;
    _queue = List.unmodifiable([for (final t in _queue) t.id == track.id ? track : t]);
    notifyListeners();
  }

  Future<void> _loadCurrent() async {
    final track = current;
    if (track == null) return;
    final token = ++_loadToken;

    _loading = true;
    _error = null;
    _loadedTrackId = null;
    position.value = Duration.zero;
    // The length is already known from the track, so the bar is right before the audio says so.
    duration.value = Duration(milliseconds: track.durationMs ?? 0);
    notifyListeners();

    try {
      final address = await _streamUrl(track.id);
      if (token != _loadToken) return; // somebody pressed another track meanwhile
      await _player.load(address);
      if (token != _loadToken) return;
      _loadedTrackId = track.id;
      _loading = false;
      _playing = true;
      notifyListeners();
      await _player.play();
    } on RepositoryException catch (e) {
      _fail(token, e.message);
    } on PlaybackException {
      _fail(token, 'Cannot play this track');
    }
  }

  void _fail(int token, String message) {
    if (token != _loadToken) return;
    _loading = false;
    _playing = false;
    _error = message;
    notifyListeners();
  }

  /// Pauses, or plays; if the track is not loaded (nothing was loaded yet, or the last try failed) it is loaded.
  Future<void> togglePlay() async {
    if (current == null) return;
    if (_loading) return;
    if (_loadedTrackId != current!.id || _error != null) {
      await _loadCurrent();
      return;
    }
    if (_playing) {
      _setPlaying(false);
      await _player.pause();
    } else {
      _setPlaying(true);
      await _player.play();
    }
  }

  Future<void> pause() async {
    if (!_playing) return;
    _setPlaying(false);
    await _player.pause();
  }

  /// Plays the next track of the queue that can be played. Does nothing at the end.
  Future<void> next() async {
    final target = _nextPlayable();
    if (target == null) return;
    _index = target;
    await _loadCurrent();
  }

  /// A track that has played for a while starts again; otherwise the track before it is played.
  Future<void> previous() async {
    if (current == null) return;
    final target = _previousPlayable();
    if (position.value > restartAfter || target == null) {
      await seek(Duration.zero);
      return;
    }
    _index = target;
    await _loadCurrent();
  }

  /// Jumps to [target], kept inside the track. In the browser this makes the audio element ask the server for
  /// the bytes from there (a `Range` request).
  Future<void> seek(Duration target) async {
    if (current == null || _loadedTrackId == null) return;
    final end = duration.value;
    var clamped = target < Duration.zero ? Duration.zero : target;
    if (end > Duration.zero && clamped > end) clamped = end;
    position.value = clamped;
    await _player.seek(clamped);
  }

  /// Jumps to a fraction (0 to 1) of the length of the track.
  Future<void> seekFraction(double fraction) =>
      seek(Duration(milliseconds: (duration.value.inMilliseconds * fraction.clamp(0.0, 1.0)).round()));

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_volume > 0) _volumeBeforeMute = _volume;
    notifyListeners();
    await _player.setVolume(_volume);
  }

  Future<void> toggleMute() => setVolume(muted ? _volumeBeforeMute : 0);

  /// Stops and empties the queue (for example on a log out).
  Future<void> stop() async {
    _loadToken++;
    _queue = const [];
    _index = 0;
    _sourceId = null;
    _loadedTrackId = null;
    _loading = false;
    _error = null;
    _playing = false;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    notifyListeners();
    await _player.stop();
  }

  Future<void> _onCompleted() async {
    if (_disposed || _loading) return;
    if (_nextPlayable() != null) {
      await next();
      return;
    }
    // The end of the queue: stop on the last track, back at its start, so play can start it again. (just_audio
    // keeps "playing" true after the end, and a seek would then make no sound.)
    position.value = Duration.zero;
    _setPlaying(false);
    await _player.pause();
    await _player.seek(Duration.zero);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    position.dispose();
    duration.dispose();
    super.dispose();
  }
}

/// Gives the widgets below it the playback controller: `PlaybackScope.of(context)`.
///
/// It holds a function that makes the controller, not the controller itself, so the audio player (which needs
/// the browser) is only made when something first asks for it.
class PlaybackScope extends InheritedWidget {
  const PlaybackScope({super.key, required this.read, required super.child});

  final PlaybackController Function() read;

  /// Null when there is no scope above.
  static PlaybackController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackScope>()?.read();

  static PlaybackController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PlaybackScope>();
    assert(scope != null, 'No PlaybackScope above this widget: wrap the app in one');
    return scope!.read();
  }

  @override
  bool updateShouldNotify(PlaybackScope oldWidget) => read != oldWidget.read;
}
