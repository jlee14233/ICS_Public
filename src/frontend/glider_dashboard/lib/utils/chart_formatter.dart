import 'dart:math';
import 'package:intl/intl.dart';

class AxisConfig {
  final double min;
  final double max;
  final double interval;
  final int decimalPlaces;

  AxisConfig({
    required this.min,
    required this.max,
    required this.interval,
    required this.decimalPlaces,
  });
}

class ChartFormatter {
  /// 입력된 시간이 초(s) 단위인지 밀리초(ms) 단위인지 동적으로 판별하여 DateTime 객체로 변환합니다.
  static DateTime _parseDynamicTimestamp(double value) {
    int vInt = value.toInt();
    if (vInt < 0) vInt = 0;
    // 10,000,000,000 이하면 초(s) 단위로 간주하고 1000을 곱해 밀리초로 변환 (약 2286년까지 대응)
    bool isSeconds = (vInt < 10000000000);
    return DateTime.fromMillisecondsSinceEpoch(
      vInt * (isSeconds ? 1000 : 1),
    ).toLocal();
  }

  /// X축 눈금용으로 시간만 반환 (포맷: HH:mm)
  static String formatTimeOnly(double value) {
    final date = _parseDynamicTimestamp(value);
    return DateFormat('HH:mm').format(date);
  }

  /// 차트 우측 하단 뱃지용으로 날짜만 반환 (포맷: yyyy-MM-dd)
  static String formatDateOnly(double value) {
    final date = _parseDynamicTimestamp(value);
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// 차트 최소화 뱃지용 짧은 날짜 (포맷: MM/dd)
  static String formatShortDateOnly(double value) {
    final date = _parseDynamicTimestamp(value);
    return DateFormat('MM/dd').format(date);
  }

  /// 데이터의 최소/최대 값을 기반으로 읽기 좋은 형태의 축 설정 정보를 반환합니다.
  /// (MATLAB의 Axis Auto-Scaling 원리 차용 - "Nice Numbers" 알고리즘)
  /// [targetTicks] : 표시할 대략적인 축(Tick) 라벨 개수 (기본값 5)
  static AxisConfig getSmartAxis(
    double minData,
    double maxData, {
    int targetTicks = 5,
  }) {
    double range = maxData - minData;

    // 데이터 변동폭이 없을 경우 (스케일 에러 방어)
    if (range == 0) {
      if (minData == 0) {
        return AxisConfig(min: -1.0, max: 1.0, interval: 1.0, decimalPlaces: 0);
      }
      double pad = minData.abs() * 0.1;
      if (pad == 0) pad = 1.0;
      return AxisConfig(
        min: minData - pad,
        max: maxData + pad,
        interval: pad,
        decimalPlaces: _getDecimalPlaces(pad),
      );
    }

    // 1. 초기 간격 산출
    double rawStep = range / targetTicks;

    // 2. 10의 제곱수로 크기 정규화 (magnitude 찾아내기)
    double mag = pow(10, (log(rawStep) / ln10).floor()).toDouble();
    double normStep = rawStep / mag; // 1.0 ~ 10.0 사이의 값

    // 3. 사람이 읽기 좋은 'Nice Number' 맵핑 (1, 2, 2.5, 5, 10 단위)
    double niceStep;
    if (normStep < 1.5) {
      niceStep = 1.0;
    } else if (normStep < 2.25) {
      niceStep = 2.0;
    } else if (normStep < 3.0) {
      niceStep = 2.5;
    } else if (normStep < 7.5) {
      niceStep = 5.0;
    } else {
      niceStep = 10.0;
    }

    // 최종적인 최적의 눈금 간격 (Interval)
    double interval = niceStep * mag;

    // 4. 간격에 맞춰 상/하단 여백(Limit) 확장 처리
    double niceMin = (minData / interval).floor() * interval;
    double niceMax = (maxData / interval).ceil() * interval;

    // 소수점 자릿수 결정
    int decimalPlaces = _getDecimalPlaces(interval);

    return AxisConfig(
      min: niceMin,
      max: niceMax,
      interval: interval,
      decimalPlaces: decimalPlaces,
    );
  }

  /// 시계열(Time) 데이터 전용 X축 스마트 스케일러 (밀리초 단위 계산)
  static AxisConfig getSmartTimeAxis(
    double minMs,
    double maxMs, {
    bool tightFit = false,
  }) {
    double rangeMs = maxMs - minMs;
    // 만약 데이터가 1개뿐이거나 모두 동일한 시간이라면 최소 1시간 마진(±30분) 부여
    if (rangeMs <= 0) {
      minMs -= 1800000;
      maxMs += 1800000;
      rangeMs = maxMs - minMs;
    }

    // 여유 마진 (tightFit일 때는 2%로 살짝 늘려서 끝단 텍스트가 잘리지 않게 방어)
    double margin = rangeMs * (tightFit ? 0.02 : 0.01);

    // 1. interval 먼저 결정 (단기 데이터 눈금 최적화)
    double interval;
    if (rangeMs <= 0) {
      interval = 21600000.0; // 기본 6시간
    } else if (rangeMs <= 3600000) {
      interval = 600000.0; // 1시간 이내 -> 10분 (1-yo 최적화)
    } else if (rangeMs <= 10800000) {
      interval = 1800000.0; // 3시간 이내 -> 30분 (1-yo 최적화)
    } else if (rangeMs <= 43200000) {
      interval = 14400000.0; // 12시간 이내 -> 4시간
    } else if (rangeMs <= 86400000) {
      interval = 21600000.0; // 24시간 이내 -> 6시간
    } else {
      interval = 43200000.0; // 그 외 -> 12시간
    }

    double niceMin;
    double niceMax;

    if (tightFit) {
      // 1-yo 비행 데이터: 라벨 겹침보다 찌그러짐 방지가 중요하므로 강제 스냅 해제 (타이트하게 렌더링)
      niceMin = minMs - margin;
      niceMax = maxMs + margin;
    } else {
      // 전체 센서/맵 데이터: interval 배수로 깔끔하게 스냅 정렬 (라벨 겹침 원천 차단)
      niceMin = ((minMs - margin) / interval).floor() * interval;
      niceMax = ((maxMs + margin) / interval).ceil() * interval;
    }

    return AxisConfig(
      min: niceMin,
      max: niceMax,
      interval: interval,
      decimalPlaces: 0,
    );
  }

  /// interval 사이즈를 분석해서 소수점 자릿수를 알아서 추천해 줍니다.
  static int _getDecimalPlaces(double interval) {
    if (interval >= 1.0) return 0;
    if (interval >= 0.1) return 1;
    if (interval >= 0.01) return 2;
    if (interval >= 0.001) return 3;
    if (interval >= 0.0001) return 4;
    return 5;
  }
}
