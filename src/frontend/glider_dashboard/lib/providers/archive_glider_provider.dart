import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sensor_data.dart';
import '../models/map_data.dart';
import '../models/archive_mission.dart';

const String BASE_DIR =
     // 'src\backend';

class ArchiveGliderProvider extends ChangeNotifier {
  bool isLoading = false;
  DateTime? selectedDate;

  // 달력 표출용 (하루 단위 ratio + value)
  Map<DateTime, Map<String, dynamic>> dailyDataMap = {};

  // SensorFrame 및 MapFrame 공통 호환용 상태 변수
  String currentGlider = '';  // archived_missions/ 폴더 스캔으로 동적 설정
  String currentMission = '';
  List<ArchiveMissionModel> availableMissions = [];
  SensorWebResponse? sensorData;
  Map<String, dynamic> allTracks = {};
  List<dynamic> aisData = [];
  ValueNotifier<List<BBoxAisData>> currentBBoxAis = ValueNotifier([]);

  // ──── 아카이브 글라이더 (폴더 스캔 결과) ────
  List<String> archivedGliders = [];

  // ──── 전역 미션 통합 리스트 (허브 테이블용) ────
  List<ArchiveMissionModel> allArchivedMissions = [];
  bool isLoadingAllMissions = false;

  ArchiveGliderProvider() {
    _initialize();
  }

  /// 초기화: 아카이브 폴더 스캔 → 전역 미션 통합 스캔 → 개별 미션 스캔
  Future<void> _initialize() async {
    await _scanArchivedGliders();
    await scanAllMissions();
    if (currentGlider.isNotEmpty) {
      await scanAvailableMissions();
    }
  }

  // ================================================================
  // 아카이브 글라이더 폴더 스캔 (Flat 구조)
  // ================================================================

  /// archived_missions/ 하위 미션 폴더명({glider}_{start}_{end})을 파싱하여
  /// 고유 글라이더 이름 목록(archivedGliders)을 추출한다.
  Future<void> _scanArchivedGliders() async {
    try {
      final archiveRoot = '$BASE_DIR\\archived_missions';
      final dir = Directory(archiveRoot);

      if (await dir.exists()) {
        final Set<String> gliderSet = {};
        await for (final entity in dir.list()) {
          if (entity is Directory) {
            final folderName =
                entity.path.split(Platform.pathSeparator).last;
            // 폴더명 파싱: {glider}_{startDate}_{endDate}
            // 마지막 2개(_로 구분)가 날짜이므로 앞쪽을 글라이더명으로 추출
            final parts = folderName.split('_');
            if (parts.length >= 4) {
              final gliderName = parts.sublist(0, parts.length - 2).join('_');
              gliderSet.add(gliderName);
            }
          }
        }
        final gliders = gliderSet.toList()..sort();
        archivedGliders = gliders;

        // Race Condition 방어: currentGlider가 외부(상세 화면)에서 이미 유효한 값으로
        // 주입된 경우, 리스트에 존재한다면 기존 값을 유지한다.
        // 빈 값이거나 리스트에 없는 경우에만 첫 번째 항목으로 Fallback한다.
        if (currentGlider.isEmpty || !archivedGliders.contains(currentGlider)) {
          currentGlider =
              archivedGliders.isNotEmpty ? archivedGliders.first : '';
        }
      } else {
        debugPrint(
            '[Archive] archived_missions directory not found: $archiveRoot');
        archivedGliders = [];
        currentGlider = '';
      }
    } catch (e) {
      debugPrint('[Archive] Error scanning archived gliders: $e');
      archivedGliders = [];
      currentGlider = '';
    }
    notifyListeners();
  }

  // ================================================================
  // 글라이더 / 미션 전환
  // ================================================================

  /// 관제사가 드롭다운에서 글라이더를 변경했을 때 호출.
  /// 글라이더 변경은 미션 변경보다 상위 수준의 리셋이다.
  void changeGlider(String newGlider) {
    if (newGlider == currentGlider) return;

    // 전체 하위 상태 초기화
    currentGlider = newGlider;
    currentMission = '';
    availableMissions = [];
    selectedDate = null;
    sensorData = null;
    allTracks = {};
    dailyDataMap = {};
    notifyListeners();

    // 새 글라이더 기준으로 미션 스캔 → 달력 로드
    scanAvailableMissions();
  }

  /// 관제사가 드롭다운에서 미션을 변경했을 때 호출
  void changeMission(String newMission) {
    if (newMission == currentMission) return;

    // 기존 데이터 초기화
    currentMission = newMission;
    selectedDate = null;
    sensorData = null;
    allTracks = {};
    dailyDataMap = {};
    notifyListeners();

    // 새 미션의 달력 데이터 로드
    loadCalendarSummary();
  }

  // ================================================================
  // 전역 미션 통합 스캔 (허브 데이터베이스용) — Flat 구조
  // ================================================================

  /// archived_missions/ 하위 폴더를 직접 스캔하여
  /// allArchivedMissions에 통합하고 회수일(archivedDate) 내림차순 정렬한다.
  Future<void> scanAllMissions() async {
    isLoadingAllMissions = true;
    notifyListeners();

    try {
      final List<ArchiveMissionModel> aggregated = [];
      final archiveRoot = '$BASE_DIR\\archived_missions';
      final dir = Directory(archiveRoot);

      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is Directory) {
            final folderName = entity.path.split(Platform.pathSeparator).last;
            final stat = await entity.stat();
            final archivedDate = stat.modified;

            aggregated.add(
              ArchiveMissionModel.fromFolderName(
                folderName,
                archivedDate: archivedDate,
              ),
            );
          }
        }
      }

      // 회수일(archivedDate) 기준 최신 데이터가 상단에 위치하도록 내림차순 정렬
      aggregated.sort((a, b) => b.archivedDate.compareTo(a.archivedDate));
      allArchivedMissions = aggregated;

      debugPrint('[Archive Hub] 전역 미션 통합 스캔 완료: ${allArchivedMissions.length}건');
    } catch (e) {
      debugPrint('[Archive Hub] 전역 미션 스캔 에러: $e');
      allArchivedMissions = [];
    } finally {
      isLoadingAllMissions = false;
      notifyListeners();
    }
  }

  // ================================================================
  // 개별 글라이더 미션 스캔 및 데이터 로드
  // ================================================================

  /// Flat 구조에서 currentGlider에 해당하는 미션만 필터링한다.
  /// allArchivedMissions를 재활용하여 회수일(archivedDate) 내림차순 정렬한다.
  Future<void> scanAvailableMissions() async {
    try {
      // allArchivedMissions가 비어있으면 먼저 전역 스캔 수행
      if (allArchivedMissions.isEmpty) {
        await scanAllMissions();
      }

      // currentGlider에 해당하는 미션만 필터링
      final missions = allArchivedMissions
          .where((m) => m.gliderName == currentGlider)
          .toList();

      // 회수일 기준 내림차순 정렬 (최신 회수 데이터가 상단)
      missions.sort((a, b) => b.archivedDate.compareTo(a.archivedDate));

      availableMissions = missions;

      if (availableMissions.isNotEmpty) {
        currentMission = availableMissions.first.folderName;
      } else {
        currentMission = '';
      }

      debugPrint('Scanned missions for $currentGlider: ${availableMissions.map((m) => m.folderName).toList()}');
      debugPrint('Selected mission: $currentMission');
    } catch (e) {
      debugPrint('Error scanning missions: $e');
      availableMissions = [];
      currentMission = '';
    }

    notifyListeners();

    // 미션이 결정되면 달력 데이터 로드
    if (currentMission.isNotEmpty) {
      await loadCalendarSummary();
    }
  }

  Future<void> loadCalendarSummary() async {
    try {
      final snapshotDir =
          '$BASE_DIR\\archived_missions\\$currentMission\\snapshot_JSON';
      final summaryFile = File('$snapshotDir\\archive_calendar_summary.json');

      if (await summaryFile.exists()) {
        final summaryStr = await summaryFile.readAsString();
        final Map<String, dynamic> summaryJson = jsonDecode(summaryStr);

        dailyDataMap.clear();

        summaryJson.forEach((dateStr, data) {
          final date = DateTime.tryParse(dateStr);
          if (date != null && data is Map<String, dynamic>) {
            final ratio = data['ratio'];
            final value = data['value'];
            dailyDataMap[date] = {
              'ratio': ratio != null ? (ratio as num).toDouble() : null,
              'value': value != null ? (value as num).toDouble() : null,
            };
          }
        });
      } else {
        debugPrint('Calendar summary file not found at: ${summaryFile.path}');
        dailyDataMap = {};
      }
    } catch (e) {
      debugPrint('Error loading calendar summary: $e');
      dailyDataMap = {};
    } finally {
      notifyListeners();
    }
  }

  Future<void> fetchArchiveDataForDate(DateTime date) async {
    selectedDate = date;
    isLoading = true;
    notifyListeners();

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final snapshotDir =
          '$BASE_DIR\\archived_missions\\$currentMission\\snapshot_JSON';

      final sensorFile = File('$snapshotDir\\${currentGlider}_sensor.json');
      final trackFile = File('$snapshotDir\\${currentGlider}_track.json');

      if (await sensorFile.exists()) {
        final sensorJsonStr = await sensorFile.readAsString();
        final sensorJson = jsonDecode(sensorJsonStr);
        final fullSensorData = SensorWebResponse.fromJson(sensorJson);

        // 선택한 날짜에 해당하는 sci_data만 필터링
        Map<String, DailySensorData> filteredSciData = {};
        if (fullSensorData.sciData.containsKey(dateStr)) {
          filteredSciData[dateStr] = fullSensorData.sciData[dateStr]!;
        }
        sensorData = SensorWebResponse(sciData: filteredSciData);
      } else {
        sensorData = null;
      }

      if (await trackFile.exists()) {
        final trackJsonStr = await trackFile.readAsString();
        final trackJson = jsonDecode(trackJsonStr);
        final trackData = GliderTrackResponse.fromJson(trackJson);
        allTracks = {currentGlider: trackData};
      } else {
        allTracks = {};
      }
    } catch (e) {
      debugPrint('Archive Fetch Error: $e');
      sensorData = null;
      allTracks = {};
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // AIS On/Off 토글 시 빈 함수 (더미)
  void updateAisBBox(double south, double north, double west, double east) {}
}
