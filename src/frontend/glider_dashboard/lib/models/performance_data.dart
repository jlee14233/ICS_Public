class PerformanceResponse {
  final List<PerformanceEntry> performanceData;

  PerformanceResponse({required this.performanceData});

  factory PerformanceResponse.fromJson(Map<String, dynamic> json) {
    return PerformanceResponse(
      performanceData: (json['performance_data'] as List?)
              ?.map((e) => PerformanceEntry.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class PerformanceEntry {
  final int yoIndex;
  final DateTime? startTime;
  final DateTime? endTime;
  final double? velocityCmps;
  final double? glideRatio;
  final double? offTrackDistanceM;

  PerformanceEntry({
    required this.yoIndex,
    this.startTime,
    this.endTime,
    this.velocityCmps,
    this.glideRatio,
    this.offTrackDistanceM,
  });

  factory PerformanceEntry.fromJson(Map<String, dynamic> json) {
    return PerformanceEntry(
      yoIndex: json['yo_index'] ?? 0,
      startTime: json['start_time'] != null ? DateTime.tryParse(json['start_time']) : null,
      endTime: json['end_time'] != null ? DateTime.tryParse(json['end_time']) : null,
      velocityCmps: (json['velocity_cmps'] as num?)?.toDouble(),
      glideRatio: (json['glide_ratio'] as num?)?.toDouble(),
      offTrackDistanceM: (json['off_track_distance_m'] as num?)?.toDouble(),
    );
  }
}
