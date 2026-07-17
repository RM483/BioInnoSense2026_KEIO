/// Mockモードの統合テスト(実機/エミュレータ, Firebase未設定でも動く)。
///
///   flutter test integration_test/mock_app_test.dart \
///     --dart-define=USE_MOCK_BLE=true
///
/// 起動→匿名ログイン→犬登録→BLE(Mock)接続→測定→データ表示→停止・保存
/// までの一連のフローを検証する。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:hydropaw/features/ble/data/ble_service.dart';
import 'package:hydropaw/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Mockモード: ログイン→犬登録→接続→測定→保存', (tester) async {
    assert(kUseMockBle,
        'このテストは --dart-define=USE_MOCK_BLE=true で実行してください');

    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // ---- ログイン(匿名) ----
    expect(find.text('登録せずに使ってみる'), findsOneWidget);
    await tester.tap(find.text('登録せずに使ってみる'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ---- ホーム: 犬未登録カード → 登録 ----
    await tester.tap(find.text('愛犬を登録する'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ポチ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ---- 接続(Mockデバイス) ----
    await tester.tap(find.text('デバイス接続'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('HydroPaw-MOCK'), findsWidgets);
    await tester.tap(find.text('接続').first);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 接続完了で自動的にホームへ戻る → 測定へ
    await tester.tap(find.text('測定をはじめる'));
    await tester.pumpAndSettle();

    // ---- 測定開始 ----
    await tester.tap(find.text('測定をはじめる'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    // 現在値・温度が表示されている
    expect(find.text('––'), findsNothing);
    expect(find.text('停止'), findsOneWidget);
    expect(find.textContaining('°'), findsWidgets); // 温度

    // ---- 停止 → 保存 ----
    await tester.tap(find.text('停止'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('測定結果を保存しました'), findsOneWidget);
  });
}
