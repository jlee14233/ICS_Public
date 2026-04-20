import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/glider_log.dart';
import '../models/sensor_data.dart';
import '../models/performance_data.dart';
import '../models/waypoint_data.dart';
import '../models/map_data.dart';
import '../services/api_service.dart';

/// use_glider.txt 경로 – Discord Bot이 매일 02:58 KST에 갱신하는 Single Source of Truth
const String USE_GLIDER_FILE =
    // '\use_glider.txt';

class GliderProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  // ──── 동적 글라이더 관리 ────
  List<String> activeGliders = [];
  int _currentIndex = 0;

  // ──── Smart File Watcher ────
  DateTime? _lastFileModified;
  Timer? _fileWatchTimer;

  bool isLoading = false;

  GliderLogResponse? logData;
  SensorWebResponse? sensorData;
  PerformanceResponse? performanceData;
  WaypointResponse? waypointData;

  Map<String, GliderTrackResponse?> allTracks = {};
  AisResponse? aisData;

  // BBox Dynamic AIS Data
  final ValueNotifier<List<BBoxAisData>> currentBBoxAis = ValueNotifier([]);
  Timer? _aisDebounceTimer;

  String get currentGlider =>
      activeGliders.isNotEmpty && _currentIndex < activeGliders.length
          ? activeGliders[_currentIndex]
          : '';

  GliderProvider() {
    _initialize();
  }

  /// 초기화: 파일 로드 → 전체 데이터 로드 → File Watcher 시작
  Future<void> _initialize() async {
    await _loadActiveGlidersFromFile();
    if (activeGliders.isNotEmpty) {
      await loadAllData();
    }
    _startFileWatcher();
  }

  // ================================================================
  // Smart File Watcher (use_glider.txt)
  // ================================================================

  /// use_glider.txt를 Dart File API로 직접 읽어 activeGliders를 갱신한다.
  Future<void> _loadActiveGlidersFromFile() async {
    try {
      final file = File(USE_GLIDER_FILE);
      if (await file.exists()) {
        final modified = await file.lastModified();
        _lastFileModified = modified;

        final lines = await file.readAsLines();
        final newList = lines
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        activeGliders = newList;

        // 🚨 Index Out of Bounds 방어:
        // 리스트가 줄어들어 현재 인덱스가 범위를 벗어나면 첫 번째로 폴백
        if (_currentIndex >= activeGliders.length) {
          _currentIndex = 0;
        }
      } else {
        debugPrint('[FileWatcher] use_glider.txt not found');
        activeGliders = [];
        _currentIndex = 0;
      }
    } catch (e) {
      debugPrint('[FileWatcher] Failed to load active gliders: $e');
      activeGliders = [];
      _currentIndex = 0;
    }
    notifyListeners();
  }

  /// 10분 주기로 use_glider.txt의 lastModified를 체크.
  /// 파일이 변경된 경우에만 상태를 갱신한다. (I/O 부하 최소화)
  void _startFileWatcher() {
    _fileWatchTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) async {
        try {
          final file = File(USE_GLIDER_FILE);
          if (await file.exists()) {
            final modified = await file.lastModified();
            if (_lastFileModified == null ||
                modified.isAfter(_lastFileModified!)) {
              debugPrint('[FileWatcher] use_glider.txt changed – reloading...');
              await _loadActiveGlidersFromFile();
              if (activeGliders.isNotEmpty) {
                await loadAllData();
              }
            }
          }
        } catch (e) {
          debugPrint('[FileWatcher] Error: $e');
        }
      },
    );
  }

  // ================================================================
  // 글라이더 전환
  // ================================================================

  void switchGlider(int index) {
    if (activeGliders.isEmpty) return;
    if (index >= 0 && index < activeGliders.length) {
      _currentIndex = index;
      loadGliderSpecificData();
    }
  }

  void nextGlider() {
    if (activeGliders.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % activeGliders.length;
    loadGliderSpecificData();
  }

  // ================================================================
  // 데이터 로딩 (동적 루프 – 하드코딩 인덱스 제거)
  // ================================================================

  Future<void> loadAllData() async {
    if (activeGliders.isEmpty) return;

    isLoading = true;
    notifyListeners();

    // AIS 데이터 공통 로드
    aisData = await _apiService.fetchAisData();

    await loadGliderSpecificData();
  }

  Future<void> loadGliderSpecificData() async {
    if (activeGliders.isEmpty) return;

    isLoading = true;
    notifyListeners();

    final glider = currentGlider;

    // 현재 글라이더의 상세 데이터 로드
    final detailFutures = <Future>[
      _apiService.fetchGliderLog(glider),
      _apiService.fetchSensorWeb(glider),
      _apiService.fetchPerformance(glider),
      _apiService.fetchWaypoints(glider),
    ];

    // 🚨 동적 API 호출: activeGliders 전체의 트랙 데이터를 동적 루프로 요청
    final trackFutures = <Future<GliderTrackResponse?>>[];
    for (final g in activeGliders) {
      trackFutures.add(_apiService.fetchGliderTrack(g));
    }

    // 병렬 실행
    final detailResults = await Future.wait(detailFutures);
    final trackResults = await Future.wait(trackFutures);

    // 상세 데이터 할당
    logData = detailResults[0] as GliderLogResponse?;
    sensorData = detailResults[1] as SensorWebResponse?;
    performanceData = detailResults[2] as PerformanceResponse?;
    waypointData = detailResults[3] as WaypointResponse?;

    // 🚨 트랙 데이터 동적 할당 (하드코딩 인덱스 제거)
    allTracks.clear();
    for (int i = 0; i < activeGliders.length; i++) {
      allTracks[activeGliders[i]] = trackResults[i];
    }

    isLoading = false;
    notifyListeners();
  }

  // ================================================================
  // AIS BBox
  // ================================================================

  void updateAisBBox(double minLat, double maxLat, double minLon, double maxLon) {
    if (_aisDebounceTimer?.isActive ?? false) {
      _aisDebounceTimer!.cancel();
    }

    _aisDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final response = await _apiService.fetchAisDataByBBox(
            currentGlider, minLat, maxLat, minLon, maxLon);
        if (response != null && response.status == 'success') {
          currentBBoxAis.value = response.data;
        }
      } catch (e) {
        debugPrint("Failed to update AIS BBox: $e");
      }
    });
  }

  // ================================================================
  // 아카이브 트리거 (백엔드 API 연동)
  // ================================================================

  /// 현재 운용 중인 글라이더 미션을 아카이브로 이관한다.
  /// POST /api/archive/{gliderName}을 호출하여 백엔드에서 폴더 이동을 수행한다.
  Future<bool> archiveCurrentMission(String gliderName) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/archive/$gliderName');
      debugPrint('[Archive Trigger] POST $uri');

      final response = await HttpClient()
          .postUrl(uri)
          .then((request) {
            request.headers.contentType = ContentType.json;
            return request.close();
          });

      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        debugPrint('[Archive Trigger] 성공: ${data['message']}');
        return true;
      } else {
        debugPrint('[Archive Trigger] 실패: ${data['detail'] ?? body}');
        return false;
      }
    } catch (e) {
      debugPrint('[Archive Trigger] 네트워크 에러: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _fileWatchTimer?.cancel();
    _aisDebounceTimer?.cancel();
    super.dispose();
  }
}
