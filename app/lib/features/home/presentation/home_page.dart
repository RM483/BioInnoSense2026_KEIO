/// ホーム — 「今日、うちの犬は元気?」に3秒で答える画面。
///
/// 主役は数値ではなく状態の言葉。ppm・温度などの専門情報は
/// 履歴/詳細画面に退避し、ここには安心感に必要な要素だけを置く:
/// 犬の名前 / 今日の状態 / ひとこと / 最終測定時刻 / 最近の推移 / 測定CTA。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../dogs/application/dog_controller.dart';
import '../../insights/application/insights_providers.dart';
import '../../insights/domain/health_assessment.dart';
import '../../insights/presentation/assessment_style.dart';
import '../../measurement/domain/measurement.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final dog = ref.watch(selectedDogProvider);
    final assessment = ref.watch(healthAssessmentProvider).valueOrNull ??
        HealthAssessment.fromHistory(const []);
    final recent =
        ref.watch(recentMeasurementsProvider).valueOrNull ?? const [];
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            // ---- 日付 + 犬の名前 ----
            Text(
              DateFormat.MMMEd(locale).format(DateTime.now()).toUpperCase(),
              style: AppText.overline.copyWith(color: p.textTertiary),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    dog?.name ?? l10n.appTitle,
                    style:
                        AppText.largeTitle.copyWith(color: p.textPrimary),
                  ),
                ),
                if (dog != null)
                  Hero(
                    tag: 'dog-avatar',
                    child: _Avatar(photoUrl: dog.photoUrl, size: 44),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // ---- 今日の状態 (主役) ----
            dog == null
                ? _RegisterDogCard(l10n: l10n)
                : _StatusCard(assessment: assessment, l10n: l10n),
            const SizedBox(height: 14),

            // ---- 最近の推移 (ミニ・無数値) ----
            if (recent.length >= 2) ...[
              _TrendCard(recent: recent, l10n: l10n),
              const SizedBox(height: 14),
            ],

            const SizedBox(height: 14),

            // ---- 測定CTA ----
            if (dog != null)
              FilledButton(
                onPressed: () => context.go(Routes.measure),
                child: Text(l10n.startMeasurement),
              ),
          ],
        ),
      ),
    );
  }
}

/// 状態カード: 色の点 + 状態の言葉 + ひとこと + 最終測定時刻。
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.assessment, required this.l10n});

  final HealthAssessment assessment;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final level = assessment.level;
    final latest = assessment.latest;

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: level.color(p),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    level.phrase(l10n),
                    key: ValueKey(level),
                    style: AppText.title.copyWith(color: p.textPrimary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            assessmentComment(assessment, l10n),
            style: AppText.body
                .copyWith(color: p.textSecondary, height: 1.55),
          ),
          if (latest != null) ...[
            const SizedBox(height: 14),
            Text(
              '${l10n.lastMeasured} · '
              '${relativeTime(l10n, latest.startedAt)}',
              style: AppText.caption.copyWith(color: p.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 最近の推移: 数値を出さないバーのならび(色 = その日の状態)。
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.recent, required this.l10n});

  final List<Measurement> recent; // 新しい順
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = recent.take(7).toList().reversed.toList(); // 古い→新しい
    final maxPpm = items
        .map((m) => m.avgPpm)
        .fold<double>(HealthAssessment.stableMaxPpm, (a, b) => a > b ? a : b);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      onTap: () => GoRouter.of(context).go(Routes.history),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.recentTrend.toUpperCase(),
                  style: AppText.overline.copyWith(color: p.textTertiary),
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: p.textTertiary),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final m in items) ...[
                  Expanded(
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      tween: Tween(
                          begin: 0,
                          end: (m.avgPpm / maxPpm).clamp(0.12, 1.0)),
                      builder: (context, t, _) => FractionallySizedBox(
                        heightFactor: t,
                        child: Container(
                          decoration: BoxDecoration(
                            color: HealthAssessment.levelForPpm(m.avgPpm)
                                .color(p)
                                .withOpacity(0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterDogCard extends StatelessWidget {
  const _RegisterDogCard({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(24),
      onTap: () => context.go(Routes.dog),
      child: Row(
        children: [
          _Avatar(photoUrl: '', size: 56),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.registerDog,
                    style: AppText.title.copyWith(color: p.textPrimary)),
                const SizedBox(height: 4),
                Text(l10n.addDogPrompt,
                    style:
                        AppText.caption.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: p.textTertiary),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.size});
  final String photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: p.cardElevated,
        shape: BoxShape.circle,
        image: photoUrl.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(photoUrl), fit: BoxFit.cover)
            : null,
      ),
      child: photoUrl.isEmpty
          ? Icon(Icons.pets, size: size * 0.45, color: p.textTertiary)
          : null,
    );
  }
}
