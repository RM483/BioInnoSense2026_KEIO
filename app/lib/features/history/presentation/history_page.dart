/// 履歴画面。日付降順リスト + スパークライン。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/h2.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../dogs/application/dog_controller.dart';
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
      appBar: AppBar(title: Text(l10n.history)),
      body: history.when(
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
        data: (items) => items.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timeline, size: 32, color: p.textTertiary),
                    const SizedBox(height: 14),
                    Text(l10n.noMeasurementYet,
                        style: AppText.body
                            .copyWith(color: p.textSecondary)),
                  ],
                ),
              )
            : NotificationListener<ScrollEndNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 200) {
                    ref.read(historyProvider.notifier).loadMore();
                  }
                  return false;
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) =>
                      _HistoryTile(measurement: items[i]),
                ),
              ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.measurement});
  final Measurement measurement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final m = measurement;
    final isHigh = m.avgPpm >= H2.highPpm;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final df = DateFormat.MMMEd(locale);
    final tf = DateFormat.Hm(locale);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${df.format(m.startedAt)}  ${tf.format(m.startedAt)}',
                    style:
                        AppText.caption.copyWith(color: p.textTertiary)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(m.avgPpm.toStringAsFixed(1),
                        style: AppText.numeral.copyWith(
                            fontSize: 24,
                            color: isHigh ? p.warn : p.textPrimary)),
                    const SizedBox(width: 5),
                    Text(l10n.ppm,
                        style: AppText.caption
                            .copyWith(color: p.textTertiary)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    '${l10n.peak} ${m.maxPpm.toStringAsFixed(1)} · '
                    '${m.durationS ~/ 60}min',
                    style:
                        AppText.caption.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
          // スパークライン
          if (m.series.isNotEmpty)
            SizedBox(
              width: 92,
              height: 40,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (final s in m.series)
                          FlSpot(s.timeMs / 1000.0, s.h2Ppm),
                      ],
                      isCurved: true,
                      barWidth: 1.5,
                      color: isHigh ? p.warn : p.accent,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
