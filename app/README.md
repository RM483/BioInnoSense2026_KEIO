# HydroPaw Flutter App

## セットアップ
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # Freezed/json生成
flutterfire configure   # firebase_options.dart を生成し main.dart に組み込む
flutter gen-l10n
flutter run
```

## 権限設定
- **Android** `android/app/src/main/AndroidManifest.xml`:
  `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_CONNECT`
- **iOS** `ios/Runner/Info.plist`: `NSBluetoothAlwaysUsageDescription`

## テスト
```bash
flutter test                     # Unit + Widget
flutter test integration_test   # 統合テスト(実機/エミュレータ)
```

## 注意
- `lib/features/ble/data/ble_service.dart` の `BleUuids` はAC02実機の
  仮想UARTサービスUUIDに合わせて要確認・変更。
