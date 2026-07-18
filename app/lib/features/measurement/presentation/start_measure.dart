/// 測定開始の共通フロー (docs/21 v2.1 §3)。
///
/// 犬未登録 → Dogsタブ / 未接続 → 接続画面 / 接続済み → **対象犬の確認** →
/// 測定セッションへ。ホームで犬をスワイプ切替するため、誤った犬への記録を
/// 防ぐ確認を必ず挟む。開始後の対象はセッション側で固定される
/// (MeasuringPageが開始時のdogIdをFWコマンドに渡し、以後変更不可)。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_ring.dart';
import '../../../l10n/app_localizations.dart';
import '../../ble/application/ble_controller.dart';
import '../../dogs/application/dog_controller.dart';
import '../../dogs/domain/dog.dart';

void startMeasureFlow(BuildContext context, WidgetRef ref) =>
    startMeasureFlowFor(context, ref, ref.read(selectedDogProvider));

/// ホームの各ページ(犬ごと)からは、そのページの犬を明示して呼ぶ (§12)。
void startMeasureFlowFor(BuildContext context, WidgetRef ref, Dog? dog) {
  HapticFeedback.selectionClick();
  if (dog == null) {
    context.go(Routes.dogs);
    return;
  }
  final connected =
      ref.read(bleControllerProvider).status == BleStatus.connected;
  if (!connected) {
    context.push(Routes.connect);
    return;
  }
  // 確認前に選択を対象犬へ合わせる(セッションはselectedDogを対象に固定する)
  ref.read(selectedDogIdProvider.notifier).state = dog.id;
  _confirmTarget(context, dog);
}

/// 対象犬の確認シート。「測定を開始」で対象を固定してセッションへ。
void _confirmTarget(BuildContext context, Dog dog) {
  final l10n = AppLocalizations.of(context)!;
  final p = context.palette;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: p.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: StatusRing(
                size: 96,
                color: p.accent,
                photoUrl: dog.photoUrl,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.measureConfirmTitle(dog.name),
              textAlign: TextAlign.center,
              style: AppText.title.copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                context.push(Routes.measureSession);
              },
              child: Text(l10n.measureConfirmStart),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    ),
  );
}
