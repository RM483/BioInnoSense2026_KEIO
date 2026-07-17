/// 測定中 — フルスクリーンの静かな画面。
/// 主役は「いまの状態の言葉」。数値(ppm)は補助情報として小さく添える。
/// 開始は画面表示と同時に自動で行われ、ユーザーは「終了する」だけ。
/// 終了後は「解析しています…」の間(最低1.2s)を置いてから結果へ —
/// 測定をひとつのイベントとして完結させる。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../ble/application/ble_controller.dart';
import '../../dogs/application/dog_controller.dart';
import '../../error/presentation/error_page.dart';
import '../../insights/domain/health_assessment.dart';
import '../../insights/presentation/assessment_style.dart';
import '../application/measurement_controller.dart';
import '../domain/measurement.dart';

class MeasuringPage extends ConsumerStatefulWidget {
  const MeasuringPage({super.key});

  @override
  ConsumerState<MeasuringPage> createState() => _MeasuringPageState();
}

class _MeasuringPageState extends ConsumerState<MeasuringPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  DateTime? _stopPressedAt;

  /// 「解析しています…」の最低表示時間(結果が一瞬で出て儀式感が失われるのを防ぐ)
  static const _minAnalyzing = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    // 画面表示と同時に測定開始(体験をひとつながりにする)
    Future.microtask(() {
      HapticFeedback.lightImpact();
      final c = ref.read(measurementControllerProvider.notifier);
      c
        ..resetSession()
        ..start();
    });
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final measure = ref.watch(measurementControllerProvider);
    final ble = ref.watch(bleControllerProvider);
    final dog = ref.watch(selectedDogProvider);

    // 保存完了 → (解析の間を保って) 結果へ / エラー → エラー画面へ
    ref.listen(measurementControllerProvider, (prev, next) {
      if (!context.mounted) return;
      if (prev?.phase != MeasurePhase.saved &&
          next.phase == MeasurePhase.saved) {
        final elapsed = _stopPressedAt == null
            ? _minAnalyzing
            : DateTime.now().difference(_stopPressedAt!);
        final wait = _minAnalyzing - elapsed;
        Future.delayed(wait.isNegative ? Duration.zero : wait, () {
          if (!context.mounted) return;
          HapticFeedback.mediumImpact();
          context.pushReplacement(Routes.measureResult);
        });
      } else if (prev?.phase != MeasurePhase.error &&
          next.phase == MeasurePhase.error) {
        context.pushReplacement(Routes.error,
            extra: ErrorKind.fromHpp(next.errorCode));
      }
    });

    final latest = measure.latest;
    final level = latest == null
        ? null
        : HealthAssessment.levelForPpm(latest.h2Ppm);
    // 終了後〜結果表示までは「解析しています…」の静かな間
    final analyzing = measure.phase == MeasurePhase.stopping ||
        measure.phase == MeasurePhase.saved;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // ---- ヘッダ: 閉じる + 経過 + 接続 ----
              Row(
                children: [
                  _QuietIconButton(
                    icon: Icons.close,
                    onTap: () {
                      ref
                          .read(measurementControllerProvider.notifier)
                          .resetSession();
                      context.pop();
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _formatElapsed(latest?.timeMs ?? 0),
                        style: AppText.numeral
                            .copyWith(color: p.textSecondary),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (measure.lowBattery)
                          Icon(Icons.battery_alert_outlined,
                              size: 18, color: p.warn),
                        if (ble.status == BleStatus.reconnecting) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.bluetooth_searching,
                              size: 18, color: p.warn),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // ---- 呼吸リング + 状態の言葉 ----
              AnimatedBuilder(
                animation: _breath,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(_breath.value);
                  final color = (level?.color(p) ?? p.accent);
                  return Container(
                    width: 216,
                    height: 216,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.05 + 0.04 * t),
                    ),
                    child: Container(
                      width: 176 + 8 * t,
                      height: 176 + 8 * t,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.card,
                        border: Border.all(
                            color: color.withOpacity(0.35), width: 1.5),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        child: analyzing
                            ? Text(
                                l10n.analyzing,
                                key: const ValueKey('analyzing'),
                                style: AppText.title.copyWith(
                                    fontSize: 19,
                                    color: p.textSecondary),
                              )
                            : Column(
                                key: const ValueKey('live'),
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(
                                        milliseconds: 300),
                                    child: Text(
                                      latest == null
                                          ? '…'
                                          : level!.shortLabel(l10n),
                                      key: ValueKey(level),
                                      style: AppText.title.copyWith(
                                          fontSize: 24,
                                          color: latest == null
                                              ? p.textTertiary
                                              : level.color(p)),
                                    ),
                                  ),
                                  if (latest != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '${latest.h2Ppm.toStringAsFixed(1)} ${l10n.ppm}',
                                      key: const ValueKey('h2-value'),
                                      style: AppText.caption.copyWith(
                                          color: p.textTertiary),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              Text(
                dog?.name ?? '',
                style: AppText.title.copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  analyzing
                      ? l10n.analyzingSub
                      : (latest?.isWarmup ?? false)
                          ? l10n.warmingUp
                          : l10n.measuringCalm,
                  key: ValueKey(analyzing),
                  style: AppText.caption.copyWith(color: p.textSecondary),
                ),
              ),
              const Spacer(),

              // ---- ライブスパークライン(装飾を排した1本の線) ----
              AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: analyzing ? 0 : 1,
                child: SizedBox(
                  height: 56,
                  child: measure.samples.length >= 2
                      ? _MiniSparkline(
                          samples: measure.samples,
                          color: (level?.color(p) ?? p.accent))
                      : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 24),

              // ---- 終了 (解析中は静かに消える) ----
              AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: analyzing ? 0 : 1,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.textPrimary,
                    foregroundColor: p.bg,
                  ),
                  onPressed: measure.phase != MeasurePhase.measuring
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          _stopPressedAt = DateTime.now();
                          ref
                              .read(
                                  measurementControllerProvider.notifier)
                              .stopAndSave(dog?.id ?? '',
                                  ble.connectedDeviceId ?? '');
                        },
                  child: Text(l10n.finishMeasurement),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatElapsed(int ms) {
    final s = ms ~/ 1000;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }
}

/// 軸なし・点なしの最小スパークライン。
class _MiniSparkline extends StatelessWidget {
  const _MiniSparkline({required this.samples, required this.color});

  final List<H2Sample> samples;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 56),
      painter: _SparkPainter(
        values: [
          for (final s in samples.length <= 120
              ? samples
              : samples.sublist(samples.length - 120))
            s.h2Ppm
        ],
        color: color,
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV =
        values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - (values[i] / maxV) * (size.height - 6) - 3;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withOpacity(0.7),
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values.length != values.length || old.color != color;
}

class _QuietIconButton extends StatelessWidget {
  const _QuietIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Icon(icon, size: 22, color: p.textSecondary),
      ),
    );
  }
}
