/// 健康日誌の入力シート — 3タップで記録できる軽さを最優先 (docs/21 §日誌)。
/// 種別チップ → (必要なら)3段階の様子 → 自由メモ → 保存。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../application/care_note_controller.dart';
import '../domain/care_note.dart';

String careNoteTypeLabel(CareNoteType t, AppLocalizations l10n) =>
    switch (t) {
      CareNoteType.walk => l10n.noteWalk,
      CareNoteType.appetite => l10n.noteAppetite,
      CareNoteType.poop => l10n.notePoop,
      CareNoteType.medicine => l10n.noteMedicine,
      CareNoteType.condition => l10n.noteCondition,
      CareNoteType.memo => l10n.noteMemo,
    };

IconData careNoteTypeIcon(CareNoteType t) => switch (t) {
      CareNoteType.walk => Icons.directions_walk,
      CareNoteType.appetite => Icons.restaurant,
      CareNoteType.poop => Icons.wc,
      CareNoteType.medicine => Icons.medication_outlined,
      CareNoteType.condition => Icons.favorite_border,
      CareNoteType.memo => Icons.edit_note,
    };

String careRatingLabel(CareRating r, AppLocalizations l10n) => switch (r) {
      CareRating.good => l10n.ratingGood,
      CareRating.normal => l10n.ratingNormal,
      CareRating.concern => l10n.ratingConcern,
    };

/// 日誌入力シートを開く。保存されたら true を返す。
Future<bool?> showCareNoteSheet(
    BuildContext context, WidgetRef ref, String dogId) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CareNoteSheet(dogId: dogId),
  );
}

class _CareNoteSheet extends ConsumerStatefulWidget {
  const _CareNoteSheet({required this.dogId});
  final String dogId;

  @override
  ConsumerState<_CareNoteSheet> createState() => _CareNoteSheetState();
}

class _CareNoteSheetState extends ConsumerState<_CareNoteSheet> {
  CareNoteType _type = CareNoteType.walk;
  CareRating _rating = CareRating.normal;
  final _memoCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(careNoteControllerProvider.notifier).add(CareNote(
            id: '',
            dogId: widget.dogId,
            at: DateTime.now(),
            type: _type,
            rating: _type.hasRating ? _rating : null,
            memo: _memoCtrl.text.trim(),
          ));
      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.recordSaved)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.errorNetwork)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + bottomInset),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 16),
            Text(l10n.addRecord,
                style: AppText.title.copyWith(color: p.textPrimary)),
            const SizedBox(height: 16),

            // ---- 種別チップ ----
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in CareNoteType.values)
                  _Chip(
                    icon: careNoteTypeIcon(t),
                    label: careNoteTypeLabel(t, l10n),
                    selected: _type == t,
                    onTap: () => setState(() => _type = t),
                  ),
              ],
            ),

            // ---- 3段階の様子(食欲・排便・体調のみ) ----
            if (_type.hasRating) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final r in CareRating.values) ...[
                    Expanded(
                      child: _Chip(
                        label: careRatingLabel(r, l10n),
                        selected: _rating == r,
                        center: true,
                        warn: r == CareRating.concern,
                        onTap: () => setState(() => _rating = r),
                      ),
                    ),
                    if (r != CareRating.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ],

            // ---- 自由メモ ----
            const SizedBox(height: 18),
            TextField(
              controller: _memoCtrl,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: l10n.memoHint),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: p.onAccent))
                  : Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.center = false,
    this.warn = false,
  });

  final IconData? icon;
  final String label;
  final bool selected;
  final bool center;
  final bool warn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final activeColor = warn ? p.warn : p.accent;
    final activeSoft = warn ? p.warnSoft : p.accentSoft;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? activeSoft : p.cardElevated,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color: selected ? activeColor : Colors.transparent,
              width: 1.2),
        ),
        child: Row(
          mainAxisSize: center ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment:
              center ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 16,
                  color: selected ? activeColor : p.textSecondary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppText.caption.copyWith(
                color: selected ? activeColor : p.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
