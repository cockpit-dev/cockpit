import 'package:flutter/widgets.dart';
import 'package:cockpit_console/i18n/console_localization.dart';

import 'cockpit_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeConsoleLocalization();
  runApp(buildCockpitConsoleDevelopmentApp());
}
