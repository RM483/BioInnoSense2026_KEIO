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
    final p = context.palette;
    final (icon, message) = switch (kind) {
      ErrorKind.sensorTimeout =>
        (Icons.sensors_off_outlined, l10n.errorSensorTimeout),
      ErrorKind.bleDisconnected =>
        (Icons.bluetooth_disabled_outlined, l10n.errorBleDisconnected),
      ErrorKind.network => (Icons.wifi_off_outlined, l10n.errorNetwork),
      ErrorKind.lowBattery =>
        (Icons.battery_alert_outlined, l10n.errorLowBattery),
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
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.cardElevated,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 34, color: p.textSecondary),
              ),
              const SizedBox(height: 28),
              Text(l10n.errorTitle,
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
                child: Text(l10n.retry),
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
