/// 設定 — デバイス・デモ・言語・アカウント。
/// 技術的な情報(接続・電池・Mock)はホームから隔離してここに集約する。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../ble/application/ble_controller.dart';
import '../../ble/data/ble_service.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final ble = ref.watch(bleControllerProvider);
    final connected = ble.status == BleStatus.connected;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            Text(l10n.tabSettings,
                style: AppText.largeTitle.copyWith(color: p.textPrimary)),
            const SizedBox(height: 20),

            // ---- デバイス ----
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingsRow(
                    icon: CupertinoIcons.dot_radiowaves_left_right,
                    title: l10n.aboutDevice,
                    subtitle: connected
                        ? '${l10n.connected}'
                            '${ble.batteryMv != null ? ' · ${l10n.battery} ${(ble.batteryMv! / 1000).toStringAsFixed(2)}V' : ''}'
                        : l10n.disconnected,
                    subtitleColor: connected ? p.success : null,
                    onTap: () => context.push(Routes.connect),
                  ),
                  if (kUseMockBle) ...[
                    Divider(height: 1, indent: 56, color: p.hairline),
                    _SettingsRow(
                      icon: CupertinoIcons.sparkles,
                      title: l10n.demoMode,
                      subtitle: l10n.demoModeDescription,
                      subtitleColor: p.accent,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ---- 一般 ----
            AppCard(
              padding: EdgeInsets.zero,
              child: _SettingsRow(
                icon: CupertinoIcons.globe,
                title: l10n.language,
                subtitle: l10n.followSystem,
              ),
            ),
            const SizedBox(height: 14),

            // ---- アカウント ----
            AppCard(
              padding: EdgeInsets.zero,
              child: _SettingsRow(
                icon: CupertinoIcons.square_arrow_right,
                title: l10n.logout,
                titleColor: p.danger,
                iconColor: p.danger,
                onTap: () async {
                  await ref
                      .read(bleControllerProvider.notifier)
                      .disconnect();
                  await ref.read(authControllerProvider.notifier).signOut();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.titleColor,
    this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Color? titleColor;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 21, color: iconColor ?? p.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.bodyMedium
                          .copyWith(color: titleColor ?? p.textPrimary)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: AppText.caption.copyWith(
                            color: subtitleColor ?? p.textSecondary)),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 18, color: p.textTertiary),
          ],
        ),
      ),
    );
  }
}
