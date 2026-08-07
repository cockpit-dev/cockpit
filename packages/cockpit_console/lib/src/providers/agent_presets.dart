/// Built-in presets for known ACP-compatible agents.
///
/// Commands and URLs sourced from the official ACP agents page:
/// https://agentclientprotocol.com/get-started/agents
final class AgentPreset {
  const AgentPreset({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
    this.description = '',
    this.icon = 'bot',
    this.docsUrl = '',
  });

  final String id;
  final String name;
  final String command;
  final List<String> args;
  final String description;
  final String icon;
  final String docsUrl;
}

/// All known ACP-compatible agents.
///
/// Links are the exact URLs from agentclientprotocol.com/get-started/agents.
/// Commands are verified from each linked page's ACP quick-start section.
const List<AgentPreset> agentPresets = <AgentPreset>[
  AgentPreset(
    id: 'omp',
    name: 'Oh My Pi',
    command: 'omp',
    args: ['acp'],
    description: 'Oh My Pi agent',
    icon: 'brain',
    docsUrl: 'https://agentclientprotocol.com/get-started/agents',
  ),
  AgentPreset(
    id: 'claude',
    name: 'Claude Code',
    command: 'claude',
    description: 'Anthropic Claude agent (via Zed SDK adapter)',
    icon: 'sparkles',
    docsUrl: 'https://github.com/zed-industries/claude-agent-acp',
  ),
  AgentPreset(
    id: 'cursor',
    name: 'Cursor',
    command: 'agent',
    args: ['acp'],
    description: 'Cursor IDE CLI agent',
    icon: 'mouse-pointer-click',
    docsUrl: 'https://cursor.com/docs/cli/acp',
  ),
  AgentPreset(
    id: 'goose',
    name: 'Goose',
    command: 'goose',
    args: ['acp'],
    description: 'Block Goose AI agent',
    icon: 'bird',
    docsUrl: 'https://block.github.io/goose/docs/guides/acp-clients',
  ),
  AgentPreset(
    id: 'kiro',
    name: 'Kiro',
    command: 'kiro-cli',
    args: ['acp'],
    description: 'AWS Kiro spec-driven agent',
    icon: 'rocket',
    docsUrl: 'https://kiro.dev/docs/cli/acp/',
  ),
  AgentPreset(
    id: 'gemini',
    name: 'Gemini CLI',
    command: 'gemini',
    description: 'Google Gemini coding agent',
    icon: 'gem',
    docsUrl: 'https://github.com/google-gemini/gemini-cli',
  ),
  AgentPreset(
    id: 'codex',
    name: 'Codex CLI',
    command: 'codex',
    description: 'OpenAI Codex CLI (via Zed adapter)',
    icon: 'terminal',
    docsUrl: 'https://github.com/zed-industries/codex-acp',
  ),
  AgentPreset(
    id: 'copilot',
    name: 'GitHub Copilot',
    command: 'copilot',
    args: ['--acp'],
    description: 'GitHub Copilot CLI (public preview)',
    icon: 'github',
    docsUrl: 'https://github.com/features/copilot',
  ),
  AgentPreset(
    id: 'cline',
    name: 'Cline',
    command: 'cline',
    description: 'Cline open-source agent',
    icon: 'code',
    docsUrl: 'https://cline.bot/',
  ),
  AgentPreset(
    id: 'pi',
    name: 'Pi',
    command: 'pi-acp',
    description: 'Pi coding agent (via pi-acp adapter)',
    icon: 'pi',
    docsUrl:
        'https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent',
  ),
  AgentPreset(
    id: 'opencode',
    name: 'OpenCode',
    command: 'opencode',
    description: 'SST OpenCode agent',
    icon: 'braces',
    docsUrl: 'https://github.com/sst/opencode',
  ),
  AgentPreset(
    id: 'openhands',
    name: 'OpenHands',
    command: 'openhands',
    description: 'OpenHands AI agent',
    icon: 'hand',
    docsUrl: 'https://docs.openhands.dev/openhands/usage/run-openhands/acp',
  ),
  AgentPreset(
    id: 'augment',
    name: 'Augment Code',
    command: 'augment',
    description: 'Augment Code CLI agent',
    icon: 'zap',
    docsUrl: 'https://docs.augmentcode.com/cli/acp',
  ),
  AgentPreset(
    id: 'kimi',
    name: 'Kimi CLI',
    command: 'kimi',
    description: 'Moonshot Kimi CLI agent',
    icon: 'moon',
    docsUrl: 'https://github.com/MoonshotAI/kimi-cli',
  ),
  AgentPreset(
    id: 'qwen',
    name: 'Qwen Code',
    command: 'qwen-code',
    description: 'Alibaba Qwen Code agent',
    icon: 'cpu',
    docsUrl: 'https://github.com/QwenLM/qwen-code',
  ),
  AgentPreset(
    id: 'factory',
    name: 'Factory Droid',
    command: 'factory',
    description: 'Factory.ai Droid agent',
    icon: 'factory',
    docsUrl: 'https://factory.ai/',
  ),
  AgentPreset(
    id: 'mistral',
    name: 'Mistral Vibe',
    command: 'mistral-vibe',
    description: 'Mistral AI Vibe agent',
    icon: 'wind',
    docsUrl: 'https://github.com/mistralai/mistral-vibe',
  ),
  AgentPreset(
    id: 'blackbox',
    name: 'Blackbox AI',
    command: 'blackbox',
    description: 'Blackbox AI CLI agent',
    icon: 'box',
    docsUrl: 'https://docs.blackbox.ai/features/blackbox-cli/introduction',
  ),
];

/// Finds a preset by ID.
AgentPreset? findAgentPreset(String? id) {
  if (id == null) return null;
  for (final preset in agentPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
