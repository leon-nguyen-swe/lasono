import 'dart:math' as math;

/// How far below the loudest part a bar may be and still be told apart from silence. Parts quieter than the
/// quietest tenth of the track are drawn as the shortest bar.
const _lowQuantile = 0.1;

/// The least range of loudness that is spread over the whole height. Without it a track that is almost the same all
/// the way would have its tiny differences blown up into noise.
const _minRange = 0.2;

/// Above 1, so the louder parts stand out from the middle ones and the shape has hills instead of a plateau.
const _gamma = 1.8;

/// The shortest bar: a quiet part is still a visible bar.
const _floor = 0.1;

/// Below this the track is taken as silent and left alone.
const _silence = 0.02;

/// Makes the peaks of a track easier to read as a shape.
///
/// The backend keeps the loudest sample of each of the 200 parts of a track. For most songs that is close to full
/// scale in every part (90% of the bars of a real song were between 0.92 and 1.0), so drawn as they are they make a
/// flat band; and a quiet track is drawn very low. This spreads each track over its own range: the loudest part is
/// full height, the quietest tenth is short, and the louder-than-usual parts are emphasised. The order of the bars
/// never changes (louder is always taller or equal), a track that is the same all the way stays flat, and silence
/// stays silence. A better fix is in the backend (a loudness average per part, not the loudest sample): see
/// `docs/ui-handoff.md`.
List<double> emphasizePeaks(List<double> peaks) {
  if (peaks.isEmpty) return peaks;
  final sorted = [...peaks]..sort();
  final highest = sorted.last;
  if (highest < _silence) return peaks;

  final lowest = sorted[((sorted.length - 1) * _lowQuantile).floor()];
  final range = math.max(highest - lowest, _minRange);
  final base = highest - range;
  return [
    for (final peak in peaks) _floor + (1 - _floor) * math.pow(((peak - base) / range).clamp(0.0, 1.0), _gamma).toDouble(),
  ];
}
