import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/glider_log.dart';
import '../models/sensor_data.dart';
import '../models/performance_data.dart';
import '../models/waypoint_data.dart';
import '../models/map_data.dart';

class ApiService {
  // 실제 백엔드 주소로 변경 필요. 
  // FastAPI 개발 서버 기본 주소 가정
  static const String baseUrl = 'http://localhost:8000';

  Future<GliderLogResponse?> fetchGliderLog(String gliderName) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/data/$gliderName/log'));
      if (response.statusCode == 200) {
        return GliderLogResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      print('Error fetching log data: $e');
    }
    return null;
  }

  Future<SensorWebResponse?> fetchSensorWeb(String gliderName) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/data/$gliderName/sensor_web'));
      if (response.statusCode == 200) {
        return SensorWebResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      print('Error fetching sensor web data: $e');
    }
    return null;
  }

  Future<PerformanceResponse?> fetchPerformance(String gliderName) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/data/$gliderName/performance'));
      if (response.statusCode == 200) {
        return PerformanceResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      print('Error fetching performance data: $e');
    }
    return null;
  }

  Future<WaypointResponse?> fetchWaypoints(String gliderName) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/data/$gliderName/waypoints'));
      // waypoints JSON이 배열 바로 시작하는 형태라면 파싱이 좀 다를 수 있으나
      // 구현상 {"waypoints": [...]} 임
      if (response.statusCode == 200) {
        return WaypointResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      print('Error fetching waypoints data: $e');
    }
    return null;
  }

  Future<GliderTrackResponse?> fetchGliderTrack(String gliderName) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/data/$gliderName/glider_track'));
      if (response.statusCode == 200) {
        return GliderTrackResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      print('Error fetching glider track data: $e');
    }
    return null;
  }

  Future<AisResponse?> fetchAisData() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/data/ais'));
      if (response.statusCode == 200) {
        return AisResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      print('Error fetching ais data: $e');
    }
    return null;
  }

  Future<BBoxAisResponse?> fetchAisDataByBBox(String gliderName, double minLat, double maxLat, double minLon, double maxLon) async {
    try {
      final uri = Uri.parse('$baseUrl/api/ais/bbox').replace(queryParameters: {
        'glider_name': gliderName,
        'min_lat': minLat.toString(),
        'max_lat': maxLat.toString(),
        'min_lon': minLon.toString(),
        'max_lon': maxLon.toString(),
      });
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return BBoxAisResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (e) {
      print('Error fetching AIS data by BBox: $e');
    }
    return null;
  }
}
