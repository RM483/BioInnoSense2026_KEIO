/// 健康日誌リポジトリ (Cloud Firestore)。
/// パス: users/{uid}/dogs/{dogId}/careNotes/{id} (firestore.rules 対応済み)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/care_note.dart';

abstract interface class CareNoteRepository {
  Stream<List<CareNote>> watchNotes(String dogId, {int limit});
  Future<String> add(CareNote note);
  /// 既存レコードの内容更新 (v2.3 §4: 1日1件のupsertに使用)
  Future<void> update(CareNote note);
  Future<void> delete(String dogId, String noteId);
}

final careNoteRepositoryProvider = Provider<CareNoteRepository>((ref) {
  final uid = ref.watch(currentUserProvider).valueOrNull?.uid;
  if (uid == null) {
    throw StateError('not signed in');
  }
  return FirestoreCareNoteRepository(ref.watch(firestoreProvider), uid);
});

class FirestoreCareNoteRepository implements CareNoteRepository {
  const FirestoreCareNoteRepository(this._db, this._uid);
  final FirebaseFirestore _db;
  final String _uid;

  CollectionReference<Map<String, dynamic>> _col(String dogId) =>
      _db.collection('users/$_uid/dogs/$dogId/careNotes');

  @override
  Stream<List<CareNote>> watchNotes(String dogId, {int limit = 200}) => _col(
          dogId)
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => CareNote.fromJson(d.id, d.data())).toList());

  @override
  Future<String> add(CareNote note) async {
    final ref = await _col(note.dogId).add(note.toJson());
    return ref.id;
  }

  @override
  Future<void> update(CareNote note) =>
      _col(note.dogId).doc(note.id).set(note.toJson());

  @override
  Future<void> delete(String dogId, String noteId) =>
      _col(dogId).doc(noteId).delete();
}
