import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/alarm_data.dart';
import '../services/websocket_service.dart';

/// 알람 상태 관리 Provider
/// WebSocket으로 수신한 알람의 라이프사이클(추가/자동삭제/강제삭제)을 관리합니다.
/// - info: 10초간 표시 후 자동 삭제 (AlarmProvider에서 처리, 부상=초록/잠항=회청)
class AlarmProvider extends ChangeNotifier {
  final List<AlarmData> _alarms = [];
  late final WebSocketService _wsService;

  /// 가장 최근 수신된 알람 (화면 전환 트리거용)
  AlarmData? _latestAlarm;
  AlarmData? get latestAlarm => _latestAlarm;

  /// DATA_UPDATED 수신 시 외부에서 등록할 콜백 (DashboardScreen에서 loadAllData 호출용)
  VoidCallback? onDataRefreshRequested;

  /// DATA_UPDATED로 갱신된 글라이더 이름
  String? _lastUpdatedGlider;
  String? get lastUpdatedGlider => _lastUpdatedGlider;

  List<AlarmData> get alarms => List.unmodifiable(_alarms);

  AlarmProvider() {
    _wsService = WebSocketService(
      onAlarmReceived: _handleAlarm,
      onDataUpdated: _handleDataUpdated,
    );
    _wsService.connect();
  }

  void _handleDataUpdated(String glider) {
    _lastUpdatedGlider = glider;
    onDataRefreshRequested?.call();
  }

  void _handleAlarm(AlarmData alarm) {
    switch (alarm.type) {
      case 'ALARM_INFO':
        _addInfoAlarm(alarm);
        break;
      case 'ALARM_START':
        _addCriticalAlarm(alarm);
        break;
      case 'ALARM_END':
        _removeCriticalAlarm(alarm);
        break;
    }
  }

  /// info 알람: 리스트에 추가 후 10초 뒤 자동 삭제
  void _addInfoAlarm(AlarmData alarm) {
    _alarms.add(alarm);
    _latestAlarm = alarm;
    notifyListeners();

    Timer(const Duration(seconds: 10), () {
      _alarms.remove(alarm);
      notifyListeners();
    });
  }

  /// critical 알람: 리스트에 추가 (무한 유지, 타이머 없음)
  void _addCriticalAlarm(AlarmData alarm) {
    _alarms.add(alarm);
    _latestAlarm = alarm;
    notifyListeners();
  }

  /// critical 알람 해제: 동일 glider + level의 ALARM_START를 찾아 삭제
  void _removeCriticalAlarm(AlarmData endSignal) {
    _alarms.removeWhere((a) => a.matchesEndSignal(endSignal));
    notifyListeners();
  }

  @override
  void dispose() {
    _wsService.dispose();
    super.dispose();
  }
}
