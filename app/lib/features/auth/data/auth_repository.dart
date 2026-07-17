/// AuthRepository実装 (FirebaseAuth)。
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../domain/app_user.dart';

abstract interface class AuthRepository {
  Stream<AppUser?> watchAuthState();
  Future<AppUser> signInWithEmail(String email, String password);
  Future<AppUser> signUpWithEmail(String email, String password);
  Future<AppUser> signInAnonymously();
  Future<void> signOut();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FirebaseAuthRepository(ref.watch(firebaseAuthProvider)),
);

class FirebaseAuthRepository implements AuthRepository {
  const FirebaseAuthRepository(this._auth);
  final FirebaseAuth _auth;

  AppUser _toAppUser(User u) => AppUser(
        uid: u.uid,
        email: u.email,
        displayName: u.displayName,
        isAnonymous: u.isAnonymous,
      );

  @override
  Stream<AppUser?> watchAuthState() =>
      _auth.authStateChanges().map((u) => u == null ? null : _toAppUser(u));

  @override
  Future<AppUser> signInWithEmail(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      return _toAppUser(cred.user!);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }

  @override
  Future<AppUser> signUpWithEmail(String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      return _toAppUser(cred.user!);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }

  @override
  Future<AppUser> signInAnonymously() async {
    final cred = await _auth.signInAnonymously();
    return _toAppUser(cred.user!);
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
