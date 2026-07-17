/// BLE接続画面。スキャン一覧・接続・状態表示。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../application/ble_controller.dart';

class ConnectPage extends ConsumerWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ble = ref.watch(bleControllerProvider);

    // 接続完了で自動的に前画面へ戻る
    ref.listen(bleControllerProvider, (prev, next) {
      if (prev?.status != BleStatus.connected &&
          next.status == BleStatus.connected &&
          context.mounted) {
        context.pop();
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.bleConnect)),
      body: Column(
        children: [
          if (ble.status == BleStatus.scanning)
            const LinearProgressIndicator(),
          Expanded(
            child: ble.devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bluetooth_searching,
                            size: 64, color: AppColors.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text(l10n.scanning,
                            style: const TextStyle(
                                color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: ble.devices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final d = ble.devices[i];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          leading: const Icon(Icons.sensors,
                              color: AppColors.primary),
                          title: Text(d.name,
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                          subtitle: Text('RSSI ${d.rssi} dBm'),
                          trailing: FilledButton(
                            onPressed: ble.status == BleStatus.connecting
                                ? null
                                : () => ref
                                    .read(bleControllerProvider.notifier)
                                    .connect(d.id),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(96, 48)),
                            child: Text(l10n.connect),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.refresh),
                label: Text(l10n.scanning),
                onPressed: () =>
                    ref.read(bleControllerProvider.notifier).startScan(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
