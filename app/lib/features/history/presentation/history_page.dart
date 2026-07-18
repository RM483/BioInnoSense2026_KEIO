/// 日誌 — 測定と毎日の記録(散歩・食欲・排便・薬・体調・メモ)をひとつの
/// タイムラインで振り返る (docs/21 §履歴/日誌)。
///
/// 普段は「今日・きのう・おととい…」の日誌形式。カレンダーは主役にせず、
/// 右上のアイコンで必要な時だけ月表示へ切り替える。
/// 数値の詳細はタップした先(詳細画面)に置く。
import 'package:fl_chart/fl_chart.dart';
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
        .fetchHistory(dog.id, limit: 20);
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
          limit: 20);
      _hasMore = more.isNotEmpty;
      state = AsyncData([...current, ...more]);
    } finally {
      _loadingMore = false;
    }
  }
}

/// タイムラインの1件(測定 or 日誌)。
class _Entry {
  const _Entry.measurement(Measurement this.measurement)
      : note = null;
  const _Entry.note(CareNote this.note) : measurement = null;

  final Measurement? measurement;
  final CareNote? note;

  DateTime get at => measurement?.startedAt ?? note!.at;
}

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  bool _calendarMode = false;

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
            final entries = <_Entry>[
              for (final m in items) _Entry.measurement(m),
              for (final n in notes) _Entry.note(n),
            ]..sort((a, b) => b.at.compareTo(a.at));

            if (entries.isEmpty) {
              return _EmptyState(l10n: l10n, p: p, ref: ref);
            }
            return _calendarMode
                ? _CalendarView(entries: entries)
                : _JournalList(items: items, entries: entries);
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
    // 空状態も行き止まりにしない (docs/17 §9, A11)
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

// ─────────────────────────── 日誌(リスト) ───────────────────────────

class _JournalList extends ConsumerWidget {
  const _JournalList({required this.items, required this.entries});

  final List<Measurement> items; // 測定のみ(推移カード用)
  final List<_Entry> entries; // 測定+日誌(新しい順)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return NotificationListener<ScrollEndNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 200) {
          ref.read(historyProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          if (items.length >= 2) ...[
            _TrendChartCard(items: items, l10n: l10n),
            const SizedBox(height: 20),
          ],
          ..._journal(context, ref, entries, l10n),
        ],
      ),
    );
  }
}

/// 日誌: 日付見出し + その日の記録行(測定・日誌が時刻順に混ざる)。
List<Widget> _journal(BuildContext context, WidgetRef ref,
    List<_Entry> entries, AppLocalizations l10n) {
  final p = context.palette;
  final out = <Widget>[];
  DateTime? lastDay;
  for (final e in entries) {
    final day = DateTime(e.at.year, e.at.month, e.at.day);
    if (day != lastDay) {
      out.add(Padding(
        padding: EdgeInsets.only(top: lastDay == null ? 0 : 14, bottom: 10),
        child: Text(
          _dayLabel(context, e.at, l10n),
          style: AppText.caption
              .copyWith(color: p.textTertiary, fontWeight: FontWeight.w600),
        ),
      ));
      lastDay = day;
    }
    out.add(e.measurement != null
        ? _HistoryRow(measurement: e.measurement!)
        : _NoteRow(note: e.note!));
    out.add(const SizedBox(height: 10));
  }
  return out;
}

String _dayLabel(BuildContext context, DateTime d, AppLocalizations l10n) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return l10n.today;
  if (day == today.subtract(const Duration(days: 1))) return l10n.yesterday;
  if (day == today.subtract(const Duration(days: 2))) {
    return l10n.dayBeforeYesterday;
  }
  return DateFormat.MMMEd(locale).format(d);
}

// ─────────────────────────── カレンダー表示 ───────────────────────────

/// 必要な時だけ使う月表示。記録のある日に点を打ち、
/// タップでその日の記録を下に表示する。
class _CalendarView extends ConsumerStatefulWidget {
  const _CalendarView({required this.entries});
  final List<_Entry> entries;

  @override
  ConsumerState<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<_CalendarView> {
  late DateTime _month; // 表示中の月(1日固定)
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final locale = Localizations.localeOf(context).toLanguageTag();

    // 日付 → 記録の索引
    final byDay = <DateTime, List<_Entry>>{};
    for (final e in widget.entries) {
      final d = DateTime(e.at.year, e.at.month, e.at.day);
      byDay.putIfAbsent(d, () => []).add(e);
    }
    final dayEntries = byDay[_selected] ?? const <_Entry>[];

    final firstWeekday = _month.weekday % 7; // 日曜=0
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final today = DateTime.now();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        // ---- 月ヘッダ ----
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat.yMMMM(locale).format(_month),
                style: AppText.title.copyWith(color: p.textPrimary),
              ),
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

        // ---- 曜日 + 日グリッド ----
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final w in _weekdayLabels(locale))
              Center(
                  child: Text(w,
                      style: AppText.caption
                          .copyWith(color: p.textTertiary, fontSize: 11))),
            for (var i = 0; i < firstWeekday; i++) const SizedBox(),
            for (var d = 1; d <= daysInMonth; d++)
              _DayCell(
                day: DateTime(_month.year, _month.month, d),
                selected: _selected ==
                    DateTime(_month.year, _month.month, d),
                isToday: today.year == _month.year &&
                    today.month == _month.month &&
                    today.day == d,
                entries: byDay[DateTime(_month.year, _month.month, d)] ??
                    const [],
                onTap: () => setState(() =>
                    _selected = DateTime(_month.year, _month.month, d)),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Divider(color: p.hairline, height: 1),
        const SizedBox(height: 16),

        // ---- 選択日の記録 ----
        Text(
          _dayLabel(context, _selected, l10n),
          style: AppText.caption
              .copyWith(color: p.textTertiary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        if (dayEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(l10n.noEntriesDay,
                style: AppText.body.copyWith(color: p.textTertiary)),
          )
        else
          for (final e in dayEntries) ...[
            e.measurement != null
                ? _HistoryRow(measurement: e.measurement!)
                : _NoteRow(note: e.note!),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  static List<String> _weekdayLabels(String locale) {
    final symbols = DateFormat.E(locale);
    // 日曜はじまり (2023-01-01は日曜)
    return [
      for (var i = 0; i < 7; i++)
        symbols.format(DateTime(2023, 1, 1 + i)),
    ];
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.entries,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final List<_Entry> entries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // その日の測定の最悪レベル色を点に使う(日誌のみの日はアクセント)
    Color? dot;
    for (final e in entries) {
      if (e.measurement != null) {
        final c =
            HealthAssessment.levelForPpm(e.measurement!.avgPpm).color(p);
        dot = c;
      }
    }
    dot ??= entries.isNotEmpty ? p.accent.withOpacity(0.6) : null;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? p.accentSoft : null,
          shape: BoxShape.circle,
          border: isToday && !selected
              ? Border.all(color: p.hairline, width: 1.2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: AppText.caption.copyWith(
                color: selected ? p.accent : p.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: dot ?? Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── 行ウィジェット ───────────────────────────

/// 直近の平均値の推移(数値ラベルは最小限)。
class _TrendChartCard extends StatelessWidget {
  const _TrendChartCard({required this.items, required this.l10n});

  final List<Measurement> items; // 新しい順
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final series = items.take(14).toList().reversed.toList();
    final spots = [
      for (var i = 0; i < series.length; i++)
        FlSpot(i.toDouble(), series[i].avgPpm),
    ];
    final maxY = [
      HealthAssessment.stableMaxPpm * 1.4,
      ...series.map((m) => m.avgPpm * 1.15),
    ].reduce((a, b) => a > b ? a : b);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.recentTrend.toUpperCase(),
              style: AppText.overline.copyWith(color: p.textTertiary)),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 2,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: p.hairline, strokeWidth: 1),
                ),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    barWidth: 2,
                    color: p.accent,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) =>
                          spot.x == spots.last.x, // 最新点のみ
                      getDotPainter: (_, __, ___, ____) =>
                          FlDotCirclePainter(
                        radius: 3,
                        color: p.accent,
                        strokeWidth: 2,
                        strokeColor: p.card,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: p.accent.withOpacity(0.06),
                    ),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 400),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.measurement});
  final Measurement measurement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final m = measurement;
    final level = HealthAssessment.levelForPpm(m.avgPpm);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      onTap: () => context.go(Routes.historyDetail, extra: m),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: level.color(p), shape: BoxShape.circle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(level.shortLabel(l10n),
                    style: AppText.bodyMedium
                        .copyWith(color: p.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  DateFormat.Hm(locale).format(m.startedAt),
                  style: AppText.caption.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
          Text('${m.avgPpm.toStringAsFixed(1)} ${l10n.ppm}',
              style: AppText.caption.copyWith(color: p.textTertiary)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 16, color: p.textTertiary),
        ],
      ),
    );
  }
}

/// 健康日誌の1行。タップで詳細(削除つき)シート。
class _NoteRow extends ConsumerWidget {
  const _NoteRow({required this.note});
  final CareNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final rating = note.rating;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      onTap: () => _showDetail(context, ref, l10n),
      child: Row(
        children: [
          Icon(careNoteTypeIcon(note.type),
              size: 18,
              color: rating == CareRating.concern
                  ? p.warn
                  : p.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rating == null
                      ? careNoteTypeLabel(note.type, l10n)
                      : '${careNoteTypeLabel(note.type, l10n)} · '
                          '${careRatingLabel(rating, l10n)}',
                  style: AppText.bodyMedium.copyWith(
                      color: rating == CareRating.concern
                          ? p.warn
                          : p.textPrimary),
                ),
                if (note.memo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(note.memo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption
                          .copyWith(color: p.textSecondary)),
                ],
              ],
            ),
          ),
          Text(DateFormat.Hm(locale).format(note.at),
              style: AppText.caption.copyWith(color: p.textTertiary)),
        ],
      ),
    );
  }

  void _showDetail(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    final p = context.palette;
    final locale = Localizations.localeOf(context).toLanguageTag();
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(careNoteTypeIcon(note.type),
                      size: 20, color: p.textSecondary),
                  const SizedBox(width: 10),
                  Text(
                    note.rating == null
                        ? careNoteTypeLabel(note.type, l10n)
                        : '${careNoteTypeLabel(note.type, l10n)} · '
                            '${careRatingLabel(note.rating!, l10n)}',
                    style: AppText.title.copyWith(color: p.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                DateFormat.yMMMEd(locale).add_Hm().format(note.at),
                style: AppText.caption.copyWith(color: p.textTertiary),
              ),
              if (note.memo.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(note.memo,
                    style: AppText.body
                        .copyWith(color: p.textPrimary, height: 1.6)),
              ],
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  ref
                      .read(careNoteControllerProvider.notifier)
                      .delete(note.dogId, note.id);
                  Navigator.of(sheetContext).pop();
                },
                child: Text(l10n.deleteRecord,
                    style: AppText.bodyMedium.copyWith(color: p.danger)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
