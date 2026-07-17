#!/usr/bin/env bash
# HydroPaw iOSプラットフォーム生成 + 権限設定 (Macで実行)
#
#   ./tool/setup_ios.sh
#
# - ios/ が無ければ `flutter create` で生成 (bundle id: jp.keio.hydropaw)
# - Info.plist にBLE/フォトライブラリの利用目的(日本語)を設定
# - Podfile の最低iOSバージョンを 13.0 に設定 (firebase/flutter_blue_plus要件)
# - pod install を実行
#
# android/ はリポジトリにコミット済みのため対象外。
set -euo pipefail
cd "$(dirname "$0")/../app"

if ! command -v flutter >/dev/null; then
  echo "error: flutter が見つかりません。https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

if [ ! -d ios ]; then
  echo "==> flutter create (iOSのみ生成。既存の lib/ pubspec.yaml android/ は変更されない)"
  flutter create --platforms=ios --org jp.keio --project-name hydropaw .
fi

PLIST=ios/Runner/Info.plist
PB=/usr/libexec/PlistBuddy

set_plist() {
  "$PB" -c "Set :$1 $2" "$PLIST" 2>/dev/null || "$PB" -c "Add :$1 string $2" "$PLIST"
}

echo "==> Info.plist: 権限文言を設定"
set_plist NSBluetoothAlwaysUsageDescription \
  "HydroPaw測定器とBluetoothで接続し、愛犬の呼気データを受信するために使用します。"
set_plist NSBluetoothPeripheralUsageDescription \
  "HydroPaw測定器とBluetoothで接続し、愛犬の呼気データを受信するために使用します。"
set_plist NSPhotoLibraryUsageDescription \
  "愛犬のプロフィール写真を選ぶためにフォトライブラリを使用します。"
"$PB" -c "Set :CFBundleDisplayName HydroPaw" "$PLIST" 2>/dev/null || \
  "$PB" -c "Add :CFBundleDisplayName string HydroPaw" "$PLIST"

echo "==> Podfile: platform :ios, '13.0'"
if [ -f ios/Podfile ]; then
  sed -i '' "s/^# platform :ios, .*/platform :ios, '13.0'/" ios/Podfile
else
  echo "warn: ios/Podfile がまだ無い (初回 flutter build 時に生成される)" >&2
fi

echo "==> pub get & pod install"
flutter pub get
if command -v pod >/dev/null && [ -f ios/Podfile ]; then
  (cd ios && pod install)
fi

echo ""
echo "完了。GoogleService-Info.plist は flutterfire configure で追加してください"
echo "(未設定でも --dart-define=USE_MOCK_BLE=true でオフライン起動できます)。"
