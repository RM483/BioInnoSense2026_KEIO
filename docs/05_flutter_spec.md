# ⑤ Flutter仕様

## 1. 技術スタック
Flutter 3.22+ / Dart 3.4+、Riverpod (hooks_riverpod + riverpod_annotation)、GoRouter、
Freezed + json_serializable、Flutter Hooks、flutter_blue_plus (BLE)、fl_chart、
Firebase (core/auth/firestore/storage/crashlytics/analytics)、intl (l10n 日英)。

## 2. アーキテクチャ (Clean + Feature First + MVVM)

- **presentation**: HookConsumerWidget。UIとイベント発火のみ。
- **application**: Riverpod `Notifier/AsyncNotifier` = ViewModel。状態(Freezed)とユースケース。
- **domain**: エンティティ(Freezed)・Repositoryインターフェース。純Dart。
- **data**: Repository実装 (Firestore / BLE / Storage)。DTO⇔エンティティ変換。

DI: Repositoryは `Provider` で公開、テスト時に `overrideWithValue` で差替え。

## 3. 画面と遷移 (GoRouter)

| route | 画面 | 内容 |
|---|---|---|
| `/splash` | Splash | ロゴ→認証状態で分岐 |
| `/login` | ログイン | メール+パスワード / 匿名 |
| `/home` | ホーム | 犬カード、最新測定サマリ、測定開始CTA |
| `/connect` | BLE接続 | スキャン一覧、接続、ペアリング状態 |
| `/measure` | 測定 | リアルタイムグラフ(fl_chart)、現在値、開始/停止 |
| `/history` | 履歴 | 日別リスト+ミニチャート、詳細へ |
| `/dog` | 犬プロフィール | 写真(Storage)、体重等、編集 |
| `/settings` | 設定 | 言語、単位、デバイス管理、ログアウト |
| `/error` | エラー | 種別別メッセージ+復帰導線 |

redirect: 未認証→`/login`、認証済みが`/login`→`/home`。`refreshListenable`にauth状態Stream。

## 4. 状態管理

| Provider | 型 | 内容 |
|---|---|---|
| `authStateProvider` | Stream<User?> | FirebaseAuth状態 |
| `bleControllerProvider` | Notifier<BleState> | scan/connect/接続状態/再接続 |
| `measurementControllerProvider` | Notifier<MeasureState> | 測定セッション、サンプル列、統計 |
| `dogsProvider` | Stream<List<Dog>> | Firestore watch |
| `historyProvider` | AsyncNotifier | ページング取得 |

BLEデータフロー: `BleService.notifyStream` → `HppCodec.feed()`(再組立)→
`HppFrame` Stream → `MeasurementController` が検証済みサンプルを状態へ反映 → チャート再描画。
チャートは直近300点をリングバッファ保持し、`setState`負荷を抑えるため100ms間隔で間引き更新。

## 5. エラー処理

- 例外は`AppException` (sealed) に正規化: `BleException` / `SensorException(HPPエラーコード)` /
  `NetworkException` / `AuthException`。
- application層で `AsyncValue.guard` により捕捉、UIは `when(error:)` で表示。
- 致命的でないBLE切断はエラー画面でなくスナックバー+自動再接続。
- 未捕捉例外は `runZonedGuarded` + `FlutterError.onError` → Crashlytics。

## 6. l10n
`l10n.yaml` + `app_ja.arb` / `app_en.arb`。文言はすべてARB経由(ハードコード禁止)。

## 7. コード生成
freezed / json_serializable / riverpod_generator 使用:
`dart run build_runner build --delete-conflicting-outputs`
