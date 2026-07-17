/// 測定画面。
/// 現在値をただひとつの主役に置き、それ以外の情報は静かに従属させる。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/constants/h2.dart';
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
    final p = context.palette;
    final measure = ref.watch(measurementControllerProvider);
    final ble = ref.watch(bleControllerProvider);
    final dog = ref.watch(selectedDogProvider);

    // エラー遷移 / 保存完了スナックバー
    ref.listen(measurementControllerProvider, (prev, next) {
      if (!context.mounted) return;
      if (prev?.phase != MeasurePhase.error &&
          next.phase == MeasurePhase.error) {
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
    final isHigh = currentPpm >= H2.highPpm;
    final valueColor = latest == null
        ? p.textTertiary
        : isHigh
            ? p.warn
            : p.textPrimary;

    return Scaffold(
      appBar: AppBar(
        title: Text(dog?.name ?? l10n.measure),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(child: _ConnectionPill(status: ble.status)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ---- 現在値 ----
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: AppText.display.copyWith(color: valueColor),
                child: Text(
                  latest == null ? '––' : currentPpm.toStringAsFixed(1),
                ),
              ),
              const SizedBox(height: 6),
              Text(l10n.ppm,
                  style: AppText.caption.copyWith(color: p.textTertiary)),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: latest == null
                    ? Text(l10n.measureHint,
                        key: const ValueKey('hint'),
                        style:
                            AppText.caption.copyWith(color: p.textTertiary))
                    : (latest.isWarmup)
                        ? StatusPill(
                            key: const ValueKey('warmup'),
                            label: l10n.warmingUp,
                            color: p.warn,
                            softColor: p.warnSoft,
                            dot: false,
                          )
                        : StatusPill(
                            key: ValueKey(isHigh),
                            label:
                                isHigh ? l10n.highValue : l10n.normalRange,
                            color: isHigh ? p.warn : p.success,
                            softColor: isHigh
                                ? p.warnSoft
                                : p.success.withOpacity(0.10),
                          ),
              ),

              const Spacer(flex: 2),

              // ---- グラフ ----
              SizedBox(
                height: 220,
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(8, 18, 18, 8),
                  child: measure.samples.isEmpty
                      ? Center(
                          child: Icon(Icons.monitor_heart_outlined,
                              size: 32, color: p.textTertiary),
                        )
                      : RealtimeChart(samples: measure.samples),
                ),
              ),
              const SizedBox(height: 20),

              // ---- 統計 ----
              Row(
                children: [
                  _Stat(
                      label: l10n.elapsed,
                      value: _formatElapsed(latest?.timeMs ?? 0)),
                  _VerticalHairline(),
                  _Stat(
                      label: l10n.average,
                      value: latest == null
                          ? '––'
                          : measure.averagePpm.toStringAsFixed(1)),
                  _VerticalHairline(),
                  _Stat(
                      label: l10n.peak,
                      value: latest == null
                          ? '––'
                          : measure.peakPpm.toStringAsFixed(1)),
                  if (latest != null) ...[
                    _VerticalHairline(),
                    _Stat(
                        label: l10n.temperature,
                        value: '${latest.tempC.toStringAsFixed(1)}°'),
                  ],
                ],
              ),
              const SizedBox(height: 28),

              // ---- 開始 / 停止 ----
              _PrimaryActionButton(
                measuring: measuring,
                phase: measure.phase,
                enabled: dog != null &&
                    (ble.status == BleStatus.connected || measuring),
                onStart: () {
                  final c = ref.read(measurementControllerProvider.notifier);
                  c
                    ..resetSession()
                    ..start();
                },
                onStop: () => ref
                    .read(measurementControllerProvider.notifier)
                    .stopAndSave(dog?.id ?? '', ble.connectedDeviceId ?? ''),
              ),
              if (dog == null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.push(Routes.dog),
                  child: Text(l10n.addDogPrompt),
                ),
              ],
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

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.measuring,
    required this.phase,
    required this.enabled,
    required this.onStart,
    required this.onStop,
  });

  final bool measuring;
  final MeasurePhase phase;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final busy =
        phase == MeasurePhase.starting || phase == MeasurePhase.stopping;

    return FilledButton(
      style: measuring
          ? FilledButton.styleFrom(
              backgroundColor: p.textPrimary,
              foregroundColor: p.bg,
            )
          : null,
      onPressed: !enabled || busy ? null : (measuring ? onStop : onStart),
      child: busy
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: measuring ? p.bg : Colors.white),
            )
          : Text(measuring ? l10n.stop : l10n.startMeasurement),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: AppText.numeral.copyWith(color: p.textPrimary)),
          const SizedBox(height: 3),
          Text(label,
              style: AppText.caption.copyWith(color: p.textTertiary)),
        ],
      ),
    );
  }
}

class _VerticalHairline extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: context.palette.hairline);
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.status});
  final BleStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final (label, color, soft) = switch (status) {
      BleStatus.connected => (
          l10n.connected,
          p.success,
          p.success.withOpacity(0.10)
        ),
      BleStatus.reconnecting => (l10n.reconnecting, p.warn, p.warnSoft),
      _ => (l10n.disconnected, p.textTertiary, p.cardElevated),
    };
    return StatusPill(label: label, color: color, softColor: soft);
  }
}
