/// BLE接続画面。スキャン一覧・接続・状態表示。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../application/ble_controller.dart';

class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  @override
  void initState() {
    super.initState();
    // 画面を開いたら自動でスキャン開始
    Future.microtask(
        () => ref.read(bleControllerProvider.notifier).startScan());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
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
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ble.devices.isEmpty
                  ? _ScanningPlaceholder(l10n: l10n)
                  : ListView.separated(
                      padding: const EdgeInsets.all(24),
                      itemCount: ble.devices.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final d = ble.devices[i];
                        final connecting =
                            ble.status == BleStatus.connecting;
                        return AppCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              _RssiIndicator(rssi: d.rssi),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(d.name,
                                        style: AppText.bodyMedium.copyWith(
                                            color: p.textPrimary)),
                                    const SizedBox(height: 2),
                                    Text('${d.rssi} dBm',
                                        style: AppText.caption.copyWith(
                                            color: p.textTertiary)),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 40,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(88, 40),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18),
                                    textStyle: AppText.caption.copyWith(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  onPressed: connecting
                                      ? null
                                      : () => ref
                                          .read(
                                              bleControllerProvider.notifier)
                                          .connect(d.id),
                                  child: connecting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : Text(l10n.connect),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: TextButton.icon(
                icon: Icon(Icons.refresh, size: 18, color: p.textSecondary),
                label: Text(l10n.scanning),
                onPressed: () =>
                    ref.read(bleControllerProvider.notifier).startScan(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanningPlaceholder extends StatelessWidget {
  const _ScanningPlaceholder({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
                strokeWidth: 2.2, color: p.textTertiary),
          ),
          const SizedBox(height: 20),
          Text(l10n.scanning,
              style: AppText.caption.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }
}

/// 電波強度の4段バー。
class _RssiIndicator extends StatelessWidget {
  const _RssiIndicator({required this.rssi});
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final level = rssi > -55
        ? 4
        : rssi > -67
            ? 3
            : rssi > -80
                ? 2
                : 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final active = i < level;
        return Container(
          width: 3.5,
          height: 6.0 + i * 4,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: active ? p.accent : p.cardElevated,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
