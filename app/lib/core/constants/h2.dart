/// H2測定に関する共有定数。
/// 閾値・フラグは FW(app_config.h / hpp.h) および Cloud Functions と
/// 意味を一致させること。変更時は docs/03 を更新する。
abstract final class H2 {
  /// 高値の目安 [ppm]。UI表示・グラフ閾値ライン・アラート判定で共用。
  /// (Cloud Functions の ALERT_THRESHOLD_PPB = 20_000 と同値)
  static const highPpm = 20.0;

  /// DGS2 (110-005) の測定レンジ上限 [ppm]
  static const rangeMaxPpm = 100.0;

  // ---- EVT_DATA flags (firmware/App/Inc/hpp.h と1:1) ----
  static const flagOutOfRange = 1 << 0;
  static const flagStuck = 1 << 1;
  static const flagWarmup = 1 << 2;
  static const flagUnstable = 1 << 3;

  /// 統計から除外すべきフラグ(レンジ外・固着)
  static const invalidMask = flagOutOfRange | flagStuck;
}
