/// ユーザー設定リポジトリ — 見守る犬の上限 (docs/21 v2.1 §9-13)。
/// Firestore: users/{uid} ドキュメントの `maxDogs` フィールド。
/// オフライン/デモは offline_overrides.dart の InMemory 実装。
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/application/auth_controller.dart';

abstract interface class UserSettingsRepository {
  /// 見守る犬の上限。null = 初回質問が未回答
  Stream<int?> watchMaxDogs();
  Future<void> setMaxDogs(int value);
}

final userSettingsRepositoryProvider = Provider<UserSettingsRepository>((ref) {
  final uid = ref.watch(currentUserProvider).valueOrNull?.uid;
  if (uid == null) {
    throw StateError('not signed in');
  }
  return FirestoreUserSettingsRepository(ref.watch(firestoreProvider), uid);
});

/// 見守る犬の上限 (null = 初回未設定 → ホームで質問する)
final maxDogsProvider = StreamProvider<int?>(
  (ref) => ref.watch(userSettingsRepositoryProvider).watchMaxDogs(),
);

class FirestoreUserSettingsRepository implements UserSettingsRepository {
  const FirestoreUserSettingsRepository(this._db, this._uid);
  final FirebaseFirestore _db;
  final String _uid;

  @override
  Stream<int?> watchMaxDogs() => _db
      .doc('users/$_uid')
      .snapshots()
      .map((s) => (s.data()?['maxDogs'] as num?)?.toInt());

  @override
  Future<void> setMaxDogs(int value) =>
      _db.doc('users/$_uid').set({'maxDogs': value}, SetOptions(merge: true));
}
