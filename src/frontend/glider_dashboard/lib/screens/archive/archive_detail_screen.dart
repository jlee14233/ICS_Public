import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'widgets/water_level_calendar.dart';
import '../../widgets/sensor_frame.dart';
import '../../widgets/map_frame.dart';
import '../../providers/archive_glider_provider.dart';

/// 아카이브 상세 대시보드 화면.
/// 허브(ArchiveHubScreen)에서 미션을 클릭하면 이 화면으로 진입한다.
/// 달력, 센서 프레임, 지도 프레임을 포함한 기존 상세 UI를 그대로 보존한다.
class ArchiveDetailScreen extends StatelessWidget {
  /// 허브에서 전달받는 글라이더 이름
  final String gliderName;

  /// 허브에서 전달받는 미션 폴더명
  final String initialFolderName;

  const ArchiveDetailScreen({
    Key? key,
    required this.gliderName,
    required this.initialFolderName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // Race Condition 방어: Cascade operator로 생성 즉시 값 주입.
      // _initialize()의 비동기 스캔보다 먼저 currentGlider/currentMission이
      // 설정되므로, _scanArchivedGliders의 Fallback이 이 값을 덮어쓰지 않는다.
      create: (_) => ArchiveGliderProvider()
        ..currentGlider = gliderName
        ..currentMission = initialFolderName,
      child: _ArchiveDetailContent(
        gliderName: gliderName,
        initialFolderName: initialFolderName,
      ),
    );
  }
}

class _ArchiveDetailContent extends StatefulWidget {
  final String gliderName;
  final String initialFolderName;

  const _ArchiveDetailContent({
    Key? key,
    required this.gliderName,
    required this.initialFolderName,
  }) : super(key: key);

  @override
  State<_ArchiveDetailContent> createState() => _ArchiveDetailContentState();
}

class _ArchiveDetailContentState extends State<_ArchiveDetailContent> {
  @override
  void initState() {
    super.initState();
    // Provider 생성 및 _initialize() 완료 후, 주입된 미션에 대한
    // 드롭다운 목록 + 달력 데이터를 명시적으로 로드한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ArchiveGliderProvider>();
      // scanAvailableMissions()는 내부에서 loadCalendarSummary()를
      // 호출하므로, 드롭다운 목록과 달력 데이터가 한 번에 채워진다.
      provider.scanAvailableMissions();
    });
  }

  /// 달력의 시작 월을 계산해주는 헬퍼 함수
  DateTime _getInitialMonth(Map<DateTime, Map<String, dynamic>> dailyData) {
    if (dailyData.isEmpty) return DateTime.now();

    final sortedDates = dailyData.keys.toList()..sort();
    return sortedDates.last;
  }

  @override
  Widget build(BuildContext context) {
    final archiveProvider = context.watch<ArchiveGliderProvider>();
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Glider Data Archive'),
        backgroundColor: Colors.blueGrey,
        actions: [
          // ──── 1) 글라이더 선택 드롭다운 ────
          if (archiveProvider.archivedGliders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: Text(
                  '아카이브 글라이더 없음',
                  style: TextStyle(fontSize: 14, color: Colors.redAccent),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: archiveProvider.currentGlider.isNotEmpty
                      ? archiveProvider.currentGlider
                      : null,
                  icon: const Icon(Icons.precision_manufacturing,
                      color: Colors.white, size: 18),
                  dropdownColor: Colors.blueGrey[800],
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                  items: archiveProvider.archivedGliders
                      .map(
                        (glider) => DropdownMenuItem<String>(
                          value: glider,
                          child: Text(glider),
                        ),
                      )
                      .toList(),
                  onChanged: (newGlider) {
                    if (newGlider != null) {
                      archiveProvider.changeGlider(newGlider);
                    }
                  },
                ),
              ),
            ),

          // ──── 구분선 ────
          const SizedBox(
            height: 24,
            child: VerticalDivider(
                color: Colors.white38, width: 1, thickness: 1),
          ),

          // ──── 2) 미션 선택 드롭다운 ────
          if (archiveProvider.availableMissions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: Text(
                  '미션 스캔 중...',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: archiveProvider.currentMission.isNotEmpty
                      ? archiveProvider.currentMission
                      : null,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  dropdownColor: Colors.blueGrey[700],
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  items: archiveProvider.availableMissions
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m.folderName,
                          child: Text(m.folderName),
                        ),
                      )
                      .toList(),
                  onChanged: (newMission) {
                    if (newMission != null) {
                      archiveProvider.changeMission(newMission);
                    }
                  },
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top: WaterLevelCalendar (넉넉한 배치 - 전체 화면의 약 1/3 ~ 1/2.5)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                child: WaterLevelCalendar(
                  dailyData: archiveProvider.dailyDataMap,
                  selectedDate: archiveProvider.selectedDate,
                  initialMonth: _getInitialMonth(archiveProvider.dailyDataMap),
                  onDateSelected: (selectedDate) {
                    archiveProvider.fetchArchiveDataForDate(selectedDate);
                  },
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1),
            // Body: MapFrame & SensorFrame (전체 화면의 약 2/3)
            Expanded(
              flex: 5,
              child: archiveProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: const [
                                Expanded(
                                  flex: 1,
                                  child: MapFrame(isArchiveMode: true),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: SensorFrame(isArchiveMode: true),
                                ),
                              ],
                            )
                          : Column(
                              children: const [
                                Expanded(
                                  flex: 1,
                                  child: MapFrame(isArchiveMode: true),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: SensorFrame(isArchiveMode: true),
                                ),
                              ],
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
