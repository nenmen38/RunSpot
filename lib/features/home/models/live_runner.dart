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
    this.isFriend = false,
    this.frame,
    this.frameColor,
    this.paceSecPerKm,
  });

  factory LiveRunner.fromJson(Map<String, dynamic> json) => LiveRunner(
    id: json['user_id'] as String,
    nickname: json['nickname'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    distanceMeters: (json['distance_m'] as num).toDouble(),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    isFriend: json['is_friend'] as bool? ?? false,
    frame: switch ((json['frame'], json['frame_color'])) {
      ('basic' || 'aura', final String color)
          when RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color) =>
        json['frame'] as String,
      _ => null,
    },
    frameColor: json['frame_color'] as String?,
    paceSecPerKm: (json['pace_sec'] as num?)?.toInt(),
  );

  final String id;
  final String nickname;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final DateTime updatedAt;

  /// 서로 친구인 러너입니다. 오라 합체는 친구끼리만 합니다.
  final bool isFriend;

  /// 착용한 테두리 종류('basic' 또는 'aura')와 색(#RRGGBB)입니다. 형식이 맞을 때만 값이 있습니다.
  final String? frame;
  final String? frameColor;

  /// 친구가 달리는 중일 때의 현재 페이스(초/km)입니다.
  final int? paceSecPerKm;

  bool get hasAura => frame == 'aura';
}
