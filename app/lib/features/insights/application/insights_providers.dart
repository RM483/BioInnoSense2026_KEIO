/// ホーム・履歴で共有する「意味」層のプロバイダ。
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../dogs/application/dog_controller.dart';
import '../../measurement/data/measurement_repository.dart';
import '../../measurement/domain/measurement.dart';
import '../domain/health_assessment.dart';

/// 最新測定のストリーム(保存を検知して評価を更新するトリガも兼ねる)
final latestMeasurementProvider = StreamProvider<Measurement?>((ref) {
  final dog = ref.watch(selectedDogProvider);
  if (dog == null) return Stream.value(null);
  return ref.watch(measurementRepositoryProvider).watchLatest(dog.id);
});

/// 直近の測定履歴(新しい順、最大14件 — ホームのミニ推移と評価に使用)
final recentMeasurementsProvider =
    FutureProvider<List<Measurement>>((ref) async {
  final dog = ref.watch(selectedDogProvider);
  if (dog == null) return const [];
  ref.watch(latestMeasurementProvider); // 新規保存で自動再評価
  return ref
      .read(measurementRepositoryProvider)
      .fetchHistory(dog.id, limit: 14);
});

/// 「今日、うちの犬は元気?」への答え。
final healthAssessmentProvider = Provider<AsyncValue<HealthAssessment>>(
  (ref) => ref
      .watch(recentMeasurementsProvider)
      .whenData(HealthAssessment.fromHistory),
);

/// 犬を指定した版 (docs/21 v2.2 §2,12)。
/// ホームの全面ページスワイプで、各ページが自分の犬のデータだけを描くために
/// 使う — 別の犬の健康状態・測定情報が混ざらないことをここで担保する。
final recentMeasurementsOfProvider =
    FutureProvider.family<List<Measurement>, String>((ref, dogId) async {
  if (dogId.isEmpty) return const [];
  ref.watch(latestMeasurementProvider); // 新規保存で自動再評価
  return ref
      .read(measurementRepositoryProvider)
      .fetchHistory(dogId, limit: 14);
});

final healthAssessmentOfProvider =
    Provider.family<AsyncValue<HealthAssessment>, String>(
  (ref, dogId) => ref
      .watch(recentMeasurementsOfProvider(dogId))
      .whenData(HealthAssessment.fromHistory),
);
