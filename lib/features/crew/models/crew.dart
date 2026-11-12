import 'package:flutter/material.dart';

/// 크루를 대표하는 아이콘입니다. 서버(create_crew)와 같은 다섯 가지만 씁니다.
enum CrewIcon {
  bolt('bolt', '번개', Icons.bolt, Color(0xFFEAB308)),
  flame('flame', '불꽃', Icons.local_fire_department, Color(0xFFF97316)),
  mountain('mountain', '산', Icons.terrain, Color(0xFF22C55E)),
  wave('wave', '파도', Icons.waves, Color(0xFF38BDF8)),
  star('star', '별', Icons.star, Color(0xFF8B5CF6));

  const CrewIcon(this.code, this.label, this.icon, this.color);
  final String code;
  final String label;
  final IconData icon;
  final Color color;

  static CrewIcon fromCode(Object? code) =>
      values.where((icon) => icon.code == code).firstOrNull ?? CrewIcon.star;
}

class CrewMember {
  CrewMember.fromJson(Map<String, dynamic> json)
    : userId = json['user_id'] as String,
      nickname = json['nickname'] as String,
      isOwner = json['role'] == 'owner';

  final String userId;
  final String nickname;
  final bool isOwner;
}

class Crew {
  Crew.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      description = json['description'] as String? ?? '',
      icon = CrewIcon.fromCode(json['icon']),
      isOwner = json['is_owner'] as bool,
      sizeLimit = json['size_limit'] as int? ?? 30,
      members = List.unmodifiable([
        for (final row in json['members'] as List? ?? const [])
          CrewMember.fromJson(Map<String, dynamic>.from(row as Map)),
      ]),
      pending = Set.unmodifiable([
        for (final id in json['pending'] as List? ?? const []) id as String,
      ]);

  final String id;
  final String name;
  final String description;
  final CrewIcon icon;

  /// 내가 이 크루를 만든 크루장인지 여부입니다. 크루장만 초대할 수 있습니다.
  final bool isOwner;
  final int sizeLimit;
  final List<CrewMember> members;

  /// 크루장이 보낸, 아직 응답하지 않은 초대의 사용자 ID입니다.
  final Set<String> pending;

  bool hasMember(String userId) =>
      members.any((member) => member.userId == userId);
}

/// 내가 받은 크루 초대입니다.
class CrewInvite {
  CrewInvite.fromJson(Map<String, dynamic> json)
    : crewId = json['crew_id'] as String,
      name = json['name'] as String,
      description = json['description'] as String? ?? '',
      icon = CrewIcon.fromCode(json['icon']),
      inviter = json['inviter'] as String;

  final String crewId;
  final String name;
  final String description;
  final CrewIcon icon;
  final String inviter;
}

class CrewDashboard {
  CrewDashboard.fromJson(Map<String, dynamic> json)
    : crew = json['crew'] == null
          ? null
          : Crew.fromJson(Map<String, dynamic>.from(json['crew'] as Map)),
      invites = List.unmodifiable([
        for (final row in json['invites'] as List? ?? const [])
          CrewInvite.fromJson(Map<String, dynamic>.from(row as Map)),
      ]);

  final Crew? crew;
  final List<CrewInvite> invites;
}
