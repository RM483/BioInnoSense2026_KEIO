/// 設定画面。デバイス管理・ログアウト等。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../ble/application/ble_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ble = ref.watch(bleControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bluetooth,
                      color: AppColors.primary),
                  title: Text(l10n.deviceManagement),
                  subtitle: Text(ble.status == BleStatus.connected
                      ? '${l10n.connected}'
                        '${ble.batteryMv != null ? ' ・ ${(ble.batteryMv! / 1000).toStringAsFixed(2)}V' : ''}'
                      : l10n.disconnected),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.connect),
                ),
                const Divider(height: 1, color: AppColors.outline),
                ListTile(
                  leading: const Icon(Icons.language,
                      color: AppColors.primary),
                  title: Text(l10n.language),
                  subtitle: const Text('システム設定に従う'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: Text(l10n.logout,
                  style: const TextStyle(color: AppColors.error)),
              onTap: () async {
                await ref.read(bleControllerProvider.notifier).disconnect();
                await ref.read(authControllerProvider.notifier).signOut();
              },
            ),
          ),
        ],
      ),
    );
  }
}
