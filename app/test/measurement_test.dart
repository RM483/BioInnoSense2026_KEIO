/// Measurementドメインロジックの単体テスト。
import 'package:flutter_test/flutter_test.dart';
import 'package:hydropaw/features/measurement/domain/measurement.dart';

H2Sample sample(int i, {int flags = 0}) =>
    H2Sample(timeMs: i * 1000, h2Ppb: i * 100, tempC: 25, rh: 40, flags: flags);

void main() {
  group('decimateSeries', () {
    test('maxPoints以下はそのまま', () {
      final s = List.generate(100, sample);
      expect(decimateSeries(s, maxPoints: 600), hasLength(100));
    });

    test('超過時は等間隔にmaxPoints点へ間引く', () {
      final s = List.generate(1800, sample);
      final out = decimateSeries(s, maxPoints: 600);
      expect(out, hasLength(600));
      expect(out.first.timeMs, 0);
      // 最後の点は末尾近傍
      expect(out.last.timeMs, greaterThan(1790 * 1000 - 5000));
    });
  });

  group('H2Sample', () {
    test('ppb→ppm変換', () {
      expect(sample(15).h2Ppm, closeTo(1.5, 1e-9));
    });

    test('OUT_OF_RANGE/STUCKは無効サンプル', () {
      expect(sample(1).isValid, isTrue);
      expect(sample(1, flags: 0x01).isValid, isFalse); // OUT_OF_RANGE
      expect(sample(1, flags: 0x02).isValid, isFalse); // STUCK
      expect(sample(1, flags: 0x04).isValid, isTrue);  // WARMUPは有効(参考)
      expect(sample(1, flags: 0x04).isWarmup, isTrue);
    });
  });
}
