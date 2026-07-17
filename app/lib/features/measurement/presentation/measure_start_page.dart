/// 測定タブ — 開始前の準備画面。
/// 「接続されているか」を専門用語なしで伝え、はじめるだけに集中させる。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_ring.dart';
import '../../../l10n/app_localizations.dart';
import '../../ble/application/ble_controller.dart';
import '../../dogs/application/dog_controller.dart';

class MeasureStartPage extends ConsumerWidget {
  const MeasureStartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final dog = ref.watch(selectedDogProvider);
    final ble = ref.watch(bleControllerProvider);
    final connected = ble.status == BleStatus.connected;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.tabMeasure,
                  style: AppText.largeTitle.copyWith(color: p.textPrimary)),
              const Spacer(),

              // ---- 中央: 見守りリング (測定中の呼吸リングへHeroで連続) ----
              Center(
                child: Column(
                  children: [
                    Hero(
                      tag: 'care-ring',
                      child: StatusRing(
                        size: 148,
                        color: connected ? p.accent : p.textTertiary,
                        photoUrl: dog?.photoUrl ?? '',
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      dog == null
                          ? l10n.registerDog
                          : l10n.measureTitleFor(dog.name),
                      style: AppText.title.copyWith(color: p.textPrimary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dog == null
                          ? l10n.addDogPrompt
                          : connected
                              ? l10n.measureHint
                              : l10n.connectFirstHint,
                      style: AppText.body.copyWith(
                          color: p.textSecondary, height: 1.55),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),

              // ---- アクション ----
              if (dog == null)
                FilledButton(
                  onPressed: () => context.go(Routes.dog),
                  child: Text(l10n.registerDog),
                )
              else if (!connected)
                FilledButton(
                  onPressed: () => context.push(Routes.connect),
                  child: Text(l10n.bleConnect),
                )
              else
                FilledButton(
                  onPressed: () => context.push(Routes.measureSession),
                  child: Text(l10n.begin),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

