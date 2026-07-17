/// HPPコーデックの単体テスト。
/// C実装 (firmware/Tests/test_hpp.c) と同一テストベクタで相互検証する。
import 'package:flutter_test/flutter_test.dart';
import 'package:hydropaw/features/ble/data/hpp_codec.dart';

void main() {
  group('hppCrc16', () {
    test('C実装との相互検証ベクタ: A5 01 01 00 01 01 => 0x53CC', () {
      expect(hppCrc16([0xA5, 0x01, 0x01, 0x00, 0x01, 0x01]), 0x53CC);
    });
  });

  group('HppCodec.encode', () {
    test('CMD_START_CONT(interval=1) は8バイトの既知フレームになる', () {
      final f = HppCodec.encode(Hpp.cmdStartCont, 0, [1]);
      expect(f, [0xA5, 0x01, 0x01, 0x00, 0x01, 0x01, 0x53, 0xCC]);
    });

    test('ペイロード超過は例外', () {
      expect(() => HppCodec.encode(Hpp.evtData, 0, List.filled(49, 0)),
          throwsArgumentError);
    });
  });

  group('HppCodec.feed', () {
    test('ラウンドトリップ', () {
      final payload = List.generate(13, (i) => (i * 7) & 0xFF);
      final wire = HppCodec.encode(Hpp.evtData, 42, payload);
      final codec = HppCodec();
      final frames = codec.feed(wire);
      expect(frames, hasLength(1));
      expect(frames.first.type, Hpp.evtData);
      expect(frames.first.seq, 42);
      expect(frames.first.payload, payload);
    });

    test('BLE MTU分割(1バイトずつ)でも再組立できる', () {
      final wire = HppCodec.encode(Hpp.cmdStop, 1);
      final codec = HppCodec();
      final frames = <HppFrame>[];
      for (final b in wire) {
        frames.addAll(codec.feed([b]));
      }
      expect(frames, hasLength(1));
      expect(frames.first.type, Hpp.cmdStop);
    });

    test('ゴミ先行データから再同期する', () {
      final wire = HppCodec.encode(Hpp.cmdStop, 1);
      final codec = HppCodec();
      final frames =
          codec.feed([0x00, 0xFF, 0xA5, 0x99, 0x12, ...wire]);
      expect(frames, hasLength(1));
      expect(frames.first.type, Hpp.cmdStop);
    });

    test('CRC破損フレームを捨てて次の正常フレームを受理する', () {
      final wire = HppCodec.encode(Hpp.cmdSingle, 7);
      final bad = List<int>.from(wire)..[3] ^= 0xFF; // seq改竄
      final codec = HppCodec();
      final frames = codec.feed([...bad, ...wire]);
      expect(frames, hasLength(1));
      expect(frames.first.seq, 7);
      expect(codec.crcErrors, greaterThanOrEqualTo(1));
    });

    test('連続する複数フレームを一括デコードできる', () {
      final w1 = HppCodec.encode(Hpp.cmdStop, 1);
      final w2 = HppCodec.encode(Hpp.cmdSleep, 2);
      final codec = HppCodec();
      final frames = codec.feed([...w1, ...w2]);
      expect(frames.map((f) => f.seq), [1, 2]);
    });
  });

  group('HppFrame EVT_DATAアクセサ', () {
    test('リトルエンディアンで正しく読める', () {
      // t=5000ms, h2=1520ppb, temp=25.3℃, rh=41.0%, flags=WARMUP
      final payload = <int>[
        0x88, 0x13, 0x00, 0x00, // 5000 LE
        0xF0, 0x05, 0x00, 0x00, // 1520 LE
        0xFD, 0x00,             // 253 LE
        0x9A, 0x01,             // 410 LE
        0x04,                   // WARMUP
      ];
      final wire = HppCodec.encode(Hpp.evtData, 0, payload);
      final f = HppCodec().feed(wire).single;
      expect(f.dataTimeMs, 5000);
      expect(f.dataH2Ppb, 1520);
      expect(f.dataTempC, closeTo(25.3, 1e-9));
      expect(f.dataRh, closeTo(41.0, 1e-9));
      expect(f.dataFlags & Hpp.flagWarmup, isNonZero);
    });
  });
}
