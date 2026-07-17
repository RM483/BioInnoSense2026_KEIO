/// Firebase SDKインスタンスのDI。テストではoverrideしてfake/mockに差し替える。
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final firebaseAuthProvider =
    Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  final db = FirebaseFirestore.instance;
  db.settings = const Settings(persistenceEnabled: true); // オフライン対応
  return db;
});

final storageProvider =
    Provider<FirebaseStorage>((ref) => FirebaseStorage.instance);

final analyticsProvider =
    Provider<FirebaseAnalytics>((ref) => FirebaseAnalytics.instance);
