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
