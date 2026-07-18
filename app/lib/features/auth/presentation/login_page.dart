/// ログイン画面。メール+パスワード / 匿名ログイン。
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../application/auth_controller.dart';

class LoginPage extends HookConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final emailCtrl = useTextEditingController();
    final passCtrl = useTextEditingController();
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final authState = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_authErrorMessage(l10n, next.error))),
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---- ブランド ----
                    Icon(Icons.pets, size: 40, color: p.accent),
                    const SizedBox(height: 16),
                    Text(l10n.appTitle,
                        textAlign: TextAlign.center,
                        style: AppText.largeTitle
                            .copyWith(color: p.textPrimary)),
                    const SizedBox(height: 8),
                    // ブランドタグライン (docs/17 §1)
                    Text(l10n.brandTagline,
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(
                            color: p.textSecondary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(l10n.welcomeSubtitle,
                        textAlign: TextAlign.center,
                        style: AppText.caption
                            .copyWith(color: p.textTertiary, height: 1.6)),
                    const SizedBox(height: 44),

                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(hintText: l10n.email),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? l10n.validatorEmail
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: passCtrl,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(hintText: l10n.password),
                      validator: (v) => (v == null || v.length < 8)
                          ? l10n.validatorPassword
                          : null,
                    ),
                    const SizedBox(height: 28),

                    FilledButton(
                      onPressed: authState.isLoading
                          ? null
                          : () {
                              if (formKey.currentState?.validate() ??
                                  false) {
                                ref
                                    .read(authControllerProvider.notifier)
                                    .signIn(emailCtrl.text.trim(),
                                        passCtrl.text);
                              }
                            },
                      child: authState.isLoading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: p.onAccent))
                          : Text(l10n.signIn),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: authState.isLoading
                          ? null
                          : () {
                              if (formKey.currentState?.validate() ??
                                  false) {
                                ref
                                    .read(authControllerProvider.notifier)
                                    .signUp(emailCtrl.text.trim(),
                                        passCtrl.text);
                              }
                            },
                      child: Text(l10n.signUp),
                    ),
                    const SizedBox(height: 28),
                    Row(children: [
                      Expanded(child: Divider(color: p.hairline)),
                    ]),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: authState.isLoading
                          ? null
                          : () => ref
                              .read(authControllerProvider.notifier)
                              .signInAnonymously(),
                      child: Text(l10n.signInAnonymously,
                          style: AppText.caption
                              .copyWith(color: p.textSecondary)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// FirebaseAuthのエラーコードを利用者向けの言葉に変換する。
  static String _authErrorMessage(AppLocalizations l10n, Object? error) {
    final code = error is AuthException ? error.message : '';
    return switch (code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'invalid-email' =>
        l10n.errorAuthInvalidCredential,
      'email-already-in-use' => l10n.errorAuthEmailInUse,
      'weak-password' => l10n.errorAuthWeakPassword,
      'network-request-failed' => l10n.errorNetwork,
      _ => l10n.errorAuthGeneric,
    };
  }
}
