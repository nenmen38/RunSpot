import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State {
  final supabase = Supabase.instance.client;
  UserProfile? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  // [1] 실제 사용자 정보 Supabase에서 페칭
  Future _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (data == null) {
        // 최초 진입 시 기본 프로필 자동 생성
        final defaultProfile = {
          'id': user.id,
          'nickname': '러너_${user.id.substring(0, 5)}',
          'is_phone_verified': false,
          'visibility': 'PRIVATE',
          'role': 'RUNNER',
          'title_badge': '초보 러너'
        };
        await supabase.from('profiles').insert(defaultProfile);
        setState(() {
          _profile = UserProfile.fromMap(defaultProfile);
          _isLoading = false;
        });
      } else {
        setState(() {
          _profile = UserProfile.fromMap(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('프로필 로드 에러: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  // [2] 닉네임 수정 기능 연결
  Future _updateNickname(String newNickname) async {
    if (newNickname.trim().isEmpty || _profile == null) return;

    try {
      await supabase
          .from('profiles')
          .update({'nickname': newNickname.trim()})
          .eq('id', _profile!.id);

      await _loadUserProfile();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('닉네임 수정 실패 (중복 여부 확인): $e')),
      );
    }
  }

  // [4] 인증 완료 후 공개 범위 선택 활성화 검증
  Future _updateVisibility(String scope) async {
    if (_profile == null) return;

    // 클라이언트 사이드 방어: 미인증자는 PRIVATE 외 설정 불가
    if (!_profile!.isPhoneVerified && scope != 'PRIVATE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전화번호 인증 완료 후 전체/친구 공개가 활성화됩니다.')),
      );
      return;
    }

    try {
      await supabase
          .from('profiles')
          .update({'visibility': scope})
          .eq('id', _profile!.id);

      await _loadUserProfile();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공개 범위 변경 실패: $e')),
      );
    }
  }

  void _showNicknameDialog() {
    final controller = TextEditingController(text: _profile?.nickname);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('닉네임 수정'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '새 닉네임 입력 (2~15자)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(
            onPressed: () => _updateNickname(controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_profile == null) {
      return const Scaffold(
        body: Center(child: Text('로그인 세션을 찾을 수 없습니다.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('내 러닝 프로필')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 1 & 2. 실제 닉네임 바인딩 및 수정 버튼
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(_profile!.nickname.isNotEmpty ? _profile!.nickname[0] : 'R'),
              ),
              title: Text(_profile!.nickname, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              subtitle: Text('칭호: ${_profile!.titleBadge}'),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: _showNicknameDialog,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. 전화번호 인증 여부 표시
          ListTile(
            leading: Icon(
              _profile!.isPhoneVerified ? Icons.verified : Icons.error_outline,
              color: _profile!.isPhoneVerified ? Colors.green : Colors.orange,
            ),
            title: const Text('전화번호 인증 상태'),
            subtitle: Text(_profile!.isPhoneVerified
                ? '본인 인증 완료 (${_profile!.phoneNumber ?? '연동됨'})'
                : '공개 위치 브로드캐스팅을 위해 인증이 필요합니다.'),
            trailing: Chip(
              label: Text(
                _profile!.isPhoneVerified ? '인증완료' : '미인증',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              backgroundColor: _profile!.isPhoneVerified ? Colors.green : Colors.grey,
            ),
          ),
          const Divider(),

          // 4. 인증 완료 후 공개 범위 선택 활성화
          Opacity(
            opacity: _profile!.isPhoneVerified ? 1.0 : 0.4,
            child: IgnorePointer(
              ignoring: !_profile!.isPhoneVerified,
              child: ListTile(
                leading: const Icon(Icons.share_location),
                title: const Text('러닝 위치 공개 범위'),
                subtitle: Text(_profile!.isPhoneVerified
                    ? '현재: ${_profile!.visibility}'
                    : '전화번호 인증 후 활성화됩니다.'),
                trailing: DropdownButton(
                  value: _profile!.visibility,
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('전체 공개')),
                    DropdownMenuItem(value: 'FRIENDS_ONLY', child: Text('친구 공개')),
                    DropdownMenuItem(value: 'PRIVATE', child: Text('나만 보기')),
                  ],
                  onChanged: (val) {
                    if (val != null) _updateVisibility(val);
                  },
                ),
              ),
            ),
          ),

          // 5. 관리자에게만 관리 탭 표시
          if (_profile!.role == 'ADMIN') ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings, color: Colors.redAccent),
              title: const Text('관리자 대시보드', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('시스템 현황 및 유저 관리'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('관리자 모드로 진입합니다.')),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}