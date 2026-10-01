import 'dart:convert';
import 'dart:io';

Future<Map<String, String>> loadLocalDevConfig() async {
  final file = File('config/dev.json');
  if (!file.existsSync()) {
    return const {};
  }

  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    return const {};
  }

  return {
    'SUPABASE_URL': _stringValue(decoded['SUPABASE_URL']),
    'SUPABASE_PUBLISHABLE_KEY': _stringValue(
      decoded['SUPABASE_PUBLISHABLE_KEY'],
    ),
  };
}

String _stringValue(Object? value) => value is String ? value : '';
