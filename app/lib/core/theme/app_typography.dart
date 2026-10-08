import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The type scale. One family, Be Vietnam Pro (bundled, see pubspec.yaml), which draws every Vietnamese
/// letter with its marks (ặ ế ữ ơ ư đ) without falling back to another font.
abstract final class AppTypography {
  static const String fontFamily = 'BeVietnamPro';

  /// For times and counters that change while they are on screen (1:07, 12 345): every digit has the same
  /// width, so the text does not jitter. Falls back to normal digits if the font has no such feature.
  static const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

  static TextTheme textTheme(AppColors c) {
    TextStyle style(
      double size,
      double height,
      FontWeight weight, {
      Color? color,
      double letterSpacing = 0,
    }) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          height: height / size,
          fontWeight: weight,
          color: color ?? c.textPrimary,
          letterSpacing: letterSpacing,
        );

    return TextTheme(
      // A title of a page, or the name of a track in its hero.
      displaySmall: style(32, 44, FontWeight.w700, letterSpacing: -0.4),
      headlineMedium: style(24, 32, FontWeight.w700, letterSpacing: -0.2),
      headlineSmall: style(20, 28, FontWeight.w700),
      titleLarge: style(20, 28, FontWeight.w600),
      titleMedium: style(16, 24, FontWeight.w600),
      titleSmall: style(14, 20, FontWeight.w600),
      bodyLarge: style(16, 24, FontWeight.w400),
      bodyMedium: style(14, 20, FontWeight.w400),
      bodySmall: style(12, 16, FontWeight.w400, color: c.textSecondary),
      labelLarge: style(14, 20, FontWeight.w600),
      labelMedium: style(12, 16, FontWeight.w500, color: c.textSecondary),
      labelSmall: style(11, 16, FontWeight.w500, color: c.textSecondary, letterSpacing: 0.2),
    );
  }
}
