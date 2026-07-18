/// 健康日誌ViewModel。
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/care_note_repository.dart';
import '../domain/care_note.dart';

/// 指定した犬の日誌(新しい順)。
final careNotesProvider =
    StreamProvider.family<List<CareNote>, String>((ref, dogId) {
  if (dogId.isEmpty) return Stream.value(const []);
  return ref.watch(careNoteRepositoryProvider).watchNotes(dogId);
});

class CareNoteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> add(CareNote note) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(careNoteRepositoryProvider).add(note));
  }

  Future<void> delete(String dogId, String noteId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(careNoteRepositoryProvider).delete(dogId, noteId));
  }
}

final careNoteControllerProvider =
    AsyncNotifierProvider<CareNoteController, void>(CareNoteController.new);
