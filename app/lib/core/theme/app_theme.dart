/// デザインシステム (docs/08_ui_design.md)。
/// 白・青・グレー基調 + アクセント琥珀のみ。余白重視のカードUI。
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF2563EB);
  static const accent = Color(0xFFF59E0B);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceContainer = Color(0xFFF5F7FA);
  static const onSurface = Color(0xFF1A1D21);
  static const onSurfaceVariant = Color(0xFF6B7280);
  static const outline = Color(0xFFE5E7EB);
  static const error = Color(0xFFDC2626);
}

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    final isLight = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: isLight
          ? scheme.copyWith(
              primary: AppColors.primary,
              surface: AppColors.surface,
              onSurface: AppColors.onSurface,
              onSurfaceVariant: AppColors.onSurfaceVariant,
              outline: AppColors.outline,
              error: AppColors.error,
            )
          : scheme,
      scaffoldBackgroundColor: isLight ? AppColors.surface : null,
      // 高齢者にも読みやすい: 本文16sp以上
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 56,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: isLight ? AppColors.surfaceContainer : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
              color: isLight ? AppColors.outline : Colors.transparent),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56), // タップ領域48dp+
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    );
  }
}
