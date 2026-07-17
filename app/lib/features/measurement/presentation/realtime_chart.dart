/// リアルタイム折れ線グラフ (fl_chart)。直近300点を描画。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/measurement.dart';

class RealtimeChart extends StatelessWidget {
  const RealtimeChart({
    super.key,
    required this.samples,
    this.thresholdPpm = 20.0,
    this.window = 300,
  });

  final List<H2Sample> samples;
  final double thresholdPpm; // 高値目安ライン
  final int window;          // 表示点数

  @override
  Widget build(BuildContext context) {
    final visible = samples.length <= window
        ? samples
        : samples.sublist(samples.length - window);

    final spots = <FlSpot>[];
    final invalidSpots = <FlSpot>[];
    for (final s in visible) {
      final spot = FlSpot(s.timeMs / 1000.0, s.h2Ppm);
      (s.isValid ? spots : invalidSpots).add(spot);
    }

    final maxY = [
      thresholdPpm * 1.2,
      ...visible.map((s) => s.h2Ppm * 1.1),
    ].reduce((a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.outline, strokeWidth: 1),
        ),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(),
          rightTitles: AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 44),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 28),
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(
            y: thresholdPpm,
            color: AppColors.accent,
            strokeWidth: 1.5,
            dashArray: [8, 4],
          ),
        ]),
        lineBarsData: [
          // 有効サンプル: 青のライン + 面グラデーション
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            barWidth: 2.5,
            color: AppColors.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withOpacity(0.20),
                  AppColors.primary.withOpacity(0.0),
                ],
              ),
            ),
          ),
          // 異常フラグ付きサンプル: グレーの点のみ(統計除外を視覚化)
          LineChartBarData(
            spots: invalidSpots,
            barWidth: 0,
            color: Colors.transparent,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 2.5,
                color: AppColors.onSurfaceVariant,
                strokeWidth: 0,
              ),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
      duration: Duration.zero, // リアルタイム描画: アニメーション無効
    );
  }
}
