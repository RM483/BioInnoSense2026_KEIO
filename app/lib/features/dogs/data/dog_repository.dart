/// DogRepository実装 (Firestore + Storage)。
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dog.dart';

abstract interface class DogRepository {
  Stream<List<Dog>> watchDogs();
  Future<String> addDog(Dog dog);
  Future<void> updateDog(Dog dog);
  Future<void> deleteDog(String dogId);
  Future<String> uploadPhoto(String dogId, Uint8List bytes);
}

final dogRepositoryProvider = Provider<DogRepository>((ref) {
  final uid = ref.watch(currentUserProvider).valueOrNull?.uid;
  if (uid == null) {
    throw StateError('not signed in');
  }
  return FirestoreDogRepository(
      ref.watch(firestoreProvider), ref.watch(storageProvider), uid);
});

class FirestoreDogRepository implements DogRepository {
  const FirestoreDogRepository(this._db, this._storage, this._uid);
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users/$_uid/dogs');

  Dog _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Dog.fromJson({
      ...data,
      'id': doc.id,
      'birthday': (data['birthday'] as Timestamp?)?.toDate().toIso8601String(),
    });
  }

  Map<String, dynamic> _toDoc(Dog dog) {
    final json = dog.toJson()..remove('id');
    json['birthday'] =
        dog.birthday == null ? null : Timestamp.fromDate(dog.birthday!);
    json['updatedAt'] = FieldValue.serverTimestamp();
    return json;
  }

  @override
  Stream<List<Dog>> watchDogs() =>
      _col.snapshots().map((s) => s.docs.map(_fromDoc).toList());

  @override
  Future<String> addDog(Dog dog) async {
    final doc = _toDoc(dog)..['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _col.add(doc);
    return ref.id;
  }

  @override
  Future<void> updateDog(Dog dog) => _col.doc(dog.id).update(_toDoc(dog));

  @override
  Future<void> deleteDog(String dogId) => _col.doc(dogId).delete();

  @override
  Future<String> uploadPhoto(String dogId, Uint8List bytes) async {
    final ref = _storage.ref('dogs/$_uid/$dogId/photo.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
