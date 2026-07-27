/// きょうの記録 — 複数カテゴリを1回で入力し、最後に1回だけ保存する
/// まとめ入力シート (docs/21 v2.3 §2-5)。
/// 当日の既存記録があれば編集として開く (§4,16)。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../application/care_note_controller.dart';
import '../data/care_note_repository.dart';
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

/// 選択肢の値 → 表示文言 (§3)
String choiceLabel(CareNoteType t, String choice, AppLocalizations l10n) =>
    switch ((t, choice)) {
      (CareNoteType.walk, 'none') => l10n.walkNone,
      (CareNoteType.walk, 'short') => l10n.walkShort,
      (CareNoteType.walk, 'usual') => l10n.usualChoice,
      (CareNoteType.walk, 'long') => l10n.walkLong,
      (CareNoteType.appetite, 'none') => l10n.appetiteNone,
      (CareNoteType.appetite, 'less') => l10n.lessChoice,
      (CareNoteType.appetite, 'normal') => l10n.ratingNormal,
      (CareNoteType.appetite, 'lots') => l10n.appetiteLots,
      (CareNoteType.poop, 'none') => l10n.noneChoice,
      (CareNoteType.poop, 'less') => l10n.lessChoice,
      (CareNoteType.poop, 'usual') => l10n.usualChoice,
      (CareNoteType.poop, 'more') => l10n.poopMore,
      (CareNoteType.medicine, 'none') => l10n.noneChoice,
      (CareNoteType.medicine, 'taken') => l10n.medicineTaken,
      (CareNoteType.condition, 'concern') => l10n.ratingConcern,
      (CareNoteType.condition, 'slight') => l10n.conditionSlight,
      (CareNoteType.condition, 'usual') => l10n.usualChoice,
      (CareNoteType.condition, 'energetic') => l10n.conditionEnergetic,
      _ => choice,
    };

/// 表示用: 記録内容の言葉。旧schema1のratingにも対応 (§19)
String noteValueLabel(CareNote n, AppLocalizations l10n) {
  final c = n.choice;
  if (c != null && c.isNotEmpty) return choiceLabel(n.type, c, l10n);
  return switch (n.rating) {
    CareRating.good => l10n.ratingGood,
    CareRating.normal => l10n.ratingNormal,
    CareRating.concern => l10n.ratingConcern,
    null => '',
  };
}

/// きょうの記録シートを開く。保存されたら true を返す。
Future<bool?> showCareNoteSheet(
    BuildContext context, WidgetRef ref, String dogId) async {
  // 当日の既存記録(カテゴリ別最新)をリポジトリから直接読み、
  // どの画面から開いても同じ編集状態にする (§4,16)
  final notes = await ref
      .read(careNoteRepositoryProvider)
      .watchNotes(dogId, limit: 100)
      .first;
  final existing = notesOfDay(notes, DateTime.now());
  if (!context.mounted) return false;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CareNoteSheet(dogId: dogId, existing: existing),
  );
}

class _Draft {
  String? choice;
  String memo = '';
  bool get hasContent =>
      choice != null || memo.trim().isNotEmpty;
}

class _CareNoteSheet extends ConsumerStatefulWidget {
  const _CareNoteSheet({required this.dogId, required this.existing});
  final String dogId;
  final Map<CareNoteType, CareNote> existing;

  @override
  ConsumerState<_CareNoteSheet> createState() => _CareNoteSheetState();
}

class _CareNoteSheetState extends ConsumerState<_CareNoteSheet> {
  CareNoteType _active = CareNoteType.walk;
  final _drafts = <CareNoteType, _Draft>{};
  final _memoCtrl = TextEditingController();
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final t in CareNoteType.values) {
      final d = _Draft();
      final n = widget.existing[t];
      if (n != null) {
        d.choice = n.choice;
        d.memo = n.memo;
      }
      _drafts[t] = d;
    }
    _memoCtrl.text = _drafts[_active]!.memo;
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  /// カテゴリ切替 — それまでの入力は保持する (§2)
  void _switchTo(CareNoteType t) {
    setState(() {
      _drafts[_active]!.memo = _memoCtrl.text;
      _active = t;
      _memoCtrl.text = _drafts[t]!.memo;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    _drafts[_active]!.memo = _memoCtrl.text;
    final entries = [
      for (final t in CareNoteType.values)
        if (_drafts[t]!.hasContent)
          DayEntryInput(
            type: t,
            choice: _drafts[t]!.choice,
            memo: _drafts[t]!.memo.trim(),
          ),
    ];
    try {
      await ref
          .read(careNoteControllerProvider.notifier)
          .saveDay(widget.dogId, entries);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.dayRecordSaved)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.errorNetwork)));
    }
  }

  /// 未保存の変更がある時だけ確認して閉じる (§5)
  Future<bool> _confirmClose() async {
    if (!_dirty) return true;
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(l10n.discardConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.discardAction),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final draft = _drafts[_active]!;
    final choices = noteChoices[_active]!;

    bool hasContent(CareNoteType t) {
      if (t == _active) {
        return draft.choice != null || _memoCtrl.text.trim().isNotEmpty;
      }
      return _drafts[t]!.hasContent;
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmClose() && mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: Container(
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

              // ---- カテゴリ: 未入力 / 入力済み(点) / 選択中 (§5) ----
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in CareNoteType.values)
                    _Chip(
                      label: careNoteTypeLabel(t, l10n),
                      selected: _active == t,
                      filledDot: hasContent(t) && _active != t,
                      onTap: () => _switchTo(t),
                    ),
                ],
              ),

              // ---- 選択中カテゴリの選択肢 (§3) ----
              if (choices.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in choices)
                      _Chip(
                        label: choiceLabel(_active, c, l10n),
                        selected: draft.choice == c,
                        onTap: () => setState(() {
                          _dirty = true;
                          draft.choice = c;
                        }),
                      ),
                  ],
                ),
              ],

              // ---- 任意メモ (memoカテゴリは本文) ----
              const SizedBox(height: 18),
              TextField(
                controller: _memoCtrl,
                maxLines: 3,
                minLines: 1,
                onChanged: (_) => _dirty = true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: _active == CareNoteType.memo
                      ? l10n.memoHint
                      : l10n.supplementMemoHint,
                ),
              ),
              const SizedBox(height: 18),

              // ---- まとめて1回で保存 (§2) ----
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: p.onAccent))
                    : Text(l10n.saveDayRecord),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.filledDot = false,
  });

  final String label;
  final bool selected;
  final bool filledDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? p.accentSoft : p.cardElevated,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color: selected ? p.accent : Colors.transparent, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppText.caption.copyWith(
                color: selected ? p.accent : p.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (filledDot) ...[
              const SizedBox(width: 6),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                    color: p.accent, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
