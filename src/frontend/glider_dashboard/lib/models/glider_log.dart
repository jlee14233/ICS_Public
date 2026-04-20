// ==============================================================================
// [보안 처리됨] 프론트엔드 데이터 모델 추상화 (Data Model Abstraction)
// 본 모델은 제조사(SFMC)의 원시 센서 데이터(SBD/TBD) 구조 및 독점 로그 포맷의
// 파싱 키(Parsing Keys)맵핑 정보를 скры기 위해 백엔드에서 1차 가공된
// 범용 포맷만을 수신하도록 설계되었습니다.
// ==============================================================================

class GliderLogResponse {
  final String gliderName;
  final String? nextSurfaceTime;
  final List<LogEntry> logData;

  GliderLogResponse({
    required this.gliderName,
    this.nextSurfaceTime,
    required this.logData,
  });

  factory GliderLogResponse.fromJson(Map<String, dynamic> json) {
    return GliderLogResponse(
      gliderName: json['glider_name'] ?? '',
      nextSurfaceTime: json['next_surface_time'],
      logData:
          (json['log_data'] as List?)
              ?.map((e) => LogEntry.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class LogEntry {
  final DateTime? timestamp;

  LogEntry({this.timestamp});

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'])
          : null,
    );
  }
}
