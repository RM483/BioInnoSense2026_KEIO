/// 測定タブ — 開始前の準備画面。
/// 「接続されているか」を専門用語なしで伝え、はじめるだけに集中させる。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../ble/application/ble_controller.dart';
import '../../dogs/application/dog_controller.dart';

class MeasureStartPage extends ConsumerWidget {
  const MeasureStartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final dog = ref.watch(selectedDogProvider);
    final ble = ref.watch(bleControllerProvider);
    final connected = ble.status == BleStatus.connected;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.tabMeasure,
                  style: AppText.largeTitle.copyWith(color: p.textPrimary)),
              const Spacer(),

              // ---- 中央: 誰の測定か + 状態 ----
              Center(
                child: Column(
                  children: [
                    _PulseRing(
                      active: connected,
                      color: connected ? p.accent : p.textTertiary,
                      size: 148,
                      child: Icon(
                        Icons.pets,
                        size: 44,
                        color: connected ? p.accent : p.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      dog == null
                          ? l10n.registerDog
                          : l10n.measureTitleFor(dog.name),
                      style: AppText.title.copyWith(color: p.textPrimary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dog == null
                          ? l10n.addDogPrompt
                          : connected
                              ? l10n.measureHint
                              : l10n.connectFirstHint,
                      style: AppText.body.copyWith(
                          color: p.textSecondary, height: 1.55),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),

              // ---- アクション ----
              if (dog == null)
                FilledButton(
                  onPressed: () => context.go(Routes.dog),
                  child: Text(l10n.registerDog),
                )
              else if (!connected)
                FilledButton(
                  onPressed: () => context.push(Routes.connect),
                  child: Text(l10n.bleConnect),
                )
              else
                FilledButton(
                  onPressed: () => context.push(Routes.measureSession),
                  child: Text(l10n.begin),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ゆっくり呼吸するようなリング。activeのとき静かに脈動する。
class _PulseRing extends StatefulWidget {
  const _PulseRing({
    required this.active,
    required this.color,
    required this.size,
    required this.child,
  });

  final bool active;
  final Color color;
  final double size;
  final Widget child;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = widget.active
            ? Curves.easeInOut.transform(_controller.value)
            : 0.0;
        return Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity(0.06 + 0.04 * t),
            border: Border.all(
              color: widget.color.withOpacity(0.25 + 0.20 * t),
              width: 1.5,
            ),
          ),
          child: Transform.scale(scale: 1.0 + 0.03 * t, child: child),
        );
      },
      child: widget.child,
    );
  }
}
