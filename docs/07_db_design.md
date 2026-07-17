# ⑦ データベース設計 (Cloud Firestore)

## ER図

```mermaid
erDiagram
    USER ||--o{ DOG : owns
    USER ||--o{ DEVICE : registers
    DOG  ||--o{ MEASUREMENT : has
    DOG  ||--o{ MEAL : has
    DOG  ||--o{ SYMPTOM : has
    DEVICE ||--o{ MEASUREMENT : produced

    USER {
        string uid PK
        string email
        string displayName
        string locale
        timestamp createdAt
    }
    DOG {
        string dogId PK
        string name
        string breed
        date   birthday
        number weightKg
        string sex
        string photoUrl
        timestamp createdAt
        timestamp updatedAt
    }
    MEASUREMENT {
        string measurementId PK
        string dogId FK
        string deviceId FK
        timestamp startedAt
        number durationS
        number sampleCount
        number avgPpb
        number maxPpb
        number minPpb
        array  series "間引き系列 最大600点 [{t,ppb}]"
        string mode "continuous|single"
        string note
    }
    MEAL {
        string mealId PK
        string dogId FK
        timestamp fedAt
        string foodName
        number amountG
        string memo
    }
    SYMPTOM {
        string symptomId PK
        string dogId FK
        timestamp observedAt
        string type "diarrhea|vomit|appetite_loss|lethargy|other"
        number severity "1-3"
        string memo
    }
    DEVICE {
        string deviceId PK "BLE remoteId"
        string name
        string sensorSn
        string fwVersion
        timestamp pairedAt
        timestamp lastConnectedAt
    }
```

## コレクションパス

```
users/{uid}                                  … USER
users/{uid}/dogs/{dogId}                     … DOG
users/{uid}/dogs/{dogId}/measurements/{id}   … MEASUREMENT
users/{uid}/dogs/{dogId}/meals/{id}          … MEAL
users/{uid}/dogs/{dogId}/symptoms/{id}       … SYMPTOM
users/{uid}/devices/{deviceId}               … DEVICE
users/{uid}/dogs/{dogId}/dailyStats/{yyyy-mm-dd}  … Functions生成の日次集計
```

## 設計理由
- サブコレクション分離により**ルールがuid一本で完結**、リストクエリも自然。
- `series` は最大600点(1点≈16B→約10KB)で1MB制限に余裕。生波形はアプリ表示用途のみ。
- 履歴一覧は `measurements` を `startedAt desc` + `limit` でページング(複合インデックス定義済み)。
- Meal/Symptomは測定と時間相関で突き合わせるため独立コレクション(JOINはアプリ側)。
