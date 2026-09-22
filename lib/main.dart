import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'auth/privacy_controls.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);
const _authRedirectUrl = 'runspot://login-callback';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );
  await _configureFirebaseMessagingForDebug();
  runApp(const RunQuestApp());
}

Future<void> _configureFirebaseMessagingForDebug() async {
  final messaging = FirebaseMessaging.instance;

  await messaging.requestPermission();

  if (!kDebugMode) {
    return;
  }

  try {
    final token = await messaging.getToken();
    // ignore: prefer_interpolation_to_compose_strings
    debugPrint('FCM token: ' + (token ?? 'null'));

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      // ignore: prefer_interpolation_to_compose_strings
      debugPrint('FCM token refreshed: ' + token);
    });
  } catch (error) {
    // ignore: prefer_interpolation_to_compose_strings
    debugPrint('FCM token error: ' + error.toString());
  }
}

class RunQuestApp extends StatelessWidget {
  const RunQuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RunQuest',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          primary: AppColors.blue,
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: AppColors.ink,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            height: 1.14,
          ),
          titleLarge: TextStyle(
            color: AppColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
          titleMedium: TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
          bodyMedium: TextStyle(
            color: AppColors.gray,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          labelLarge: TextStyle(
            color: AppColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      home: const MobileAppViewport(child: AuthGate()),
    );
  }
}


class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _authSubscription;
  late bool _signedIn;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _signedIn = auth.currentSession != null;
    _authSubscription = auth.onAuthStateChange.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() => _signedIn = state.session != null);
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _signedIn ? const RunQuestShell() : const AuthScreen();
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithOAuth(OAuthProvider provider) async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: _authRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } on AuthException catch (error) {
      setState(() => _message = error.message);
    } catch (_) {
      setState(() => _message = '소셜 로그인 처리 중 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _message = '이메일과 비밀번호를 모두 입력해 주세요.');
      return;
    }

    if (password.length < 6) {
      setState(() => _message = '비밀번호는 6자 이상이어야 합니다.');
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final auth = Supabase.instance.client.auth;
      if (_isSignUp) {
        final response = await auth.signUp(email: email, password: password);
        if (response.session == null) {
          setState(() => _message = '가입 확인 메일을 확인해 주세요.');
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (error) {
      setState(() => _message = error.message);
    } catch (_) {
      setState(() => _message = '로그인 처리 중 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSignUp ? '회원가입' : '로그인';
    final actionLabel = _isSignUp ? '회원가입' : '이메일로 로그인';
    final switchLabel = _isSignUp ? '이미 계정이 있어요' : '새 계정 만들기';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.directions_run,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text('RunSpot', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                '러닝 조건을 확인하고 주변 러너와 함께 달려요.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: '이메일',
                        prefixIcon: Icon(Icons.mail_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(
                        labelText: '비밀번호',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _loading ? null : _submit(),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _message!,
                        style: TextStyle(
                          color: _message!.contains('확인')
                              ? AppColors.green
                              : AppColors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(actionLabel),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _isSignUp = !_isSignUp;
                                _message = null;
                              }),
                      child: Text(switchLabel),
                    ),
                    const Divider(height: 24),
                    OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _signInWithOAuth(OAuthProvider.google),
                      icon: const Icon(Icons.g_mobiledata),
                      label: const Text('Google로 계속하기'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _signInWithOAuth(OAuthProvider.kakao),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Kakao로 계속하기'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '소셜 로그인은 브라우저 인증 후 앱으로 돌아옵니다.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class MobileAppViewport extends StatelessWidget {
  const MobileAppViewport({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const phoneAspectRatio = 390 / 844;
            final maxWidth = math.min(constraints.maxWidth, 430.0);
            final maxHeight = math.min(constraints.maxHeight, 932.0);
            var width = maxWidth;
            var height = width / phoneAspectRatio;
            if (height > maxHeight) {
              height = maxHeight;
              width = height * phoneAspectRatio;
            }
            return Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: constraints.maxWidth > 430
                    ? BorderRadius.circular(32)
                    : BorderRadius.zero,
                boxShadow: constraints.maxWidth > 430
                    ? [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: .10),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(width: 390, height: 844, child: child),
              ),
            );
          },
        ),
      ),
    );
  }
}

class AppColors {
  static const blue = Color(0xFF3182F6);
  static const blueDark = Color(0xFF1B64DA);
  static const blueSoft = Color(0xFFE8F3FF);
  static const bg = Color(0xFFF7F8FA);
  static const ink = Color(0xFF191F28);
  static const gray = Color(0xFF6B7684);
  static const line = Color(0xFFE5E8EB);
  static const green = Color(0xFF00B894);
  static const orange = Color(0xFFFF9F1C);
  static const red = Color(0xFFE34949);
  static const purple = Color(0xFF7C5CFF);
}

class RunPreset {
  const RunPreset(this.name, this.short, this.icon, this.color);

  final String name;
  final String short;
  final IconData icon;
  final Color color;
}

class RoutePlan {
  const RoutePlan({
    required this.title,
    required this.distance,
    required this.slope,
    required this.flow,
    required this.environment,
    required this.safety,
    required this.mission,
    required this.scores,
  });

  final String title;
  final String distance;
  final String slope;
  final String flow;
  final String environment;
  final String safety;
  final String mission;
  final Map<String, int> scores;
}

class Achievement {
  const Achievement(this.title, this.value, this.icon, this.progress);

  final String title;
  final String value;
  final IconData icon;
  final double progress;
}

class RunnerRank {
  const RunnerRank(this.rank, this.name, this.badge, this.value, this.isMe);

  final int rank;
  final String name;
  final String badge;
  final String value;
  final bool isMe;
}

class ReviewCase {
  const ReviewCase({
    required this.user,
    required this.reason,
    required this.summary,
    required this.risk,
    required this.status,
  });

  final String user;
  final String reason;
  final String summary;
  final int risk;
  final String status;

  ReviewCase copyWith({String? status}) {
    return ReviewCase(
      user: user,
      reason: reason,
      summary: summary,
      risk: risk,
      status: status ?? this.status,
    );
  }
}

const presets = [
  RunPreset('야간 안전런', '안전 우선', Icons.shield_outlined, AppColors.blue),
  RunPreset('페이스런', '신호 적게', Icons.speed_outlined, AppColors.orange),
  RunPreset('업힐런', '경사 도전', Icons.terrain_outlined, AppColors.red),
  RunPreset('힐링런', '공원/하천', Icons.park_outlined, AppColors.green),
  RunPreset('10K 기록 도전', '정확한 10K', Icons.flag_outlined, AppColors.purple),
];

const achievements = [
  Achievement('코스 탐색가', '12개', Icons.explore_outlined, .68),
  Achievement('야간 안전러', '8회', Icons.nightlight_outlined, .80),
  Achievement('업힐 사냥꾼', '420m', Icons.terrain_outlined, .56),
];

const rankings = [
  RunnerRank(1, '하천킬러', '힐링런 Lv.9', '42.8km', false),
  RunnerRank(2, '성장러너', '성장률 1위', '+38%', false),
  RunnerRank(3, '나', '코스 탐색가', '31.4km', true),
  RunnerRank(4, '페이스장인', '5K 21:40', '29.7km', false),
];

class RunQuestShell extends StatefulWidget {
  const RunQuestShell({super.key});

  @override
  State<RunQuestShell> createState() => _RunQuestShellState();
}

class _RunQuestShellState extends State<RunQuestShell> {
  int _tab = 0;
  String _distance = '5 km';
  String _slope = '평지 위주';
  String _flow = '페이스 유지';
  String _environment = '공원/하천';
  String _safety = '골목길 회피';
  int _rankingMode = 0;
  late RoutePlan _plan;
  ReviewCase _review = const ReviewCase(
    user: 'speed_ghost',
    reason: '순간 속도 34.2km/h 감지',
    summary: '10.02km · 22:18 · 페이스 변동 1.2%',
    risk: 92,
    status: '검토 필요',
  );

  @override
  void initState() {
    super.initState();
    _plan = _makePlan();
  }

  RoutePlan _makePlan() {
    final distanceNumber = int.parse(_distance.split(' ').first);
    final safetyScore =
        76 + (_safety == '야간 안전' ? 14 : 0) + (_safety == '골목길 회피' ? 8 : 0);
    final flowScore =
        72 + (_flow == '신호 적게' ? 14 : 0) + (_flow == '페이스 유지' ? 10 : 0);
    final slopeScore = _slope == '업힐 도전' ? 92 : (_slope == '완만한 경사' ? 76 : 88);
    final natureScore = _environment == '공원/하천'
        ? 94
        : (_environment == '혼합' ? 78 : 64);

    return RoutePlan(
      title:
          '${distanceNumber}K ${_environment.replaceAll('/', '·')} ${_flow.replaceAll(' ', '')}',
      distance: _distance,
      slope: _slope,
      flow: _flow,
      environment: _environment,
      safety: _safety,
      mission: distanceNumber >= 10 ? '마지막 2km 페이스 유지' : '마지막 700m 가속',
      scores: {
        '안전': math.min(safetyScore, 98),
        '흐름': math.min(flowScore, 98),
        '경사': slopeScore,
        '환경': natureScore,
      },
    );
  }

  void _updatePlan({
    String? distance,
    String? slope,
    String? flow,
    String? environment,
    String? safety,
  }) {
    setState(() {
      _distance = distance ?? _distance;
      _slope = slope ?? _slope;
      _flow = flow ?? _flow;
      _environment = environment ?? _environment;
      _safety = safety ?? _safety;
      _plan = _makePlan();
    });
  }

  void _applyPreset(RunPreset preset) {
    switch (preset.name) {
      case '야간 안전런':
        _updatePlan(
          distance: '5 km',
          slope: '평지 위주',
          flow: '여유런',
          environment: '혼합',
          safety: '야간 안전',
        );
      case '페이스런':
        _updatePlan(
          distance: '5 km',
          slope: '평지 위주',
          flow: '신호 적게',
          environment: '도심',
          safety: '최적 경로',
        );
      case '업힐런':
        _updatePlan(
          distance: '7 km',
          slope: '업힐 도전',
          flow: '여유런',
          environment: '도심',
          safety: '골목길 회피',
        );
      case '힐링런':
        _updatePlan(
          distance: '5 km',
          slope: '완만한 경사',
          flow: '여유런',
          environment: '공원/하천',
          safety: '최적 경로',
        );
      default:
        _updatePlan(
          distance: '10 km',
          slope: '평지 위주',
          flow: '신호 적게',
          environment: '도심',
          safety: '최적 경로',
        );
    }
  }

  void _setReviewStatus(String status) {
    setState(() => _review = _review.copyWith(status: status));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_review.user}님에게 "$status" 알림을 보냈습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(plan: _plan, onCourseTap: () => setState(() => _tab = 1)),
      CourseScreen(
        plan: _plan,
        distance: _distance,
        slope: _slope,
        flow: _flow,
        environment: _environment,
        safety: _safety,
        onDistance: (value) => _updatePlan(distance: value),
        onSlope: (value) => _updatePlan(slope: value),
        onFlow: (value) => _updatePlan(flow: value),
        onEnvironment: (value) => _updatePlan(environment: value),
        onSafety: (value) => _updatePlan(safety: value),
        onPresetTap: _applyPreset,
      ),
      SocialScreen(
        rankingMode: _rankingMode,
        onModeChanged: (value) => setState(() => _rankingMode = value),
      ),
      const ProfileScreen(),
      AdminScreen(review: _review, onAction: _setReviewStatus),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: pages[_tab],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 66,
        selectedIndex: _tab,
        indicatorColor: AppColors.blueSoft,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: '코스',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: '소셜',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '프로필',
          ),
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings),
            label: '관리',
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.plan, required this.onCourseTap, super.key});

  final RoutePlan plan;
  final VoidCallback onCourseTap;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(title: 'RunQuest', subtitle: '오늘에 맞는 러닝 코스'),
          const SizedBox(height: 10),
          Text(
            '오늘은\n어디로 달릴까요?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 8,
            child: RouteCard(plan: plan, onCourseTap: onCourseTap),
          ),
          const SizedBox(height: 10),
          Expanded(flex: 4, child: QuickStats()),
        ],
      ),
    );
  }
}

class CourseScreen extends StatelessWidget {
  const CourseScreen({
    required this.plan,
    required this.distance,
    required this.slope,
    required this.flow,
    required this.environment,
    required this.safety,
    required this.onDistance,
    required this.onSlope,
    required this.onFlow,
    required this.onEnvironment,
    required this.onSafety,
    required this.onPresetTap,
    super.key,
  });

  final RoutePlan plan;
  final String distance;
  final String slope;
  final String flow;
  final String environment;
  final String safety;
  final ValueChanged<String> onDistance;
  final ValueChanged<String> onSlope;
  final ValueChanged<String> onFlow;
  final ValueChanged<String> onEnvironment;
  final ValueChanged<String> onSafety;
  final ValueChanged<RunPreset> onPresetTap;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(title: '코스 만들기', subtitle: '5가지만 고르면 추천 완료'),
          const SizedBox(height: 12),
          ChoiceMenu(
            label: '거리',
            selected: distance,
            options: const ['3 km', '5 km', '7 km', '10 km'],
            onChanged: onDistance,
          ),
          ChoiceMenu(
            label: '경사',
            selected: slope,
            options: const ['평지 위주', '완만한 경사', '업힐 도전'],
            onChanged: onSlope,
          ),
          ChoiceMenu(
            label: '흐름',
            selected: flow,
            options: const ['페이스 유지', '여유런', '신호 적게'],
            onChanged: onFlow,
          ),
          ChoiceMenu(
            label: '환경',
            selected: environment,
            options: const ['도심', '공원/하천', '혼합'],
            onChanged: onEnvironment,
          ),
          ChoiceMenu(
            label: '안전',
            selected: safety,
            options: const ['최적 경로', '골목길 회피', '야간 안전'],
            onChanged: onSafety,
          ),
          const SizedBox(height: 8),
          Text('프리셋', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Expanded(flex: 5, child: PresetGrid(onPresetTap: onPresetTap)),
          const SizedBox(height: 10),
          Expanded(flex: 5, child: CompactPlanCard(plan: plan)),
        ],
      ),
    );
  }
}

class SocialScreen extends StatelessWidget {
  const SocialScreen({
    required this.rankingMode,
    required this.onModeChanged,
    super.key,
  });

  final int rankingMode;
  final ValueChanged<int> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final modes = ['거리', '성장', '5K', '꾸준'];
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(title: '소셜', subtitle: '친구와 기록을 비교해요'),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < modes.length; i++) ...[
                Expanded(
                  child: TinyTab(
                    label: modes[i],
                    selected: i == rankingMode,
                    onTap: () => onModeChanged(i),
                  ),
                ),
                if (i != modes.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Panel(
              child: Column(
                children: [
                  const SectionHeader(
                    title: '친구 랭킹',
                    subtitle: '이번 주 기준',
                    icon: Icons.leaderboard_outlined,
                  ),
                  const SizedBox(height: 10),
                  for (final runner in rankings)
                    Expanded(child: RankRow(runner: runner)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const ShareCard(),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(title: '프로필', subtitle: '통계와 업적 공개 범위 설정'),
          const SizedBox(height: 12),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: const BoxDecoration(
                        color: AppColors.blueSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.directions_run,
                        color: AppColors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'nenmen_runner',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'Lv.12 코스 탐색가',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.ios_share, color: AppColors.blue),
                  ],
                ),
                const SizedBox(height: 12),
                const PrivacyControls(),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                    icon: const Icon(Icons.logout),
                    label: const Text('로그아웃'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const QuickStats(),
          const SizedBox(height: 10),
          Expanded(
            child: Panel(
              child: Column(
                children: [
                  const SectionHeader(
                    title: '대표 업적',
                    subtitle: '프로필에 표시돼요',
                    icon: Icons.military_tech_outlined,
                  ),
                  const SizedBox(height: 10),
                  for (final item in achievements)
                    Expanded(child: AchievementRow(achievement: item)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminScreen extends StatelessWidget {
  const AdminScreen({required this.review, required this.onAction, super.key});

  final ReviewCase review;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(title: '관리', subtitle: '기록 신뢰도를 지키는 운영 화면'),
          const SizedBox(height: 12),
          const AdminStats(),
          const SizedBox(height: 10),
          Expanded(
            child: AdminReviewCard(review: review, onAction: onAction),
          ),
        ],
      ),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: ValueKey(child.runtimeType), child: child);
  }
}

class AppTopBar extends StatelessWidget {
  const AppTopBar({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.blue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.directions_run,
            color: Colors.white,
            size: 21,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none),
          color: AppColors.blue,
        ),
      ],
    );
  }
}

class RouteCard extends StatelessWidget {
  const RouteCard({required this.plan, required this.onCourseTap, super.key});

  final RoutePlan plan;
  final VoidCallback onCourseTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              BadgePill(text: plan.distance),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: RouteMapPreview(plan: plan)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final entry in plan.scores.entries) ...[
                Expanded(
                  child: ScoreMini(label: entry.key, score: entry.value),
                ),
                if (entry.key != plan.scores.keys.last)
                  const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onCourseTap,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('코스 다시 만들기'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              backgroundColor: AppColors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CompactPlanCard extends StatelessWidget {
  const CompactPlanCard({required this.plan, super.key});

  final RoutePlan plan;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(plan.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  plan.mission,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                const BadgePill(text: '기록 인증 ON'),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 116, child: RouteMapPreview(plan: plan)),
        ],
      ),
    );
  }
}

class ChoiceMenu extends StatelessWidget {
  const ChoiceMenu({
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String selected;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: '$label 선택',
              onSelected: onChanged,
              itemBuilder: (context) => [
                for (final option in options)
                  PopupMenuItem(value: option, child: Text(option)),
              ],
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColors.gray,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PresetGrid extends StatelessWidget {
  const PresetGrid({required this.onPresetTap, super.key});

  final ValueChanged<RunPreset> onPresetTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              for (final preset in presets.take(3)) ...[
                Expanded(
                  child: PresetTile(
                    preset: preset,
                    onTap: () => onPresetTap(preset),
                  ),
                ),
                if (preset != presets[2]) const SizedBox(width: 7),
              ],
            ],
          ),
        ),
        const SizedBox(height: 7),
        Expanded(
          child: Row(
            children: [
              for (final preset in presets.skip(3)) ...[
                Expanded(
                  child: PresetTile(
                    preset: preset,
                    onTap: () => onPresetTap(preset),
                  ),
                ),
                if (preset != presets.last) const SizedBox(width: 7),
              ],
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }
}

class PresetTile extends StatelessWidget {
  const PresetTile({required this.preset, required this.onTap, super.key});

  final RunPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(preset.icon, color: preset.color, size: 20),
            const SizedBox(height: 4),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
            Text(
              preset.short,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.gray,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RouteMapPreview extends StatelessWidget {
  const RouteMapPreview({required this.plan, super.key});

  final RoutePlan plan;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CustomPaint(
        painter: RouteMapPainter(),
        child: Stack(
          children: [
            const Positioned(
              left: 10,
              top: 10,
              child: MapPill(icon: Icons.my_location, text: '출발 숨김'),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: MapPill(icon: Icons.flag_outlined, text: plan.distance),
            ),
          ],
        ),
      ),
    );
  }
}

class RouteMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF2F6FB),
    );

    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < 6; i++) {
      final y = size.height * i / 6;
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), road);
    }
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 8), Offset(x, size.height - 8), road);
    }

    final park = Paint()..color = AppColors.green.withValues(alpha: .14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .56,
          size.height * .12,
          size.width * .31,
          size.height * .27,
        ),
        const Radius.circular(12),
      ),
      park,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .08,
          size.height * .58,
          size.width * .35,
          size.height * .24,
        ),
        const Radius.circular(12),
      ),
      park,
    );

    final route = Path()
      ..moveTo(size.width * .22, size.height * .70)
      ..cubicTo(
        size.width * .14,
        size.height * .28,
        size.width * .44,
        size.height * .14,
        size.width * .66,
        size.height * .25,
      )
      ..cubicTo(
        size.width * .88,
        size.height * .35,
        size.width * .82,
        size.height * .72,
        size.width * .57,
        size.height * .78,
      )
      ..cubicTo(
        size.width * .42,
        size.height * .82,
        size.width * .30,
        size.height * .80,
        size.width * .22,
        size.height * .70,
      );

    canvas.drawPath(
      route,
      Paint()
        ..color = AppColors.blueSoft
        ..strokeWidth = 15
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = AppColors.blue
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final start = Offset(size.width * .22, size.height * .70);
    canvas.drawCircle(start, 8, Paint()..color = AppColors.ink);
    canvas.drawCircle(start, 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class QuickStats extends StatelessWidget {
  const QuickStats({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: StatCard(
            label: '이번 주',
            value: '31.4km',
            icon: Icons.calendar_month,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: StatCard(label: '평균 페이스', value: '5′42″', icon: Icons.speed),
        ),
        SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '완주 코스',
            value: '18개',
            icon: Icons.route_outlined,
          ),
        ),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.blue, size: 19),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class ShareCard extends StatelessWidget {
  const ShareCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(12),
      child: const Row(
        children: [
          Icon(Icons.ios_share, color: AppColors.blue),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '인스타/페이스북 공유 카드 생성 · 위치는 자동 보호',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminStats extends StatelessWidget {
  const AdminStats({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: StatCard(
            label: '오늘 러닝',
            value: '1,284',
            icon: Icons.directions_run,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '검토 필요',
            value: '17',
            icon: Icons.warning_amber,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '소명 대기',
            value: '6',
            icon: Icons.outgoing_mail,
          ),
        ),
      ],
    );
  }
}

class AdminReviewCard extends StatelessWidget {
  const AdminReviewCard({
    required this.review,
    required this.onAction,
    super.key,
  });

  final ReviewCase review;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: '이상 기록',
            subtitle: '자동 탐지 후 관리자 검토',
            icon: Icons.admin_panel_settings_outlined,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  review.user,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              BadgePill(text: review.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.reason,
            style: const TextStyle(
              color: AppColors.red,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(review.summary, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: review.risk / 100,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(99),
                  color: AppColors.red,
                  backgroundColor: AppColors.line,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '위험 ${review.risk}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const Spacer(),
          ActionButton(
            label: '소명 요청 알림 보내기',
            icon: Icons.outgoing_mail,
            onTap: () => onAction('소명 요청'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: '경고',
                  icon: Icons.warning_amber,
                  onTap: () => onAction('경고'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ActionButton(
                  label: '정지',
                  icon: Icons.pause_circle_outline,
                  onTap: () => onAction('일시 정지'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.blueSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.blue, size: 19),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RankRow extends StatelessWidget {
  const RankRow({required this.runner, super.key});

  final RunnerRank runner;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: runner.isMe ? AppColors.blueSoft : AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '#${runner.rank}',
              style: const TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  runner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  runner.badge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.gray,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            runner.value,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class AchievementRow extends StatelessWidget {
  const AchievementRow({required this.achievement, super.key});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(achievement.icon, color: AppColors.blue, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      achievement.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    achievement.value,
                    style: const TextStyle(
                      color: AppColors.gray,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: achievement.progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(99),
                color: AppColors.blue,
                backgroundColor: AppColors.line,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TinyTab extends StatelessWidget {
  const TinyTab({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.blue : AppColors.line),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.gray,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class ScoreMini extends StatelessWidget {
  const ScoreMini({required this.label, required this.score, super.key});

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.gray,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '$score',
            style: const TextStyle(
              color: AppColors.blue,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class MapPill extends StatelessWidget {
  const MapPill({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.blue),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class BadgePill extends StatelessWidget {
  const BadgePill({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.blueSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.blueDark,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  const ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(42),
        foregroundColor: AppColors.ink,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: .04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
