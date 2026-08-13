import '../cockpit_cli_runtime.dart';

const String cockpitSkillInstallUrl =
    'https://github.com/cockpit-dev/cockpit/blob/main/skills/cockpit/INSTALL.md';

const String cockpitSkillPrompt =
    'Install or update Cockpit for the current AI host, including the CLI, '
    'complete cockpit Skill, native adapter, and cockpit_mcp when supported, '
    'by following $cockpitSkillInstallUrl';

CockpitLeafCommand cockpitSkillCommand(CockpitCliRuntime runtime) =>
    CockpitLeafCommand(
      runtime: runtime,
      name: 'skill',
      description: 'Show the AI prompt to install or update the Cockpit Skill.',
      action: (_) async {
        await runtime.success(<String, Object?>{
          'prompt': cockpitSkillPrompt,
          'docs': cockpitSkillInstallUrl,
        });
        return cockpitSuccessExitCode;
      },
    );
