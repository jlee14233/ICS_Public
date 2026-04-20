import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/alarm_data.dart';

/// WebSocket 서비스
/// 백엔드(ws://localhost:8000/ws)에 연결하여 알람 이벤트를 수신합니다.
/// 자동 재연결 로직을 포함합니다.
class WebSocketService {
  static const String _wsUrl = 'ws://localhost:8000/ws';
  static const int _maxRetries = 10;
  static const Duration _retryDelay = Duration(seconds: 5);

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _retryCount = 0;
  bool _disposed = false;

  /// 알람 타입 이벤트만 필터링하여 전달하는 콜백
  final void Function(AlarmData alarm)? onAlarmReceived;

  /// DATA_UPDATED 이벤트 수신 시 프론트엔드 새로고침 트리거용 콜백
  final void Function(String glider)? onDataUpdated;

  WebSocketService({this.onAlarmReceived, this.onDataUpdated});

  /// WebSocket 연결 시작
  void connect() {
    if (_disposed) return;
    _tryConnect();
  }

  void _tryConnect() {
    try {
      debugPrint('[WS] Connecting to $_wsUrl...');
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _retryCount = 0;
      debugPrint('[WS] Connected successfully');
    } catch (e) {
      debugPrint('[WS] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      final Map<String, dynamic> data = jsonDecode(message as String);
      final type = data['type'] as String?;

      // 프론트엔드 알람 전용 타입만 필터링
      if (type == 'ALARM_INFO' || type == 'ALARM_START' || type == 'ALARM_END') {
        final alarm = AlarmData.fromJson(data);
        onAlarmReceived?.call(alarm);
      }

      // 데이터 갱신 이벤트: 파싱 완료 후 차트/맵 새로고침 트리거
      if (type == 'DATA_UPDATED') {
        final glider = data['glider'] as String? ?? '';
        onDataUpdated?.call(glider);
      }
    } catch (e) {
      debugPrint('[WS] Message parse error: $e');
    }
  }

  void _onError(dynamic error) {
    debugPrint('[WS] Error: $error');
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[WS] Connection closed');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_retryCount >= _maxRetries) {
      debugPrint('[WS] Max retries ($_maxRetries) reached. Stopping.');
      return;
    }

    _retryCount++;
    debugPrint('[WS] Reconnecting in ${_retryDelay.inSeconds}s (attempt $_retryCount/$_maxRetries)...');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_retryDelay, () {
      _subscription?.cancel();
      _channel?.sink.close();
      _tryConnect();
    });
  }

  /// WebSocket 연결 해제 및 리소스 정리
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
  }
}
