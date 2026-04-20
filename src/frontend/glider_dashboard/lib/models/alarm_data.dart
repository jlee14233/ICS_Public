/// 알람 데이터 모델
/// 백엔드 WebSocket에서 수신하는 ALARM_INFO, ALARM_START, ALARM_END 이벤트를 파싱합니다.
class AlarmData {
  final String type;      // ALARM_INFO, ALARM_START, ALARM_END
  final String glider;    // 글라이더 이름 
  final String level;     // info, critical
  final String msg;       // 알람 메시지 (ALARM_END에는 빈 문자열)
  final String timestamp; // KST 기준 yyyy-mm-dd HH:MM:SS

  AlarmData({
    required this.type,
    required this.glider,
    required this.level,
    this.msg = '',
    this.timestamp = '',
  });

  factory AlarmData.fromJson(Map<String, dynamic> json) {
    return AlarmData(
      type: json['type'] as String? ?? '',
      glider: json['glider'] as String? ?? '',
      level: json['level'] as String? ?? 'info',
      msg: json['msg'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
    );
  }

  /// critical 알람 매칭용 (ALARM_END가 ALARM_START를 찾을 때 사용)
  bool matchesEndSignal(AlarmData endSignal) {
    return glider == endSignal.glider && level == endSignal.level && type == 'ALARM_START';
  }
}
