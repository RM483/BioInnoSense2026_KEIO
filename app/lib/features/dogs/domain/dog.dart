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
  }) = _Dog;

  const Dog._();

  factory Dog.fromJson(Map<String, dynamic> json) => _$DogFromJson(json);

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
