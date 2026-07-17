/// 履歴 — 日々の記録を「状態の言葉」で振り返る。
/// 数値の詳細はタップした先(詳細画面)に置く。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../dogs/application/dog_controller.dart';
import '../../insights/domain/health_assessment.dart';
import '../../insights/presentation/assessment_style.dart';
import '../../measurement/data/measurement_repository.dart';
import '../../measurement/domain/measurement.dart';

final historyProvider =
    AsyncNotifierProvider<HistoryNotifier, List<Measurement>>(
        HistoryNotifier.new);

class HistoryNotifier extends AsyncNotifier<List<Measurement>> {
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  Future<List<Measurement>> build() async {
    final dog = ref.watch(selectedDogProvider);
    if (dog == null) return [];
    _hasMore = true;
    _loadingMore = false;
    return ref
        .read(measurementRepositoryProvider)
        .fetchHistory(dog.id, limit: 20);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull ?? [];
    final dog = ref.read(selectedDogProvider);
    if (dog == null || current.isEmpty || !_hasMore || _loadingMore) return;
    _loadingMore = true;
    try {
      final more = await ref.read(measurementRepositoryProvider).fetchHistory(
          dog.id,
          before: current.last.startedAt,
          limit: 20);
      _hasMore = more.isNotEmpty;
      state = AsyncData([...current, ...more]);
    } finally {
      _loadingMore = false;
    }
  }
}

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final history = ref.watch(historyProvider);

    return Scaffold(
      body: SafeArea(
        child: history.when(
          loading: () => Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2, color: p.textTertiary),
            ),
          ),
          error: (e, _) => Center(
            child: Text(l10n.errorNetwork,
                style: AppText.body.copyWith(color: p.textSecondary)),
          ),
          data: (items) => NotificationListener<ScrollEndNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 200) {
                ref.read(historyProvider.notifier).loadMore();
              }
              return false;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              children: [
                Text(l10n.tabHistory,
                    style:
                        AppText.largeTitle.copyWith(color: p.textPrimary)),
                const SizedBox(height: 20),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 120),
                    child: Column(
                      children: [
                        Icon(Icons.timeline,
                            size: 30, color: p.textTertiary),
                        const SizedBox(height: 12),
                        Text(l10n.noMeasurementYet,
                            style: AppText.body
                                .copyWith(color: p.textSecondary)),
                      ],
                    ),
                  )
                else ...[
                  if (items.length >= 2) ...[
                    _TrendChartCard(items: items, l10n: l10n),
                    const SizedBox(height: 14),
                  ],
                  for (final m in items) ...[
                    _HistoryRow(measurement: m),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 直近の平均値の推移(数値ラベルは最小限)。
class _TrendChartCard extends StatelessWidget {
  const _TrendChartCard({required this.items, required this.l10n});

  final List<Measurement> items; // 新しい順
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final series = items.take(14).toList().reversed.toList();
    final spots = [
      for (var i = 0; i < series.length; i++)
        FlSpot(i.toDouble(), series[i].avgPpm),
    ];
    final maxY = [
      HealthAssessment.stableMaxPpm * 1.4,
      ...series.map((m) => m.avgPpm * 1.15),
    ].reduce((a, b) => a > b ? a : b);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.recentTrend.toUpperCase(),
              style: AppText.overline.copyWith(color: p.textTertiary)),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 2,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: p.hairline, strokeWidth: 1),
                ),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    barWidth: 2,
                    color: p.accent,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) =>
                          spot.x == spots.last.x, // 最新点のみ
                      getDotPainter: (_, __, ___, ____) =>
                          FlDotCirclePainter(
                        radius: 3,
                        color: p.accent,
                        strokeWidth: 2,
                        strokeColor: p.card,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: p.accent.withOpacity(0.06),
                    ),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 400),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.measurement});
  final Measurement measurement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final m = measurement;
    final level = HealthAssessment.levelForPpm(m.avgPpm);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      onTap: () => context.go('/history/detail', extra: m),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: level.color(p), shape: BoxShape.circle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(level.shortLabel(l10n),
                    style: AppText.bodyMedium
                        .copyWith(color: p.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat.MMMEd(locale).format(m.startedAt)} '
                  '${DateFormat.Hm(locale).format(m.startedAt)}',
                  style: AppText.caption.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
          Text('${m.avgPpm.toStringAsFixed(1)} ${l10n.ppm}',
              style: AppText.caption.copyWith(color: p.textTertiary)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 16, color: p.textTertiary),
        ],
      ),
    );
  }
}
