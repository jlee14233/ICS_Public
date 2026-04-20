class GliderTrackResponse {
  final String name;
  final List<GpsPoint> trackHistory;
  final List<GpsPoint> pastTrackHistory;
  final GpsPoint? latestPosition;
  final num? heading;
  final Map<String, GpsPoint>? waypoints;

  GliderTrackResponse({
    required this.name,
    required this.trackHistory,
    required this.pastTrackHistory,
    this.latestPosition,
    this.heading,
    this.waypoints,
  });

  factory GliderTrackResponse.fromJson(Map<String, dynamic> json) {
    var latest = json['latest_position'];
    num? headingVal;
    if (latest != null && latest['heading'] != null) {
      headingVal = latest['heading'];
    }

    Map<String, GpsPoint>? wpts;
    if (json['waypoints'] != null && json['waypoints'] is Map) {
      wpts = {};
      (json['waypoints'] as Map<String, dynamic>).forEach((key, value) {
        wpts![key] = GpsPoint.fromJson(value);
      });
    }

    return GliderTrackResponse(
      name: json['name'] ?? '',
      trackHistory: (json['track_history'] as List?)
              ?.map((e) => GpsPoint.fromJson(e))
              .toList() ??
          [],
      pastTrackHistory: (json['past_track_history'] as List?)
              ?.map((e) => GpsPoint.fromJson(e))
              .toList() ??
          [],
      latestPosition: latest != null ? GpsPoint.fromJson(latest) : null,
      heading: headingVal,
      waypoints: wpts,
    );
  }
}

class GpsPoint {
  final double lat;
  final double lon;
  final DateTime? timestamp;

  GpsPoint({required this.lat, required this.lon, this.timestamp});

  factory GpsPoint.fromJson(Map<String, dynamic> json) {
    return GpsPoint(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'])
          : null,
    );
  }
}

class AisResponse {
  final List<GliderAisData> gliders;

  AisResponse({required this.gliders});

  factory AisResponse.fromJson(Map<String, dynamic> json) {
    return AisResponse(
      gliders: (json['gliders'] as List?)
              ?.map((e) => GliderAisData.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class GliderAisData {
  final String name;
  final AisData? ais;

  GliderAisData({required this.name, this.ais});

  factory GliderAisData.fromJson(Map<String, dynamic> json) {
    return GliderAisData(
      name: json['name'] ?? '',
      ais: json['ais'] != null ? AisData.fromJson(json['ais']) : null,
    );
  }
}

class AisData {
  final DateTime? timestamp;
  final List<VesselData> vessels;

  AisData({this.timestamp, required this.vessels});

  factory AisData.fromJson(Map<String, dynamic> json) {
    return AisData(
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'])
          : null,
      vessels: (json['vessels'] as List?)
              ?.map((e) => VesselData.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class VesselData {
  final String gridId;
  final double lat;
  final double lon;
  final int vmtc;
  final double density;
  final List<List<double>> box;

  VesselData({
    required this.gridId,
    required this.lat,
    required this.lon,
    required this.vmtc,
    required this.density,
    required this.box,
  });

  factory VesselData.fromJson(Map<String, dynamic> json) {
    List<List<double>> parsedBox = [];
    if (json['box'] != null) {
      for (var point in json['box']) {
        if (point is List && point.length >= 2) {
          parsedBox.add([
            (point[0] as num).toDouble(),
            (point[1] as num).toDouble()
          ]);
        }
      }
    }

    return VesselData(
      gridId: json['grid_id'] ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      vmtc: json['vmtc'] ?? 0,
      density: (json['density'] as num?)?.toDouble() ?? 0.0,
      box: parsedBox,
    );
  }
}

// 신규 BBox 기반 AIS 데이터 모델
class BBoxAisResponse {
  final String status;
  final int count;
  final List<BBoxAisData> data;

  BBoxAisResponse({required this.status, required this.count, required this.data});

  factory BBoxAisResponse.fromJson(Map<String, dynamic> json) {
    return BBoxAisResponse(
      status: json['status'] ?? '',
      count: json['count'] ?? 0,
      data: (json['data'] as List?)?.map((e) => BBoxAisData.fromJson(e)).toList() ?? [],
    );
  }
}

class BBoxAisData {
  final String gridId;
  final int vmtc;
  final double density;
  final List<double> center;
  final List<List<double>> box;
  final double size;

  BBoxAisData({
    required this.gridId,
    required this.vmtc,
    required this.density,
    required this.center,
    required this.box,
    required this.size,
  });

  factory BBoxAisData.fromJson(Map<String, dynamic> json) {
    List<double> parsedCenter = [];
    if (json['center'] != null) {
      for (var c in json['center']) {
        parsedCenter.add((c as num).toDouble());
      }
    }

    List<List<double>> parsedBox = [];
    if (json['box'] != null) {
      for (var point in json['box']) {
        if (point is List && point.length >= 2) {
          parsedBox.add([
            (point[0] as num).toDouble(),
            (point[1] as num).toDouble()
          ]);
        }
      }
    }

    return BBoxAisData(
      gridId: json['grid_id'] ?? '',
      vmtc: json['vmtc'] ?? 0,
      density: (json['dnsty'] as num?)?.toDouble() ?? 0.0,
      center: parsedCenter,
      box: parsedBox,
      size: (json['size'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
