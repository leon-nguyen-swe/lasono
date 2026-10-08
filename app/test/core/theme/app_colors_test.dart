import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/theme/app_colors.dart';
import 'package:lasono_app/core/theme/contrast.dart';

// WCAG 2.1: 4.5:1 for body text, 3:1 for large text and for graphics that carry meaning.
const _text = 4.5;
const _graphic = 3.0;

void main() {
  group('contrastRatio', () {
    test('is 21 for black on white and 1 for the same colour', () {
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(21, 0.01));
      expect(contrastRatio(const Color(0xFF123456), const Color(0xFF123456)), closeTo(1, 0.0001));
    });

    test('does not depend on the order of the colours', () {
      const a = Color(0xFF9B82FF);
      const b = Color(0xFF0B0D12);
      expect(contrastRatio(a, b), contrastRatio(b, a));
    });

    test('matches a value checked by hand with a contrast checker', () {
      // #9B82FF on #0B0D12 is 6.51:1 (WebAIM contrast checker).
      expect(contrastRatio(const Color(0xFF9B82FF), const Color(0xFF0B0D12)), closeTo(6.51, 0.02));
    });
  });

  for (final entry in {'dark': AppColors.dark, 'light': AppColors.light}.entries) {
    final name = entry.key;
    final c = entry.value;

    group('$name palette', () {
      final surfaces = {
        'background': c.background,
        'surface': c.surface,
        'surfaceRaised': c.surfaceRaised,
        'surfaceHigh': c.surfaceHigh,
      };

      for (final s in surfaces.entries) {
        test('primary and secondary text are readable on ${s.key}', () {
          expect(contrastRatio(c.textPrimary, s.value), greaterThanOrEqualTo(_text));
          expect(contrastRatio(c.textSecondary, s.value), greaterThanOrEqualTo(_text));
        });
      }

      for (final key in ['background', 'surface', 'surfaceRaised']) {
        test('muted text and the accent are readable on $key', () {
          expect(contrastRatio(c.textMuted, surfaces[key]!), greaterThanOrEqualTo(_text));
          expect(contrastRatio(c.accent, surfaces[key]!), greaterThanOrEqualTo(_text));
        });
      }

      test('text on an accent button is readable, also when the pointer is over it', () {
        expect(contrastRatio(c.onAccent, c.accent), greaterThanOrEqualTo(_text));
        expect(contrastRatio(c.onAccent, c.accentHover), greaterThanOrEqualTo(_text));
      });

      test('the meaning colours are readable as text on the surfaces', () {
        for (final colour in [c.success, c.warning, c.error]) {
          expect(contrastRatio(colour, c.background), greaterThanOrEqualTo(_text));
          expect(contrastRatio(colour, c.surface), greaterThanOrEqualTo(_text));
        }
      });

      test('the border of an input can be seen on the surfaces it sits on', () {
        expect(contrastRatio(c.inputBorder, c.surface), greaterThanOrEqualTo(_graphic));
        expect(contrastRatio(c.inputBorder, c.background), greaterThanOrEqualTo(_graphic));
      });

      test('the waveform colours can be told from the surfaces under them', () {
        for (final surface in [c.surface, c.surfaceRaised]) {
          expect(contrastRatio(c.waveformPlayed, surface), greaterThanOrEqualTo(_graphic));
          expect(contrastRatio(c.waveformUnplayed, surface), greaterThanOrEqualTo(_graphic));
          expect(contrastRatio(c.waveformHover, surface), greaterThanOrEqualTo(_graphic));
        }
      });

      test('the played part of the waveform is told from the part not played yet', () {
        // Not by colour alone: the played bars are also the ones before the playhead. Still, a
        // visible difference is required, otherwise the progress cannot be read.
        expect(contrastRatio(c.waveformPlayed, c.waveformUnplayed), greaterThanOrEqualTo(1.5));
      });
    });
  }

  test('the dark palette is not the light palette', () {
    expect(AppColors.dark.background, isNot(AppColors.light.background));
    expect(AppColors.dark.textPrimary, isNot(AppColors.light.textPrimary));
  });

  test('the accent is not orange (SoundCloud\'s colour)', () {
    for (final accent in [AppColors.dark.accent, AppColors.light.accent]) {
      final hue = HSVColor.fromColor(accent).hue;
      // Orange sits roughly between 15 and 45 degrees of the colour wheel.
      expect(hue < 15 || hue > 45, isTrue, reason: 'hue $hue is in the orange band');
    }
  });

  test('lerp at 0 and 1 gives the two palettes', () {
    expect(AppColors.dark.lerp(AppColors.light, 0).background, AppColors.dark.background);
    expect(AppColors.dark.lerp(AppColors.light, 1).background, AppColors.light.background);
  });
}
