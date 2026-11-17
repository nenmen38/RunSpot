import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../run_history/models/run_record.dart';
import '../run_history/models/run_route.dart';

class RunFileCodec {
  static String encode(RunRecord record, RunRoute route) => jsonEncode({
    'format': 'runspot',
    'version': 1,
    'started_at': record.startedAt.toUtc().toIso8601String(),
    'ended_at': record.endedAt.toUtc().toIso8601String(),
    'distance_m': record.distanceMeters,
    'duration_sec': record.durationSeconds,
    'route': route.toJson(),
  });
  static String gpx(RunRecord record, RunRoute route) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'gpx',
      attributes: {
        'version': '1.1',
        'creator': 'RunSpot',
        'xmlns': 'http://www.topografix.com/GPX/1/1',
      },
      nest: () {
        builder.element(
          'metadata',
          nest: () {
            builder.element(
              'time',
              nest: record.startedAt.toUtc().toIso8601String(),
            );
          },
        );
        builder.element(
          'trk',
          nest: () {
            builder.element('name', nest: '런스팟 러닝');
            for (final segment in route.segments) {
              builder.element(
                'trkseg',
                nest: () {
                  for (final point in segment) {
                    builder.element(
                      'trkpt',
                      attributes: {
                        'lat': point.latitude.toString(),
                        'lon': point.longitude.toString(),
                      },
                    );
                  }
                },
              );
            }
          },
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: true);
  }

  static Map<String, dynamic> decode(String source) {
    if (utf8.encode(source).length > 1000000) {
      throw const FormatException('1MB 이하의 기록 파일을 선택해 주세요.');
    }
    final value = jsonDecode(source);
    if (value is! Map ||
        value['format'] != 'runspot' ||
        value['version'] != 1) {
      throw const FormatException('런스팟에서 내보낸 기록 파일을 선택해 주세요.');
    }
    final start = DateTime.parse(value['started_at'] as String);
    final end = DateTime.parse(value['ended_at'] as String);
    final distance = value['distance_m'];
    final seconds = value['duration_sec'];
    final route = RunRoute.fromJson(value['route']);
    if (distance is! int ||
        distance < 0 ||
        distance > 500000 ||
        seconds is! int ||
        seconds < 1 ||
        seconds > 604800 ||
        !end.isAfter(start) ||
        end.difference(start) > const Duration(days: 7) ||
        route.segments.fold<int>(0, (n, s) => n + s.length) > 10000) {
      throw const FormatException('기록 값이 올바르지 않습니다.');
    }
    final payload = <String, dynamic>{
      'started_at': start.toUtc().toIso8601String(),
      'ended_at': end.toUtc().toIso8601String(),
      'distance_m': distance,
      'duration_sec': seconds,
      'route': route.toJson(),
    };
    return {
      'source': 'file',
      'source_id': sha256.convert(utf8.encode(jsonEncode(payload))).toString(),
      ...payload,
    };
  }
}
