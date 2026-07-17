/// 犬プロフィールViewModel。
import 'dart:typed_data';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/dog_repository.dart';
import '../domain/dog.dart';

final dogsProvider = StreamProvider<List<Dog>>(
  (ref) => ref.watch(dogRepositoryProvider).watchDogs(),
);

/// 現在選択中の犬(単頭運用ではfirst)。
final selectedDogProvider = Provider<Dog?>((ref) {
  final dogs = ref.watch(dogsProvider).valueOrNull;
  return (dogs == null || dogs.isEmpty) ? null : dogs.first;
});

class DogController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> save(Dog dog, {Uint8List? photoBytes}) async {
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
      }
      await repo.updateDog(toSave);
    });
  }
}

final dogControllerProvider =
    AsyncNotifierProvider<DogController, void>(DogController.new);
