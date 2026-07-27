/// 健康日誌の1件 — docs/21 v2.3。
///
/// 考え方 (§1,4):
/// - 測定以外の健康日誌は「1日につき各カテゴリ1件まで」(upsertで担保)
/// - schema 2: 構造化された選択(choice) + 任意の補足メモ(memo)
/// - schema 1(旧): rating(3段階) — 読み取り互換を維持し、既存データは
///   削除・変換しない (§19)
/// コード生成(Freezed)に依存しない素のDartクラス。
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
}

/// 旧schema1の3段階評価(読み取り互換用)。新規保存では使わない。
enum CareRating {
  good,
  normal,
  concern;

  static CareRating? parse(String? v) {
    for (final r in CareRating.values) {
      if (r.name == v) return r;
    }
    return null;
  }
}

/// カテゴリごとの選択肢の値 (§3)。表示文言はl10n側(care_note_sheet)。
const noteChoices = <CareNoteType, List<String>>{
  CareNoteType.walk: ['none', 'short', 'usual', 'long'],
  CareNoteType.appetite: ['none', 'less', 'normal', 'lots'],
  CareNoteType.poop: ['none', 'less', 'usual', 'more'],
  CareNoteType.medicine: ['none', 'taken'],
  CareNoteType.condition: ['concern', 'slight', 'usual', 'energetic'],
  CareNoteType.memo: [],
};

class CareNote {
  const CareNote({
    required this.id,
    required this.dogId,
    required this.at,
    required this.type,
    this.choice,
    this.rating,
    this.memo = '',
    this.schema = 2,
  });

  final String id;
  final String dogId;
  final DateTime at;
  final CareNoteType type;

  /// schema2: 選択肢の値 (§3)
  final String? choice;

  /// schema1(旧)の評価 — 表示互換のみ
  final CareRating? rating;

  /// 自由記述(memoカテゴリ本文、他カテゴリでは補足メモ)
  final String memo;
  final int schema;

  /// 「気になる」系の内容か(控えめな注意色に使う)
  bool get isConcern =>
      rating == CareRating.concern ||
      (type == CareNoteType.condition &&
          (choice == 'concern' || choice == 'slight')) ||
      (type == CareNoteType.appetite && choice == 'none');

  CareNote copyWith({String? id, String? choice, String? memo}) => CareNote(
        id: id ?? this.id,
        dogId: dogId,
        at: at,
        type: type,
        choice: choice ?? this.choice,
        rating: rating,
        memo: memo ?? this.memo,
        schema: 2,
      );

  Map<String, dynamic> toJson() => {
        'dogId': dogId,
        'at': at.toIso8601String(),
        'type': type.name,
        'choice': choice,
        'rating': rating?.name,
        'memo': memo,
        'schema': schema,
      };

  factory CareNote.fromJson(String id, Map<String, dynamic> json) => CareNote(
        id: id,
        dogId: (json['dogId'] as String?) ?? '',
        at: DateTime.tryParse((json['at'] as String?) ?? '') ??
            DateTime.now(),
        type: CareNoteType.parse(json['type'] as String?),
        choice: json['choice'] as String?,
        rating: CareRating.parse(json['rating'] as String?),
        memo: (json['memo'] as String?) ?? '',
        schema: (json['schema'] as num?)?.toInt() ?? 1,
      );
}

/// ローカル日付キー(yyyy-mm-dd相当の比較用)
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// ある日のカテゴリ別「最新1件」(§4)。旧重複データは削除せず最新を採用。
Map<CareNoteType, CareNote> notesOfDay(
    List<CareNote> notes, DateTime day) {
  final map = <CareNoteType, CareNote>{};
  for (final n in notes) {
    // notesは新しい順 — 先勝ちで最新を採用
    if (!sameDay(n.at, day)) continue;
    map.putIfAbsent(n.type, () => n);
  }
  return map;
}
