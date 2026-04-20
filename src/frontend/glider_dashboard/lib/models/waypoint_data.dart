class WaypointResponse {
  final List<Waypoint> waypoints;

  WaypointResponse({required this.waypoints});

  factory WaypointResponse.fromJson(Map<String, dynamic> json) {
    return WaypointResponse(
      waypoints: (json['waypoints'] as List?)
              ?.map((e) => Waypoint.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class Waypoint {
  final double lat;
  final double lon;

  Waypoint({required this.lat, required this.lon});

  factory Waypoint.fromJson(Map<String, dynamic> json) {
    return Waypoint(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
