/// 犬エンティティ(Freezed)。
import 'package:freezed_annotation/freezed_annotation.dart';

part 'dog.freezed.dart';
part 'dog.g.dart';

@freezed
class Dog with _$Dog {
  const factory Dog({
    required String id,
    required String name,
    @Default('') String breed,
    DateTime? birthday,
    @Default(0) double weightKg,
    @Default('unknown') String sex, // 'male' | 'female' | 'unknown'
    @Default('') String photoUrl,
    /// 見守りを終了した犬 (docs/21 v2.1 §5C)。
    /// データは保持したまま、ホーム/測定対象/頭数から外す。
    @Default(false) bool archived,
  }) = _Dog;

  const Dog._();

  factory Dog.fromJson(Map<String, dynamic> json) => _$DogFromJson(json);

  /// プロフィール設定完了 = 名前が保存されている (§5A)
  bool get isComplete => name.trim().isNotEmpty;

  /// 見守り中 = 設定完了かつ見守り終了していない
  bool get isWatching => isComplete && !archived;

  int? get ageYears {
    final b = birthday;
    if (b == null) return null;
    final now = DateTime.now();
    var age = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) {
      age--;
    }
    return age;
  }
}
