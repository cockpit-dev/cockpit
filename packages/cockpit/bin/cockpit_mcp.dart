import 'package:cockpit/cockpit.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'profile',
      allowed: CockpitMcpProfile.values.map((profile) => profile.name),
      defaultsTo: CockpitMcpProfile.core.name,
    )
    ..addMultiOption('enable')
    ..addMultiOption('disable', abbr: 'x');
  final options = parser.parse(arguments);
  await CockpitMcpServer.standard(
    featureConfiguration: CockpitMcpFeatureConfiguration.forProfile(
      CockpitMcpProfile.parse(options.option('profile')!),
      enabledNames: options.multiOption('enable').toSet(),
      disabledNames: options.multiOption('disable').toSet(),
    ),
  ).serveStdio();
}
