import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/alarm_provider.dart';
import '../models/alarm_data.dart';

/// 토스트 스택 위젯
/// 화면 우측 하단에 알람을 아래에서 위로 쌓아 표시합니다.
/// - info (초록색): 1초간 표시 후 자동 삭제 (AlarmProvider에서 처리)
/// - critical (빨간색): 깜빡임 애니메이션, ALARM_END 수신 전까지 무한 유지
class ToastStackWidget extends StatelessWidget {
  const ToastStackWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final alarmProvider = context.watch<AlarmProvider>();
    final alarms = alarmProvider.alarms;

    if (alarms.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: alarms.map((alarm) {
          if (alarm.level == 'critical') {
            return _CriticalToast(alarm: alarm);
          }
          return _InfoToast(alarm: alarm);
        }).toList(),
      ),
    );
  }
}

/// INFO 토스트 (부상=초록, 잠항=짙은 회청색으로 시각 분리)
class _InfoToast extends StatelessWidget {
  final AlarmData alarm;
  const _InfoToast({required this.alarm});

  @override
  Widget build(BuildContext context) {
    // 메시지에 "잠항"이 포함되면 잠항 스타일 적용
    final bool isSubmerge = alarm.msg.contains('잠항');
    final Color bgColor = isSubmerge
        ? const Color(0xFF37474F) // Blue Grey 800 (잠항)
        : const Color(0xFF2E7D32); // Green 800 (부상)
    final IconData icon = isSubmerge
        ? Icons.arrow_downward
        : Icons.info_outline;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: bgColor,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      alarm.glider.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alarm.msg,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 빨간색 CRITICAL 토스트 (무한 깜빡임 애니메이션)
class _CriticalToast extends StatefulWidget {
  final AlarmData alarm;
  const _CriticalToast({required this.alarm});

  @override
  State<_CriticalToast> createState() => _CriticalToastState();
}

class _CriticalToastState extends State<_CriticalToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _opacity = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AnimatedBuilder(
        animation: _opacity,
        builder: (context, child) {
          return Opacity(opacity: _opacity.value, child: child);
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFFC62828), // 진한 빨간색
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CRITICAL - ${widget.alarm.glider.toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.yellowAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.alarm.msg,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.alarm.timestamp,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
