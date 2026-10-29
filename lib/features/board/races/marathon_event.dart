import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';

enum MarathonStatus {
  upcoming('upcoming', '접수 예정', AppColors.blueDark),
  open('open', '접수 중', Color(0xFF00805A)),
  closed('closed', '접수 마감', AppColors.gray),
  unknown('unknown', '접수 미정', AppColors.gray);

  const MarathonStatus(this.code, this.label, this.color);
  final String code;
  final String label;
  final Color color;
}

class MarathonEvent {
  MarathonEvent.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      status = MarathonStatus.values.firstWhere(
        (s) => s.code == json['status'],
      ),
      data = Map<String, dynamic>.unmodifiable(json['data'] as Map);

  final String id;
  final MarathonStatus status;
  final Map<String, dynamic> data;
  String get name => data['name'] as String;
  String? get description => _text(data['description']);
  Map<String, dynamic> section(String key) =>
      Map<String, dynamic>.from(data[key] as Map? ?? const {});
  String? field(String group, String key) => _text(section(group)[key]);
  DateTime get date => DateTime.parse(field('event', 'startDate')!);
  String get place =>
      field('location', 'venue') ?? field('location', 'region') ?? '장소 미정';
  String? get address => field('location', 'address');
  String? get registrationPeriod {
    final start = field('registration', 'startDate');
    final end = field('registration', 'endDate');
    if (start == null && end == null) return null;
    return '${start ?? '시작 미정'} ~ ${end ?? '마감 미정'}';
  }

  Map<String, dynamic> get prices => Map<String, dynamic>.from(
    section('registration')['price'] as Map? ?? const {},
  );
  Uri? get website {
    for (final value in [
      field('registration', 'site'),
      field('info', 'site'),
      field('event', 'site'),
    ]) {
      final uri = value == null ? null : Uri.tryParse(value);
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        return uri;
      }
    }
    return null;
  }

  bool matches(String query) =>
      [name, description, place, field('location', 'region')]
          .whereType<String>()
          .any((s) => s.toLowerCase().contains(query.toLowerCase()));

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
