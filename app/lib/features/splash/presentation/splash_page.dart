/// Splash画面。認証状態が確定したら遷移する。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';

class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;

    // 認証状態の初回解決を待って遷移
    ref.listen(authStateChangesProvider, (_, next) {
      next.whenData((user) {
        if (!context.mounted) return;
        context.go(user == null ? Routes.login : Routes.home);
      });
    });

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pets, size: 44, color: p.accent),
            const SizedBox(height: 16),
            Text('HydroPaw',
                style: AppText.largeTitle.copyWith(color: p.textPrimary)),
          ],
        ),
      ),
    );
  }
}
