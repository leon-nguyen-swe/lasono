import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// WCAG 2.x contrast ratio between two opaque colours, from 1 (same colour) to 21 (black on white).
///
/// Body text needs at least 4.5; large text and meaningful graphics (borders of an input, the bars of a
/// waveform) need at least 3. See https://www.w3.org/TR/WCAG21/#contrast-minimum
double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

// Relative luminance of sRGB. Not Color.computeLuminance(): the formula is written out so the
// number in a test can be checked against any online contrast checker.
double _luminance(Color color) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}
