import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/theme/app_tokens.dart';

void main() {
  group('spacing and radius scales', () {
    test('spacing grows strictly and starts small', () {
      expect(AppSpacing.scale.first, lessThanOrEqualTo(2));
      for (var i = 1; i < AppSpacing.scale.length; i++) {
        expect(AppSpacing.scale[i], greaterThan(AppSpacing.scale[i - 1]));
      }
    });

    test('spacing from xs up is a multiple of 4, so layouts snap to a grid', () {
      for (final value in AppSpacing.scale.where((v) => v >= AppSpacing.xs)) {
        expect(value % 4, 0, reason: '$value is not on the 4 px grid');
      }
    });

    test('radius grows strictly and the pill is bigger than any box', () {
      for (var i = 1; i < AppRadius.scale.length; i++) {
        expect(AppRadius.scale[i], greaterThan(AppRadius.scale[i - 1]));
      }
      expect(AppRadius.pill, greaterThan(AppRadius.scale.last * 10));
    });
  });

  group('breakpoints', () {
    test('a phone, a tablet and a desktop window are told apart', () {
      expect(AppBreakpoints.of(360), ScreenSize.compact);
      expect(AppBreakpoints.of(599.9), ScreenSize.compact);
      expect(AppBreakpoints.of(600), ScreenSize.medium);
      expect(AppBreakpoints.of(1023.9), ScreenSize.medium);
      expect(AppBreakpoints.of(1024), ScreenSize.expanded);
      expect(AppBreakpoints.of(1920), ScreenSize.expanded);
    });

    testWidgets('the size is read from the window of the context', (tester) async {
      late ScreenSize seen;
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              seen = context.screenSize;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, ScreenSize.medium);
    });
  });

  group('durations and curves', () {
    test('fast < normal < slow, and none is longer than half a second', () {
      expect(AppDurations.fast, lessThan(AppDurations.normal));
      expect(AppDurations.normal, lessThan(AppDurations.slow));
      expect(AppDurations.slow, lessThanOrEqualTo(const Duration(milliseconds: 500)));
    });
  });

  group('elevation', () {
    test('a higher level has a bigger blur and offset, in both brightnesses', () {
      for (final brightness in Brightness.values) {
        final low = AppElevation.low(brightness).single;
        final medium = AppElevation.medium(brightness).single;
        final high = AppElevation.high(brightness).single;
        expect(medium.blurRadius, greaterThan(low.blurRadius));
        expect(high.blurRadius, greaterThan(medium.blurRadius));
        expect(high.offset.dy, greaterThan(low.offset.dy));
      }
    });

    test('a shadow is stronger on a dark surface, where it is harder to see', () {
      final dark = AppElevation.medium(Brightness.dark).single.color.a;
      final light = AppElevation.medium(Brightness.light).single.color.a;
      expect(dark, greaterThan(light));
    });
  });

  group('cover gradients', () {
    test('there are enough pairs to avoid obvious repeats, and each pair is two colours', () {
      expect(AppGradients.cover.length, greaterThanOrEqualTo(6));
      for (final (a, b) in AppGradients.cover) {
        expect(a, isNot(b));
      }
    });
  });
}
