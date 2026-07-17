# ⑥ Firebase仕様

| サービス | 用途 | 設定 |
|---|---|---|
| Authentication | メール+パスワード、匿名 | 匿名→本登録のリンクアップ対応 |
| Cloud Firestore | User/Dog/Measurement/Meal/Symptom/Device | オフライン永続化ON |
| Storage | 犬の写真 (`dogs/{uid}/{dogId}/photo.jpg`) | 5MB制限、画像のみ |
| Crashlytics | クラッシュ収集 | Flutter未捕捉例外送信 |
| Analytics | 画面遷移、測定開始/完了イベント | `measure_start`, `measure_complete`, `ble_connect` |
| Cloud Functions | 日次集計、H2高値アラート | Node.js 20 / TypeScript |

## セキュリティ原則
- すべて `users/{uid}` 配下のサブコレクションに置き、**uid一致のみ許可**(firestore.rules)。
- Storageも同様に `dogs/{uid}/...` パスでuid検証。
- Functionsは Admin SDK(ルール非適用)だがトリガ元データがuidスコープ内のため安全。

## Functions
1. `onMeasurementCreated` (Firestoreトリガ): 日次統計 `dailyStats/{yyyy-mm-dd}` を増分更新。
   avgPpbが閾値(既定 20,000ppb=20ppm)超で `alerts` ドキュメント作成(将来FCM通知拡張点)。
2. `cleanupOrphanPhotos` (スケジュール, 毎日04:00 JST): Dog削除済みの写真をStorageから削除。
