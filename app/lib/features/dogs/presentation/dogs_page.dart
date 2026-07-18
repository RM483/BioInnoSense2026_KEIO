/// Dogsタブ — 犬カードを縦に並べて管理する (docs/21 v2.1 §4-7)。
///
/// 犬の切り替えはホームの左右スワイプへ移動。この画面は「管理の置き場」:
/// プロフィール編集 / 削除(記録なしのみ・警告つき) / 見守り終了(記録あり) /
/// 再開(上限チェック) / 追加(上限チェック)。カードのデザインは従来を維持し、
/// カード自体のタップには何も割り当てない(誤操作防止)。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_ring.dart';
import '../../../l10n/app_localizations.dart';
import '../../insights/application/insights_providers.dart';
import '../../insights/domain/health_assessment.dart';
import '../../settings/data/user_settings_repository.dart';
import '../application/dog_controller.dart';
import '../domain/dog.dart';

class DogsPage extends ConsumerWidget {
  const DogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final watching = ref.watch(watchingDogsProvider);
    final archived = ref.watch(archivedDogsProvider);
    final drafts = ref.watch(draftDogsProvider);
    final selected = ref.watch(selectedDogProvider);
    final maxDogs = ref.watch(maxDogsProvider).valueOrNull ?? 1;

    final locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            // ---- ヘッダー: 日付(小) + 画面タイトル (v2.2 §3) ----
            Text(
              DateFormat.MMMEd(locale).format(DateTime.now()),
              style: AppText.caption.copyWith(color: p.textTertiary),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(l10n.tabDogs,
                      style: AppText.largeTitle
                          .copyWith(color: p.textPrimary)),
                ),
                Text(
                  l10n.watchingCountOf(watching.length, maxDogs),
                  style: AppText.caption.copyWith(color: p.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ---- 見守り中 (縦並び §4) ----
            for (final dog in watching) ...[
              _DogCard(
                dog: dog,
                watching: dog.id == selected?.id,
                kind: _CardKind.watching,
              ),
              const SizedBox(height: 14),
            ],

            // ---- 未設定の残骸 (存在する場合のみ §5A) ----
            for (final dog in drafts) ...[
              _DogCard(dog: dog, watching: false, kind: _CardKind.draft),
              const SizedBox(height: 14),
            ],

            // ---- 追加 (上限チェック §11) ----
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 20),
              label: Text(l10n.addDog),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: p.accent,
                side: BorderSide(color: p.hairline, width: 1.2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: () {
                if (watching.length >= maxDogs) {
                  _showLimitSheet(
                    context,
                    title: l10n.limitReachedTitle,
                    body: l10n.limitReachedBody(maxDogs),
                  );
                } else {
                  context.push(Routes.dogEdit,
                      extra: const Dog(id: '', name: ''));
                }
              },
            ),

            // ---- 見守りを終了した犬 (存在する場合のみ §7) ----
            if (archived.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                l10n.archivedDogsHeading,
                style: AppText.caption.copyWith(
                    color: p.textTertiary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              for (final dog in archived) ...[
                _DogCard(
                    dog: dog, watching: false, kind: _CardKind.archived),
                const SizedBox(height: 14),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

enum _CardKind { watching, draft, archived }

/// 文言用: 名前が空でも安全に表示する (v2.2 §5)
String _safeName(Dog dog, AppLocalizations l10n) =>
    dog.isComplete ? dog.name : l10n.thisDog;

class _DogCard extends ConsumerWidget {
  const _DogCard({
    required this.dog,
    required this.watching,
    required this.kind,
  });

  final Dog dog;
  final bool watching;
  final _CardKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    // 犬ごとの評価(family)で、別の犬の状態が混ざらないようにする (§12)
    final assessment = watching
        ? (ref.watch(healthAssessmentOfProvider(dog.id)).valueOrNull ??
            HealthAssessment.fromHistory(const []))
        : null;
    final hasRecords =
        ref.watch(hasRecordsProvider(dog.id)).valueOrNull ?? true;
    // ↑ 判定完了までは安全側(true=削除を出さない)に倒す (§15)

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        children: [
          StatusRing(
            size: 108,
            color: assessment != null
                ? assessment.level.color(p)
                : p.textTertiary.withOpacity(0.4),
            photoUrl: dog.photoUrl,
          ),
          const SizedBox(height: 14),
          Text(
            dog.isComplete ? dog.name : l10n.draftDogName,
            style: AppText.title.copyWith(
                color: dog.isComplete ? p.textPrimary : p.textTertiary,
                fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (dog.breed.isNotEmpty) dog.breed,
              if (dog.ageYears != null) l10n.dogAgeYears(dog.ageYears!),
              if (dog.weightKg > 0) '${dog.weightKg}kg',
            ].join(' · '),
            style: AppText.caption.copyWith(color: p.textSecondary),
          ),
          if (watching) ...[
            const SizedBox(height: 12),
            StatusPill(
              label: l10n.watchingNow,
              color: p.accent,
              softColor: p.accentSoft,
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => context.push(Routes.dogEdit, extra: dog),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(color: p.hairline),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
            child: Text(l10n.editProfile,
                style: AppText.bodyMedium.copyWith(color: p.textPrimary)),
          ),

          // 破壊的/低頻度操作: 編集との誤操作を防ぐ余白をとり、控えめに (§5,6)
          const SizedBox(height: 20),
          switch (kind) {
            // 文言には犬の名前を入れる。空なら「この愛犬」 (v2.2 §5)
            _CardKind.watching => hasRecords
                ? _SubtleAction(
                    label: l10n.endWatchActionFor(_safeName(dog, l10n)),
                    color: p.textTertiary,
                    onTap: () => _confirmEndWatch(context, ref, dog),
                  )
                : _SubtleAction(
                    label:
                        l10n.deleteProfileActionFor(_safeName(dog, l10n)),
                    color: p.danger.withOpacity(0.75),
                    onTap: () => _confirmDelete(context, ref, dog),
                  ),
            _CardKind.draft => _SubtleAction(
                label: l10n.deleteProfileActionFor(_safeName(dog, l10n)),
                color: p.danger.withOpacity(0.75),
                onTap: () => _confirmDelete(context, ref, dog),
              ),
            _CardKind.archived => _SubtleAction(
                label: l10n.resumeWatchAction,
                color: p.accent,
                underline: false,
                onTap: () => _resume(context, ref, dog),
              ),
          },
        ],
      ),
    );
  }

  /// 記録なし/未設定の完全削除 — 必ず警告 (§5A,5B)
  void _confirmDelete(BuildContext context, WidgetRef ref, Dog dog) {
    final l10n = AppLocalizations.of(context)!;
    _showConfirmSheet(
      context,
      dogPhotoUrl: dog.photoUrl,
      title: l10n.deleteConfirmTitle(_safeName(dog, l10n)),
      body: l10n.deleteConfirmBody,
      confirmLabel: l10n.deleteConfirmAction,
      danger: true,
      onConfirm: () => ref.read(dogControllerProvider.notifier).delete(dog.id),
    );
  }

  /// 見守り終了 — データは残る (§6)
  void _confirmEndWatch(BuildContext context, WidgetRef ref, Dog dog) {
    final l10n = AppLocalizations.of(context)!;
    _showConfirmSheet(
      context,
      dogPhotoUrl: dog.photoUrl,
      title: l10n.endWatchConfirmTitle(dog.name),
      body: l10n.endWatchConfirmBody(dog.name),
      confirmLabel: l10n.endWatchConfirmAction,
      onConfirm: () =>
          ref.read(dogControllerProvider.notifier).endWatch(dog),
    );
  }

  /// 見守り再開 — 上限に空きがなければ設定へ誘導 (§7)
  void _resume(BuildContext context, WidgetRef ref, Dog dog) {
    final l10n = AppLocalizations.of(context)!;
    final watching = ref.read(watchingDogsProvider);
    final maxDogs = ref.read(maxDogsProvider).valueOrNull ?? 1;
    if (watching.length >= maxDogs) {
      _showLimitSheet(
        context,
        title: l10n.resumeLimitTitle,
        body: l10n.resumeLimitBody(dog.name),
      );
      return;
    }
    ref.read(dogControllerProvider.notifier).resume(dog);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.resumedToast(dog.name))));
  }
}

/// 控えめなテキスト操作(削除/見守り終了/再開)
class _SubtleAction extends StatelessWidget {
  const _SubtleAction({
    required this.label,
    required this.color,
    required this.onTap,
    this.underline = true,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            decoration:
                underline ? TextDecoration.underline : TextDecoration.none,
            decorationColor: color.withOpacity(0.4),
          ),
        ),
      ),
    );
  }
}

/// 汎用確認シート
void _showConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required VoidCallback onConfirm,
  String dogPhotoUrl = '',
  bool danger = false,
}) {
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
              child:
                  StatusRing(size: 80, color: p.accent, photoUrl: dogPhotoUrl),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(color: p.textPrimary)),
            const SizedBox(height: 10),
            Text(body,
                textAlign: TextAlign.center,
                style: AppText.caption
                    .copyWith(color: p.textSecondary, height: 1.7)),
            const SizedBox(height: 20),
            FilledButton(
              style: danger
                  ? FilledButton.styleFrom(backgroundColor: p.danger)
                  : null,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                onConfirm();
              },
              child: Text(confirmLabel),
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

/// 上限到達 — 理由と解決方法(設定へ)を示す (§11)
void _showLimitSheet(
  BuildContext context, {
  required String title,
  required String body,
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
            Text(title,
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(color: p.textPrimary)),
            const SizedBox(height: 10),
            Text(body,
                textAlign: TextAlign.center,
                style: AppText.caption
                    .copyWith(color: p.textSecondary, height: 1.7)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                context.go(Routes.settings);
              },
              child: Text(l10n.openSettings),
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
