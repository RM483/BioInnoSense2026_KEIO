/// 設定 — デバイス・デモ・言語・アカウント。
/// 技術的な情報(接続・電池・Mock)はホームから隔離してここに集約する。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../ble/application/ble_controller.dart';
import '../../ble/data/ble_service.dart';
import '../../dogs/application/dog_controller.dart';
import '../../dogs/domain/dog.dart';
import '../data/user_settings_repository.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final ble = ref.watch(bleControllerProvider);
    final connected = ble.status == BleStatus.connected;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            // ---- ヘッダー: 日付(小) + 画面タイトル (v2.2 §4) ----
            Text(
              DateFormat.MMMEd(
                      Localizations.localeOf(context).toLanguageTag())
                  .format(DateTime.now()),
              style: AppText.caption.copyWith(color: p.textTertiary),
            ),
            const SizedBox(height: 4),
            Text(l10n.tabSettings,
                style: AppText.largeTitle.copyWith(color: p.textPrimary)),
            const SizedBox(height: 20),

            // ---- デバイス ----
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingsRow(
                    icon: CupertinoIcons.dot_radiowaves_left_right,
                    title: l10n.aboutDevice,
                    subtitle: connected
                        ? '${l10n.connected}'
                            '${ble.batteryMv != null ? ' · ${l10n.battery} ${(ble.batteryMv! / 1000).toStringAsFixed(2)}V' : ''}'
                        : l10n.disconnected,
                    subtitleColor: connected ? p.success : null,
                    onTap: () => context.push(Routes.connect),
                  ),
                  if (kUseMockBle) ...[
                    Divider(height: 1, indent: 56, color: p.hairline),
                    _SettingsRow(
                      icon: CupertinoIcons.sparkles,
                      title: l10n.demoMode,
                      subtitle: l10n.demoModeDescription,
                      subtitleColor: p.accent,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ---- 愛犬の登録設定 (デバイスとデータ系の間 §10) ----
            const _DogSettingsCard(),
            const SizedBox(height: 14),

            // ---- 一般 ----
            AppCard(
              padding: EdgeInsets.zero,
              child: _SettingsRow(
                icon: CupertinoIcons.globe,
                title: l10n.language,
                subtitle: l10n.followSystem,
              ),
            ),
            const SizedBox(height: 14),

            // ---- アカウント ----
            AppCard(
              padding: EdgeInsets.zero,
              child: _SettingsRow(
                icon: CupertinoIcons.square_arrow_right,
                title: l10n.logout,
                titleColor: p.danger,
                iconColor: p.danger,
                onTap: () async {
                  await ref
                      .read(bleControllerProvider.notifier)
                      .disconnect();
                  await ref.read(authControllerProvider.notifier).signOut();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 愛犬の登録設定 — 見守る犬の上限 (docs/21 v2.1 §10-13)。
/// 減らして超過する場合は、見守りを終了する犬の選択シートを開く。
class _DogSettingsCard extends ConsumerWidget {
  const _DogSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final maxDogs = ref.watch(maxDogsProvider).valueOrNull ?? 1;
    final watching = ref.watch(watchingDogsProvider);

    void change(int next) {
      if (next < 1 || next > 9) return;
      if (next < watching.length) {
        _showReduceSheet(context, ref,
            newMax: next, watching: watching);
        return;
      }
      ref.read(userSettingsRepositoryProvider).setMaxDogs(next);
      if (next > maxDogs) {
        // 増やす操作は確認なし・即時反映+短い通知 (v2.2 §11)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.limitIncreasedToast(next))));
      }
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(CupertinoIcons.heart, size: 21, color: p.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.watchDogsLabel, // 「見守る愛犬」 (v2.2 §7)
                      style: AppText.bodyMedium
                          .copyWith(color: p.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    l10n.watchingCountOf(watching.length, maxDogs),
                    style:
                        AppText.caption.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            _StepButton(
              icon: Icons.remove,
              enabled: maxDogs > 1,
              semantics: l10n.decrease,
              onTap: () => change(maxDogs - 1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                l10n.headCountN(maxDogs),
                style: AppText.bodyMedium.copyWith(
                    color: p.textPrimary, fontWeight: FontWeight.w600),
              ),
            ),
            _StepButton(
              icon: Icons.add,
              enabled: maxDogs < 9,
              semantics: l10n.increase,
              onTap: () => change(maxDogs + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.semantics,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: semantics,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.cardElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon,
              size: 18,
              color: enabled ? p.textPrimary : p.textTertiary),
        ),
      ),
    );
  }
}

/// 頭数を減らす場合: 見守りを終了する愛犬を選ばせる (v2.2 §8,9)。
///
/// ラジオボタン式の単一選択 — 最初の1頭が選択済みで、別の犬をタップすると
/// 即座に切り替わる。再タップで未選択にはならない。
/// 「見守りを終了して変更」の後に最終確認(§10)を出し、確認後にのみ
/// archived+上限を変更する。キャンセル時は何も変わらない。
void _showReduceSheet(
  BuildContext context,
  WidgetRef ref, {
  required int newMax,
  required List<Dog> watching,
}) {
  final l10n = AppLocalizations.of(context)!;
  final p = context.palette;
  var selectedId = watching.first.id; // 常に1頭が選択された状態 (§9)
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) => Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
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
              Text(l10n.reduceTitle,
                  textAlign: TextAlign.center,
                  style: AppText.title.copyWith(color: p.textPrimary)),
              const SizedBox(height: 8),
              Text(l10n.reduceBody(watching.length),
                  textAlign: TextAlign.center,
                  style: AppText.caption
                      .copyWith(color: p.textSecondary, height: 1.6)),
              const SizedBox(height: 16),
              for (final dog in watching) ...[
                Semantics(
                  inMutuallyExclusiveGroup: true,
                  checked: selectedId == dog.id,
                  child: GestureDetector(
                    // タップで即座に切り替え。再タップでは解除しない (§9)
                    onTap: () => setState(() => selectedId = dog.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: selectedId == dog.id
                            ? p.warnSoft
                            : p.cardElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: selectedId == dog.id
                                ? p.warn
                                : Colors.transparent,
                            width: 1.2),
                      ),
                      child: Text(
                        dog.name,
                        textAlign: TextAlign.center,
                        style: AppText.bodyMedium.copyWith(
                          color: selectedId == dog.id
                              ? p.warn
                              : p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  final dog =
                      watching.firstWhere((d) => d.id == selectedId);
                  Navigator.of(sheetContext).pop();
                  // すぐには変更せず、最終確認を挟む (§10)
                  _showReduceFinalConfirm(context, ref,
                      dog: dog, newMax: newMax);
                },
                child: Text(l10n.reduceConfirm),
              ),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 減数の最終確認 (§10)。文言はDogs画面の見守り終了と同じ。
void _showReduceFinalConfirm(
  BuildContext context,
  WidgetRef ref, {
  required Dog dog,
  required int newMax,
}) {
  final l10n = AppLocalizations.of(context)!;
  final p = context.palette;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
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
            Text(l10n.endWatchConfirmTitle(dog.name),
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(color: p.textPrimary)),
            const SizedBox(height: 10),
            Text(l10n.endWatchConfirmBody(dog.name),
                textAlign: TextAlign.center,
                style: AppText.caption
                    .copyWith(color: p.textSecondary, height: 1.7)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                // 確認後にのみ適用 (§10)。キャンセルなら何も変えない
                await ref
                    .read(dogControllerProvider.notifier)
                    .endWatch(dog);
                await ref
                    .read(userSettingsRepositoryProvider)
                    .setMaxDogs(newMax);
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
              },
              child: Text(l10n.reduceConfirm),
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

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.titleColor,
    this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Color? titleColor;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 21, color: iconColor ?? p.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.bodyMedium
                          .copyWith(color: titleColor ?? p.textPrimary)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: AppText.caption.copyWith(
                            color: subtitleColor ?? p.textSecondary)),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 18, color: p.textTertiary),
          ],
        ),
      ),
    );
  }
}
