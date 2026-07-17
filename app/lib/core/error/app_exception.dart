/// アプリ内例外の正規化。HPPエラーコード(docs/03)はここで唯一Dart側に定義する。
sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class BleException extends AppException {
  const BleException(super.message);
}

class SensorException extends AppException {
  const SensorException(this.code, super.message);

  /// HPPエラーコード (firmware/App/Inc/app_error.h と1:1)
  final int code;

  static const sensorTimeout = 0x01;
  static const sensorParse = 0x02;
  static const outOfRange = 0x03;
  static const busy = 0x04;
  static const invalidCmd = 0x05;
  static const invalidParam = 0x06;
  static const lowBattery = 0x07;
  static const internal = 0x08;
  static const crc = 0x09;
}

class NetworkException extends AppException {
  const NetworkException(super.message);
}

class AuthException extends AppException {
  const AuthException(super.message);
}
