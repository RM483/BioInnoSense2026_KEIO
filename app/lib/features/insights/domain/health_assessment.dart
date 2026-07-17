/// 測定データを「人が理解できる意味」へ変換するドメインロジック。
///
/// このアプリの主役は ppm ではなく「今日、うちの犬は元気？」への答え。
/// 数値→意味の変換はここに一元化し、UI(ホーム/結果/履歴)は
/// HealthAssessment だけを表示する。純Dart — ホストでユニットテスト可能。
///
/// 判定根拠:
/// - 呼気水素は腸内での炭水化物の異常発酵(吸収不良等)の指標。
///   ヒト呼気水素検査では基準からの +20ppm 上昇を陽性とするのが一般的で、
///   本プロダクトでも 20ppm を「高め」の目安とする (H2.highPpm と同値)。
/// - 10ppm 未満を「安定」、10〜20ppm を「やや高め」として段階表示する。
/// - 前回測定との比較(±20%以上の変化)で「改善/上昇」の傾向を添える。
/// - 24時間以上測定が無ければ「そろそろ測定を」と促す。
import '../../../core/constants/h2.dart';
import '../../measurement/domain/measurement.dart';

/// 健康状態のレベル(色・トーンを決める)
enum HealthLevel {
  /// まだ測定がない
  none,

  /// < 10ppm: 安定
  stable,

  /// 10–20ppm: やや高め(様子見)
  slightlyElevated,

  /// > 20ppm: 高め(獣医師への相談を推奨)
  elevated,
}

/// 前回との比較傾向
enum HealthTrend { none, improving, steady, worsening }

/// ホーム・結果画面に表示する評価。
class HealthAssessment {
  const HealthAssessment({
    required this.level,
    required this.trend,
    required this.latest,
    required this.isStale,
  });

  final HealthLevel level;
  final HealthTrend trend;
  final Measurement? latest;

  /// 最終測定から24時間以上経過
  final bool isStale;

  static const stableMaxPpm = 10.0;
  static const staleAfter = Duration(hours: 24);

  /// 直近の測定履歴(新しい順)から評価を作る。
  factory HealthAssessment.fromHistory(
    List<Measurement> history, {
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    if (history.isEmpty) {
      return const HealthAssessment(
        level: HealthLevel.none,
        trend: HealthTrend.none,
        latest: null,
        isStale: false,
      );
    }
    final latest = history.first;
    final level = levelForPpm(latest.avgPpm);

    var trend = HealthTrend.none;
    if (history.length >= 2) {
      final prev = history[1].avgPpm;
      final cur = latest.avgPpm;
      if (prev > 0.5) {
        final change = (cur - prev) / prev;
        if (change <= -0.2) {
          trend = HealthTrend.improving;
        } else if (change >= 0.2) {
          trend = HealthTrend.worsening;
        } else {
          trend = HealthTrend.steady;
        }
      } else {
        trend = cur < stableMaxPpm ? HealthTrend.steady : HealthTrend.worsening;
      }
    }

    return HealthAssessment(
      level: level,
      trend: trend,
      latest: latest,
      isStale: t.difference(latest.startedAt) >= staleAfter,
    );
  }

  static HealthLevel levelForPpm(double avgPpm) {
    if (avgPpm >= H2.highPpm) return HealthLevel.elevated;
    if (avgPpm >= stableMaxPpm) return HealthLevel.slightlyElevated;
    return HealthLevel.stable;
  }
}
