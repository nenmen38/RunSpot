import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/run_transfer/run_file_codec.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/models/run_route.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

void main() {
  final record = RunRecord(
    id: 'record',
    clientRunId: 'client',
    startedAt: DateTime.utc(2026, 11, 17),
    endedAt: DateTime.utc(2026, 11, 17, 0, 30),
    distanceMeters: 5000,
    durationSeconds: 1800,
  );
  final route = RunRoute([
    [const LatLng(35.9, 128.8)],
    [const LatLng(35.91, 128.81)],
  ]);
  test('내보내기와 가져오기가 구간과 값을 보존하고 동일 자료는 같은 키를 생성합니다', () {
    final file = RunFileCodec.encode(record, route);
    final first = RunFileCodec.decode(file);
    final second = RunFileCodec.decode(
      const JsonEncoder.withIndent('  ').convert(jsonDecode(file)),
    );
    expect(first['source_id'], second['source_id']);
    expect(first['route'], route.toJson());
    expect(first['duration_sec'], 1800);
  });
  test('좌표 범위와 음수 측정값을 거부합니다', () {
    final data = jsonDecode(RunFileCodec.encode(record, route)) as Map;
    data['distance_m'] = -1;
    expect(() => RunFileCodec.decode(jsonEncode(data)), throwsFormatException);
    data['distance_m'] = 100;
    data['route'] = [
      [
        [91, 0],
      ],
    ];
    expect(() => RunFileCodec.decode(jsonEncode(data)), throwsFormatException);
  });
  test('GPX는 일시정지 구간을 합치거나 없는 시각을 만들어내지 않습니다', () {
    final doc = XmlDocument.parse(RunFileCodec.gpx(record, route));
    expect(doc.findAllElements('trkseg').length, 2);
    expect(doc.findAllElements('trkpt').length, 2);
    expect(doc.findAllElements('trkpt').first.findElements('time'), isEmpty);
  });
}
