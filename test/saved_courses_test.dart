import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:runquest/features/courses/saved_course.dart';

SavedCourse course(String id, String name) => SavedCourse(
  id: id,
  name: name,
  distanceMeters: 5230,
  segments: const [
    [LatLng(37.5, 127), LatLng(37.51, 127.01)],
  ],
);

class FakeCourseService implements CourseService {
  final courses = <SavedCourse>[course('c1', '한강 5km')];
  final saved = <(String, String)>[];
  @override
  Future<List<SavedCourse>> load() async => [...courses];
  @override
  Future<SavedCourse> save(String runId, String name) async {
    saved.add((runId, name));
    return course('c2', name);
  }

  @override
  Future<void> delete(String id) async =>
      courses.removeWhere((item) => item.id == id);
}

void main() {
  tearDown(() => CourseGuide.instance.select(null));

  test('서버 코스를 읽어 구간별 좌표로 바꿉니다', () {
    final parsed = SavedCourse.fromJson({
      'id': 'c1',
      'name': '한강',
      'distance_m': 5230,
      'segments': [
        [
          [37.5, 127.0],
          [37.6, 127.1],
        ],
      ],
    });
    expect(parsed.distanceLabel, '5.2km');
    expect(parsed.segments.single.last, const LatLng(37.6, 127.1));
  });

  testWidgets('내 코스를 골라 지도에 띄우고 ✕로 끕니다', (tester) async {
    final service = FakeCourseService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CourseGuideButton(service: service)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('course-guide')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('course-c1')));
    await tester.pumpAndSettle();
    expect(CourseGuide.instance.selected?.id, 'c1');
    expect(find.text('코스: 한강 5km · 5.2km'), findsOneWidget);
    await tester.tap(find.byTooltip('코스 안내 끄기'));
    await tester.pumpAndSettle();
    expect(CourseGuide.instance.selected, isNull);
  });

  testWidgets('코스를 지우면 목록과 지도에서 사라집니다', (tester) async {
    final service = FakeCourseService();
    CourseGuide.instance.select(service.courses.single);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CourseGuideButton(service: service)),
      ),
    );
    await tester.tap(find.text('코스: 한강 5km · 5.2km'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('한강 5km 지우기'));
    await tester.pumpAndSettle();
    expect(service.courses, isEmpty);
    expect(CourseGuide.instance.selected, isNull);
    expect(find.textContaining('아직 저장한 코스가 없어요'), findsOneWidget);
  });

  testWidgets('기록에서 이름을 정해 내 코스로 저장합니다', (tester) async {
    final service = FakeCourseService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SaveCourseButton(
            service: service,
            runId: 'run-1',
            distanceMeters: 5230,
            endedAt: DateTime(2026, 11, 27, 8),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('save-course')));
    await tester.pumpAndSettle();
    expect(find.text('5.2km 코스 · 11월 27일'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '출근길');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(service.saved.single, ('run-1', '출근길'));
    expect(find.text('내 코스에 저장됨'), findsOneWidget);
  });
}
