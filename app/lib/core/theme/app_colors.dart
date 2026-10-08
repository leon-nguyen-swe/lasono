import 'package:flutter/material.dart';

/// The colour tokens of LaSono, one set per brightness. Read them with `AppColors.of(context)`.
///
/// Rules of use (checked by `app_colors_test.dart`):
/// - [textPrimary] and [textSecondary] on [background], [surface], [surfaceRaised], [surfaceHigh].
/// - [textMuted] only on [background], [surface], [surfaceRaised] (it is too faint on [surfaceHigh]).
/// - [onAccent] on [accent]; [accent] as text or icon on [background], [surface], [surfaceRaised].
/// - [inputBorder] and the waveform colours are graphics: at least 3:1 on the surface they sit on.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHigh,
    required this.outline,
    required this.inputBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentHover,
    required this.onAccent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.error,
    required this.waveformPlayed,
    required this.waveformUnplayed,
    required this.waveformHover,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceHigh;

  /// A hairline between areas. Decorative, so it is allowed to be faint.
  final Color outline;

  /// The border of a text field: it tells the user where to type, so it must be visible.
  final Color inputBorder;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color accent;
  final Color accentHover;
  final Color onAccent;

  /// A faint tint of the accent for selected rows and chips.
  final Color accentSoft;

  final Color success;
  final Color warning;
  final Color error;

  /// The part of the waveform already played, the part not played yet, and the part under the pointer.
  final Color waveformPlayed;
  final Color waveformUnplayed;
  final Color waveformHover;

  /// The default: a deep, slightly blue black (a music app is used in dim rooms), one electric-violet accent.
  static const dark = AppColors(
    background: Color(0xFF0B0D12),
    surface: Color(0xFF12151C),
    surfaceRaised: Color(0xFF1A1E28),
    surfaceHigh: Color(0xFF232836),
    outline: Color(0xFF2C3242),
    inputBorder: Color(0xFF5F6A8A),
    textPrimary: Color(0xFFF2F4F8),
    textSecondary: Color(0xFFA9B1C3),
    textMuted: Color(0xFF8089A0),
    accent: Color(0xFF9B82FF),
    accentHover: Color(0xFFB9A8FF),
    onAccent: Color(0xFF0B0D12),
    accentSoft: Color(0x299B82FF),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    error: Color(0xFFFF7A85),
    waveformPlayed: Color(0xFF9B82FF),
    waveformUnplayed: Color(0xFF5F6A8A),
    waveformHover: Color(0xFFC9BCFF),
  );

  static const light = AppColors(
    background: Color(0xFFF6F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF0F2F8),
    surfaceHigh: Color(0xFFE6E9F2),
    outline: Color(0xFFD9DDEA),
    inputBorder: Color(0xFF7F8AA8),
    textPrimary: Color(0xFF12151C),
    textSecondary: Color(0xFF4A5266),
    textMuted: Color(0xFF5F6880),
    accent: Color(0xFF5B3DE0),
    accentHover: Color(0xFF4A2FC4),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0x1F5B3DE0),
    success: Color(0xFF0F7B55),
    warning: Color(0xFF8A5A00),
    error: Color(0xFFC62839),
    waveformPlayed: Color(0xFF5B3DE0),
    waveformUnplayed: Color(0xFF7F8AA8),
    waveformHover: Color(0xFF7A5FF0),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? dark;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceHigh,
    Color? outline,
    Color? inputBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentHover,
    Color? onAccent,
    Color? accentSoft,
    Color? success,
    Color? warning,
    Color? error,
    Color? waveformPlayed,
    Color? waveformUnplayed,
    Color? waveformHover,
  }) =>
      AppColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        outline: outline ?? this.outline,
        inputBorder: inputBorder ?? this.inputBorder,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        accent: accent ?? this.accent,
        accentHover: accentHover ?? this.accentHover,
        onAccent: onAccent ?? this.onAccent,
        accentSoft: accentSoft ?? this.accentSoft,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        error: error ?? this.error,
        waveformPlayed: waveformPlayed ?? this.waveformPlayed,
        waveformUnplayed: waveformUnplayed ?? this.waveformUnplayed,
        waveformHover: waveformHover ?? this.waveformHover,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceHigh: mix(surfaceHigh, other.surfaceHigh),
      outline: mix(outline, other.outline),
      inputBorder: mix(inputBorder, other.inputBorder),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      accent: mix(accent, other.accent),
      accentHover: mix(accentHover, other.accentHover),
      onAccent: mix(onAccent, other.onAccent),
      accentSoft: mix(accentSoft, other.accentSoft),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      error: mix(error, other.error),
      waveformPlayed: mix(waveformPlayed, other.waveformPlayed),
      waveformUnplayed: mix(waveformUnplayed, other.waveformUnplayed),
      waveformHover: mix(waveformHover, other.waveformHover),
    );
  }
}
