/// ホーム — 「見守りリング」(docs/16 案B)。
///
/// 犬のアバターを状態色のリングが囲み、その下に
/// 状態の一文 → 前回からの変化 → 取るべき行動 → 最終測定 の順で言葉が続く。
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
import '../../dogs/application/dog_controller.dart';
import '../../insights/application/insights_providers.dart';
import '../../insights/domain/health_assessment.dart';
import '../../insights/presentation/assessment_style.dart';
import '../../measurement/domain/measurement.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final dog = ref.watch(selectedDogProvider);
    final assessment = ref.watch(healthAssessmentProvider).valueOrNull ??
        HealthAssessment.fromHistory(const []);
    final recent =
        ref.watch(recentMeasurementsProvider).valueOrNull ?? const [];
    final locale = Localizations.localeOf(context).toLanguageTag();
    final level = assessment.level;
    final trend = assessmentTrendLabel(assessment, l10n);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            // ---- 挨拶 + 日付 (話しかける入口) ----
            Text(
              '${_greeting(l10n)} · '
              '${DateFormat.MMMEd(locale).format(DateTime.now())}',
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: p.textTertiary),
            ),
            const SizedBox(height: 28),

            // ---- 見守りリング (主役) ----
            Center(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.go(Routes.measure);
                },
                child: StatusRing(
                  size: 176,
                  color: dog == null ? p.accent : level.color(p),
                  photoUrl: dog?.photoUrl ?? '',
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ---- 言葉: 状態 → 変化 → 行動 → 最終測定 ----
            if (dog == null) ...[
              Text(
                l10n.registerDog,
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(
                    fontSize: 22, color: p.textPrimary),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.addDogPrompt,
                textAlign: TextAlign.center,
                style: AppText.body
                    .copyWith(color: p.textSecondary, height: 1.6),
              ),
            ] else ...[
              // 犬の名前 — 実在が中心にいることを言葉でも支える (Fi)
              Text(
                dog.name,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  level.phrase(l10n),
                  key: ValueKey(level),
                  textAlign: TextAlign.center,
                  style: AppText.title.copyWith(
                      fontSize: 22, color: p.textPrimary),
                ),
              ),
              if (trend != null) ...[
                const SizedBox(height: 8),
                Text(
                  trend,
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(
                      color: p.textSecondary,
                      fontWeight: FontWeight.w600),
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
                  style:
                      AppText.caption.copyWith(color: p.textTertiary),
                ),
              ],
            ],
            const SizedBox(height: 32),

            // ---- ここ7日のようす (平置き・カードにしない) ----
            if (recent.length >= 2) ...[
              Divider(color: p.hairline, height: 1),
              const SizedBox(height: 20),
              _TrendSection(recent: recent, l10n: l10n),
              const SizedBox(height: 24),
            ],

            // ---- 測定CTA ----
            if (dog != null)
              _PressableCta(
                label: l10n.startMeasurement,
                onPressed: () => context.go(Routes.measure),
              )
            else
              _PressableCta(
                label: l10n.registerDog,
                onPressed: () => context.go(Routes.dog),
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
          SizedBox(
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
          height: 58,
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
            style: AppText.bodyMedium.copyWith(
              color: Colors.white,
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
