import 'package:flutter/material.dart';

/// Spacing scale (logical pixels). Layout uses these and nothing else, so the app keeps one rhythm.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;

  static const List<double> scale = [xxs, xs, sm, md, lg, xl, xxl, xxxl, huge];
}

abstract final class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Fully round ends: pills and circular buttons.
  static const double pill = 999;

  static const List<double> scale = [xs, sm, md, lg, xl];

  static BorderRadius all(double radius) => BorderRadius.circular(radius);
}

/// Shadows. On a dark surface a shadow is hardly visible, so it is stronger there and a light hairline
/// ([AppColors.outline]) does the separating work.
abstract final class AppElevation {
  static List<BoxShadow> low(Brightness brightness) => _shadow(brightness, 0.10, 0.28, 4, 1);
  static List<BoxShadow> medium(Brightness brightness) => _shadow(brightness, 0.14, 0.40, 14, 6);
  static List<BoxShadow> high(Brightness brightness) => _shadow(brightness, 0.20, 0.55, 32, 14);

  static List<BoxShadow> _shadow(
    Brightness brightness,
    double lightOpacity,
    double darkOpacity,
    double blur,
    double dy,
  ) {
    final dark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? darkOpacity : lightOpacity),
        blurRadius: blur,
        offset: Offset(0, dy),
      ),
    ];
  }
}

abstract final class AppDurations {
  /// Hover and pressed feedback.
  static const Duration fast = Duration(milliseconds: 120);

  /// Most transitions: a button changing state, a panel opening.
  static const Duration normal = Duration(milliseconds: 200);

  /// A whole page, or something large moving.
  static const Duration slow = Duration(milliseconds: 320);
}

abstract final class AppCurves {
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
}

enum ScreenSize { compact, medium, expanded }

/// Width breakpoints, in logical pixels. compact: a phone, medium: a tablet or a narrow window,
/// expanded: a desktop window.
abstract final class AppBreakpoints {
  static const double compact = 600;
  static const double medium = 1024;

  /// The widest the page content gets; a wider window gets empty margins.
  static const double contentMaxWidth = 1200;

  static ScreenSize of(double width) {
    if (width < compact) return ScreenSize.compact;
    if (width < medium) return ScreenSize.medium;
    return ScreenSize.expanded;
  }
}

extension ScreenSizeContext on BuildContext {
  ScreenSize get screenSize => AppBreakpoints.of(MediaQuery.sizeOf(this).width);
}

/// Pairs of colours for the cover of a track that has no image. One pair is picked from the track id, so
/// the same track always has the same cover.
abstract final class AppGradients {
  static const List<(Color, Color)> cover = [
    (Color(0xFF7C5CFF), Color(0xFFFF6FB5)),
    (Color(0xFF2BB3FF), Color(0xFF7C5CFF)),
    (Color(0xFF16C79A), Color(0xFF2BB3FF)),
    (Color(0xFFFF6FB5), Color(0xFFFFB86B)),
    (Color(0xFF5B3DE0), Color(0xFF16C79A)),
    (Color(0xFFE5489B), Color(0xFF5B3DE0)),
    (Color(0xFF0EA5A5), Color(0xFF7C5CFF)),
    (Color(0xFFF2709C), Color(0xFF3B82F6)),
  ];
}
