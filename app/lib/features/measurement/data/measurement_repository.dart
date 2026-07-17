/// MeasurementRepository実装 (Cloud Firestore)。
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/measurement.dart';

abstract interface class MeasurementRepository {
  Future<String> save(String dogId, Measurement m);
  Future<List<Measurement>> fetchHistory(String dogId,
      {DateTime? before, int limit});
  Stream<Measurement?> watchLatest(String dogId);
}

final measurementRepositoryProvider = Provider<MeasurementRepository>((ref) {
  final uid = ref.watch(currentUserProvider).valueOrNull?.uid;
  if (uid == null) {
    throw StateError('not signed in');
  }
  return FirestoreMeasurementRepository(ref.watch(firestoreProvider), uid);
});

class FirestoreMeasurementRepository implements MeasurementRepository {
  const FirestoreMeasurementRepository(this._db, this._uid);
  final FirebaseFirestore _db;
  final String _uid;

  CollectionReference<Map<String, dynamic>> _col(String dogId) =>
      _db.collection('users/$_uid/dogs/$dogId/measurements');

  Measurement _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Measurement.fromJson({
      ...data,
      'id': doc.id,
      'startedAt': (data['startedAt'] as Timestamp).toDate().toIso8601String(),
    });
  }

  Map<String, dynamic> _toDoc(Measurement m) {
    final json = m.toJson()..remove('id');
    json['startedAt'] = Timestamp.fromDate(m.startedAt);
    return json;
  }

  @override
  Future<String> save(String dogId, Measurement m) async {
    final ref = await _col(dogId).add(_toDoc(m));
    return ref.id;
  }

  @override
  Future<List<Measurement>> fetchHistory(String dogId,
      {DateTime? before, int limit = 20}) async {
    var q = _col(dogId).orderBy('startedAt', descending: true).limit(limit);
    if (before != null) {
      q = q.startAfter([Timestamp.fromDate(before)]);
    }
    final snap = await q.get();
    return snap.docs.map(_fromDoc).toList();
  }

  @override
  Stream<Measurement?> watchLatest(String dogId) => _col(dogId)
      .orderBy('startedAt', descending: true)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : _fromDoc(s.docs.first));
}
