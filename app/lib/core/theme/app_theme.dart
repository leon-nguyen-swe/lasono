import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// The two themes of LaSono. Dark is the default (see [ThemeController]).
abstract final class AppTheme {
  static final ThemeData dark = _build(Brightness.dark, AppColors.dark);
  static final ThemeData light = _build(Brightness.light, AppColors.light);

  static ThemeData _build(Brightness brightness, AppColors c) {
    final text = AppTypography.textTheme(c);
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: Color.alphaBlend(c.accentSoft, c.surface),
      onPrimaryContainer: c.textPrimary,
      // One accent colour for the whole brand: the secondary role repeats it.
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.error,
      onError: isDark ? c.background : Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      outline: c.inputBorder,
      outlineVariant: c.outline,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surfaceRaised,
      surfaceContainerHigh: c.surfaceHigh,
      surfaceContainerHighest: c.surfaceHigh,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.background,
      inversePrimary: c.accentHover,
    );

    final shape = RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md));
    const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md);
    const minimumButton = Size(64, 44);

    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: AppRadius.all(AppRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      fontFamily: AppTypography.fontFamily,
      textTheme: text,
      primaryTextTheme: text,
      extensions: [c],
      splashFactory: InkRipple.splashFactory,
      dividerColor: c.outline,
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge,
      ),
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.lg),
          side: BorderSide(color: c.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return c.surfaceHigh;
            if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) {
              return c.accentHover;
            }
            return c.accent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? c.textMuted : c.onAccent,
          ),
          minimumSize: const WidgetStatePropertyAll(minimumButton),
          padding: const WidgetStatePropertyAll(buttonPadding),
          shape: WidgetStatePropertyAll(shape),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          animationDuration: AppDurations.fast,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? c.textMuted : c.textPrimary,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.hovered) ? c.accent : c.inputBorder,
            ),
          ),
          minimumSize: const WidgetStatePropertyAll(minimumButton),
          padding: const WidgetStatePropertyAll(buttonPadding),
          shape: WidgetStatePropertyAll(shape),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          animationDuration: AppDurations.fast,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? c.textMuted
                : states.contains(WidgetState.hovered)
                    ? c.accentHover
                    : c.accent,
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
          shape: WidgetStatePropertyAll(shape),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? c.textMuted
                : states.contains(WidgetState.hovered)
                    ? c.textPrimary
                    : c.textSecondary,
          ),
          minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        border: border(c.inputBorder),
        enabledBorder: border(c.inputBorder),
        focusedBorder: border(c.accent, 2),
        errorBorder: border(c.error),
        focusedErrorBorder: border(c.error, 2),
        disabledBorder: border(c.outline),
        labelStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
        floatingLabelStyle: text.bodySmall?.copyWith(color: c.accent),
        hintStyle: text.bodyMedium?.copyWith(color: c.textMuted),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: c.error),
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceRaised,
        selectedColor: Color.alphaBlend(c.accentSoft, c.surfaceRaised),
        side: BorderSide(color: c.outline),
        labelStyle: text.labelMedium?.copyWith(color: c.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: c.accent,
        inactiveTrackColor: c.waveformUnplayed,
        thumbColor: c.accent,
        overlayColor: c.accentSoft,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.onAccent : c.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.accent : c.surfaceHigh,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.accent : c.inputBorder,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surfaceHigh,
        circularTrackColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.xl),
          side: BorderSide(color: c.outline),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceHigh,
        contentTextStyle: text.bodyMedium,
        actionTextColor: c.accent,
        shape: shape,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.md),
          side: BorderSide(color: c.outline),
        ),
        textStyle: text.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          borderRadius: AppRadius.all(AppRadius.sm),
          border: Border.all(color: c.outline),
        ),
        textStyle: text.bodySmall?.copyWith(color: c.textPrimary),
        waitDuration: const Duration(milliseconds: 400),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.accent,
        unselectedLabelColor: c.textSecondary,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        indicatorColor: c.accent,
        dividerColor: c.outline,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(c.inputBorder.withValues(alpha: 0.6)),
        radius: const Radius.circular(AppRadius.pill),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        shape: shape,
      ),
    );
  }
}
