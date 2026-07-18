/// 測定結果 — 「できました」と意味をまず伝え、数値は控えめに添える。
/// 保存は自動で完了しているため、ユーザーの操作は「ホームへ」だけ。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../insights/domain/health_assessment.dart';
import '../../insights/presentation/assessment_style.dart';
import '../application/measurement_controller.dart';

class ResultPage extends ConsumerWidget {
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final summary = ref.watch(measurementControllerProvider).summary;
    final level = summary == null
        ? HealthLevel.none
        : HealthAssessment.levelForPpm(summary.avgPpm);

    void goHome() {
      ref.read(measurementControllerProvider.notifier).resetSession();
      context.go(Routes.home);
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ---- 見守りリングの完了形 (満色+✓ / docs/12 §3b) ----
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0.92, end: 1),
                builder: (context, t, child) => Opacity(
                  opacity: ((t - 0.92) / 0.08).clamp(0, 1),
                  child: Transform.scale(scale: t, child: child),
                ),
                child: Container(
                  width: 120,
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: level.color(p).withOpacity(0.55),
                        width: 1.75),
                    color: level.softColor(p),
                  ),
                  child: Icon(Icons.check_rounded,
                      size: 44, color: level.color(p)),
                ),
              ),
              const SizedBox(height: 28),
              Text(l10n.resultTitle,
                  style: AppText.largeTitle.copyWith(color: p.textPrimary)),
              const SizedBox(height: 10),
              Text(
                level.phrase(l10n),
                style: AppText.body.copyWith(color: p.textSecondary),
              ),

              // ---- 測定の質(BAP品質スコアの言葉化 — 数値は出さない) ----
              if (summary != null && summary.hasQuality) ...[
                const SizedBox(height: 14),
                _QualityBadge(quality: summary.quality),
              ],
              const Spacer(),

              // 低品質時は再測定を「提案」する(押し付けない — docs/18 §S8)
              if (summary != null && summary.remeasureAdvised) ...[
                Text(
                  l10n.remeasureAdvice,
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: p.textSecondary),
                ),
                TextButton(
                  onPressed: () {
                    ref
                        .read(measurementControllerProvider.notifier)
                        .resetSession();
                    // 接続済みのままなので、そのまま次のセッションへ
                    context.pushReplacement(Routes.measureSession);
                  },
                  child: Text(l10n.remeasureAction,
                      style:
                          AppText.bodyMedium.copyWith(color: p.accent)),
                ),
                const SizedBox(height: 6),
              ],
              // 計測器の不調はユーザーの失敗と区別して伝える (信頼度C)
              if (summary != null &&
                  summary.hasQuality &&
                  summary.confidence < 70) ...[
                Text(
                  l10n.sensorHealthNote,
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: p.warn),
                ),
                const SizedBox(height: 10),
              ],

              // ---- 詳細(控えめな数値 — 単位は小さく添える: docs/17 A18) ----
              if (summary != null)
                AppCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 18),
                  child: Row(
                    children: [
                      _Stat(
                        label: l10n.resultDuration,
                        value: l10n.minutesShort(
                            (summary.durationS / 60).ceil()),
                        unit: '',
                      ),
                      _Hairline(),
                      _Stat(
                        label: l10n.average,
                        value: summary.avgPpm.toStringAsFixed(1),
                        unit: l10n.ppm,
                      ),
                      _Hairline(),
                      _Stat(
                        label: l10n.peak,
                        value: summary.maxPpm.toStringAsFixed(1),
                        unit: l10n.ppm,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),

              // 電池の助言(責めない言葉で) — docs/17 A16
              if (ref.watch(measurementControllerProvider).lowBattery) ...[
                Text(
                  l10n.batteryAdvice,
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: p.warn),
                ),
                const SizedBox(height: 8),
              ],
              // 医療免責 — docs/17 A12
              Text(
                l10n.disclaimer,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(
                    color: p.textTertiary, fontSize: 11.5),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: goHome,
                child: Text(l10n.backToHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 測定の質を言葉で伝えるバッジ。
/// Q≥80=高い(緑) / 60-79=ふつう(ブランド) / <60=低い(琥珀)。
/// 数値のQ/Cは詳細画面と研究用エクスポートにのみ出す(docs/17の思想)。
class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.quality});
  final int quality;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final (label, color) = quality >= 80
        ? (l10n.qualityHigh, p.success)
        : quality >= 60
            ? (l10n.qualityMedium, p.accent)
            : (l10n.qualityLow, p.warn);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${l10n.qualityLabel} · $label',
        style: AppText.caption
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: AppText.bodyMedium
                      .copyWith(color: p.textPrimary)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                // 数値は証拠であって主張ではない — 単位は60%で添える
                Text(unit,
                    style: AppText.caption.copyWith(
                        color: p.textTertiary, fontSize: 10.5)),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(label,
              style: AppText.caption.copyWith(color: p.textTertiary)),
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: context.palette.hairline);
}
