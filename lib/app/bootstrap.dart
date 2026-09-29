import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../firebase_options.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

Future<void> initializeApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );
  await _configureFirebaseMessagingForDebug();
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
