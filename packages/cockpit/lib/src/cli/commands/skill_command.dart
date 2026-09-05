import '../cockpit_cli_runtime.dart';

const String cockpitSkillInstallUrl =
    'https://raw.githubusercontent.com/cockpit-dev/cockpit/main/skills/cockpit/INSTALL.md';

const String cockpitSkillPrompt =
    'First fetch and read the complete Cockpit installation guide with '
    '`curl -fsSL $cockpitSkillInstallUrl`, then install or update the Cockpit '
    'runtime once and load the complete Skill. Use CLI + Skill as the default '
    'control surface; configure one Cockpit MCP server only if this host cannot '
    'reliably run shell commands or typed tools are explicitly needed. Do not '
    'configure a second MCP server or duplicate Skill copy.';

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
