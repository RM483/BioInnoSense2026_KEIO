/// ログイン画面。メール+パスワード / 匿名ログイン。
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/auth_controller.dart';

class LoginPage extends HookConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final emailCtrl = useTextEditingController();
    final passCtrl = useTextEditingController();
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final authState = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorNetwork)),
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.appTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 48),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: l10n.email,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? '✕' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.password,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 8) ? '✕' : null,
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: authState.isLoading
                          ? null
                          : () {
                              if (formKey.currentState?.validate() ?? false) {
                                ref.read(authControllerProvider.notifier).signIn(
                                    emailCtrl.text.trim(), passCtrl.text);
                              }
                            },
                      child: authState.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(l10n.signIn),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: authState.isLoading
                          ? null
                          : () {
                              if (formKey.currentState?.validate() ?? false) {
                                ref.read(authControllerProvider.notifier).signUp(
                                    emailCtrl.text.trim(), passCtrl.text);
                              }
                            },
                      child: Text(l10n.signUp),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: authState.isLoading
                          ? null
                          : () => ref
                              .read(authControllerProvider.notifier)
                              .signInAnonymously(),
                      child: Text(l10n.signInAnonymously),
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
}
