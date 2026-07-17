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
              const Spacer(),

              // ---- 詳細(控えめな数値) ----
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
                      ),
                      _Hairline(),
                      _Stat(
                        label: l10n.average,
                        value:
                            '${summary.avgPpm.toStringAsFixed(1)} ${l10n.ppm}',
                      ),
                      _Hairline(),
                      _Stat(
                        label: l10n.peak,
                        value:
                            '${summary.maxPpm.toStringAsFixed(1)} ${l10n.ppm}',
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: AppText.bodyMedium.copyWith(color: p.textPrimary)),
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
