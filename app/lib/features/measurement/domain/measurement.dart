/// 測定エンティティ(Freezed)。docs/07_db_design.md のMEASUREMENTに対応。
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/constants/h2.dart';

part 'measurement.freezed.dart';
part 'measurement.g.dart';

/// リアルタイム1サンプル (EVT_DATA由来)
@freezed
class H2Sample with _$H2Sample {
  const factory H2Sample({
    required int timeMs,   // セッション相対時刻
    required int h2Ppb,
    required double tempC,
    required double rh,
    @Default(0) int flags, // HPP flags
  }) = _H2Sample;

  const H2Sample._();

  factory H2Sample.fromJson(Map<String, dynamic> json) =>
      _$H2SampleFromJson(json);

  double get h2Ppm => h2Ppb / 1000.0;
  bool get isValid => (flags & H2.invalidMask) == 0; // OUT_OF_RANGE|STUCKなし
  bool get isWarmup => (flags & H2.flagWarmup) != 0;
}

/// 保存される測定セッション
@freezed
class Measurement with _$Measurement {
  const factory Measurement({
    required String id,
    required String dogId,
    required String deviceId,
    required DateTime startedAt,
    required int durationS,
    required int sampleCount,
    required int avgPpb,
    required int maxPpb,
    required int minPpb,
    required String mode, // 'continuous' | 'single' | 'breath'
    @Default([]) List<H2Sample> series, // 間引き済み(最大600点)
    @Default('') String note,
    // ---- v2: 呼気解析結果 (BAP, docs/18)。-1 = ラボモード/旧データ ----
    @Default(-1) int quality, // Q: この測定は信頼できるか (0-100)
    @Default(-1) int confidence, // C: 計測器は健全か (0-100)
    @Default(0) int qualityFlags, // Hpp.rf* ビットマスク
    // 研究用の呼気特徴量(卒論の解析でエクスポートする — レビューF6)
    @Default(0) int aucPpbS, // 総排出量に比例 ΣΔ·1s
    @Default(0) int riseDs, // 10→90%立上り [0.1s]
  }) = _Measurement;

  const Measurement._();

  factory Measurement.fromJson(Map<String, dynamic> json) =>
      _$MeasurementFromJson(json);

  double get avgPpm => avgPpb / 1000.0;
  double get maxPpm => maxPpb / 1000.0;

  bool get hasQuality => quality >= 0;
  bool get remeasureAdvised => (qualityFlags & 0x01) != 0;
}

/// 系列を最大[maxPoints]点に間引く(等間隔サンプリング)。
List<H2Sample> decimateSeries(List<H2Sample> series, {int maxPoints = 600}) {
  if (series.length <= maxPoints) return List.unmodifiable(series);
  final step = series.length / maxPoints;
  return List.unmodifiable([
    for (var i = 0; i < maxPoints; i++) series[(i * step).floor()],
  ]);
}
