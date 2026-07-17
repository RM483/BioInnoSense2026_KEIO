/// HydroPawデザインシステム。
///
/// 方針 (docs/08):
/// - システムフォント(SF Pro / Roboto)をそのまま使い、サイズ・ウェイト・
///   字間・行間・色の階層だけで品質を出す
/// - 色は「背景 / カード / ヘアライン / 文字3階層 / アクセント1色」のみ。
///   グラデーション・影は原則使わない(影は浮遊要素のみ、極薄)
/// - ライト/ダークは AppPalette (ThemeExtension) で完全対応。
///   WidgetはAppPalette経由でのみ色を参照する(直値の参照は禁止)
import 'package:flutter/material.dart';

/// セマンティックカラーパレット。Widgetからは `context.palette` で参照する。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.card,
    required this.cardElevated,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.warn,
    required this.warnSoft,
    required this.danger,
    required this.success,
  });

  final Color bg;            // 画面背景
  final Color card;          // カード面
  final Color cardElevated;  // 入力欄・チップなど一段上の面
  final Color hairline;      // 罫線(1px)
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;        // ブランドブルー(CTA・グラフ・アクティブ)
  final Color accentSoft;    // アクセントの淡い面(バッジ・塗り)
  final Color warn;          // H2高値・注意(琥珀)
  final Color warnSoft;
  final Color danger;
  final Color success;

  static const light = AppPalette(
    bg: Color(0xFFF7F7F8),
    card: Color(0xFFFFFFFF),
    cardElevated: Color(0xFFF2F2F4),
    hairline: Color(0x14000000),
    textPrimary: Color(0xFF17181C),
    textSecondary: Color(0xFF6E7076),
    textTertiary: Color(0xFFA3A5AB),
    accent: Color(0xFF2563EB),
    accentSoft: Color(0x142563EB),
    warn: Color(0xFFD97706),
    warnSoft: Color(0x14D97706),
    danger: Color(0xFFE5484D),
    success: Color(0xFF16A34A),
  );

  static const dark = AppPalette(
    bg: Color(0xFF0E0F12),
    card: Color(0xFF1A1B1F),
    cardElevated: Color(0xFF232429),
    hairline: Color(0x1AFFFFFF),
    textPrimary: Color(0xFFF2F2F4),
    textSecondary: Color(0xFF9B9DA3),
    textTertiary: Color(0xFF5F6167),
    accent: Color(0xFF5B8DEF),
    accentSoft: Color(0x1F5B8DEF),
    warn: Color(0xFFF5A623),
    warnSoft: Color(0x1FF5A623),
    danger: Color(0xFFF2555A),
    success: Color(0xFF3DD68C),
  );

  @override
  AppPalette copyWith() => this; // 個別上書きは不要(全置換のみ)

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      bg: l(bg, other.bg),
      card: l(card, other.card),
      cardElevated: l(cardElevated, other.cardElevated),
      hairline: l(hairline, other.hairline),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      warn: l(warn, other.warn),
      warnSoft: l(warnSoft, other.warnSoft),
      danger: l(danger, other.danger),
      success: l(success, other.success),
    );
  }
}

extension AppPaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// タイポグラフィ。数値表示はタブラー等幅、見出しはタイトな字間。
abstract final class AppText {
  static const _tabular = [FontFeature.tabularFigures()];

  /// 測定中の現在値 (ppm)
  static const display = TextStyle(
    fontSize: 68,
    height: 1.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -2.5,
    fontFeatures: _tabular,
  );

  static const largeTitle = TextStyle(
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );

  static const title = TextStyle(
    fontSize: 19,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  static const body = TextStyle(
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
  );

  static const bodyMedium = TextStyle(
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
  );

  static const caption = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  /// セクション見出し(大文字トラッキング)
  static const overline = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
  );

  static const numeral = TextStyle(
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    fontFeatures: _tabular,
  );
}

abstract final class AppTheme {
  static ThemeData get light => _build(AppPalette.light, Brightness.light);
  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
      surface: p.bg,
    ).copyWith(
      primary: p.accent,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      outline: p.hairline,
      error: p.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [p],
      scaffoldBackgroundColor: p.bg,
      splashFactory: NoSplash.splashFactory, // Material波紋を使わない
      highlightColor: p.textPrimary.withOpacity(0.04),
      textTheme: TextTheme(
        displayLarge: AppText.display.copyWith(color: p.textPrimary),
        headlineMedium: AppText.largeTitle.copyWith(color: p.textPrimary),
        titleMedium: AppText.title.copyWith(color: p.textPrimary),
        bodyLarge: AppText.body.copyWith(color: p.textPrimary),
        bodyMedium: AppText.body.copyWith(color: p.textSecondary),
        labelLarge: AppText.bodyMedium.copyWith(color: p.textPrimary),
        labelSmall: AppText.caption.copyWith(color: p.textSecondary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.title.copyWith(color: p.textPrimary),
      ),
      dividerTheme: DividerThemeData(color: p.hairline, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.cardElevated,
          disabledForegroundColor: p.textTertiary,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(27),
          ),
          textStyle: AppText.bodyMedium.copyWith(fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.textSecondary,
          textStyle: AppText.bodyMedium,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.cardElevated,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: AppText.body.copyWith(color: p.textTertiary),
        labelStyle: AppText.body.copyWith(color: p.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.danger, width: 1.5),
        ),
        errorStyle: AppText.caption.copyWith(color: p.danger),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.light
            ? const Color(0xFF232429)
            : const Color(0xFFF2F2F4),
        contentTextStyle: AppText.bodyMedium.copyWith(
          color: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF17181C),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}

/// 標準カード。角丸18・ヘアライン枠・影なし。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}

/// 状態を示す小さなピル(接続状態・高値など)。
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    required this.softColor,
    this.dot = true,
  });

  final String label;
  final Color color;
  final Color softColor;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: softColor,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: AppText.caption.copyWith(
                  color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
