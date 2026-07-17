# ⑨ API設計

外部公開REST APIは持たない(Firebase SDK直結)。「API」は以下3層で定義する。

## 1. Repositoryインターフェース (domain層 = アプリ内API)

```dart
abstract class AuthRepository {
  Stream<AppUser?> watchAuthState();
  Future<AppUser> signInWithEmail(String email, String password);
  Future<AppUser> signUpWithEmail(String email, String password);
  Future<AppUser> signInAnonymously();
  Future<void> signOut();
}

abstract class DogRepository {
  Stream<List<Dog>> watchDogs();
  Future<String> addDog(Dog dog);
  Future<void> updateDog(Dog dog);
  Future<void> deleteDog(String dogId);
  Future<String> uploadPhoto(String dogId, Uint8List bytes); // Storage→URL
}

abstract class MeasurementRepository {
  Future<String> saveMeasurement(String dogId, Measurement m);
  Future<List<Measurement>> fetchHistory(String dogId,
      {DateTime? before, int limit = 20});
  Stream<Measurement?> watchLatest(String dogId);
}

abstract class BleRepository {
  Stream<List<ScannedDevice>> scan();
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Stream<BleConnectionState> get connectionState;
  Stream<HppFrame> get frames;          // 受信フレーム
  Future<void> sendCommand(HppCommand cmd); // ACK待ち+再送はController側
}
```

## 2. デバイスAPI = HPPプロトコル
docs/03_ble_spec.md 参照。コマンド/イベント/エラーコードが機器とのAPI契約。

## 3. Cloud Functions (サーバ側)

| 関数 | トリガ | 入出力 |
|---|---|---|
| `onMeasurementCreated` | Firestore onCreate `users/{uid}/dogs/{dogId}/measurements/{id}` | dailyStats upsert、閾値超でalerts作成 |
| `cleanupOrphanPhotos` | Scheduler (daily) | 孤児画像削除 |

Callable/HTTPは現段階でYAGNIにより未実装(拡張点としてコメント記載)。
