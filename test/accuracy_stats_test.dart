import 'package:flutter_test/flutter_test.dart';
import 'package:locationx_install_tool/services/accuracy_stats.dart';

void main() {
  test('percentile: 선형 보간', () {
    expect(AccuracyStats.percentile([1, 2, 3, 4, 5], 0.5), 3);
    expect(AccuracyStats.percentile([0, 10], 0.95), closeTo(9.5, 1e-9));
    expect(AccuracyStats.percentile([7], 0.95), 7);
  });

  test('of: 치우침·흩어짐·CEP', () {
    // 기준점 (0,0) · 표본은 (1,0) 주위 ±0.1
    final pts = [(1.1, 0.0), (0.9, 0.0), (1.0, 0.1), (1.0, -0.1)];
    final s = AccuracyStats.of(pts, (0.0, 0.0), 2)!;
    expect(s.samples, 4);
    expect(s.rate, 2);
    expect(s.meanError, closeTo(1.0, 1e-9)); // 평균 위치 (1,0)
    expect(s.spread, closeTo(0.1, 1e-9));
    expect(s.maxError, closeTo(1.1, 1e-9));
    expect(s.cep50, inInclusiveRange(0.9, 1.1));
    expect(AccuracyStats.of([], (0.0, 0.0), 1), isNull);
  });

  test('pool: 전체 CEP는 모든 표본, 치우침은 기준점 평균', () {
    final a = [(0.1, 0.0)], b = [(0.3, 0.0)];
    final sa = AccuracyStats.of(a, (0.0, 0.0), 1)!, sb = AccuracyStats.of(b, (0.0, 0.0), 1)!;
    final all = AccuracyStats.pool([
      (sa, AccuracyStats.errorsOf(a, (0.0, 0.0))),
      (sb, AccuracyStats.errorsOf(b, (0.0, 0.0))),
    ])!;
    expect(all.samples, 2);
    expect(all.meanError, closeTo(0.2, 1e-9));
    expect(all.maxError, closeTo(0.3, 1e-9));
    expect(all.cep50, closeTo(0.2, 1e-9));
  });

  test('CSV: 기준점 행 + 전체 행', () {
    final pts = [(0.1, 0.0), (0.2, 0.0)];
    final run = AccuracyRun(
      name: '기준선',
      at: DateTime(2026, 11, 18, 10),
      settings: 'aox=BASIC',
      points: [
        AccuracyPointResult(
            index: 1, x: 0, y: 0, z: 0,
            stats: AccuracyStats.of(pts, (0.0, 0.0), 2)!,
            errors: AccuracyStats.errorsOf(pts, (0.0, 0.0))),
      ],
    );
    final lines = accuracyRunsCsv([run]).trim().split('\n');
    expect(lines.length, 3);
    expect(lines[1], startsWith('"기준선",2026-11-18T10:00:00,"aox=BASIC",1,'));
    expect(lines[2], contains(',all,'));
  });
}
