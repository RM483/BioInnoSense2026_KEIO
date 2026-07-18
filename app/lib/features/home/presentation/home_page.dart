/// ホーム — 「見守りリング」(docs/16 案B / docs/21 v2.1)。
///
/// ホーム=測定の入口 + 見守り中の犬の左右スワイプ切替 (§2)。
/// リングのPageViewをスワイプすると selectedDogIdProvider が更新され、
/// 状態の言葉・7日のようす・履歴・記録・測定対象がその犬に切り替わる。
/// 主CTAは「◯◯の測定をはじめる」1つ(1段目)、副導線は2段目 (§1,3)。
/// 見守り中が0頭なら空状態 (§8)。初回は頭数の質問を1つだけ出す (§9)。
/// 数値はここには住まない(ppmの住所は履歴詳細)。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/h2.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_ring.dart';
import '../../../l10n/app_localizations.dart';
import '../../ble/application/ble_controller.dart';
import '../../dogs/application/dog_controller.dart';
import '../../dogs/domain/dog.dart';
import '../../insights/application/insights_providers.dart';
import '../../insights/domain/health_assessment.dart';
import '../../insights/presentation/assessment_style.dart';
import '../../measurement/domain/measurement.dart';
import '../../measurement/presentation/start_measure.dart';
import '../../records/presentation/care_note_sheet.dart';
import '../../settings/data/user_settings_repository.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  PageController? _pager;
  bool _askedHeadCount = false; // 初回質問は1度だけ (§9)

  @override
  void dispose() {
    _pager?.dispose();
    super.dispose();
  }

  void _maybeAskHeadCount(
      AsyncValue<int?> maxDogs, AppLocalizations l10n) {
    if (_askedHeadCount) return;
    // ストリームが「値なし(null)」を返した時だけ質問する(読込中は出さない)
    if (maxDogs is! AsyncData<int?> || maxDogs.value != null) return;
    _askedHeadCount = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showHeadCountSheet(context, ref, l10n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final watching = ref.watch(watchingDogsProvider);
    final dog = ref.watch(selectedDogProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();

    _maybeAskHeadCount(ref.watch(maxDogsProvider), l10n);

    // ---- 空状態: 見守り中の犬がいない (§8) ----
    if (dog == null) {
      return Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            children: [
              Text(
                '${_greeting(l10n)} · '
                '${DateFormat.MMMEd(locale).format(DateTime.now())}',
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: p.textTertiary),
              ),
              const SizedBox(height: 28),
              Center(
                child: StatusRing(size: 176, color: p.accent, photoUrl: ''),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.noWatchingDogs,
                textAlign: TextAlign.center,
                style:
                    AppText.title.copyWith(fontSize: 22, color: p.textPrimary),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.noWatchingDogsBody,
                textAlign: TextAlign.center,
                style: AppText.body
                    .copyWith(color: p.textSecondary, height: 1.6),
              ),
              const SizedBox(height: 32),
              _PressableCta(
                label: l10n.registerDog,
                onPressed: () => context.go(Routes.dogs),
              ),
            ],
          ),
        ),
      );
    }

    final found = watching.indexWhere((d) => d.id == dog.id);
    final index = found < 0 ? 0 : found;
    _pager ??= PageController(initialPage: index);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ---- 固定ヘッダー: 挨拶 + 日付 (犬に依存しない §2) ----
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                '${_greeting(l10n)} · '
                '${DateFormat.MMMEd(locale).format(DateTime.now())}',
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: p.textTertiary),
              ),
            ),

            // ---- 犬ごとの全面ページ: 指に追従してページ単位で切替 (§2) ----
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: watching.length,
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  ref.read(selectedDogIdProvider.notifier).state =
                      watching[i].id;
                },
                itemBuilder: (context, i) => _DogHomePage(
                  dog: watching[i],
                  pageIndex: i,
                  pageCount: watching.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _greeting(AppLocalizations l10n) {
    final h = DateTime.now().hour;
    if (h < 11) return l10n.goodMorning;
    if (h < 18) return l10n.goodAfternoon;
    return l10n.goodEvening;
  }
}

/// 犬1頭ぶんのホームページ (v2.2 §2)。
/// リング・名前・ページ位置・状態・7日のようす・CTA・副導線までが
/// ひとまとまりにスライドする。データはすべてこのページの犬のもの (§12)。
class _DogHomePage extends ConsumerWidget {
  const _DogHomePage({
    required this.dog,
    required this.pageIndex,
    required this.pageCount,
  });

  final Dog dog;
  final int pageIndex;
  final int pageCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final assessment =
        ref.watch(healthAssessmentOfProvider(dog.id)).valueOrNull ??
            HealthAssessment.fromHistory(const []);
    final recent =
        ref.watch(recentMeasurementsOfProvider(dog.id)).valueOrNull ??
            const <Measurement>[];
    final connected =
        ref.watch(bleControllerProvider).status == BleStatus.connected;
    final level = assessment.level;
    final trend = assessmentTrendLabel(assessment, l10n);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      children: [
        // ---- 見守りリング (主役。写真があれば表示 §6) ----
        Center(
          child: Semantics(
            button: true,
            label: '${dog.name} — ${level.phrase(l10n)}',
            hint: l10n.measureStartFor(dog.name),
            child: GestureDetector(
              onTap: () => startMeasureFlowFor(context, ref, dog),
              child: ExcludeSemantics(
                child: StatusRing(
                  size: 176,
                  color: level.color(p),
                  photoUrl: dog.photoUrl,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ---- どの犬か一目で分かる: 名前 + ドット + 1/N (§2) ----
        Text(
          dog.name,
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(
              color: p.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 14),
        ),
        if (pageCount > 1) ...[
          const SizedBox(height: 8),
          _DogPager(count: pageCount, index: pageIndex),
        ],
        const SizedBox(height: 6),

        // ---- 言葉: 状態 → 変化 → 行動 → 最終測定 ----
        Text(
          level.phrase(l10n),
          textAlign: TextAlign.center,
          style: AppText.title.copyWith(fontSize: 22, color: p.textPrimary),
        ),
        if (trend != null) ...[
          const SizedBox(height: 8),
          Text(
            trend,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(
                color: p.textSecondary, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          assessmentAction(assessment, l10n),
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(
              color: p.textPrimary,
              fontWeight: FontWeight.w500,
              height: 1.6),
        ),
        if (assessment.latest != null) ...[
          const SizedBox(height: 12),
          Text(
            '${l10n.lastMeasured} · '
            '${relativeTime(l10n, assessment.latest!.startedAt)}',
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: p.textTertiary),
          ),
        ],
        const SizedBox(height: 28),

        // ---- ここ7日のようす (この犬のデータのみ §12) ----
        if (recent.length >= 2) ...[
          Divider(color: p.hairline, height: 1),
          const SizedBox(height: 20),
          _TrendSection(recent: recent, l10n: l10n),
          const SizedBox(height: 24),
        ],

        // ---- 1段目: 大きな主CTA(名前入り §1,3) ----
        _PressableCta(
          label: l10n.measureStartFor(dog.name),
          onPressed: () => startMeasureFlowFor(context, ref, dog),
        ),
        if (!connected) ...[
          const SizedBox(height: 10),
          Text(
            l10n.connectFirstHint,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: p.textTertiary),
          ),
        ],
        const SizedBox(height: 18),

        // ---- 2段目: 静かな副導線 (§1) ----
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _QuietLink(
              icon: Icons.menu_book_outlined,
              label: l10n.viewHistory,
              onTap: () => context.go(Routes.history),
            ),
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 18),
              color: p.hairline,
            ),
            _QuietLink(
              icon: Icons.edit_note,
              label: l10n.addRecord,
              onTap: () => showCareNoteSheet(context, ref, dog.id),
            ),
          ],
        ),
      ],
    );
  }
}

/// 初回設定: 一緒に暮らしている犬の頭数 (§9)。回答は上限として保存。
void _showHeadCountSheet(
    BuildContext context, WidgetRef ref, AppLocalizations l10n) {
  final p = context.palette;
  var selected = 1;
  showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
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
              Text(l10n.headCountTitle,
                  textAlign: TextAlign.center,
                  style: AppText.title.copyWith(color: p.textPrimary)),
              const SizedBox(height: 8),
              Text(l10n.headCountBody,
                  textAlign: TextAlign.center,
                  style: AppText.caption
                      .copyWith(color: p.textSecondary, height: 1.6)),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final n in [1, 2, 3]) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => selected = n),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected == n
                                ? p.accentSoft
                                : p.cardElevated,
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                                color: selected == n
                                    ? p.accent
                                    : Colors.transparent,
                                width: 1.2),
                          ),
                          child: Text(
                            l10n.headCountN(n),
                            style: AppText.caption.copyWith(
                              color: selected == n
                                  ? p.accent
                                  : p.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (n != 3) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () {
                  ref
                      .read(userSettingsRepositoryProvider)
                      .setMaxDogs(selected);
                  Navigator.of(sheetContext).pop();
                },
                child: Text(l10n.begin),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 犬ページャ: ドット + 1/N (§2)。切替はページ全体のスワイプで行う。
class _DogPager extends StatelessWidget {
  const _DogPager({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == index ? 16 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i == index ? p.accent : p.hairline,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        const SizedBox(width: 10),
        Text(
          '${index + 1} / $count',
          style: AppText.caption.copyWith(
              color: p.textTertiary,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

/// ホーム下部の静かなテキスト導線(履歴・記録)。
class _QuietLink extends StatelessWidget {
  const _QuietLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: p.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: AppText.bodyMedium.copyWith(color: p.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// ここ7日のようす — 見出し+チップ、正常帯つき無数値ライン、言葉の要約。
class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.recent, required this.l10n});

  final List<Measurement> recent; // 新しい順
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = recent.take(7).toList().reversed.toList();
    final values = [for (final m in items) m.avgPpm];
    final level = HealthAssessment.levelForPpm(values.last);
    final summary =
        windowSummaryText(HealthAssessment.windowSummary(recent), l10n);

    return GestureDetector(
      onTap: () => GoRouter.of(context).go(Routes.history),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.recent7days,
                  style: AppText.bodyMedium.copyWith(
                      color: p.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
              StatusPill(
                label: level.shortLabel(l10n),
                color: level.color(p),
                softColor: level.softColor(p),
                dot: false,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // VoiceOverには要約文だけを読ませる(装飾は無音) — docs/17 A8
          Semantics(
            label: '${l10n.recent7days}。$summary',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 88,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TrendLinePainter(
                    values: values,
                    lineColor: p.textSecondary.withOpacity(0.65),
                    normalBand: p.success,
                    guideColor: p.danger,
                    pointFill: p.card,
                    lastColor: level.color(p),
                    normalLabel: l10n.normalRangeLabel,
                    guideLabel: l10n.consultGuideLabel,
                    labelStyle: AppText.caption.copyWith(fontSize: 10.5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            summary,
            style: AppText.caption
                .copyWith(color: p.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 押下で0.98に沈み、指を離すと戻る主CTA(触覚つき)。
class _PressableCta extends StatefulWidget {
  const _PressableCta({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_PressableCta> createState() => _PressableCtaState();
}

class _PressableCtaState extends State<_PressableCta> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onPressed();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // Dynamic Type拡大でも文字が切れない (docs/17 A9)
          constraints: const BoxConstraints(minHeight: 58),
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: BorderRadius.circular(29),
            boxShadow: [
              BoxShadow(
                color: p.accent.withOpacity(_pressed ? 0.15 : 0.28),
                blurRadius: _pressed ? 6 : 14,
                offset: Offset(0, _pressed ? 1 : 5),
              ),
            ],
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: AppText.bodyMedium.copyWith(
              // darkは明るいティール面のため黒文字(コントラスト確保) — docs/17 A21
              color: p.onAccent,
              fontWeight: FontWeight.w600,
              fontSize: 17,
            ),
          ),
        ),
      ),
    );
  }
}

/// 意味の読めるミニ折れ線 (docs/13の設計そのまま):
/// 0基準・正常帯のみ薄緑・受診目安は必要時のみ点線・最新点のみ状態色。
class _TrendLinePainter extends CustomPainter {
  _TrendLinePainter({
    required this.values,
    required this.lineColor,
    required this.normalBand,
    required this.guideColor,
    required this.pointFill,
    required this.lastColor,
    required this.normalLabel,
    required this.guideLabel,
    required this.labelStyle,
  });

  final List<double> values;
  final Color lineColor;
  final Color normalBand;
  final Color guideColor;
  final Color pointFill;
  final Color lastColor;
  final String normalLabel;
  final String guideLabel;
  final TextStyle labelStyle;

  static const _stable = HealthAssessment.stableMaxPpm; // 10
  static const _guide = H2.highPpm; // 20

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final dataMax = values.reduce((a, b) => a > b ? a : b);
    final maxY =
        [_stable * 1.35, dataMax * 1.2].reduce((a, b) => a > b ? a : b);
    const padTop = 8.0;
    const padBottom = 8.0;
    const padLeft = 6.0;
    const padRight = 64.0; // ラベル領域

    final plotRight = size.width - padRight;
    double yOf(double v) =>
        padTop + (1 - v / maxY) * (size.height - padTop - padBottom);
    Offset at(int i) => Offset(
          padLeft + i / (values.length - 1) * (plotRight - padLeft),
          yOf(values[i]),
        );

    final yStable = yOf(_stable);
    final yBottom = size.height - padBottom;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(padLeft, yStable, plotRight, yBottom),
        const Radius.circular(6),
      ),
      Paint()..color = normalBand.withOpacity(0.07),
    );
    canvas.drawLine(
      Offset(padLeft, yStable),
      Offset(plotRight, yStable),
      Paint()
        ..color = normalBand.withOpacity(0.25)
        ..strokeWidth = 1,
    );
    _label(canvas, normalLabel, normalBand,
        Offset(plotRight + 8, (yStable + yBottom) / 2));

    final showGuide = dataMax >= _stable * 1.2;
    if (showGuide) {
      final yG = yOf(_guide);
      if (yG > padTop) {
        final dash = Paint()
          ..color = guideColor.withOpacity(0.35)
          ..strokeWidth = 1;
        for (var x = padLeft; x < plotRight; x += 10) {
          canvas.drawLine(Offset(x, yG), Offset(x + 5, yG), dash);
        }
        _label(canvas, guideLabel, guideColor, Offset(plotRight + 8, yG));
      }
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = lineColor,
    );

    for (var i = 0; i < values.length - 1; i++) {
      canvas.drawCircle(at(i), 2.4, Paint()..color = pointFill);
      canvas.drawCircle(
        at(i),
        2.4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = lineColor,
      );
    }

    final last = at(values.length - 1);
    canvas.drawCircle(
        last, 8, Paint()..color = lastColor.withOpacity(0.18));
    canvas.drawCircle(last, 3.8, Paint()..color = lastColor);
    canvas.drawCircle(
      last,
      3.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = pointFill,
    );
  }

  void _label(Canvas canvas, String text, Color color, Offset leftCenter) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: labelStyle.copyWith(
              color: color, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, leftCenter - Offset(0, tp.height / 2));
  }

  @override
  bool shouldRepaint(_TrendLinePainter old) =>
      old.values != values || old.lastColor != lastColor;
}
