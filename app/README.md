# HydroPaw Flutter App

## セットアップ

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # Freezed/json生成
flutter gen-l10n
```

### 実機なし(Mockモード) — Firebase設定も不要
```bash
flutter run --dart-define=USE_MOCK_BLE=true
```
BLEはMock(FW挙動を模した1Hzデータ)、Firebaseが未設定なら
認証・保存もメモリ内で完結する(オフラインDI)。全画面が動作する。

### 本番(実BLE + Firebase)
```bash
flutterfire configure   # firebase_options / ネイティブ設定を生成
flutter run             # dart-define無し → 実BLE(BleProvider)
```

## プラットフォーム
- **Android**: `android/` をコミット済み (applicationId: `jp.keio.hydropaw`,
  minSdk 23, BLE権限設定済み)。`flutter build apk --debug` がそのまま通る。
  `google-services.json` を置いた場合のみFirebase Gradleプラグインが自動適用される。
- **iOS**: 初回のみ `../tool/setup_ios.sh` を実行 (flutter createでios/生成
  → Info.plistにBLE/写真の利用目的(日本語)を設定 → Podfile iOS 13.0 → pod install)。
  bundle id: `jp.keio.hydropaw`。

## 検証一式
```bash
../tool/verify_app.sh           # pub get / build_runner / format / analyze / test
../tool/verify_app.sh --build   # + apk(debug) / iOSシミュレータビルド
```

## テスト
```bash
flutter test                                            # Unit + Widget
flutter test integration_test/mock_app_test.dart \
  --dart-define=USE_MOCK_BLE=true                       # Mock統合テスト(実機/エミュ)
flutter test integration_test/app_test.dart             # Firebase構成済み環境用
```

## 注意
- **BLE UUIDは `lib/core/constants/ble_constants.dart` の1箇所のみ**。
  AC02実機の仮想UARTサービスUUIDを確認後、ここだけ差し替える
  (webapp側 `src/providers/BleProvider.ts` も同時に)。
- リリース署名は未設定 (`android/app/build.gradle` のTODO参照)。
