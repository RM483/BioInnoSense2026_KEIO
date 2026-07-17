/// ホーム — 「今日、うちの犬は元気?」に3秒で答える画面。
///
/// 主役は数値ではなく状態の言葉。ppm・温度などの専門情報は
/// 履歴/詳細画面に退避し、ここには安心感に必要な要素だけを置く:
/// 犬の名前 / 今日の状態 / ひとこと / 最終測定時刻 / 最近の推移 / 測定CTA。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/h2.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
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

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            // ---- 日付 + 犬の名前 ----
            Text(
              DateFormat.MMMEd(locale).format(DateTime.now()).toUpperCase(),
              style: AppText.overline.copyWith(color: p.textTertiary),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    dog?.name ?? l10n.appTitle,
                    style:
                        AppText.largeTitle.copyWith(color: p.textPrimary),
                  ),
                ),
                if (dog != null)
                  Hero(
                    tag: 'dog-avatar',
                    child: _Avatar(photoUrl: dog.photoUrl, size: 44),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // ---- 今日の状態 (主役) ----
            dog == null
                ? _RegisterDogCard(l10n: l10n)
                : _StatusCard(assessment: assessment, l10n: l10n),
            const SizedBox(height: 14),

            // ---- 最近の推移 (ミニ・無数値) ----
            if (recent.length >= 2) ...[
              _TrendCard(recent: recent, l10n: l10n),
              const SizedBox(height: 14),
            ],

            const SizedBox(height: 14),

            // ---- 測定CTA (最重要ボタン: 少し高く・押下で沈む) ----
            if (dog != null)
              _PressableCta(
                label: l10n.startMeasurement,
                onPressed: () => context.go(Routes.measure),
              ),
          ],
        ),
      ),
    );
  }
}

/// 状態カード — 3秒で伝える3行:
/// 「今日の状態」→「前回からの変化」→「取るべき行動」(+最終測定時刻)。
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.assessment, required this.l10n});

  final HealthAssessment assessment;
  final AppLocalizations l10n;

  /// ドット(10) + 間隔(10) — 2行目以降の光学揃え
  static const _indent = EdgeInsets.only(left: 20);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final level = assessment.level;
    final latest = assessment.latest;
    final trend = assessmentTrendLabel(assessment, l10n);

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- 1. 今日の状態 ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: level.color(p),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    level.phrase(l10n),
                    key: ValueKey(level),
                    style: AppText.title.copyWith(color: p.textPrimary),
                  ),
                ),
              ),
            ],
          ),

          // ---- 2. 前回からの変化 ----
          if (trend != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: _indent,
              child: Text(
                trend,
                style: AppText.caption.copyWith(
                    color: p.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ],

          // ---- 3. 取るべき行動 ----
          const SizedBox(height: 10),
          Padding(
            padding: _indent,
            child: Text(
              assessmentAction(assessment, l10n),
              style: AppText.bodyMedium
                  .copyWith(color: p.textPrimary, height: 1.55),
            ),
          ),

          if (latest != null) ...[
            const SizedBox(height: 14),
            Padding(
              padding: _indent,
              child: Text(
                '${l10n.lastMeasured} · '
                '${relativeTime(l10n, latest.startedAt)}',
                style: AppText.caption.copyWith(color: p.textTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 最近の健康状態 — 「良い/変わらない/心配」が一目で分かるグラフ。
/// 正常範囲を薄緑の帯で示し、強調は現在の1点だけ。下に言葉の要約を添える。
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.recent, required this.l10n});

  final List<Measurement> recent; // 新しい順
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = recent.take(7).toList().reversed.toList(); // 古い→新しい
    final values = [for (final m in items) m.avgPpm];
    final level = HealthAssessment.levelForPpm(values.last);
    final summary = windowSummaryText(
        HealthAssessment.windowSummary(recent), l10n);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      onTap: () => GoRouter.of(context).go(Routes.history),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.healthTrendTitle,
                  style: AppText.bodyMedium.copyWith(
                      color: p.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
              // 状態チップ: 色 + 記号 + 語(色覚に依存しない)
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
                labelStyle:
                    AppText.caption.copyWith(fontSize: 10.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
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

/// 意味の読めるミニ折れ線:
/// - 縦軸は絶対スケール(0基準) — 線の高さ自体が状態を表す
/// - 正常範囲(〜10ppm)だけを薄緑の帯 + ラベルで示す
/// - 受診の目安(20ppm)はデータが近づいた時だけ点線で現れる
/// - 線は中立色、強調は現在(最新)の1点のみ
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
    final maxY = [_stable * 1.35, dataMax * 1.2]
        .reduce((a, b) => a > b ? a : b);
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

    // ---- 正常範囲の帯(薄緑) + 上端ライン ----
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

    // ---- 受診の目安(必要なときだけ点線) ----
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

    // ---- 推移線(中立色) ----
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

    // 途中の点(控えめ)
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

    // ---- 現在(最新)だけ状態色で強調 ----
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

class _RegisterDogCard extends StatelessWidget {
  const _RegisterDogCard({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(24),
      onTap: () => context.go(Routes.dog),
      child: Row(
        children: [
          _Avatar(photoUrl: '', size: 56),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.registerDog,
                    style: AppText.title.copyWith(color: p.textPrimary)),
                const SizedBox(height: 4),
                Text(l10n.addDogPrompt,
                    style:
                        AppText.caption.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: p.textTertiary),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.size});
  final String photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: p.cardElevated,
        shape: BoxShape.circle,
        image: photoUrl.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(photoUrl), fit: BoxFit.cover)
            : null,
      ),
      child: photoUrl.isEmpty
          ? Icon(Icons.pets, size: size * 0.45, color: p.textTertiary)
          : null,
    );
  }
}
