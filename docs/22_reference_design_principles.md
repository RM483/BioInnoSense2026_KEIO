# 22. 参考リポジトリの設計思想 → HydroPaw 適用マッピング

対象: Apple Design (emilkowalski/skills) / CareKit / Flutter Gallery / Medplum。
方針: **コピーではなく原則の抽出**。各原則を現状(IA v2.2)と突き合わせ、
「既に満たす / 今回適用 / 意図的に採らない」を明示する。

---

## 1. Apple Design skill — 流体的インターフェースの原則

出典はWWDC "Designing Fluid Interfaces" 等の蒸留。核は
「**動きは常に現在値から始まり、速度を継承し、いつでも掴んで反転できる**」。

| 原則 | 現状 | 判定 |
|---|---|---|
| 押下の瞬間に反応(pointer-down) | care-ring/btn に :active scale、Flutterは押下scale+ハプティクス | ✅ 既に満たす |
| タイポ: サイズ別トラッキング(大は負、本文は0) | AppText: display -2.5/largeTitle -0.6/body -0.1、web同様 | ✅ 既に満たす |
| Reduced Motion = 無効化でなく穏やかな代替 | web: ring/chart/view/toast停止済み・Flutter: 呼吸リング静止 | ✅ 既に満たす |
| 出入りは同じ経路(空間的一貫性) | シート(日誌入力等)が**無アニメーションで出現** | 🔧 今回適用: slide-up入場+背景フェード+reduced-motionはクロスフェード |
| prefers-reduced-transparency / contrast: more | 未対応(タブバーはblurのみ) | 🔧 今回適用: 3信号(motion/transparency/contrast)を独立処理 |
| フィードバックは押下中も連続 | タブに押下フィードバックなし(web) | 🔧 今回適用: .tab:active |
| 半透明マテリアル=階層(下にコンテンツが流れる) | タブバー/ヘッダはblur+半透明で実装済み | ✅ 既に満たす |
| スプリング/速度ハンドオフ/1:1ドラッグ | ドラッグ操作がほぼ無い(タップ中心のIA) | ⏸ 採らない(今は): ジェスチャ導入自体が目的化するため。ホームの犬スワイプが将来対象 |
| 確認ダイアログは真に破壊的な操作だけ(Agency) | 全削除のみconfirm、他は易しいundo無し | ✅ 方針一致 |
| 具体的なラベル("Home"より内容を語る) | タブ=ホーム/愛犬/設定(内容が明確) | ✅ 既に満たす |

## 2. CareKit — 医療アプリのUI/データ設計

| 原則 | HydroPawへの翻訳 | 判定 |
|---|---|---|
| **カード様式の統一**: headerView(タイトル+詳細)+contentStack。全カードが同じ構造だから読める | AppCard+card-head(label+aside)で同型。日誌/履歴/設定も同構造 | ✅ 既に満たす |
| **Task→Outcome モデル**: 「予定された行為」と「その結果」を分離 | 測定=Task、EVT_RESULT=Outcome(値+品質)。日誌CareNoteもtype+rating+自由記述の構造化Outcome | ✅ 概念一致(docs/21の日誌設計がCareKit的) |
| **スタイルの注入と伝播**(OCKStylable) | AppPalette/CSSトークンが同役割。子は親のスタイルを継承 | ✅ 既に満たす |
| **ストア同期ビュー**: ビューはストアの観察者 | Riverpod/Reactの単方向データフロー | ✅ 既に満たす |
| Outcomeの**欠落も情報**(未実施が見える) | 「最終測定・6日前」「そろそろ測定を」表示 | ✅ 既に満たす |
| チャートはカードの1様式 | 測定詳細/日誌のグラフはカード内 | ✅ 既に満たす |

## 3. Medplum — 医療データ基盤の思想

| 原則 | HydroPawへの翻訳 | 判定 |
|---|---|---|
| **標準準拠(FHIR)**: データは相互運用可能な構造で | Measurement→FHIR Observation への対応表を将来docsに用意(value/device/method/quality拡張)。今は構造化(quality/confidence/flags/AUC)まで | 📝 docsのみ(実装は将来) |
| **来歴(Provenance)**: 誰が/何が/どうやって生成したデータかを提示できる | **測定詳細に「データについて」節を追加**: 取得方法(呼気イベント/ラボ)・デバイスID・品質Q/信頼度C・品質フラグの言葉化。docs/21が約束して未実装だった品質表示のギャップも同時に解消 | 🔧 今回適用 |
| コンプライアンス=UI以前の設計事項 | 免責表示(結果画面)・診断をしない文言・BLE平文の限界はdocs/20 R35で管理 | ✅ 方針一致 |
| モノレポ+モック+テストの開発規律 | FW/app/webapp同居・Mock provider・ホストテスト | ✅ 既に満たす |

## 4. Flutter Gallery — ウィジェットカタログの規律

Gallery自体は**deprecated**(公式が Wonderous / Material 3 Demo / flutter/samples を後継として案内)。採るべきは個別ウィジェットではなく規律:

| 原則 | 判定 |
|---|---|
| テキストスケール/ダーク/ロケールを設定で強制できる検証環境 | ✅ Mockモード+l10n(ja/en)+textScaler対応で担保 |
| 1コンポーネント=1責務のカタログ化 | ✅ docs/16 コンポーネント一覧が同役割 |
| 2つのデザイン言語を混ぜない(Material/Cupertino) | ✅ HydroPawは自前Design Language(docs/17)に統一。Materialの素の部品を露出させない方針を維持 |

## 5. 今回の実装(この原則適用で行う変更)

1. **Flutter 測定詳細**: 「測定の質」バッジ(言葉)+信頼度注記 + 「データについて」
   来歴カード(取得方法/デバイス/Q/C/品質フラグの言葉化)。数値の唯一の住所である
   詳細画面なので、ここではQ/Cの数値も添える。
2. **Web シート**: 入場アニメーション(下から・背景フェード)。
   prefers-reduced-motionではクロスフェードに置換。
3. **Web A11y 3信号**: reduced-transparency(タブバー/ヘッダを不透明化)、
   contrast: more(カード/タブバーに明確な境界)。
4. **Web タブ押下フィードバック**(:active)。

**採らないもの(理由つき)**: ドラッグ/スプリング物理(ジェスチャ面が現状ほぼ無い)、
CareKitのスケジューリング(毎日1回の測定にはCFG_WARMUP等FW側が担う)、
Medplumのサーバ構成(Firebaseで足りる規模)、Galleryのウィジェット移植(deprecated)。

## 6. 検証

- web: tsc / vitest / build green + シート入場の実描画確認
- Flutter: 構文チェックのみ(ビルドはMac、既知の制約)
