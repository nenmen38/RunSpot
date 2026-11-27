import 'package:flutter/material.dart';

import 'appearance/app_appearance.dart';

/// 집·직장 근처 위치 숨기기 설정입니다. 러닝을 시작한 곳(보통 집) 주변은
/// 친구에게 실시간 위치를 보내지 않고, 공유 카드의 경로에서도 출발·도착 주변을 가립니다.
/// 기기에 저장하며 처음에는 300m로 켜져 있습니다.
class LocationPrivacy extends ChangeNotifier {
  LocationPrivacy({AppearanceStore? store}) : _given = store;

  static final instance = LocationPrivacy();

  /// 고를 수 있는 반경(m)입니다. 0이면 끕니다.
  static const options = [0, 200, 300, 500];
  static const defaultRadius = 300;
  static const _key = 'privacy.hide_radius_m';

  final AppearanceStore? _given;
  late final AppearanceStore _store = _given ?? DeviceAppearanceStore();

  int radiusMeters = defaultRadius;

  bool get enabled => radiusMeters > 0;

  Future<void> load() async {
    try {
      final saved = int.tryParse(await _store.read(_key) ?? '');
      if (saved != null && options.contains(saved)) {
        radiusMeters = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setRadius(int meters) async {
    if (!options.contains(meters) || meters == radiusMeters) return;
    radiusMeters = meters;
    notifyListeners();
    try {
      await _store.write(_key, '$meters');
    } catch (_) {}
  }

  /// 설정 목록에 보여 줄 한 줄 요약입니다.
  String get summary => enabled ? '반경 ${radiusMeters}m 가림' : '끔';
}

/// 설정 → 집·직장 근처 위치 숨기기: 가릴 반경을 고릅니다.
class LocationPrivacyScreen extends StatelessWidget {
  const LocationPrivacyScreen({this.privacy, super.key});

  final LocationPrivacy? privacy;

  @override
  Widget build(BuildContext context) {
    final settings = privacy ?? LocationPrivacy.instance;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('집·직장 근처 위치 숨기기')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              '러닝을 시작한 곳(보통 집이나 직장) 주변은 다른 사람에게 보이지 않게 해요.',
              style: text.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 16),
            SegmentedButton<int>(
              key: const ValueKey('privacy-radius'),
              showSelectedIcon: false,
              segments: [
                for (final meters in LocationPrivacy.options)
                  ButtonSegment(
                    value: meters,
                    label: Text(meters == 0 ? '끄기' : '${meters}m'),
                  ),
              ],
              selected: {settings.radiusMeters},
              onSelectionChanged: (value) => settings.setRadius(value.single),
            ),
            const SizedBox(height: 24),
            const _Rule(
              icon: Icons.share_location_outlined,
              title: '실시간 위치 공유',
              body:
                  '러닝 시작 지점에서 이 거리 안에 있는 동안은 친구와 주변 러너에게 내 위치를 보내지 않아요. '
                  '멀어지면 보이고, 돌아와 이 안에 들어오면 다시 사라져요.',
            ),
            const _Rule(
              icon: Icons.image_outlined,
              title: '공유 카드의 경로',
              body:
                  '카드에 넣는 이동 경로에서 출발점과 도착점 주변을 잘라 내요. 경로가 너무 짧으면 경로 없이 만들어져요.',
            ),
            const _Rule(
              icon: Icons.lock_outline,
              title: '내 기록은 그대로',
              body: '내 기록 화면의 경로와 거리·시간은 달라지지 않아요. 나만 보는 정보입니다.',
            ),
            if (!settings.enabled) ...[
              const SizedBox(height: 8),
              Text(
                '지금은 꺼져 있어요. 집 주변 위치가 친구에게 보일 수 있으니 켜 두기를 권해요.',
                style: text.bodySmall?.copyWith(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
