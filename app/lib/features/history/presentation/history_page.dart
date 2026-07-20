/// 日誌 — 日付ごとの1枚カード (docs/21 v2.3 §6-18)。
///
/// - 記録が存在する最新3日分の日付カード。測定を上部で主表示 (§6-8)
/// - 同日の複数測定は同じカードにまとめ、注意結果を状態表示で優先 (§9,10)
/// - 健康日誌はラベル+値でまとめて表示。未入力項目は出さない (§13)
/// - 削除は「…」メニューへ。健康日誌を削除しても測定は残す (§15,20)
/// Web版 journal.tsx のミラー。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../dogs/application/dog_controller.dart';
import '../../insights/domain/health_assessment.dart';
import '../../insights/presentation/assessment_style.dart';
import '../../measurement/data/measurement_repository.dart';
import '../../measurement/domain/measurement.dart';
import '../../measurement/presentation/start_measure.dart';
import '../../records/application/care_note_controller.dart';
import '../../records/domain/care_note.dart';
import '../../records/presentation/care_note_sheet.dart';

final historyProvider =
    AsyncNotifierProvider<HistoryNotifier, List<Measurement>>(
        HistoryNotifier.new);

class HistoryNotifier extends AsyncNotifier<List<Measurement>> {
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  Future<List<Measurement>> build() async {
    final dog = ref.watch(selectedDogProvider);
    if (dog == null) return [];
    _hasMore = true;
    _loadingMore = false;
    return ref
        .read(measurementRepositoryProvider)
        .fetchHistory(dog.id, limit: 30);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull ?? [];
    final dog = ref.read(selectedDogProvider);
    if (dog == null || current.isEmpty || !_hasMore || _loadingMore) return;
    _loadingMore = true;
    try {
      final more = await ref.read(measurementRepositoryProvider).fetchHistory(
          dog.id,
          before: current.last.startedAt,
          limit: 30);
      _hasMore = more.isNotEmpty;
      state = AsyncData([...current, ...more]);
    } finally {
      _loadingMore = false;
    }
  }
}

/* ─────────────── 状態語と優先ルール (§10,11) ─────────────── */

enum DayStatus { stable, slight, elevated, unknown }

String dayStatusWord(DayStatus s, AppLocalizations l10n) => switch (s) {
      DayStatus.stable => l10n.dayStatusStable,
      DayStatus.slight => l10n.dayStatusSlight,
      DayStatus.elevated => l10n.dayStatusElevated,
      DayStatus.unknown => l10n.dayStatusUnknown,
    };

Color dayStatusColor(DayStatus s, AppPalette p) => switch (s) {
      DayStatus.stable => p.success,
      // 注意でも赤一色で強調しない (§11)
      DayStatus.slight || DayStatus.elevated => p.warn,
      DayStatus.unknown => p.textTertiary,
    };

const _qualityMin = 60;

bool _reliable(Measurement m) => !m.hasQuality || m.quality >= _qualityMin;

/// その日の状態: 安定していない結果が1件でもあれば優先 (§10)。
DayStatus? dayStatusOf(List<Measurement> ms) {
  if (ms.isEmpty) return null;
  final reliable = ms.where(_reliable).toList();
  if (reliable.isEmpty) return DayStatus.unknown;
  final levels =
      reliable.map((m) => HealthAssessment.levelForPpm(m.avgPpm)).toSet();
  if (levels.contains(HealthLevel.elevated)) return DayStatus.elevated;
  if (levels.contains(HealthLevel.slightlyElevated)) return DayStatus.slight;
  return DayStatus.stable;
}

/* ─────────────── 日付グループ ─────────────── */

class DayData {
  DayData(this.day);
  final DateTime day;
  final measurements = <Measurement>[]; // 新しい順
  final notes = <CareNoteType, CareNote>{}; // カテゴリ別最新 (§4)
}

List<DayData> buildDays(List<Measurement> history, List<CareNote> notes) {
  final map = <DateTime, DayData>{};
  DayData of(DateTime at) =>
      map.putIfAbsent(dayOf(at), () => DayData(dayOf(at)));
  for (final m in history) {
    of(m.startedAt).measurements.add(m);
  }
  for (final n in notes) {
    of(n.at).notes.putIfAbsent(n.type, () => n); // 最新を採用 (§19)
  }
  final days = map.values.toList()
    ..sort((a, b) => b.day.compareTo(a.day));
  for (final d in days) {
    d.measurements.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }
  return days;
}

/* ─────────────── 画面 ─────────────── */

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  bool _calendarMode = false;
  int _visibleDays = 3; // 最新3日分 (§6)

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final dog = ref.watch(selectedDogProvider);
    final history = ref.watch(historyProvider);
    final notes = dog == null
        ? const <CareNote>[]
        : ref.watch(careNotesProvider(dog.id)).valueOrNull ??
            const <CareNote>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.journalTitle),
        actions: [
          IconButton(
            tooltip:
                _calendarMode ? l10n.listViewLabel : l10n.calendarViewLabel,
            icon: Icon(_calendarMode
                ? Icons.view_agenda_outlined
                : Icons.calendar_month_outlined),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _calendarMode = !_calendarMode);
            },
          ),
          IconButton(
            tooltip: l10n.addRecord,
            icon: const Icon(Icons.add),
            onPressed: dog == null
                ? null
                : () => showCareNoteSheet(context, ref, dog.id),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: history.when(
          loading: () => Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2, color: p.textTertiary),
            ),
          ),
          error: (e, _) => Center(
            child: Text(l10n.errorNetwork,
                style: AppText.body.copyWith(color: p.textSecondary)),
          ),
          data: (items) {
            final days = buildDays(items, notes);
            if (days.isEmpty) {
              return _EmptyState(l10n: l10n, p: p, ref: ref);
            }
            return _calendarMode
                ? _CalendarView(days: days, dogId: dog?.id ?? '')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    children: [
                      for (final day
                          in days.take(_visibleDays)) ...[
                        DayCard(day: day, dogId: dog?.id ?? ''),
                        const SizedBox(height: 14),
                      ],
                      // ---- 過去の記録 (§17) ----
                      if (days.length > _visibleDays)
                        TextButton(
                          onPressed: () {
                            setState(() => _visibleDays += 7);
                            ref
                                .read(historyProvider.notifier)
                                .loadMore();
                          },
                          child: Text(l10n.pastRecords,
                              style: AppText.bodyMedium
                                  .copyWith(color: p.accent)),
                        ),
                    ],
                  );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n, required this.p, required this.ref});
  final AppLocalizations l10n;
  final AppPalette p;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pets, size: 30, color: p.textTertiary),
          const SizedBox(height: 12),
          Text(l10n.noMeasurementYet,
              style: AppText.body.copyWith(color: p.textSecondary)),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => startMeasureFlow(context, ref),
            child: Text(l10n.startMeasurement,
                style: AppText.bodyMedium.copyWith(color: p.accent)),
          ),
        ],
      ),
    );
  }
}

/* ─────────────── 日付カード (§7) ─────────────── */

class DayCard extends ConsumerStatefulWidget {
  const DayCard({super.key, required this.day, required this.dogId});
  final DayData day;
  final String dogId;

  @override
  ConsumerState<DayCard> createState() => _DayCardState();
}

class _DayCardState extends ConsumerState<DayCard> {
  bool _showAll = false;
  bool _memoOpen = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final day = widget.day;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final isToday = sameDay(day.day, DateTime.now());

    final status = dayStatusOf(day.measurements);
    final latest =
        day.measurements.isEmpty ? null : day.measurements.first;
    final latestLevel = latest == null
        ? null
        : _reliable(latest)
            ? HealthAssessment.levelForPpm(latest.avgPpm)
            : null;
    // 状態表示は注意結果を優先。最新と判定が違う時は短い補足 (§10)
    final mismatch = status != null &&
        latest != null &&
        ((status == DayStatus.elevated &&
                latestLevel != HealthLevel.elevated) ||
            (status == DayStatus.slight &&
                latestLevel == HealthLevel.stable));

    final memoNote = day.notes[CareNoteType.memo];
    final journalTypes = CareNoteType.values
        .where((t) => t != CareNoteType.memo && day.notes.containsKey(t))
        .toList();
    final hasJournal = journalTypes.isNotEmpty ||
        (memoNote != null && memoNote.memo.isNotEmpty);
    final memoText = memoNote?.memo ?? '';
    final memoLong = memoText.length > 100;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- 1. その日の状態 (§10,11) ----
          Row(
            children: [
              Text(_dayLabel(context, day.day, l10n),
                  style: AppText.bodyMedium.copyWith(
                      color: p.textPrimary, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (status != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: dayStatusColor(status, p),
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(dayStatusWord(status, l10n),
                    style: AppText.caption.copyWith(
                        color: dayStatusColor(status, p),
                        fontWeight: FontWeight.w600)),
              ],
              // ---- 控えめな操作メニュー (§15,16) ----
              if (isToday || hasJournal)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz,
                      size: 20, color: p.textTertiary),
                  color: p.card,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  onSelected: (v) {
                    if (v == 'edit') {
                      showCareNoteSheet(context, ref, widget.dogId);
                    } else if (v == 'delete') {
                      _confirmDeleteJournal(context, l10n, p);
                    }
                  },
                  itemBuilder: (_) => [
                    if (isToday)
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(l10n.editTodayRecord,
                            style: AppText.body
                                .copyWith(color: p.textPrimary)),
                      ),
                    if (hasJournal)
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l10n.deleteJournalMenu,
                            style:
                                AppText.body.copyWith(color: p.danger)),
                      ),
                  ],
                )
              else
                const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 10),

          // ---- 2. 測定結果(主表示 §8,9,18) ----
          if (latest != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: p.cardElevated,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(l10n.latestMeasurementLabel,
                          style: AppText.caption.copyWith(
                              color: p.textTertiary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Text(latest.avgPpm.toStringAsFixed(1),
                          style: AppText.numeral.copyWith(
                              fontSize: 24, color: p.textPrimary)),
                      Text(' ${l10n.ppm}',
                          style: AppText.caption
                              .copyWith(color: p.textSecondary)),
                      const SizedBox(width: 10),
                      Text(DateFormat.Hm(locale).format(latest.startedAt),
                          style: AppText.caption
                              .copyWith(color: p.textTertiary)),
                    ],
                  ),
                  if (mismatch) ...[
                    const SizedBox(height: 6),
                    Text(l10n.dayMismatchNote,
                        style: AppText.caption
                            .copyWith(color: p.warn, height: 1.5)),
                  ],
                  if (day.measurements.length >= 2) ...[
                    const SizedBox(height: 8),
                    Text(
                        l10n.dayMeasureCount(day.measurements.length),
                        style: AppText.caption.copyWith(
                            color: p.textTertiary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    for (final m in (day.measurements.length <= 2 ||
                            _showAll
                        ? day.measurements
                        : day.measurements.take(1)))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Text(
                                DateFormat.Hm(locale)
                                    .format(m.startedAt),
                                style: AppText.caption.copyWith(
                                    color: p.textTertiary)),
                            const SizedBox(width: 12),
                            Text(
                                '${m.avgPpm.toStringAsFixed(1)} ${l10n.ppm}',
                                style: AppText.caption.copyWith(
                                    color: p.textPrimary,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 12),
                            Text(
                              _reliable(m)
                                  ? HealthAssessment.levelForPpm(m.avgPpm)
                                      .shortLabel(l10n)
                                  : l10n.unreliableShort,
                              style: AppText.caption.copyWith(
                                  color: _reliable(m)
                                      ? HealthAssessment.levelForPpm(
                                              m.avgPpm)
                                          .color(p)
                                      : p.textTertiary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    if (day.measurements.length > 2)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _showAll = !_showAll),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                              _showAll ? l10n.closeLabel : l10n.showAll,
                              style: AppText.caption.copyWith(
                                  color: p.textSecondary,
                                  decoration: TextDecoration.underline,
                                  decorationColor: p.hairline)),
                        ),
                      ),
                  ],
                ],
              ),
            )
          else
            // 測定がない日は控えめに (§18)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(l10n.noMeasureThisDay,
                  style:
                      AppText.caption.copyWith(color: p.textTertiary)),
            ),

          // ---- 3. 健康日誌 (§13) ----
          if (journalTypes.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final t in journalTypes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(careNoteTypeLabel(t, l10n),
                          style: AppText.caption.copyWith(
                              color: p.textTertiary,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            noteValueLabel(day.notes[t]!, l10n),
                            style: AppText.bodyMedium.copyWith(
                                fontSize: 14.5,
                                color: day.notes[t]!.isConcern
                                    ? p.warn
                                    : p.textPrimary),
                          ),
                          if (day.notes[t]!.memo.isNotEmpty)
                            Text(day.notes[t]!.memo,
                                style: AppText.caption.copyWith(
                                    color: p.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],

          // ---- 4. 自由メモ (§14) ----
          if (memoText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Divider(color: p.hairline, height: 16),
            Text(l10n.noteMemo,
                style: AppText.caption.copyWith(
                    color: p.textTertiary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                memoText,
                maxLines: memoLong && !_memoOpen ? 3 : null,
                overflow: memoLong && !_memoOpen
                    ? TextOverflow.ellipsis
                    : null,
                style: AppText.body
                    .copyWith(color: p.textPrimary, height: 1.6),
              ),
            ),
            if (memoLong)
              GestureDetector(
                onTap: () => setState(() => _memoOpen = !_memoOpen),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_memoOpen ? l10n.closeLabel : l10n.readMore,
                      style: AppText.caption.copyWith(
                          color: p.textSecondary,
                          decoration: TextDecoration.underline,
                          decorationColor: p.hairline)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 健康日誌のみ削除。測定結果は残す (§15,20)
  void _confirmDeleteJournal(
      BuildContext context, AppLocalizations l10n, AppPalette p) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(l10n.deleteJournalConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref
                  .read(careNoteControllerProvider.notifier)
                  .deleteDay(widget.dogId, widget.day.day);
            },
            child: Text(l10n.deleteConfirmAction,
                style: TextStyle(color: p.danger)),
          ),
        ],
      ),
    );
  }
}

/* ─────────────── カレンダー表示 (必要な時だけ §17) ─────────────── */

class _CalendarView extends ConsumerStatefulWidget {
  const _CalendarView({required this.days, required this.dogId});
  final List<DayData> days;
  final String dogId;

  @override
  ConsumerState<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<_CalendarView> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = dayOf(now);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final byDay = {for (final d in widget.days) d.day: d};
    final selectedData = byDay[_selected];

    final firstWeekday = _month.weekday % 7; // 日曜=0
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final today = dayOf(DateTime.now());

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(DateFormat.yMMMM(locale).format(_month),
                  style: AppText.title.copyWith(color: p.textPrimary)),
            ),
            IconButton(
              icon: Icon(Icons.chevron_left, color: p.textSecondary),
              onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1)),
            ),
            IconButton(
              icon: Icon(Icons.chevron_right, color: p.textSecondary),
              onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < 7; i++)
              Center(
                child: Text(
                    DateFormat.E(locale).format(DateTime(2023, 1, 1 + i)),
                    style: AppText.caption
                        .copyWith(color: p.textTertiary, fontSize: 11)),
              ),
            for (var i = 0; i < firstWeekday; i++) const SizedBox(),
            for (var d = 1; d <= daysInMonth; d++)
              _dayCell(DateTime(_month.year, _month.month, d), byDay,
                  today, p),
          ],
        ),
        const SizedBox(height: 20),
        Divider(color: p.hairline, height: 1),
        const SizedBox(height: 16),
        if (selectedData != null)
          DayCard(day: selectedData, dogId: widget.dogId)
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(l10n.noEntriesDay,
                style: AppText.body.copyWith(color: p.textTertiary)),
          ),
      ],
    );
  }

  Widget _dayCell(DateTime d, Map<DateTime, DayData> byDay,
      DateTime today, AppPalette p) {
    final data = byDay[d];
    final selected = d == _selected;
    Color? dot;
    if (data != null) {
      final s = dayStatusOf(data.measurements);
      dot = s != null
          ? dayStatusColor(s, p)
          : p.accent.withOpacity(0.6);
    }
    return GestureDetector(
      onTap: () => setState(() => _selected = d),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? p.accentSoft : null,
          shape: BoxShape.circle,
          border: d == today && !selected
              ? Border.all(color: p.hairline, width: 1.2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${d.day}',
                style: AppText.caption.copyWith(
                  color: selected ? p.accent : p.textPrimary,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                )),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                  color: dot ?? Colors.transparent,
                  shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}

/* ─────────────── 日付ラベル ─────────────── */

String _dayLabel(BuildContext context, DateTime d, AppLocalizations l10n) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final today = dayOf(DateTime.now());
  final diff = today.difference(dayOf(d)).inDays;
  if (diff == 0) return l10n.today;
  if (diff == 1) return l10n.yesterday;
  if (diff == 2) return l10n.dayBeforeYesterday;
  return DateFormat.MMMEd(locale).format(d);
}
