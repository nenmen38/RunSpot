/// 코스 안내는 기존 게시글의 본문에도 읽을 수 있는 형식으로 보존합니다.
class CourseNotes {
  const CourseNotes({required this.body, this.values = const {}});

  static const labels = ['조명', '화장실', '급수대', '대중교통', '확인 날짜'];
  static const _heading = '코스 이용 정보';
  final String body;
  final Map<String, String> values;

  factory CourseNotes.parse(String text) {
    final start = text.lastIndexOf('\n\n$_heading\n');
    if (start < 0) return CourseNotes(body: text);
    final values = <String, String>{};
    for (final line
        in text.substring(start + _heading.length + 3).split('\n')) {
      final index = line.indexOf(' · ');
      if (index < 0) return CourseNotes(body: text);
      final label = line.substring(0, index);
      final value = line.substring(index + 3);
      if (!labels.contains(label) ||
          values.containsKey(label) ||
          value.isEmpty) {
        return CourseNotes(body: text);
      }
      values[label] = value;
    }
    return CourseNotes(body: text.substring(0, start), values: values);
  }

  String get postBody {
    final details = [
      for (final label in labels)
        if (values[label] case final value? when value.trim().isNotEmpty)
          '$label · ${value.trim().replaceAll(RegExp(r"[\r\n]+"), " ")}',
    ];
    if (details.isEmpty) return body.trim();
    return [body.trim(), '', _heading, ...details].join('\n');
  }
}
