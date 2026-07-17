/// 食事記録エンティティ(Freezed)。
import 'package:freezed_annotation/freezed_annotation.dart';

part 'meal.freezed.dart';
part 'meal.g.dart';

@freezed
class Meal with _$Meal {
  const factory Meal({
    required String id,
    required String dogId,
    required DateTime fedAt,
    required String foodName,
    @Default(0) double amountG,
    @Default('') String memo,
  }) = _Meal;

  factory Meal.fromJson(Map<String, dynamic> json) => _$MealFromJson(json);
}
