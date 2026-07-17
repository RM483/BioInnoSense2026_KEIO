/// 統合テスト。実機/エミュレータで実行:
///   flutter test integration_test
/// Firebaseエミュレータ使用を推奨 (firebase emulators:start)。
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:hydropaw/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('起動 → Splash → ログイン画面が表示される', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 未認証ならログイン画面のボタンが見える
    expect(find.text('ログインする'), findsOneWidget);
  });

  // NOTE: BLE測定フローの統合テストは FakeBleRepository を
  // bleRepositoryProvider にoverrideして模擬EVT_DATAを注入する
  // (docs/10_plan_and_test.md 参照)。実BLEはCI環境で不安定なため
  // 実機手順書ベースのBLE Testで担保する。
}
