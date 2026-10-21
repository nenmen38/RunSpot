class GroupMember {
  GroupMember.fromJson(Map<String, dynamic> json)
    : userId = json['user_id'] as String,
      nickname = json['nickname'] as String,
      status = json['status'] as String,
      ready = json['ready'] == true,
      distance = json['distance_m'] as int?,
      seconds = json['duration_sec'] as int?,
      clientRunId = json['client_run_id'] as String?;
  final String userId;
  final String nickname;
  final String status;
  final bool ready;
  final int? distance;
  final int? seconds;
  final String? clientRunId;
}

class RunningGroup {
  RunningGroup.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      hostId = json['host_id'] as String,
      state = json['state'] as String,
      myStatus = json['my_status'] as String,
      startsAt = json['starts_at'] == null
          ? null
          : DateTime.parse(json['starts_at'] as String),
      members = (json['members'] as List)
          .map(
            (row) =>
                GroupMember.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
  final String id;
  final String hostId;
  final String state;
  final String myStatus;
  final DateTime? startsAt;
  final List<GroupMember> members;
  bool get active =>
      state == 'lobby' || state == 'scheduled' || state == 'running';
}

class GroupDashboard {
  GroupDashboard.fromJson(Map<String, dynamic> json)
    : serverNow = DateTime.parse(json['server_now'] as String),
      groups = (json['groups'] as List)
          .map(
            (row) =>
                RunningGroup.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
  final DateTime serverNow;
  final List<RunningGroup> groups;
}
