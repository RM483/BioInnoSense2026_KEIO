/// エラー画面。技術用語を出さず、次の行動を1つ示す。
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
  unknown;

  /// HPPエラーコード → 表示種別
  static ErrorKind fromHpp(int? code) => switch (code) {
        0x01 || 0x02 => ErrorKind.sensorTimeout,
        0x07 => ErrorKind.lowBattery,
        _ => ErrorKind.unknown,
      };
}

class ErrorPage extends StatelessWidget {
  const ErrorPage({super.key, required this.kind});
  final ErrorKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (icon, message) = switch (kind) {
      ErrorKind.sensorTimeout =>
        (Icons.sensors_off, l10n.errorSensorTimeout),
      ErrorKind.bleDisconnected =>
        (Icons.bluetooth_disabled, l10n.errorBleDisconnected),
      ErrorKind.network => (Icons.wifi_off, l10n.errorNetwork),
      ErrorKind.lowBattery =>
        (Icons.battery_alert, l10n.errorLowBattery),
      ErrorKind.unknown => (Icons.error_outline, l10n.errorTitle),
    };

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 80, color: AppColors.onSurfaceVariant),
              const SizedBox(height: 24),
              Text(l10n.errorTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.onSurfaceVariant, height: 1.6)),
              const SizedBox(height: 48),
              FilledButton(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(Routes.home),
                child: Text(l10n.retry),
              ),
              const SizedBox(height: 12),
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
