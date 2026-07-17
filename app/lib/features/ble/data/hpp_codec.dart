/// HPP (HydroPaw Protocol) v1 コーデック — firmware/App/Src/hpp.c のDartミラー。
/// 純Dart(SDK非依存)。仕様: docs/03_ble_spec.md
/// C側と同一のテストベクタで相互検証している (test/hpp_codec_test.dart)。
import 'dart:typed_data';

abstract final class Hpp {
  static const sof = 0xA5;
  static const version = 0x01;
  static const maxPayload = 48;
  static const headerSize = 5;
  static const crcSize = 2;
  static const maxFrameSize = headerSize + maxPayload + crcSize;

  // コマンド (App→FW)
  static const cmdStartCont = 0x01;
  static const cmdStop = 0x02;
  static const cmdSingle = 0x03;
  static const cmdSleep = 0x04;
  static const cmdWake = 0x05;
  static const cmdGetStatus = 0x06;
  static const cmdGetInfo = 0x07;
  static const cmdZero = 0x08; // DGS2ゼロ校正(クリーンエア中)
  // 応答・イベント (FW→App)
  static const ack = 0x40;
  static const nak = 0x41;
  static const evtData = 0x81;
  static const evtSummary = 0x82;
  static const evtStatus = 0x83;
  static const evtError = 0x84;
  static const evtInfo = 0x85;

  // EVT_DATA flags
  static const flagOutOfRange = 1 << 0;
  static const flagStuck = 1 << 1;
  static const flagWarmup = 1 << 2;
  static const flagUnstable = 1 << 3;
}

/// デコード済みフレーム
class HppFrame {
  const HppFrame(this.type, this.seq, this.payload);
  final int type;
  final int seq;
  final Uint8List payload;

  ByteData get _view => ByteData.sublistView(payload);

  // ---- EVT_DATA アクセサ ----
  int get dataTimeMs => _view.getUint32(0, Endian.little);
  int get dataH2Ppb => _view.getInt32(4, Endian.little);
  double get dataTempC => _view.getInt16(8, Endian.little) / 10.0;
  double get dataRh => _view.getUint16(10, Endian.little) / 10.0;
  int get dataFlags => payload[12];

  // ---- EVT_SUMMARY アクセサ ----
  int get summaryCount => _view.getUint16(0, Endian.little);
  int get summaryAvgPpb => _view.getInt32(2, Endian.little);
  int get summaryMaxPpb => _view.getInt32(6, Endian.little);
  int get summaryMinPpb => _view.getInt32(10, Endian.little);
  int get summaryDurationS => _view.getUint16(14, Endian.little);

  // ---- EVT_STATUS アクセサ ----
  int get statusState => payload[0];
  int get statusBatteryMv => _view.getUint16(1, Endian.little);
  bool get statusSensorOk => payload[3] != 0;
  int get statusUptimeS => _view.getUint32(4, Endian.little);

  /// v1.1拡張フィールド(FW側12Bペイロード)。旧FW(8B)では0を返す。
  int get statusCrcErrors =>
      payload.length >= 12 ? _view.getUint16(8, Endian.little) : 0;
  int get statusResyncs =>
      payload.length >= 12 ? _view.getUint16(10, Endian.little) : 0;

  /// FW状態: SM_MEASURING(=3)なら測定継続中(再接続後のUI再同期に使用)
  bool get statusIsMeasuring => statusState == 3;

  // ---- ACK/NAK/EVT_ERROR ----
  int get ackCmd => payload[0];
  int get nakError => payload[1];
  int get errorCode => payload[0];
}

/// CRC16 CCITT-FALSE (poly 0x1021, init 0xFFFF) — C実装と同一。
int hppCrc16(List<int> data, [int? length]) {
  var crc = 0xFFFF;
  final n = length ?? data.length;
  for (var i = 0; i < n; i++) {
    crc ^= (data[i] & 0xFF) << 8;
    for (var b = 0; b < 8; b++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xFFFF;
    }
  }
  return crc;
}

/// エンコーダ/ストリーミングデコーダ。
/// BLE Notifyは20B等に分割され得るため、feed()でバイト列を逐次供給し
/// 完成フレームのリストを受け取る設計。
class HppCodec {
  final _buf = <int>[];
  int crcErrors = 0;
  int resyncs = 0;

  /// フレームを組み立てる。
  static Uint8List encode(int type, int seq, [List<int> payload = const []]) {
    if (payload.length > Hpp.maxPayload) {
      throw ArgumentError('payload too long: ${payload.length}');
    }
    final frame = Uint8List(Hpp.headerSize + payload.length + Hpp.crcSize);
    frame[0] = Hpp.sof;
    frame[1] = Hpp.version;
    frame[2] = type;
    frame[3] = seq & 0xFF;
    frame[4] = payload.length;
    frame.setRange(Hpp.headerSize, Hpp.headerSize + payload.length, payload);
    final body = Hpp.headerSize + payload.length;
    final crc = hppCrc16(frame, body);
    frame[body] = (crc >> 8) & 0xFF; // CRCのみビッグエンディアン
    frame[body + 1] = crc & 0xFF;
    return frame;
  }

  /// 受信チャンクを供給し、完成したフレームを返す(0個以上)。
  /// C実装と同じ「先頭1バイト破棄による再同期」で破損から自己回復する。
  List<HppFrame> feed(List<int> chunk) {
    _buf.addAll(chunk);
    final frames = <HppFrame>[];

    while (_buf.isNotEmpty) {
      if (_buf[0] != Hpp.sof) {
        _buf.removeAt(0);
        continue;
      }
      if (_buf.length >= 2 && _buf[1] != Hpp.version) {
        resyncs++;
        _buf.removeAt(0);
        continue;
      }
      if (_buf.length < Hpp.headerSize) break; // ヘッダ未完

      final len = _buf[4];
      if (len > Hpp.maxPayload) {
        resyncs++;
        _buf.removeAt(0);
        continue;
      }
      final total = Hpp.headerSize + len + Hpp.crcSize;
      if (_buf.length < total) break; // フレーム未完

      final body = total - Hpp.crcSize;
      final calc = hppCrc16(_buf, body);
      final recv = (_buf[body] << 8) | _buf[body + 1];
      if (calc != recv) {
        crcErrors++;
        _buf.removeAt(0);
        continue;
      }

      frames.add(HppFrame(
        _buf[2],
        _buf[3],
        Uint8List.fromList(_buf.sublist(Hpp.headerSize, Hpp.headerSize + len)),
      ));
      _buf.removeRange(0, total);
    }
    return frames;
  }

  void reset() => _buf.clear();
}
