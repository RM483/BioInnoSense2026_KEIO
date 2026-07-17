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

/// 最近の推移 — 直感的に「上がった/下がった」が分かる1本の折れ線。
/// 軸・数値は出さない(数値の居場所は履歴・詳細)。最新点だけ状態色で強調。
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.recent, required this.l10n});

  final List<Measurement> recent; // 新しい順
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = recent.take(7).toList().reversed.toList(); // 古い→新しい
    final values = [for (final m in items) m.avgPpm];

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
                  l10n.recentTrend.toUpperCase(),
                  style: AppText.overline.copyWith(color: p.textTertiary),
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: p.textTertiary),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 64,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendLinePainter(
                values: values,
                lineColor: p.accent,
                fillColor: p.accent.withOpacity(0.06),
                pointFill: p.card,
                lastColor: HealthAssessment.levelForPpm(values.last)
                    .color(p),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 軸なしのミニ折れ線(各点は控えめ、最新点のみ状態色でハロー付き)。
class _TrendLinePainter extends CustomPainter {
  _TrendLinePainter({
    required this.values,
    required this.lineColor,
    required this.fillColor,
    required this.pointFill,
    required this.lastColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color fillColor;
  final Color pointFill;
  final Color lastColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final span = (max - min) < 1 ? 1.0 : (max - min);
    const padY = 10.0;
    const padX = 6.0;

    Offset at(int i) => Offset(
          padX + i / (values.length - 1) * (size.width - padX * 2),
          padY +
              (1 - (values[i] - min) / span) * (size.height - padY * 2),
        );

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }

    // 薄い面
    final area = Path.from(path)
      ..lineTo(at(values.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fillColor);

    // 線
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

    // 最新点(状態色 + ハロー)
    final last = at(values.length - 1);
    canvas.drawCircle(
        last, 7, Paint()..color = lastColor.withOpacity(0.15));
    canvas.drawCircle(last, 3.4, Paint()..color = lastColor);
    canvas.drawCircle(
      last,
      3.4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = pointFill,
    );
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
