/// HealthAssessment(数値→意味変換)の単体テスト。
import 'package:flutter_test/flutter_test.dart';
import 'package:hydropaw/features/insights/domain/health_assessment.dart';
import 'package:hydropaw/features/measurement/domain/measurement.dart';

Measurement m(double avgPpm, {DateTime? at}) => Measurement(
      id: 'x',
      dogId: 'd',
      deviceId: 'dev',
      startedAt: at ?? DateTime.now(),
      durationS: 120,
      sampleCount: 100,
      avgPpb: (avgPpm * 1000).round(),
      maxPpb: (avgPpm * 1500).round(),
      minPpb: 0,
      mode: 'continuous',
    );

void main() {
  final now = DateTime(2026, 7, 17, 12);

  test('履歴なし → none', () {
    final a = HealthAssessment.fromHistory(const [], now: now);
    expect(a.level, HealthLevel.none);
    expect(a.trend, HealthTrend.none);
    expect(a.latest, isNull);
  });

  test('レベル判定: <10 安定 / 10-20 やや高め / >=20 高め', () {
    expect(HealthAssessment.levelForPpm(4.2), HealthLevel.stable);
    expect(HealthAssessment.levelForPpm(9.9), HealthLevel.stable);
    expect(HealthAssessment.levelForPpm(12.0), HealthLevel.slightlyElevated);
    expect(HealthAssessment.levelForPpm(20.0), HealthLevel.elevated);
    expect(HealthAssessment.levelForPpm(45.0), HealthLevel.elevated);
  });

  test('傾向: -20%以上で改善、+20%以上で上昇、それ以外は横ばい', () {
    final improving = HealthAssessment.fromHistory(
        [m(8, at: now), m(12, at: now)],
        now: now);
    expect(improving.trend, HealthTrend.improving);

    final worsening = HealthAssessment.fromHistory(
        [m(15, at: now), m(10, at: now)],
        now: now);
    expect(worsening.trend, HealthTrend.worsening);

    final steady = HealthAssessment.fromHistory(
        [m(10.5, at: now), m(10, at: now)],
        now: now);
    expect(steady.trend, HealthTrend.steady);
  });

  test('1件のみ → 傾向なし', () {
    final a = HealthAssessment.fromHistory([m(5, at: now)], now: now);
    expect(a.trend, HealthTrend.none);
    expect(a.level, HealthLevel.stable);
  });

  test('ウィンドウ要約: 全て正常/一時的に高め/現在高め を区別する', () {
    expect(HealthAssessment.windowSummary([m(5), m(7), m(6)]),
        WindowSummaryKind.allStable);
    expect(HealthAssessment.windowSummary([m(6), m(22), m(8)]),
        WindowSummaryKind.recovered);
    expect(HealthAssessment.windowSummary([m(14), m(8)]),
        WindowSummaryKind.slightlyElevated);
    expect(HealthAssessment.windowSummary([m(25), m(8)]),
        WindowSummaryKind.elevated);
    expect(HealthAssessment.windowSummary(const []),
        WindowSummaryKind.none);
  });

  test('prevLevel: 正常範囲内の変動を判定できる材料を持つ', () {
    final a = HealthAssessment.fromHistory(
        [m(8, at: now), m(5, at: now)],
        now: now);
    expect(a.level, HealthLevel.stable);
    expect(a.prevLevel, HealthLevel.stable);
    expect(a.trend, HealthTrend.worsening); // +60%だがレベルは安定のまま
  });

  test('24時間以上前の測定 → stale(再測定のおすすめ)', () {
    final fresh = HealthAssessment.fromHistory(
        [m(5, at: now.subtract(const Duration(hours: 23)))],
        now: now);
    expect(fresh.isStale, isFalse);

    final stale = HealthAssessment.fromHistory(
        [m(5, at: now.subtract(const Duration(hours: 25)))],
        now: now);
    expect(stale.isStale, isTrue);
  });
}
