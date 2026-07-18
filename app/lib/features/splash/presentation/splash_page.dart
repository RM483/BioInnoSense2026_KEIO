/// Splash — ブランドの一呼吸 (docs/17 §11)。
/// マーク(肉球) + ワードマーク + タグラインのみ。
/// ローディング表示は置かない(起動は一瞬であるべき)。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';

class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;

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
            // ---- マーク: Mizuhaの円面に肉球 ----
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.alphaBlend(p.accentSoft, p.bg),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.pets, size: 42, color: p.accent),
            ),
            const SizedBox(height: 20),
            // ---- ワードマーク ----
            Text(
              'HydroPaw',
              style: AppText.largeTitle.copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: 8),
            // ---- タグライン ----
            Text(
              l10n.brandTagline,
              style: AppText.caption.copyWith(color: p.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
