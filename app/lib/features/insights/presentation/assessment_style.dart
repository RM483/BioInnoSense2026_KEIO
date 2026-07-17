/// HealthAssessment → 表示表現(言葉・色)への変換。
/// UIはこのマッピングだけを使い、ppmの解釈を自前で行わない。
import 'dart:ui';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/health_assessment.dart';

extension HealthLevelStyle on HealthLevel {
  Color color(AppPalette p) => switch (this) {
        HealthLevel.none => p.accent,
        HealthLevel.stable => p.success,
        HealthLevel.slightlyElevated => p.warn,
        HealthLevel.elevated => p.danger,
      };

  Color softColor(AppPalette p) => switch (this) {
        HealthLevel.none => p.accentSoft,
        HealthLevel.stable => p.success.withOpacity(0.10),
        HealthLevel.slightlyElevated => p.warnSoft,
        HealthLevel.elevated => p.danger.withOpacity(0.10),
      };

  /// ホームの主文(状態を人の言葉で)
  String phrase(AppLocalizations l10n) => switch (this) {
        HealthLevel.none => l10n.statusNoData,
        HealthLevel.stable => l10n.statusStable,
        HealthLevel.slightlyElevated => l10n.statusSlightlyElevated,
        HealthLevel.elevated => l10n.statusElevated,
      };

  /// 履歴などで使う短いラベル
  String shortLabel(AppLocalizations l10n) => switch (this) {
        HealthLevel.none => '—',
        HealthLevel.stable => l10n.levelStableShort,
        HealthLevel.slightlyElevated => l10n.levelSlightlyElevatedShort,
        HealthLevel.elevated => l10n.levelElevatedShort,
      };
}

/// 前回からの変化(なければnull) — ホームの2行目。
/// 医学的に問題のない変動(正常範囲内)では不安を与える表現を避ける。
String? assessmentTrendLabel(HealthAssessment a, AppLocalizations l10n) {
  if (a.trend == HealthTrend.none) return null;
  final bothStable = a.level == HealthLevel.stable &&
      a.prevLevel == HealthLevel.stable;

  return switch (a.trend) {
    HealthTrend.improving =>
      // 高め→正常へ戻った時だけ「改善」を明言(正常内の低下はノイズ)
      (a.prevLevel != HealthLevel.stable && a.level == HealthLevel.stable)
          ? l10n.trendImproving
          : bothStable
              ? l10n.trendStableSteady
              : l10n.trendCalming,
    HealthTrend.worsening =>
      // 正常範囲内の上振れは「変動」— 不安を与えない
      a.level == HealthLevel.stable
          ? l10n.trendStableFluctuation
          : l10n.trendWorsening,
    HealthTrend.steady =>
      bothStable ? l10n.trendStableSteady : l10n.trendSteady,
    HealthTrend.none => null,
  };
}

/// グラフの言葉による要約(線の意味を一文で)
String windowSummaryText(WindowSummaryKind kind, AppLocalizations l10n) =>
    switch (kind) {
      WindowSummaryKind.none => '',
      WindowSummaryKind.allStable => l10n.summaryAllStable,
      WindowSummaryKind.recovered => l10n.summaryRecovered,
      WindowSummaryKind.slightlyElevated => l10n.summarySlightlyElevated,
      WindowSummaryKind.elevated => l10n.summaryElevated,
    };

/// ユーザーが取るべき行動 — ホームで最も大切な一文
String assessmentAction(HealthAssessment a, AppLocalizations l10n) {
  if (a.level == HealthLevel.none) return l10n.commentNoData;
  if (a.isStale) return l10n.staleSuggestion;
  return switch (a.level) {
    HealthLevel.stable => l10n.actionStable,
    HealthLevel.slightlyElevated => l10n.actionSlightlyElevated,
    HealthLevel.elevated => l10n.actionElevated,
    HealthLevel.none => l10n.commentNoData,
  };
}

/// 添える一言(優先度: 再測定のおすすめ > 傾向 > レベル別の一言)
String assessmentComment(HealthAssessment a, AppLocalizations l10n) {
  if (a.level == HealthLevel.none) return l10n.commentNoData;
  if (a.isStale) return l10n.staleSuggestion;
  switch (a.trend) {
    case HealthTrend.improving:
      return l10n.trendImproving;
    case HealthTrend.worsening:
      return l10n.trendWorsening;
    case HealthTrend.steady:
      return l10n.trendSteady;
    case HealthTrend.none:
      break;
  }
  return switch (a.level) {
    HealthLevel.stable => l10n.commentStable,
    HealthLevel.slightlyElevated => l10n.commentSlightlyElevated,
    HealthLevel.elevated => l10n.commentElevated,
    HealthLevel.none => l10n.commentNoData,
  };
}

/// 相対時刻(たった今 / n分前 / n時間前 / n日前)
String relativeTime(AppLocalizations l10n, DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return l10n.relJustNow;
  if (d.inHours < 1) return l10n.relMinutesAgo(d.inMinutes);
  if (d.inDays < 1) return l10n.relHoursAgo(d.inHours);
  return l10n.relDaysAgo(d.inDays);
}
