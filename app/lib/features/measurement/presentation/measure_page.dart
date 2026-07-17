/// 測定画面。現在値を最大要素に、リアルタイムグラフと開始/停止を配置。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../ble/application/ble_controller.dart';
import '../../dogs/application/dog_controller.dart';
import '../../error/presentation/error_page.dart';
import '../application/measurement_controller.dart';
import 'realtime_chart.dart';

class MeasurePage extends ConsumerWidget {
  const MeasurePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final measure = ref.watch(measurementControllerProvider);
    final ble = ref.watch(bleControllerProvider);
    final dog = ref.watch(selectedDogProvider);

    // エラー遷移 / 保存完了スナックバー
    ref.listen(measurementControllerProvider, (prev, next) {
      if (!context.mounted) return;
      if (next.phase == MeasurePhase.error) {
        context.push(Routes.error, extra: ErrorKind.fromHpp(next.errorCode));
      } else if (prev?.phase != MeasurePhase.saved &&
          next.phase == MeasurePhase.saved) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.measurementSaved)));
      }
    });

    final latest = measure.latest;
    final measuring = measure.phase == MeasurePhase.measuring;
    final currentPpm = latest?.h2Ppm ?? 0;
    final isHigh = currentPpm >= 20.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(dog?.name ?? l10n.measure),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _ConnectionChip(status: ble.status),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // ---- 現在値 ----
              Text(
                latest == null ? '--' : currentPpm.toStringAsFixed(1),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: isHigh ? AppColors.accent : AppColors.primary,
                    ),
              ),
              Text(l10n.ppm,
                  style:
                      const TextStyle(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 8),
              if (latest?.isWarmup ?? false)
                Text(l10n.warmingUp,
                    style: const TextStyle(color: AppColors.accent))
              else if (latest != null)
                Text(
                  isHigh ? l10n.highValue : l10n.normalRange,
                  style: TextStyle(
                    color: isHigh ? AppColors.accent : AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 24),

              // ---- グラフ ----
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
                    child: measure.samples.isEmpty
                        ? const Center(
                            child: Icon(Icons.show_chart,
                                size: 48,
                                color: AppColors.onSurfaceVariant))
                        : RealtimeChart(samples: measure.samples),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ---- 統計 ----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat(
                      label: l10n.elapsed,
                      value: _formatElapsed(latest?.timeMs ?? 0)),
                  _Stat(
                      label: l10n.average,
                      value: measure.averagePpm.toStringAsFixed(1)),
                  _Stat(
                      label: l10n.peak,
                      value: measure.samples.isEmpty
                          ? '--'
                          : measure.samples
                              .map((s) => s.h2Ppm)
                              .reduce((a, b) => a > b ? a : b)
                              .toStringAsFixed(1)),
                ],
              ),
              const SizedBox(height: 24),

              // ---- 開始 / 停止 ----
              FilledButton.icon(
                icon: Icon(measuring ? Icons.stop : Icons.play_arrow),
                label: Text(
                    measuring ? l10n.stop : l10n.startMeasurement),
                style: measuring
                    ? FilledButton.styleFrom(
                        backgroundColor: AppColors.error)
                    : null,
                onPressed: switch (measure.phase) {
                  MeasurePhase.starting || MeasurePhase.stopping => null,
                  MeasurePhase.measuring => () => ref
                      .read(measurementControllerProvider.notifier)
                      .stopAndSave(
                          dog?.id ?? '', ble.connectedDeviceId ?? ''),
                  _ => () {
                      ref
                          .read(measurementControllerProvider.notifier)
                          .resetSession();
                      ref
                          .read(measurementControllerProvider.notifier)
                          .start();
                    },
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatElapsed(int ms) {
    final s = ms ~/ 1000;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.onSurfaceVariant, fontSize: 14)),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      );
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.status});
  final BleStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (label, color) = switch (status) {
      BleStatus.connected => (l10n.connected, AppColors.primary),
      BleStatus.reconnecting => (l10n.reconnecting, AppColors.accent),
      _ => (l10n.disconnected, AppColors.onSurfaceVariant),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 14)),
      ],
    );
  }
}
