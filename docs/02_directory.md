# ② ディレクトリ構成

```
hydropaw/
├── README.md
├── docs/                          # 設計書 ①〜⑩
├── firmware/                      # ⑪ STM32 (STM32CubeIDEプロジェクト)
│   ├── HydroPaw.ioc               # CubeMX設定
│   ├── Core/
│   │   ├── Inc/  main.h, app_config.h, stm32l4xx_it.h
│   │   └── Src/  main.c, stm32l4xx_it.c
│   ├── App/                       # アプリ層(HAL依存はコールバック注入でモック可能)
│   │   ├── Inc/  dgs2.h, hpp.h, ble_link.h, state_machine.h,
│   │   │         ring_buffer.h, app_error.h, power.h
│   │   └── Src/  dgs2.c, hpp.c, ble_link.c, state_machine.c,
│   │             ring_buffer.c, power.c
│   └── Tests/                     # ⑭ ホストPC実行の単体テスト
│       ├── Makefile
│       ├── test_dgs2_parser.c
│       └── test_hpp.c
├── app/                           # ⑫ Flutter (Clean Architecture / Feature First)
│   ├── pubspec.yaml / analysis_options.yaml / l10n.yaml
│   ├── lib/
│   │   ├── main.dart              # Firebase初期化 / Crashlytics
│   │   ├── app.dart               # MaterialApp.router / テーマ / l10n
│   │   ├── core/
│   │   │   ├── router/app_router.dart
│   │   │   ├── theme/app_theme.dart
│   │   │   ├── error/app_exception.dart
│   │   │   ├── utils/result.dart
│   │   │   └── firebase/firebase_providers.dart
│   │   ├── features/              # 各feature = domain/data/application/presentation
│   │   │   ├── splash/presentation/splash_page.dart
│   │   │   ├── auth/        data/auth_repository.dart
│   │   │   │                application/auth_controller.dart
│   │   │   │                presentation/login_page.dart
│   │   │   ├── home/presentation/home_page.dart
│   │   │   ├── ble/         data/hpp_codec.dart        # HPP encode/decode
│   │   │   │                data/ble_service.dart      # flutter_blue_plusラッパ
│   │   │   │                application/ble_controller.dart
│   │   │   │                presentation/connect_page.dart
│   │   │   ├── measurement/ domain/measurement.dart
│   │   │   │                data/measurement_repository.dart
│   │   │   │                application/measurement_controller.dart
│   │   │   │                presentation/measure_page.dart, realtime_chart.dart
│   │   │   ├── history/presentation/history_page.dart
│   │   │   ├── dogs/        domain/dog.dart
│   │   │   │                data/dog_repository.dart
│   │   │   │                application/dog_controller.dart
│   │   │   │                presentation/dog_profile_page.dart
│   │   │   ├── records/domain/meal.dart, symptom.dart
│   │   │   ├── device/domain/device.dart
│   │   │   ├── settings/presentation/settings_page.dart
│   │   │   └── error/presentation/error_page.dart
│   │   └── l10n/ app_ja.arb, app_en.arb
│   ├── test/                      # ⑭ Unit / Widget
│   └── integration_test/app_test.dart
└── firebase/                      # ⑬ クラウド
    ├── firebase.json / firestore.rules / firestore.indexes.json / storage.rules
    └── functions/src/index.ts     # 日次集計 / 高値アラート
```

## 依存方向 (Flutter)

```
presentation → application → domain ← data
                    ↑________________↑ (Riverpod DI)
```
- domainは純Dart(SDK非依存)。dataがRepository実装を提供、application(Riverpod Notifier=ViewModel)がユースケースを担う。
- firmwareのApp/もHAL関数ポインタ注入でホストテスト可能。
