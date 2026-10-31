class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.recordedAt,
    this.altitude,
    this.altitudeAccuracy,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime recordedAt;
  final double? altitude;
  final double? altitudeAccuracy;

  bool get isUsable =>
      latitude.isFinite &&
      longitude.isFinite &&
      accuracy.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      accuracy >= 0 &&
      accuracy <= 100 &&
      DateTime.now().difference(recordedAt).abs() < const Duration(minutes: 1);
}

class LiveRunner {
  const LiveRunner({
    required this.id,
    required this.nickname,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.updatedAt,
  });

  factory LiveRunner.fromJson(Map<String, dynamic> json) => LiveRunner(
    id: json['user_id'] as String,
    nickname: json['nickname'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    distanceMeters: (json['distance_m'] as num).toDouble(),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final String id;
  final String nickname;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final DateTime updatedAt;
}
