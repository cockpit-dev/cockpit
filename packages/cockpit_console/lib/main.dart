import 'package:cockpit_console/cockpit_console.dart';
import 'package:cockpit_console/i18n/console_localization.dart';
import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeConsoleLocalization();
  runApp(
    TranslationProvider(
      child: const ProviderScope(
        retry: consoleProviderRetry,
        child: CockpitConsoleApp(),
      ),
    ),
  );
}
