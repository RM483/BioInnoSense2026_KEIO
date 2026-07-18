/// 犬プロフィールViewModel + 見守り状態の管理 (docs/21 v2.1 §5-8, §11-13)。
import 'dart:typed_data';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../measurement/data/measurement_repository.dart';
import '../../records/data/care_note_repository.dart';
import '../data/dog_repository.dart';
import '../domain/dog.dart';

final dogsProvider = StreamProvider<List<Dog>>(
  (ref) => ref.watch(dogRepositoryProvider).watchDogs(),
);

/// 見守り中(名前あり && 見守り終了していない)の犬 — ホーム/測定対象はこれだけ
final watchingDogsProvider = Provider<List<Dog>>((ref) {
  final dogs = ref.watch(dogsProvider).valueOrNull ?? const <Dog>[];
  return dogs.where((d) => d.isWatching).toList();
});

/// 見守りを終了した犬 (§7)
final archivedDogsProvider = Provider<List<Dog>>((ref) {
  final dogs = ref.watch(dogsProvider).valueOrNull ?? const <Dog>[];
  return dogs.where((d) => d.isComplete && d.archived).toList();
});

/// 未設定プロフィール(名前が空のまま残った残骸 §5A)
final draftDogsProvider = Provider<List<Dog>>((ref) {
  final dogs = ref.watch(dogsProvider).valueOrNull ?? const <Dog>[];
  return dogs.where((d) => !d.isComplete).toList();
});

/// 選択中の犬ID。ホームのスワイプで更新される(多頭飼い対応)。
final selectedDogIdProvider = StateProvider<String?>((ref) => null);

/// 現在選択中の犬。見守り中の犬のみ対象。無効なIDは先頭へフォールバック、
/// 見守り中が0頭ならnull(ホームは空状態を表示 §8,15)。
final selectedDogProvider = Provider<Dog?>((ref) {
  final watching = ref.watch(watchingDogsProvider);
  if (watching.isEmpty) return null;
  final id = ref.watch(selectedDogIdProvider);
  for (final d in watching) {
    if (d.id == id) return d;
  }
  return watching.first;
});

/// 記録(測定 or 健康日誌)が1件でもあるか — 削除可否の判定 (§5,15)
final hasRecordsProvider =
    FutureProvider.family<bool, String>((ref, dogId) async {
  final measurements = await ref
      .read(measurementRepositoryProvider)
      .fetchHistory(dogId, limit: 1);
  if (measurements.isNotEmpty) return true;
  final notes = await ref
      .read(careNoteRepositoryProvider)
      .watchNotes(dogId, limit: 1)
      .first;
  return notes.isNotEmpty;
});

class DogController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// [removePhoto] は「現在の写真を削除」(v2.2 §6)。新しい写真が
  /// 指定されていない場合のみ有効で、肉球アイコン表示へ戻す。
  Future<void> save(Dog dog,
      {Uint8List? photoBytes, bool removePhoto = false}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(dogRepositoryProvider);
      var toSave = dog;
      if (dog.id.isEmpty) {
        final id = await repo.addDog(dog);
        toSave = dog.copyWith(id: id);
      }
      if (photoBytes != null) {
        final url = await repo.uploadPhoto(toSave.id, photoBytes);
        toSave = toSave.copyWith(photoUrl: url);
      } else if (removePhoto) {
        toSave = toSave.copyWith(photoUrl: '');
      }
      await repo.updateDog(toSave);
    });
  }

  /// 完全削除 — 記録のない犬のみ (§5A,5B。確認はUI側)
  Future<void> delete(String dogId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final has = await ref.read(hasRecordsProvider(dogId).future);
      if (has) {
        throw StateError('records exist'); // 防御: 記録がある犬は削除しない (§15)
      }
      await ref.read(dogRepositoryProvider).deleteDog(dogId);
    });
  }

  /// 見守りを終了する — データは残す (§5C,6)
  Future<void> endWatch(Dog dog) =>
      save(dog.copyWith(archived: true));

  /// 見守りを再開する (§7。上限判定はUI側)
  Future<void> resume(Dog dog) =>
      save(dog.copyWith(archived: false));
}

final dogControllerProvider =
    AsyncNotifierProvider<DogController, void>(DogController.new);
