/// 健康日誌の1件 — 散歩・食欲・排便・薬・体調・自由メモ (docs/21 §日誌)。
///
/// 「構造化データ + 自由記述」の両方を持つ:
/// - type / rating はAI解析・集計に使える構造化フィールド
/// - memo は飼い主の言葉をそのまま残す自由記述
/// コード生成(Freezed)に依存しない素のDartクラス(ビルド手順を増やさない)。
enum CareNoteType {
  walk, // 散歩
  appetite, // 食欲
  poop, // 排便
  medicine, // 薬
  condition, // 体調
  memo; // 自由メモ

  static CareNoteType parse(String? v) => CareNoteType.values.firstWhere(
        (t) => t.name == v,
        orElse: () => CareNoteType.memo,
      );

  /// 3段階評価(良い/ふつう/気になる)を持つ種別か
  bool get hasRating =>
      this == appetite || this == poop || this == condition;
}

/// 3段階の様子評価。数値でなく「気になる」という言葉に対応させる。
enum CareRating {
  good, // 良い
  normal, // ふつう
  concern; // 気になる

  static CareRating? parse(String? v) {
    for (final r in CareRating.values) {
      if (r.name == v) return r;
    }
    return null;
  }
}

class CareNote {
  const CareNote({
    required this.id,
    required this.dogId,
    required this.at,
    required this.type,
    this.rating,
    this.memo = '',
  });

  final String id;
  final String dogId;
  final DateTime at;
  final CareNoteType type;
  final CareRating? rating; // hasRatingの種別のみ
  final String memo;

  CareNote copyWith({String? id}) => CareNote(
        id: id ?? this.id,
        dogId: dogId,
        at: at,
        type: type,
        rating: rating,
        memo: memo,
      );

  Map<String, dynamic> toJson() => {
        'dogId': dogId,
        'at': at.toIso8601String(),
        'type': type.name,
        'rating': rating?.name,
        'memo': memo,
        'schema': 1, // 将来のAI解析のためのスキーマバージョン
      };

  factory CareNote.fromJson(String id, Map<String, dynamic> json) => CareNote(
        id: id,
        dogId: (json['dogId'] as String?) ?? '',
        at: DateTime.tryParse((json['at'] as String?) ?? '') ??
            DateTime.now(),
        type: CareNoteType.parse(json['type'] as String?),
        rating: CareRating.parse(json['rating'] as String?),
        memo: (json['memo'] as String?) ?? '',
      );
}
