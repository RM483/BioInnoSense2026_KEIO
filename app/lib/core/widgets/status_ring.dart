/// StatusRing — アプリ全体を貫く「見守りの輪」(docs/16 案B / docs/12 §3b)。
///
/// 犬のアバターを状態色のリングがやさしく囲む。
/// **進捗リングではない**: 目盛り・%・端点・進捗表現は描かない。
/// 状態色の変化はAnimatedContainerで400msかけて静かに移る。
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatusRing extends StatelessWidget {
  const StatusRing({
    super.key,
    required this.size,
    required this.color,
    this.photoUrl = '',
    this.child,
  });

  /// 外径(ハロー含む)。ホーム176 / 準備148 / 結果120。
  final double size;

  /// 状態色(リング・ハローに使用)
  final Color color;

  /// 犬の写真URL。空なら[child]、それも無ければ肉球アイコン。
  final String photoUrl;

  /// アバターの代わりに表示する中身(任意)
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final inner = size * 0.78;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.07), // ハロー
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        width: inner + 14,
        height: inner + 14,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.55), width: 1.75),
        ),
        child: Container(
          width: inner,
          height: inner,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // 写真がない時の面はブランドの気配(Primary Soft) — docs/17 A19
            color: Color.alphaBlend(p.accentSoft, p.card),
            image: photoUrl.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(photoUrl), fit: BoxFit.cover)
                : null,
          ),
          child: photoUrl.isEmpty
              ? (child ??
                  Icon(Icons.pets,
                      size: inner * 0.42,
                      color: p.accent.withOpacity(0.55)))
              : null,
        ),
      ),
    );
  }
}
