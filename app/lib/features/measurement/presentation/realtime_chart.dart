/// リアルタイム折れ線グラフ (fl_chart)。直近300点を描画。
/// 装飾は最小限: 細い線・薄い水平グリッド・閾値の破線のみ。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/h2.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/measurement.dart';

class RealtimeChart extends StatelessWidget {
  const RealtimeChart({
    super.key,
    required this.samples,
    this.thresholdPpm = H2.highPpm,
    this.window = 300,
  });

  final List<H2Sample> samples;
  final double thresholdPpm; // 高値目安ライン
  final int window;          // 表示点数

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
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
              reservedSize: 40,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(meta.formattedValue,
                    style: labelStyle, textAlign: TextAlign.right),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(meta.formattedValue, style: labelStyle),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(
            y: thresholdPpm,
            color: p.warn.withOpacity(0.6),
            strokeWidth: 1,
            dashArray: [6, 5],
          ),
        ]),
        lineBarsData: [
          // 有効サンプル: アクセント色の細線 + ごく薄い面
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.18,
            barWidth: 2,
            color: p.accent,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: p.accent.withOpacity(0.06),
            ),
          ),
          // 異常フラグ付きサンプル: 三次色の点のみ(統計除外を可視化)
          LineChartBarData(
            spots: invalidSpots,
            barWidth: 0,
            color: Colors.transparent,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 2,
                color: p.textTertiary,
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
