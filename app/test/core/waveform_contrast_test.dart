import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/waveform_contrast.dart';

double _spread(List<double> values) {
  final sorted = [...values]..sort();
  return sorted.last - sorted.first;
}

void main() {
  group('emphasizePeaks', () {
    test('has nothing to do for no peaks', () {
      expect(emphasizePeaks(const []), isEmpty);
    });

    test('a loud track whose every part peaks near the top (the backend takes the loudest sample of each part) gets visible ups and downs', () {
      // What a mastered song looks like once only the loudest sample of each part is kept: 0.92 to 1.0.
      final loud = [for (var i = 0; i < 200; i++) 0.92 + 0.08 * ((i * 37) % 100) / 100];
      expect(_spread(loud), lessThan(0.09));

      final shown = emphasizePeaks(loud);

      expect(_spread(shown), greaterThan(0.5));
    });

    test('a quiet track is drawn as tall as a loud one, so it fills the height', () {
      final quiet = [0.02, 0.05, 0.3, 0.1, 0.07, 0.02];
      expect(emphasizePeaks(quiet).reduce((a, b) => a > b ? a : b), 1.0);
    });

    test('louder stays taller: the order of the bars is never changed', () {
      final peaks = [0.1, 0.9, 0.5, 0.95, 0.2, 0.7, 0.93, 0.4];
      final shown = emphasizePeaks(peaks);
      for (var a = 0; a < peaks.length; a++) {
        for (var b = 0; b < peaks.length; b++) {
          if (peaks[a] < peaks[b]) expect(shown[a], lessThanOrEqualTo(shown[b]), reason: '${peaks[a]} vs ${peaks[b]}');
          if (peaks[a] == peaks[b]) expect(shown[a], shown[b]);
        }
      }
    });

    test('every bar stays inside the view and none vanishes', () {
      final shown = emphasizePeaks([0.0, 0.0, 0.4, 1.0, 0.7, 0.01]);
      expect(shown.every((v) => v >= 0.1 && v <= 1.0), isTrue, reason: '$shown');
    });

    test('a track that is the same all the way (a tone) stays flat', () {
      final tone = List.filled(50, 0.24);
      expect(_spread(emphasizePeaks(tone)), 0);
    });

    test('silence stays silence, and is not blown up to full height', () {
      final silent = List.filled(20, 0.0);
      expect(emphasizePeaks(silent), silent);
    });

    test('the list it was given is not changed', () {
      final peaks = [0.9, 0.95, 1.0];
      emphasizePeaks(peaks);
      expect(peaks, [0.9, 0.95, 1.0]);
    });
  });
}
