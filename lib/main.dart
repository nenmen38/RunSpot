import 'package:flutter/widgets.dart';

import 'app/bootstrap.dart';
import 'app/run_quest_app.dart';

Future<void> main() async {
  await initializeApp();
  runApp(const RunQuestApp());
}
