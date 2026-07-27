/// 健康日誌ViewModel — 1日1件のまとめ保存 (docs/21 v2.3 §2,4)。
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/care_note_repository.dart';
import '../domain/care_note.dart';

/// 指定した犬の日誌(新しい順)。
final careNotesProvider =
    StreamProvider.family<List<CareNote>, String>((ref, dogId) {
  if (dogId.isEmpty) return Stream.value(const []);
  return ref.watch(careNoteRepositoryProvider).watchNotes(dogId);
});

/// きょうの記録の入力1件分
class DayEntryInput {
  const DayEntryInput({required this.type, this.choice, this.memo = ''});
  final CareNoteType type;
  final String? choice;
  final String memo;
}

class CareNoteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// きょうの記録をまとめてupsertする (§2,4)。
  /// カテゴリごとに「今日の既存レコードがあれば更新、なければ追加」。
  /// 同じ日に同じカテゴリを重複追加しない。旧重複データは削除しない (§19)。
  Future<void> saveDay(String dogId, List<DayEntryInput> entries) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(careNoteRepositoryProvider);
      final notes = await repo.watchNotes(dogId).first;
      final today = notesOfDay(notes, DateTime.now());
      for (final e in entries) {
        final existing = today[e.type];
        if (existing != null) {
          // 既存(最新)を更新 — 別カテゴリには触れない (§20)
          await repo.update(
              existing.copyWith(choice: e.choice, memo: e.memo));
        } else {
          await repo.add(CareNote(
            id: '',
            dogId: dogId,
            at: DateTime.now(),
            type: e.type,
            choice: e.choice,
            memo: e.memo,
          ));
        }
      }
    });
  }

  /// その日の健康日誌をすべて削除する。測定結果は削除しない (§15,20)。
  Future<void> deleteDay(String dogId, DateTime day) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(careNoteRepositoryProvider);
      final notes = await repo.watchNotes(dogId).first;
      for (final n in notes.where((n) => sameDay(n.at, day))) {
        await repo.delete(dogId, n.id);
      }
    });
  }
}

final careNoteControllerProvider =
    AsyncNotifierProvider<CareNoteController, void>(CareNoteController.new);
