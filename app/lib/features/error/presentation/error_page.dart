/// 「エラー画面」は存在しない (docs/17 §10)。
/// 題は状況報告ではなく次の一歩。構成は常に:
/// やわらかい図 → 何が起きたか(1文・非難なし) → 主ボタン(次の一歩) → ホームへ。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';

enum ErrorKind {
  sensorTimeout,
  bleDisconnected,
  network,
  lowBattery,
  noBreath,
  unknown;

  /// HPPエラーコード → 表示種別
  static ErrorKind fromHpp(int? code) => switch (code) {
        0x01 || 0x02 => ErrorKind.sensorTimeout,
        0x07 => ErrorKind.lowBattery,
        0x0A => ErrorKind.noBreath, // E_NO_BREATH (READYタイムアウト)
        _ => ErrorKind.unknown,
      };
}

class ErrorPage extends StatelessWidget {
  const ErrorPage({super.key, required this.kind});
  final ErrorKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;

    // kindごとに 題(次の一歩) / 一文 / 主ボタン を変える
    final (icon, title, message, action) = switch (kind) {
      ErrorKind.sensorTimeout => (
          Icons.sensors_outlined,
          l10n.errorTitleSensor,
          l10n.errorSensorTimeout,
          l10n.retry,
        ),
      ErrorKind.bleDisconnected => (
          Icons.bluetooth_outlined,
          l10n.errorTitleBle,
          l10n.errorBleDisconnected,
          l10n.reconnectAction,
        ),
      ErrorKind.network => (
          Icons.wifi_outlined,
          l10n.errorTitleNetwork,
          l10n.errorNetwork,
          l10n.retry,
        ),
      ErrorKind.lowBattery => (
          Icons.battery_5_bar_outlined,
          l10n.errorTitleBattery,
          l10n.errorLowBattery,
          l10n.okUnderstood,
        ),
      ErrorKind.noBreath => (
          Icons.air_outlined,
          l10n.errorTitleNoBreath,
          l10n.errorNoBreath,
          l10n.retry,
        ),
      ErrorKind.unknown => (
          Icons.refresh_outlined,
          l10n.errorTitle,
          l10n.errorNetwork,
          l10n.retry,
        ),
    };

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.cardElevated,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: p.textSecondary),
              ),
              const SizedBox(height: 28),
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppText.title.copyWith(color: p.textPrimary)),
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: AppText.body
                      .copyWith(color: p.textSecondary, height: 1.6)),
              const SizedBox(height: 44),
              FilledButton(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(Routes.home),
                child: Text(action),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.go(Routes.home),
                child: Text(l10n.backToHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
