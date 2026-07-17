/// 測定デバイス(ペアリング済みHydroPawハードウェア)エンティティ。
import 'package:freezed_annotation/freezed_annotation.dart';

part 'device.freezed.dart';
part 'device.g.dart';

@freezed
class Device with _$Device {
  const factory Device({
    required String id, // BLE remoteId
    required String name,
    @Default('') String sensorSn,
    @Default('') String fwVersion,
    DateTime? pairedAt,
    DateTime? lastConnectedAt,
  }) = _Device;

  factory Device.fromJson(Map<String, dynamic> json) =>
      _$DeviceFromJson(json);
}
