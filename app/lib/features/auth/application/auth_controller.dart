/// 認証ViewModel。
/// Firebaseの型はrepository層で吸収し、ここから上は AppUser のみを扱う
/// (オフライン/テスト時は authRepositoryProvider の差し替えだけで完結する)。
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/auth_repository.dart';
import '../domain/app_user.dart';

/// 現在ユーザーのストリーム (GoRouterのredirect・画面共通)
final authStateChangesProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).watchAuthState(),
);

/// authStateChangesProviderの別名(可読性のため)
final currentUserProvider = authStateChangesProvider;

class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signIn(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signInWithEmail(email, password),
    );
  }

  Future<void> signUp(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signUpWithEmail(email, password),
    );
  }

  Future<void> signInAnonymously() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signInAnonymously(),
    );
  }

  Future<void> signOut() =>
      ref.read(authRepositoryProvider).signOut();
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
