#!/usr/bin/env bash
# HydroPaw Flutterアプリの検証一式 (Macで実行)
#
#   ./tool/verify_app.sh            # pub get / format / analyze / test
#   ./tool/verify_app.sh --build    # + apk(debug) & iOSシミュレータビルド
set -euo pipefail
cd "$(dirname "$0")/../app"

echo "==> flutter pub get"
flutter pub get

echo "==> build_runner (freezed/json/l10n生成)"
dart run build_runner build --delete-conflicting-outputs

echo "==> dart format"
dart format .

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test"
flutter test

if [ "${1:-}" = "--build" ]; then
  echo "==> flutter build apk --debug"
  flutter build apk --debug

  if [ "$(uname)" = "Darwin" ]; then
    [ -d ios ] || ../tool/setup_ios.sh
    echo "==> flutter build ios --simulator --no-codesign"
    flutter build ios --simulator --no-codesign
  fi
fi

echo ""
echo "OK. Mockモード起動: flutter run --dart-define=USE_MOCK_BLE=true"
