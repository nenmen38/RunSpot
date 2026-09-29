class UserProfile {
  final String id;
  final String nickname;
  final String? phoneNumber;
  final bool isPhoneVerified;
  final String visibility; // 'ALL' | 'FRIENDS_ONLY' | 'PRIVATE'
  final String role;       // 'RUNNER' | 'ADMIN'
  final String titleBadge;

  UserProfile({
    required this.id,
    required this.nickname,
    this.phoneNumber,
    required this.isPhoneVerified,
    required this.visibility,
    required this.role,
    required this.titleBadge,
  });

  factory UserProfile.fromMap(Map map) {
    return UserProfile(
      id: map['id'],
      nickname: map['nickname'] ?? '러너',
      phoneNumber: map['phone_number'],
      isPhoneVerified: map['is_phone_verified'] ?? false,
      visibility: map['visibility'] ?? 'PRIVATE',
      role: map['role'] ?? 'RUNNER',
      titleBadge: map['title_badge'] ?? '초보 러너',
    );
  }

  Map toMap() {
    return {
      'nickname': nickname,
      'visibility': visibility,
    };
  }
}