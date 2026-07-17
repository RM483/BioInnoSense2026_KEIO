/// 症状記録エンティティ(Freezed)。
import 'package:freezed_annotation/freezed_annotation.dart';

part 'symptom.freezed.dart';
part 'symptom.g.dart';

/// 症状種別 (docs/07)
enum SymptomType { diarrhea, vomit, appetiteLoss, lethargy, other }

@freezed
class Symptom with _$Symptom {
  const factory Symptom({
    required String id,
    required String dogId,
    required DateTime observedAt,
    required SymptomType type,
    @Default(1) int severity, // 1(軽)〜3(重)
    @Default('') String memo,
  }) = _Symptom;

  factory Symptom.fromJson(Map<String, dynamic> json) =>
      _$SymptomFromJson(json);
}
