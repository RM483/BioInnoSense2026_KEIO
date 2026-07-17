/// ログイン画面のWidgetテスト。AuthRepositoryをfakeに差し替えて検証。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hydropaw/features/auth/data/auth_repository.dart';
import 'package:hydropaw/features/auth/domain/app_user.dart';
import 'package:hydropaw/features/auth/presentation/login_page.dart';
import 'package:hydropaw/l10n/app_localizations.dart';

class FakeAuthRepository implements AuthRepository {
  String? signedInEmail;

  @override
  Stream<AppUser?> watchAuthState() => Stream.value(null);

  @override
  Future<AppUser> signInWithEmail(String email, String password) async {
    signedInEmail = email;
    return AppUser(uid: 'test-uid', email: email);
  }

  @override
  Future<AppUser> signUpWithEmail(String email, String password) =>
      signInWithEmail(email, password);

  @override
  Future<AppUser> signInAnonymously() async =>
      const AppUser(uid: 'anon', isAnonymous: true);

  @override
  Future<void> signOut() async {}
}

Widget wrap(Widget child, FakeAuthRepository fake) => ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(fake)],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('ja')],
        locale: Locale('ja'),
        home: LoginPage(),
      ),
    );

void main() {
  testWidgets('不正な入力ではサインインが実行されない', (tester) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(wrap(const LoginPage(), fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tester.enterText(find.byType(TextFormField).last, 'short');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(fake.signedInEmail, isNull);
  });

  testWidgets('正しい入力でリポジトリが呼ばれる', (tester) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(wrap(const LoginPage(), fake));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextFormField).first, 'test@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'password123');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(fake.signedInEmail, 'test@example.com');
  });
}
