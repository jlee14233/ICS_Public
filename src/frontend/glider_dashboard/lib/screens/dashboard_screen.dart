import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/glider_provider.dart';
import '../providers/alarm_provider.dart';
import '../widgets/sensor_frame.dart';
import '../widgets/map_frame.dart';
import '../widgets/flight_frame.dart';
import '../widgets/toast_stack_widget.dart';
import 'archive/archive_dashboard_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();

    // 이벤트 기반 자동 포커싱: ALARM_INFO 또는 ALARM_START 수신 시 해당 글라이더 탭으로 전환
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final alarmProvider = context.read<AlarmProvider>();
      alarmProvider.addListener(() {
        final latest = alarmProvider.latestAlarm;
        if (latest == null) return;

        // ALARM_INFO 또는 ALARM_START일 때만 탭 전환
        if (latest.type == 'ALARM_INFO' || latest.type == 'ALARM_START') {
          final gliderProvider = context.read<GliderProvider>();
          // 🚨 동적 인덱스 조회: 하드코딩 매핑 대신 activeGliders에서 indexOf
          final targetIndex =
              gliderProvider.activeGliders.indexOf(latest.glider);
          if (targetIndex != -1 &&
              gliderProvider.currentGlider != latest.glider) {
            gliderProvider.switchGlider(targetIndex);
          }
        }
      });

      // DATA_UPDATED 이벤트 수신 시 자동 새로고침
      alarmProvider.onDataRefreshRequested = () {
        debugPrint('[Dashboard] DATA_UPDATED 수신 → 데이터 자동 새로고침');
        context.read<GliderProvider>().loadAllData();
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<GliderProvider>(
          builder: (context, provider, child) {
            return Text('Glider Control Room - ${provider.currentGlider}');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<GliderProvider>().loadAllData();
            },
            tooltip: 'Refresh Data',
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ArchiveHubScreen(),
                ),
              );
            },
            tooltip: 'Archive Management Hub',
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: () {
              context.read<GliderProvider>().nextGlider();
            },
            tooltip: 'Next Glider',
          ),
        ],
      ),
      body: Stack(
        children: [
          // 기존 대시보드 레이아웃
          Consumer<GliderProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading && provider.sensorData == null) {
                return const Center(child: CircularProgressIndicator());
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  bool isWide = constraints.maxWidth > 800;

                  if (!isWide) {
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          SizedBox(height: 300, child: const SensorFrame()),
                          SizedBox(height: 300, child: const MapFrame()),
                          SizedBox(height: 300, child: const FlightFrame()),
                        ],
                      ),
                    );
                  }

                  return Center(
                    child: AspectRatio(
                      aspectRatio: 8 / 3,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Expanded(child: SensorFrame()),
                          const Expanded(child: MapFrame()),
                          const Expanded(child: FlightFrame()),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          // 토스트 스택 오버레이 (우측 하단)
          const ToastStackWidget(),
        ],
      ),
    );
  }
}
