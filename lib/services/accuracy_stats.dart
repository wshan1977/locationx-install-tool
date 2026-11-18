import 'dart:math' as math;

/// 정확도 측정 통계 — 기준점(실제 위치를 아는 곳)에 태그를 두고 positioning이
/// 낸 위치 표본으로 계산한다. 모두 수평(x, y) 기준, 단위 m.
///
/// - meanError: 표본 평균 위치와 기준점 사이 거리 (치우침 · 보정·자세 오차가 여기 나타남)
/// - spread: 표본들이 평균 위치에서 흩어진 정도 (2D RMS · 흔들림)
/// - cep50 / cep95: 표본 하나하나의 오차를 줄 세웠을 때 50% / 95% 지점
///   ("표본의 절반은 cep50 안에 든다")
class AccuracyStats {
  final int samples;
  final double seconds;
  final double meanError;
  final double spread;
  final double cep50;
  final double cep95;
  final double maxError;

  const AccuracyStats({
    required this.samples,
    required this.seconds,
    required this.meanError,
    required this.spread,
    required this.cep50,
    required this.cep95,
    required this.maxError,
  });

  /// 초당 표본 수 (위치 갱신율).
  double get rate => seconds > 0 ? samples / seconds : 0;

  /// 표본별 오차 목록 (기준점까지 거리).
  static List<double> errorsOf(List<(double, double)> pts, (double, double) target) =>
      [for (final p in pts) math.sqrt(_sq(p.$1 - target.$1) + _sq(p.$2 - target.$2))];

  /// 기준점 1곳의 통계 (표본이 없으면 null).
  static AccuracyStats? of(
      List<(double, double)> pts, (double, double) target, double seconds) {
    if (pts.isEmpty) return null;
    final n = pts.length;
    final mx = pts.fold<double>(0, (a, p) => a + p.$1) / n;
    final my = pts.fold<double>(0, (a, p) => a + p.$2) / n;
    final spread = math.sqrt(
        pts.fold<double>(0, (a, p) => a + _sq(p.$1 - mx) + _sq(p.$2 - my)) / n);
    final errors = errorsOf(pts, target)..sort();
    return AccuracyStats(
      samples: n,
      seconds: seconds,
      meanError: math.sqrt(_sq(mx - target.$1) + _sq(my - target.$2)),
      spread: spread,
      cep50: percentile(errors, 0.5),
      cep95: percentile(errors, 0.95),
      maxError: errors.last,
    );
  }

  /// 여러 기준점을 합친 전체 통계: CEP·최대는 모든 표본 오차로, 치우침·흩어짐은
  /// 기준점별 값의 평균(치우침) / RMS(흩어짐)로 낸다.
  static AccuracyStats? pool(List<(AccuracyStats, List<double>)> parts) {
    if (parts.isEmpty) return null;
    final all = [for (final p in parts) ...p.$2]..sort();
    if (all.isEmpty) return null;
    final k = parts.length;
    return AccuracyStats(
      samples: parts.fold(0, (a, p) => a + p.$1.samples),
      seconds: parts.fold(0.0, (a, p) => a + p.$1.seconds),
      meanError: parts.fold<double>(0, (a, p) => a + p.$1.meanError) / k,
      spread: math.sqrt(parts.fold<double>(0, (a, p) => a + _sq(p.$1.spread)) / k),
      cep50: percentile(all, 0.5),
      cep95: percentile(all, 0.95),
      maxError: all.last,
    );
  }

  /// 정렬된 값의 분위수 (선형 보간, q = 0..1).
  static double percentile(List<double> sorted, double q) {
    if (sorted.isEmpty) return double.nan;
    if (sorted.length == 1) return sorted.first;
    final pos = q.clamp(0.0, 1.0) * (sorted.length - 1);
    final lo = pos.floor(), hi = pos.ceil();
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }

  static double _sq(double v) => v * v;
}

/// 측정 묶음 1개 (예: "기준선", "고정밀 모드") — 기준점별 결과 + 전체.
class AccuracyRun {
  final String name;
  final DateTime at;

  /// 측정 당시 설정 요약 (예: "aox=HIGH_ACCURACY · 높이고정=0.0 · 튐제거=15°")
  final String settings;
  final List<AccuracyPointResult> points;
  final AccuracyStats? overall;

  AccuracyRun({
    required this.name,
    required this.at,
    required this.settings,
    required this.points,
  }) : overall = AccuracyStats.pool([for (final p in points) (p.stats, p.errors)]);
}

class AccuracyPointResult {
  final int index; // 기준점 번호 (1부터)
  final double x, y, z;
  final AccuracyStats stats;
  final List<double> errors;

  AccuracyPointResult({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    required this.stats,
    required this.errors,
  });
}

/// 측정 묶음들을 CSV로 (엑셀에서 바로 열리게 UTF-8 BOM은 호출 쪽에서 붙인다).
String accuracyRunsCsv(List<AccuracyRun> runs) {
  String f(double v) => v.isNaN ? '' : v.toStringAsFixed(3);
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  final b = StringBuffer(
      'run,time,settings,point,x,y,z,samples,rate_hz,mean_error_m,spread_m,cep50_m,cep95_m,max_error_m\n');
  for (final r in runs) {
    final t = r.at.toIso8601String().substring(0, 19);
    void row(String point, double? x, double? y, double? z, AccuracyStats s) {
      b.writeln([
        q(r.name), t, q(r.settings), point,
        x == null ? '' : f(x), y == null ? '' : f(y), z == null ? '' : f(z),
        s.samples, s.rate.toStringAsFixed(2), f(s.meanError), f(s.spread),
        f(s.cep50), f(s.cep95), f(s.maxError),
      ].join(','));
    }

    for (final p in r.points) {
      row('${p.index}', p.x, p.y, p.z, p.stats);
    }
    if (r.overall != null) row('all', null, null, null, r.overall!);
  }
  return b.toString();
}
