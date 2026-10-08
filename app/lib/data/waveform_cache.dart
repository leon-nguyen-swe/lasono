import '../models/track.dart';
import 'track_repository.dart';

/// The waveforms of tracks, kept in memory.
///
/// A list of tracks carries no waveform (200 numbers for each of 20 tracks would bloat it), but every card of the list
/// draws one. So a card asks this cache, which reads the track on its own once, keeps the peaks, and never asks twice for
/// the same track, even when two cards (or the card and the player) ask at the same moment.
class WaveformCache {
  WaveformCache(this._tracks);

  final TrackRepository _tracks;

  final Map<String, List<double>> _peaks = {};
  final Map<String, Future<List<double>?>> _inFlight = {};

  /// The peaks if they are known now, from the track itself or from an earlier read.
  List<double>? cached(Track track) => track.waveform ?? _peaks[track.id];

  /// The peaks of [track], read from the server if needed. Null when the track has none yet (it is still processing,
  /// or failed) or when it could not be read; a failure is not remembered, so the next ask tries again.
  Future<List<double>?> peaksOf(Track track) {
    final known = cached(track);
    if (known != null) return Future.value(known);
    if (!track.isReady) return Future.value();
    return _inFlight[track.id] ??= _load(track.id);
  }

  Future<List<double>?> _load(String id) async {
    try {
      final peaks = (await _tracks.getTrack(id)).waveform;
      if (peaks != null) _peaks[id] = peaks;
      return peaks;
    } on Object {
      return null;
    } finally {
      _inFlight.remove(id);
    }
  }

  /// Forgets what is kept (for example after a track was replaced).
  void clear() => _peaks.clear();
}
