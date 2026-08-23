import '../cockpit_cli_runtime.dart';

const String cockpitSkillInstallUrl =
    'https://raw.githubusercontent.com/cockpit-dev/cockpit/main/skills/cockpit/INSTALL.md';

const String cockpitSkillPrompt =
    'First fetch and read the complete Cockpit installation guide with '
    '`curl -fsSL $cockpitSkillInstallUrl`, then install or update the CLI, '
    'complete cockpit Skill, native adapter, and cockpit_mcp for the current '
    'AI host exactly as that guide directs.';

CockpitLeafCommand cockpitSkillCommand(CockpitCliRuntime runtime) =>
    CockpitLeafCommand(
      runtime: runtime,
      name: 'skill',
      description: 'Show the AI prompt to install or update the Cockpit Skill.',
      action: (_) async {
        await runtime.success(<String, Object?>{'prompt': cockpitSkillPrompt});
        return cockpitSuccessExitCode;
      },
    );
