import 'package:args/args.dart';

void cockpitAddDevSessionOption(ArgParser parser) {
  parser.addOption(
    'session',
    abbr: 's',
    help: 'Select an exact development session.',
  );
}
