/// 測定の詳細 — 専門的な数値・グラフはすべてここに集約する。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../insights/domain/health_assessment.dart';
import '../../insights/presentation/assessment_style.dart';
import '../../measurement/domain/measurement.dart';

class HistoryDetailPage extends ConsumerWidget {
  const HistoryDetailPage({super.key, required this.measurement});

  final Measurement measurement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final m = measurement;
    final level = HealthAssessment.levelForPpm(m.avgPpm);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat.MMMEd(locale).format(m.startedAt)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            // ---- 状態 ----
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: level.color(p), shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Text(level.phrase(l10n),
                    style: AppText.title.copyWith(color: p.textPrimary)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${DateFormat.Hm(locale).format(m.startedAt)} · '
              '${l10n.minutesShort((m.durationS / 60).ceil())}',
              style: AppText.caption.copyWith(color: p.textTertiary),
            ),
            const SizedBox(height: 20),

            // ---- セッション波形 ----
            if (m.series.length >= 2) ...[
              AppCard(
                padding: const EdgeInsets.fromLTRB(12, 18, 18, 8),
                child: SizedBox(
                  height: 180,
                  child: _SeriesChart(m: m),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // ---- 統計 ----
            AppCard(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
              child: Row(
                children: [
                  _Stat(
                      label: l10n.average,
                      value: m.avgPpm.toStringAsFixed(1),
                      unit: l10n.ppm),
                  _Hairline(),
                  _Stat(
                      label: l10n.peak,
                      value: m.maxPpm.toStringAsFixed(1),
                      unit: l10n.ppm),
                  _Hairline(),
                  _Stat(
                      label: l10n.resultSamples,
                      value: '${m.sampleCount}',
                      unit: ''),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesChart extends StatelessWidget {
  const _SeriesChart({required this.m});
  final Measurement m;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final spots = [
      for (final s in m.series) FlSpot(s.timeMs / 1000.0, s.h2Ppm),
    ];
    final maxY = [
      HealthAssessment.stableMaxPpm * 1.4,
      ...m.series.map((s) => s.h2Ppm * 1.1),
    ].reduce((a, b) => a > b ? a : b);
    final labelStyle = AppText.caption.copyWith(color: p.textTertiary);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: p.hairline, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(meta.formattedValue, style: labelStyle),
              ),
            ),
          ),
          bottomTitles: const AxisTitles(),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            barWidth: 2,
            color: p.accent,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: p.accent.withOpacity(0.06),
            ),
          ),
        ],
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
                  style: AppText.numeral.copyWith(color: p.textPrimary)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(unit,
                    style:
                        AppText.caption.copyWith(color: p.textTertiary)),
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
      Container(width: 1, height: 34, color: context.palette.hairline);
}
