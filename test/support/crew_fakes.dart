import 'package:runquest/features/crew/data/crew_service.dart';
import 'package:runquest/features/crew/models/crew.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'wallet_fakes.dart';

/// 서버 규칙(생성권·크루장 초대·한 크루만 가입)을 흉내 내는 크루 서비스입니다.
class FakeCrewService implements CrewService {
  FakeCrewService({this.wallet});

  /// 크루를 만들면 생성권을 쓰고 크루에 들어간 상태로 바꿉니다.
  final FakeWalletService? wallet;
  Map<String, dynamic>? crew;
  List<Map<String, dynamic>> invites = [];
  final calls = <String>[];

  CrewDashboard get _dashboard =>
      CrewDashboard.fromJson({'crew': crew, 'invites': invites});

  /// [owner]가 true면 내가 크루장인 크루, 아니면 크루원으로 속한 크루입니다.
  static Map<String, dynamic> crewJson({
    bool owner = true,
    List<String> pending = const [],
  }) => {
    'id': 'crew-1',
    'name': '새벽런',
    'description': '매일 아침 한강 5km',
    'icon': 'flame',
    'is_owner': owner,
    'size_limit': 30,
    'members': [
      {'user_id': 'me', 'nickname': '나', 'role': owner ? 'owner' : 'member'},
      {'user_id': '2', 'nickname': '러너2', 'role': owner ? 'member' : 'owner'},
    ],
    'pending': pending,
  };

  @override
  bool get isCurrentOwner => true;

  @override
  Future<CrewDashboard> load() async => _dashboard;

  @override
  Future<CrewDashboard> create(
    String name,
    String description,
    CrewIcon icon,
  ) async {
    calls.add('create:$name:$description:${icon.code}');
    if (name == '이미있음') {
      throw const PostgrestException(
        message: '이미 쓰고 있는 크루 이름이에요.',
        code: 'P0001',
      );
    }
    crew = {
      ...crewJson(),
      'name': name,
      'description': description,
      'icon': icon.code,
      'members': [
        {'user_id': 'me', 'nickname': '나', 'role': 'owner'},
      ],
    };
    if (wallet case final wallet?) {
      wallet.crewTickets--;
      wallet.inCrew = true;
    }
    return _dashboard;
  }

  @override
  Future<CrewDashboard> invite(String userId) async {
    calls.add('invite:$userId');
    crew = {
      ...crew!,
      'pending': [...crew!['pending'] as List, userId],
    };
    return _dashboard;
  }

  @override
  Future<CrewDashboard> respond(String crewId, {required bool accept}) async {
    calls.add('respond:$crewId:$accept');
    if (accept) crew = crewJson(owner: false);
    invites = [];
    return _dashboard;
  }
}
