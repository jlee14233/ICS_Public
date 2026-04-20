// ==============================================================================
// [보안 처리됨] 프론트엔드 센서 모델 추상화 (Sensor Profile Abstraction)
// 본 모델은 해양물리/생지화학 센서의 원시 바이너리(DAT 엔진 출력) 구조를 숨기고,
// 백엔드에서 Depth Binning 및 Downsampling이 완료된 "시각화 전용 규격"만을
// 수용하도록 설계되었습니다. 원천 센서의 Sampling Rate 및 채널 정보는 비공개입니다.
// ==============================================================================

class SensorWebResponse {
  final Map<String, DailySensorData> sciData;

  SensorWebResponse({required this.sciData});

  factory SensorWebResponse.fromJson(Map<String, dynamic> json) {
    var sciMap = json['sci_data'] as Map<String, dynamic>? ?? {};
    var processedMap = <String, DailySensorData>{};
    
    sciMap.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        processedMap[key] = DailySensorData.fromJson(value);
      }
    });

    return SensorWebResponse(sciData: processedMap);
  }
}

class DailySensorData {
  final SensorProfile fullProfile;
  final SensorValues temperature;
  final SensorValues salinity;
  final SensorValues oxygen;
  final SensorValues chlorophyll;
  final SensorValues density;
  final SensorValues par;

  DailySensorData({
    required this.fullProfile,
    required this.temperature,
    required this.salinity,
    required this.oxygen,
    required this.chlorophyll,
    required this.density,
    required this.par,
  });

  factory DailySensorData.fromJson(Map<String, dynamic> json) {
    return DailySensorData(
      fullProfile: SensorProfile.fromJson(json['full_profile'] ?? {}),
      temperature: SensorValues.fromJson(json['temperature'] ?? {}),
      salinity: SensorValues.fromJson(json['salinity'] ?? {}),
      oxygen: SensorValues.fromJson(json['oxygen'] ?? {}),
      chlorophyll: SensorValues.fromJson(json['chlorophyll'] ?? {}),
      density: SensorValues.fromJson(json['density'] ?? {}),
      par: SensorValues.fromJson(json['par'] ?? {}),
    );
  }
}

class SensorProfile {
  final List<int> time;
  final List<double> pres;

  SensorProfile({required this.time, required this.pres});

  factory SensorProfile.fromJson(Map<String, dynamic> json) {
    return SensorProfile(
      time: (json['time'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [],
      pres: (json['pres'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
    );
  }
}

class SensorValues {
  final List<int> time;
  final List<double> pres;
  final List<double> value;

  SensorValues({required this.time, required this.pres, required this.value});

  factory SensorValues.fromJson(Map<String, dynamic> json) {
    return SensorValues(
      time: (json['time'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [],
      pres: (json['pres'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
      value: (json['value'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
    );
  }
}
