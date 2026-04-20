import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/glider_provider.dart';
import '../providers/archive_glider_provider.dart';
import '../models/map_data.dart';

class MapFrame extends StatefulWidget {
  final bool isArchiveMode;
  const MapFrame({super.key, this.isArchiveMode = false});

  @override
  State<MapFrame> createState() => _MapFrameState();
}

class _MapFrameState extends State<MapFrame> {
  bool _showAIS = false; // AIS 데이터 토글 (기본 Off)
  bool _isMapReady = false; // 플러터 맵 초기화 상태

  double? _startMs;
  double? _endMs;
  double? _prevMaxMs;
  bool _isRangeInitialized = false;

  final MapController _mapController = MapController();
  double _currentZoom = 8.5;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  bool _isPointInRange(DateTime? pointDate) {
    if (pointDate == null || _startMs == null || _endMs == null) return false;
    final ms = pointDate.toLocal().millisecondsSinceEpoch.toDouble();
    return ms >= _startMs! && ms <= _endMs!;
  }

  Color _getVesselColor(int vmtc) {
    if (vmtc < 8) return const Color(0xFF008000).withOpacity(0.5); // 원활 (녹색)
    if (vmtc < 15) return const Color(0xFFFFFF00).withOpacity(0.6); // 보통 (황색)
    if (vmtc < 22) return const Color(0xFFFFA500).withOpacity(0.7); // 혼잡 (오렌지색)
    return const Color(0xFFFF0000).withOpacity(0.8); // 매우 혼잡 (적색)
  }

  @override
  Widget build(BuildContext context) {
    final dynamic provider = widget.isArchiveMode 
        ? context.watch<ArchiveGliderProvider>() 
        : context.watch<GliderProvider>();
    final allTracks = provider.allTracks;
    final aisData = provider.aisData;

    final Map<String, Color> gliderColors = {
      'kg_1105': Colors.blue,
      'kg_1167': Colors.redAccent,
      'kg_1219': Colors.green,
    };

    DateTime? minTime;
    DateTime? maxTime;

    allTracks.forEach((name, trackData) {
      if (trackData == null) return;
      final allP = [...trackData.pastTrackHistory, ...trackData.trackHistory];
      for (var pt in allP) {
        if (pt.timestamp != null) {
          if (minTime == null || pt.timestamp!.isBefore(minTime!)) {
            minTime = pt.timestamp;
          }
          if (maxTime == null || pt.timestamp!.isAfter(maxTime!)) {
            maxTime = pt.timestamp;
          }
        }
      }
    });

    minTime ??= DateTime.now().subtract(const Duration(days: 7));
    maxTime ??= DateTime.now();

    double computedMinMs = minTime!.millisecondsSinceEpoch.toDouble();
    double computedMaxMs = maxTime!.millisecondsSinceEpoch.toDouble();
    if (computedMinMs >= computedMaxMs) {
      computedMinMs -= 3600000;
      computedMaxMs += 3600000;
    }

    if (!_isRangeInitialized) {
      _endMs = computedMaxMs;
      _startMs = math.max(computedMinMs, computedMaxMs - 72.0 * 3600000.0);
      _prevMaxMs = computedMaxMs; // ✅ 초기화 시 최대 시간 기록
      _isRangeInitialized = true;
    } else {
      // ✅ 핵심 픽스: 새로운 데이터가 수신되어 최대 시간이 늘어난 경우
      if (_prevMaxMs != null && computedMaxMs > _prevMaxMs!) {
        _endMs = computedMaxMs; // 끝점을 최신 시간으로 강제 스냅(Snap)
        _prevMaxMs = computedMaxMs; // 최대 시간 갱신
      }

      if (_startMs! < computedMinMs) _startMs = computedMinMs;
      if (_endMs! > computedMaxMs) _endMs = computedMaxMs;
      if (_startMs! > _endMs!) _startMs = _endMs!;
    }

    List<Polyline> polylines = [];
    List<CircleMarker> circleMarkers = [];
    List<Marker> markers = [];
    LatLng? mapCenter;

    // 1. 글라이더 궤적 빌드 (3기 모두)
    allTracks.forEach((name, trackData) {
      if (trackData == null) return;

      final color = gliderColors[name] ?? Colors.black;
      List<LatLng> points = [];

      final allPoints = [
        ...trackData.pastTrackHistory,
        ...trackData.trackHistory,
      ];

      for (var pt in allPoints) {
        if (_isPointInRange(pt.timestamp)) {
          final latLng = LatLng(pt.lat, pt.lon);
          points.add(latLng);
          // 꺾이는 지점 (포인트 표기)
          circleMarkers.add(
            CircleMarker(
              point: latLng,
              color: Colors.yellow, // 노란색 부상 포인트
              radius: 4.5, // 눈에 잘 띄게 반지름 확장
            ),
          );
        }
      }

      if (points.isNotEmpty) {
        polylines.add(
          Polyline(
            points: points,
            color: color.withOpacity(0.6), // 옅은 색 투명도
            strokeWidth: 1.5, // 굵기 축소
          ),
        );
      }

      // 최신 위치 마커
      if (trackData.latestPosition != null &&
          _isPointInRange(trackData.latestPosition!.timestamp)) {
        final latLng = LatLng(
          trackData.latestPosition!.lat,
          trackData.latestPosition!.lon,
        );
        mapCenter ??= latLng;

        final heading = trackData.heading?.toDouble() ?? 0.0;
        final timeStr = trackData.latestPosition!.timestamp != null
            ? DateFormat(
                'MM/dd HH:mm',
              ).format(trackData.latestPosition!.timestamp!.toLocal())
            : 'N/A';
        final latStr = latLng.latitude.toStringAsFixed(4);
        final lonStr = latLng.longitude.toStringAsFixed(4);

        // 줌 레벨에 비례하여 마커 크기 조정 (기본 크기를 키우고 줌인 시 더 커지게)
        double baseSize = 48.0; // 기본 크기를 32 -> 48로 확대
        double scaleFactor = _currentZoom / 7.0;
        double iconSize = baseSize * scaleFactor;
        // 너무 작아지거나 커지는 것을 방지 (Max: 100, Min: 24)
        iconSize = iconSize.clamp(24.0, 100.0);

        // 서쪽(좌측)을 향할 때 이미지가 배면 비행(뒤집어짐)처럼 보이는 것을 막기 위한 플래그
        bool isFacingLeft =
            (heading % 360.0) > 180.0 && (heading % 360.0) < 360.0;

        markers.add(
          Marker(
            point: latLng,
            width: iconSize + 110, // 아이콘 크기에 맞춰 넉넉하게 확장
            height: iconSize + 80, // 이름표를 감싸기 위해 높이 추가
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // 글라이더 이미지 에셋 대체 및 회전, 그리고 방향에 따른 상하 반전 처리
                Transform.rotate(
                  angle:
                      (heading - 90) *
                      (math.pi / 180), // 이미지 원본이 우측을 보므로 -90도 오프셋 보정
                  child: Transform.scale(
                    scaleY: isFacingLeft
                        ? -1.0
                        : 1.0, // 좌측을 바라볼 때 이미지가 뒤집어지는 것(배면 비행) 방지
                    child: Image.asset(
                      'assets/images/glider_150.png',
                      width: iconSize,
                      height: iconSize,
                      filterQuality:
                          FilterQuality.high, // 축소/확대 시 계단현상(깨짐) 방지스무딩
                      isAntiAlias: true, // 안티앨리어싱 강제 적용
                    ),
                  ),
                ),
                // 오버레이 텍스트 라벨 (Semantic Zoom: Animated Fade-in)
                Positioned(
                  top: 80, // 아이콘을 완전히 벗어나 아래로 배치 (고정 여백)
                  child: AnimatedOpacity(
                    opacity: _currentZoom >= 7.5 ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: color.withOpacity(0.8),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors
                                .black54, // 밝은 지도 바탕에서도 쉽게 식별 가능한 흑색 반투명 박스
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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

      // 웨이포인트 스팟 마커
      if (trackData.waypoints != null) {
        trackData.waypoints!.forEach((key, wpt) {
          markers.add(
            Marker(
              point: LatLng(wpt.lat, wpt.lon),
              width: 30,
              height: 30,
              child: Icon(Icons.flag, color: color.withOpacity(0.5), size: 16),
            ),
          );
        });
      }
    });

    // 2. AIS 데이터 생성 부분 제거 (아래 빌더 내로 이동됨)

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      elevation: 4,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isArchiveMode ? 'Mission Map (Archive)' : 'Mission Map (Tracks & AIS)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (!widget.isArchiveMode)
                  Row(
                    children: [
                      const Text(
                        'AIS 연동',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Switch(
                        value: _showAIS,
                        activeColor: Colors.blue,
                        onChanged: (val) {
                          setState(() {
                            _showAIS = val;
                          });
                          // 토글 켤 때 현재 화면 BBox 기준으로 데이터 즉시 1회 요청 (맵이 렌더링 된 상태일 때만)
                          if (val && _isMapReady) {
                            final bounds = _mapController.camera.visibleBounds;
                            provider.updateAisBBox(
                              bounds.south,
                              bounds.north,
                              bounds.west,
                              bounds.east,
                            );
                          }
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: mapCenter ?? const LatLng(37.5, 131.0),
                    initialZoom: _currentZoom,
                    minZoom: 5.5,
                    maxZoom: 10.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                    onMapReady: () {
                      setState(() {
                        _isMapReady = true;
                      });
                    },
                    onPositionChanged: (camera, hasGesture) {
                      // position을 camera로 명칭 변경 (v8 규격)
                      if (hasGesture && camera.zoom != _currentZoom) {
                        setState(() {
                          _currentZoom = camera.zoom;
                        });
                      }
                      // ✅ _mapController를 통해 안전하게 현재 화면의 경계값(visibleBounds)을 추출
                      if (_showAIS && _isMapReady) {
                        final bounds = _mapController.camera.visibleBounds;
                        provider.updateAisBBox(
                          bounds.south,
                          bounds.north,
                          bounds.west,
                          bounds.east,
                        );
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      // urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}', //구글지도
                      urlTemplate:
                          'https://server.arcgisonline.com/ArcGIS/rest/services/Ocean/World_Ocean_Base/MapServer/tile/{z}/{y}/{x}', //ArcGIS
                      userAgentPackageName: 'com.glider.dashboard',
                    ),
                    ValueListenableBuilder<List<BBoxAisData>>(
                      valueListenable: provider.currentBBoxAis,
                      builder: (context, currentBBoxAis, child) {
                        List<Polygon> polygons = [];
                        if (_showAIS && currentBBoxAis.isNotEmpty) {
                          for (var vessel in currentBBoxAis) {
                            if (vessel.vmtc <= 0) continue;
                            List<LatLng> boxPoints = vessel.box
                                .map((p) => LatLng(p[0], p[1]))
                                .toList();
                            if (boxPoints.isNotEmpty) {
                              final polyColor = _getVesselColor(vessel.vmtc);
                              polygons.add(
                                Polygon(
                                  points: boxPoints,
                                  color: polyColor,
                                  borderColor: polyColor.withOpacity(1.0),
                                  borderStrokeWidth: 1.0,
                                ),
                              );
                            }
                          }
                        }
                        return PolygonLayer(polygons: polygons);
                      },
                    ),
                    PolylineLayer(polylines: polylines),
                    CircleLayer(circles: circleMarkers), // 꺾이는 지점 표기 레이어
                    MarkerLayer(markers: markers),
                  ],
                ),
                // 시간 필터 RangeSlider 오버레이 (좌측 상단 안쪽)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                        ),
                      ],
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.history,
                              size: 10,
                              color: Colors.blueGrey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_startMs!.toInt()))} ~ ${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_endMs!.toInt()))}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: 200, // 전체 라인 텍스트와 맞춰 축소
                          height: 20, // 높이도 타이트하게 축소
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              rangeThumbShape: const RoundRangeSliderThumbShape(
                                enabledThumbRadius: 6,
                              ), // 포인터 크기 대폭 축소
                              trackHeight: 2.0, // 줄기 두께
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ), // 포인터 주변 투명 효과 축소
                            ),
                            child: RangeSlider(
                              values: RangeValues(_startMs!, _endMs!),
                              min: computedMinMs,
                              max: computedMaxMs,
                              activeColor: Colors.blue,
                              inactiveColor: Colors.grey.withOpacity(0.7),
                              onChanged: (values) {
                                setState(() {
                                  _startMs = values.start;
                                  _endMs = values.end;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Folium Example HTML 기준 범례(Legend) 오버레이 - AIS On일 때만 표기
                if (_showAIS)
                  Positioned(
                    bottom: 20,
                    left: 20,
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        border: Border.all(color: Colors.grey, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '교통량 (Density)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: const [
                              Icon(
                                Icons.square,
                                color: Color(0xFFFF0000),
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '22척 이상 (매우 혼잡)',
                                style: TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                          Row(
                            children: const [
                              Icon(
                                Icons.square,
                                color: Color(0xFFFFA500),
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '15척~22척 (혼잡)',
                                style: TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                          Row(
                            children: const [
                              Icon(
                                Icons.square,
                                color: Color(0xFFFFFF00),
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '8척~15척 (보통)',
                                style: TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                          Row(
                            children: const [
                              Icon(
                                Icons.square,
                                color: Color(0xFF008000),
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '8척 미만 (원활)',
                                style: TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '─ 0.1도 그리드 적용됨\n─ 격자 레벨 약 2.3km x 2.8km',
                            style: TextStyle(color: Colors.grey, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
