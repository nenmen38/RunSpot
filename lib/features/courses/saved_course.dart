import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_colors.dart';

/// 이름을 붙여 저장한 내 달리기 코스입니다. 지도에 점선 안내선으로 띄웁니다.
@immutable
class SavedCourse {
  const SavedCourse({
    required this.id,
    required this.name,
    required this.distanceMeters,
    required this.segments,
  });

  factory SavedCourse.fromJson(Map<String, dynamic> json) => SavedCourse(
    id: json['id'] as String,
    name: json['name'] as String,
    distanceMeters: (json['distance_m'] as num).toInt(),
    segments: [
      for (final segment in json['segments'] as List? ?? const [])
        [
          for (final point in segment as List)
            LatLng(
              ((point as List)[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ),
        ],
    ],
  );

  final String id;
  final String name;
  final int distanceMeters;
  final List<List<LatLng>> segments;

  String get distanceLabel => '${(distanceMeters / 1000).toStringAsFixed(1)}km';
}

abstract interface class CourseService {
  Future<List<SavedCourse>> load();
  Future<SavedCourse> save(String runId, String name);
  Future<void> delete(String id);
}

class SupabaseCourseService implements CourseService {
  SupabaseCourseService(this.client);
  final SupabaseClient client;

  @override
  Future<List<SavedCourse>> load() async => [
    for (final item in await client.rpc('my_courses') as List? ?? const [])
      SavedCourse.fromJson(Map<String, dynamic>.from(item as Map)),
  ];

  @override
  Future<SavedCourse> save(String runId, String name) async =>
      SavedCourse.fromJson(
        Map<String, dynamic>.from(
          await client.rpc(
            'save_course',
            params: {'requested_run_id': runId, 'course_name': name},
          ) as Map,
        ),
      );

  @override
  Future<void> delete(String id) =>
      client.rpc<void>('delete_course', params: {'course_id': id});
}

/// 지금 지도에 띄운 코스입니다(앱을 쓰는 동안만 기억).
class CourseGuide extends ChangeNotifier {
  CourseGuide._();
  static final instance = CourseGuide._();

  SavedCourse? selected;

  void select(SavedCourse? course) {
    if (selected?.id == course?.id) return;
    selected = course;
    notifyListeners();
  }
}

/// 홈의 '코스 따라 달리기' 버튼입니다. 고른 코스는 지도에 점선으로 보이고 ✕로 끕니다.
class CourseGuideButton extends StatelessWidget {
  const CourseGuideButton({required this.service, super.key});

  final CourseService service;

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<SavedCourse>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CoursePicker(service: service),
    );
    if (picked != null) CourseGuide.instance.select(picked);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: CourseGuide.instance,
    builder: (context, _) {
      final course = CourseGuide.instance.selected;
      if (course == null) {
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('course-guide'),
            onPressed: () => _pick(context),
            icon: const Icon(Icons.alt_route, size: 18),
            label: const Text('내 코스 따라 달리기'),
          ),
        );
      }
      return Row(
        children: [
          const Icon(Icons.alt_route, size: 18, color: AppColors.blue),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: () => _pick(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '코스: ${course.name} · ${course.distanceLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '코스 안내 끄기',
            onPressed: () => CourseGuide.instance.select(null),
            icon: const Icon(Icons.close),
          ),
        ],
      );
    },
  );
}

class _CoursePicker extends StatefulWidget {
  const _CoursePicker({required this.service});

  final CourseService service;

  @override
  State<_CoursePicker> createState() => _CoursePickerState();
}

class _CoursePickerState extends State<_CoursePicker> {
  List<SavedCourse>? _courses;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final courses = await widget.service.load();
      if (mounted) setState(() => _courses = courses);
    } catch (_) {
      if (mounted) setState(() => _error = '코스를 불러오지 못했어요.');
    }
  }

  Future<void> _delete(SavedCourse course) async {
    try {
      await widget.service.delete(course.id);
      if (CourseGuide.instance.selected?.id == course.id) {
        CourseGuide.instance.select(null);
      }
      if (mounted) {
        setState(
          () => _courses = [
            for (final item in _courses ?? const <SavedCourse>[])
              if (item.id != course.id) item,
          ],
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '코스를 지우지 못했어요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final courses = _courses;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '내 코스',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(20), child: Text(_error!))
            else if (courses == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (courses.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Text(
                  "아직 저장한 코스가 없어요.\n내 기록에서 러닝을 열고 '내 코스로 저장'을 눌러 보세요.",
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.gray,
                    height: 1.5,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final course in courses)
                      ListTile(
                        key: ValueKey('course-${course.id}'),
                        leading: const Icon(Icons.route_outlined),
                        title: Text(course.name),
                        subtitle: Text(course.distanceLabel),
                        onTap: () => Navigator.pop(context, course),
                        trailing: IconButton(
                          tooltip: '${course.name} 지우기',
                          onPressed: () => _delete(course),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 러닝 기록 상세의 '내 코스로 저장' 버튼입니다. 이름을 정하면 경로를 코스로 남깁니다.
class SaveCourseButton extends StatefulWidget {
  const SaveCourseButton({
    required this.service,
    required this.runId,
    required this.distanceMeters,
    required this.endedAt,
    super.key,
  });

  final CourseService service;
  final String runId;
  final int distanceMeters;
  final DateTime endedAt;

  @override
  State<SaveCourseButton> createState() => _SaveCourseButtonState();
}

class _SaveCourseButtonState extends State<SaveCourseButton> {
  bool _busy = false;
  bool _saved = false;

  Future<void> _save() async {
    final local = widget.endedAt.toLocal();
    final suggested =
        '${(widget.distanceMeters / 1000).toStringAsFixed(1)}km 코스 · ${local.month}월 ${local.day}일';
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CourseNameDialog(initial: suggested),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _busy = true);
    String message;
    try {
      await widget.service.save(widget.runId, name);
      _saved = true;
      message = "'$name'을 내 코스로 저장했어요. 홈에서 '내 코스 따라 달리기'로 띄울 수 있어요.";
    } on PostgrestException catch (error) {
      message = error.code == 'P0001' || error.code == '22023'
          ? error.message
          : '코스를 저장하지 못했어요.';
    } catch (_) {
      message = '코스를 저장하지 못했어요.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const ValueKey('save-course'),
    onPressed: _busy || _saved ? null : _save,
    icon: Icon(_saved ? Icons.check : Icons.bookmark_add_outlined),
    label: Text(_saved ? '내 코스에 저장됨' : '내 코스로 저장'),
  );
}

/// 코스 이름을 정하는 창입니다. 입력 칸은 창이 완전히 닫힐 때 정리합니다.
class _CourseNameDialog extends StatefulWidget {
  const _CourseNameDialog({required this.initial});

  final String initial;

  @override
  State<_CourseNameDialog> createState() => _CourseNameDialogState();
}

class _CourseNameDialogState extends State<_CourseNameDialog> {
  late final _input = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('내 코스로 저장'),
    content: TextField(
      controller: _input,
      autofocus: true,
      maxLength: 30,
      decoration: const InputDecoration(labelText: '코스 이름'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _input.text.trim()),
        child: const Text('저장'),
      ),
    ],
  );
}
