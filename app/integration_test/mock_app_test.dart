/// Mockモードの統合テスト(実機/エミュレータ, Firebase未設定でも動く)。
///
///   flutter test integration_test/mock_app_test.dart \
///     --dart-define=USE_MOCK_BLE=true
///
/// 起動→匿名ログイン→犬登録→接続→測定→結果表示 までの
/// 一連のプロダクト体験を検証する。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:hydropaw/features/ble/data/ble_service.dart';
import 'package:hydropaw/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Mockモード: ログイン→犬登録→接続→測定→結果', (tester) async {
    assert(kUseMockBle,
        'このテストは --dart-define=USE_MOCK_BLE=true で実行してください');

    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // ---- ログイン(匿名) ----
    expect(find.text('登録せずに使ってみる'), findsOneWidget);
    await tester.tap(find.text('登録せずに使ってみる'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ---- 初回設定: 頭数の質問 (v2.1 §9) ----
    expect(find.textContaining('何頭ですか'), findsOneWidget);
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();

    // ---- ホーム(空状態) → Dogsで登録 (§5A,8) ----
    await tester.tap(find.text('愛犬を登録する'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新しい愛犬を追加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ポチ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ---- ホームのCTA(名前入り §3)。未接続なら接続画面が開く ----
    await tester.tap(find.text('ホーム'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ポチの測定をはじめる'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('HydroPaw-MOCK'), findsWidgets);
    await tester.tap(find.text('接続').first);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ---- 接続済み: CTA → 対象犬の確認 → 測定セッションへ (§3) ----
    await tester.tap(find.text('ポチの測定をはじめる'));
    await tester.pumpAndSettle();
    expect(find.text('ポチを測定します'), findsOneWidget);
    await tester.tap(find.text('測定を開始'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('終了する'), findsOneWidget);

    // ---- 終了 → 結果 ----
    await tester.tap(find.text('終了する'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('測定できました'), findsOneWidget);

    // ---- ホームへ戻ると状態の言葉が表示される ----
    await tester.tap(find.text('ホームに戻る'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('しています'), findsWidgets);
  });
}
