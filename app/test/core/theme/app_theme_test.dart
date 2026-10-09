import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/theme/theme.dart';

import 'true_type_character_map.dart';

void main() {
  for (final entry in {'dark': AppTheme.dark, 'light': AppTheme.light}.entries) {
    final theme = entry.value;
    final colors = entry.key == 'dark' ? AppColors.dark : AppColors.light;

    group('${entry.key} theme', () {
      test('has the brightness it is named after', () {
        expect(theme.brightness, entry.key == 'dark' ? Brightness.dark : Brightness.light);
      });

      test('carries its colour tokens as a theme extension', () {
        expect(theme.extension<AppColors>(), same(colors));
      });

      test('paints the page with the background token and links the accent to the colour scheme', () {
        expect(theme.scaffoldBackgroundColor, colors.background);
        expect(theme.colorScheme.primary, colors.accent);
        expect(theme.colorScheme.onPrimary, colors.onAccent);
        expect(theme.colorScheme.error, colors.error);
      });

      test('uses Be Vietnam Pro for every text style', () {
        final styles = [
          theme.textTheme.displaySmall,
          theme.textTheme.titleMedium,
          theme.textTheme.bodyMedium,
          theme.textTheme.labelSmall,
        ];
        for (final style in styles) {
          expect(style!.fontFamily, AppTypography.fontFamily);
        }
      });

      test('the type scale goes down from the title to the caption and no text is smaller than 11', () {
        final t = theme.textTheme;
        final sizes = [
          t.displaySmall!.fontSize!,
          t.headlineMedium!.fontSize!,
          t.titleLarge!.fontSize!,
          t.titleMedium!.fontSize!,
          t.bodyMedium!.fontSize!,
          t.bodySmall!.fontSize!,
          t.labelSmall!.fontSize!,
        ];
        for (var i = 1; i < sizes.length; i++) {
          expect(sizes[i], lessThanOrEqualTo(sizes[i - 1]));
        }
        expect(sizes.last, greaterThanOrEqualTo(11));
      });

      test('every text style leaves room for the Vietnamese marks (line height at least 1.3)', () {
        // Stacked marks like "ề" or "ặ" are tall; a tight line cuts them off or makes them touch the line above.
        for (final style in [
          theme.textTheme.displaySmall!,
          theme.textTheme.titleMedium!,
          theme.textTheme.bodyMedium!,
          theme.textTheme.bodySmall!,
        ]) {
          expect(style.height!, greaterThanOrEqualTo(1.3));
        }
      });

      test('primary buttons are at least 44 logical pixels high, so they can be touched', () {
        final style = theme.filledButtonTheme.style!;
        expect(style.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(44));
      });

      test('a filled button is the accent, lighter under the pointer, grey when disabled', () {
        final style = theme.filledButtonTheme.style!;
        expect(style.backgroundColor!.resolve({}), colors.accent);
        expect(style.backgroundColor!.resolve({WidgetState.hovered}), colors.accentHover);
        expect(style.backgroundColor!.resolve({WidgetState.disabled}), colors.surfaceHigh);
        expect(style.foregroundColor!.resolve({}), colors.onAccent);
      });

      test('a focused text field is outlined with the accent', () {
        final focused = theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
        expect(focused.borderSide.color, colors.accent);
        expect(focused.borderSide.width, greaterThanOrEqualTo(2));
      });
    });
  }

  group('the bundled font', () {
    // Every letter of the Vietnamese alphabet with every tone: 134 precomposed letters.
    const lower = 'aàáảãạăằắẳẵặâầấẩẫậeèéẻẽẹêềếểễệiìíỉĩịoòóỏõọôồốổỗộơờớởỡợuùúủũụưừứửữựyỳýỷỹỵđ';
    final letters = {...lower.runes, ...lower.toUpperCase().runes};

    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      test('BeVietnamPro-$weight has a glyph for every Vietnamese letter', () {
        // flutter test draws all text with a stand-in font, so measuring text proves nothing here.
        // The font file itself is asked instead: does its character map know each letter?
        final bytes = File('assets/fonts/BeVietnamPro-$weight.ttf').readAsBytesSync();
        final cmap = TrueTypeCharacterMap.parse(bytes);
        final missing = [for (final r in letters) if (!cmap.hasGlyph(r)) String.fromCharCode(r)];
        expect(missing, isEmpty, reason: 'no glyph for: ${missing.join(' ')}');
      });
    }

    test('the check can fail: a letter no Latin font draws is reported missing', () {
      final bytes = File('assets/fonts/BeVietnamPro-Regular.ttf').readAsBytesSync();
      final cmap = TrueTypeCharacterMap.parse(bytes);
      expect(cmap.hasGlyph('語'.runes.first), isFalse);
      expect(cmap.hasGlyph('ặ'.runes.first), isTrue);
    });

    test('pubspec.yaml registers the four weights under the family the theme uses', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: ${AppTypography.fontFamily}'));
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        expect(pubspec, contains('assets/fonts/BeVietnamPro-$weight.ttf'));
      }
    });
  });

  group('ThemeController', () {
    test('starts in dark mode', () {
      expect(ThemeController().mode, ThemeMode.dark);
    });

    test('toggle goes dark -> light -> dark and tells the listeners each time', () {
      final controller = ThemeController();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.toggle();
      expect(controller.mode, ThemeMode.light);
      controller.toggle();
      expect(controller.mode, ThemeMode.dark);
      expect(notified, 2);
    });

    test('setting the mode it already has tells nobody', () {
      final controller = ThemeController();
      var notified = 0;
      controller.addListener(() => notified++);
      controller.setMode(ThemeMode.dark);
      expect(notified, 0);
    });
  });
}
