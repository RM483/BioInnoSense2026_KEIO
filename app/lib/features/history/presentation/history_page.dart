/// 履歴画面。日付降順リスト + スパークライン。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

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
    final history = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.history)),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.errorNetwork)),
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.noMeasurementYet))
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
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
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
    final m = measurement;
    final df = DateFormat.yMMMd(
        Localizations.localeOf(context).toLanguageTag());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(df.format(m.startedAt),
                      style: const TextStyle(
                          color: AppColors.onSurfaceVariant, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text('${m.avgPpm.toStringAsFixed(1)} ${l10n.ppm}',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(
                      '${l10n.peak} ${m.maxPpm.toStringAsFixed(1)} ・ '
                      '${m.durationS ~/ 60}min',
                      style: const TextStyle(
                          color: AppColors.onSurfaceVariant, fontSize: 14)),
                ],
              ),
            ),
            // スパークライン
            if (m.series.isNotEmpty)
              SizedBox(
                width: 96,
                height: 44,
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
                        color: AppColors.primary,
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
