import 'package:acpd/acpd.dart';

/// A chat message shown in the active ACP session.
final class AcpChatMessage {
  const AcpChatMessage({
    required this.role,
    required this.text,
    this.messageId,
    this.isStreaming = false,
    this.thoughts = const [],
    this.toolCallIds = const [],
    this.content = const [],
  });

  final AcpMessageRole role;
  final String text;
  final String? messageId;
  final bool isStreaming;
  final List<String> thoughts;
  final List<String> toolCallIds;
  final List<ContentBlock> content;

  AcpChatMessage copyWith({
    String? text,
    String? messageId,
    bool? isStreaming,
    List<String>? thoughts,
    List<String>? toolCallIds,
    List<ContentBlock>? content,
  }) {
    return AcpChatMessage(
      role: role,
      text: text ?? this.text,
      messageId: messageId ?? this.messageId,
      isStreaming: isStreaming ?? this.isStreaming,
      thoughts: thoughts ?? this.thoughts,
      toolCallIds: toolCallIds ?? this.toolCallIds,
      content: content ?? this.content,
    );
  }
}

enum AcpMessageRole { user, assistant, error }

/// A permission request surfaced to the user for interactive approval.
final class AcpPermissionPrompt {
  const AcpPermissionPrompt({
    required this.requestId,
    required this.toolCall,
    required this.options,
  });

  final String requestId;
  final AcpToolCallState toolCall;
  final List<PermissionOption> options;

  bool acceptsDecision({required String requestId, String? optionId}) {
    return this.requestId == requestId &&
        (optionId == null ||
            options.any((option) => option.optionId == optionId));
  }
}

/// Authoritative merged state for one ACP tool call.
final class AcpToolCallState {
  const AcpToolCallState({
    required this.toolCallId,
    required this.title,
    this.kind,
    this.status,
    this.content = const [],
    this.locations = const [],
    this.rawInput,
    this.rawOutput,
  });

  factory AcpToolCallState.fromToolCall(ToolCall call) {
    return AcpToolCallState(
      toolCallId: call.toolCallId,
      title: call.title,
      kind: call.kind,
      status: call.status,
      content: List.unmodifiable(call.content),
      locations: List.unmodifiable(call.locations),
      rawInput: call.rawInput,
      rawOutput: call.rawOutput,
    );
  }

  factory AcpToolCallState.fromUpdate(ToolCallUpdate update) {
    return AcpToolCallState(
      toolCallId: update.toolCallId,
      title: update.title ?? update.toolCallId,
      kind: update.kind,
      status: update.status,
      content: List.unmodifiable(update.content ?? const []),
      locations: List.unmodifiable(update.locations ?? const []),
      rawInput: update.rawInput,
      rawOutput: update.rawOutput,
    );
  }

  final String toolCallId;
  final String title;
  final ToolKind? kind;
  final ToolCallStatus? status;
  final List<ToolCallContent> content;
  final List<ToolCallLocation> locations;
  final Object? rawInput;
  final Object? rawOutput;

  AcpToolCallState merge(ToolCallUpdate update) {
    if (update.toolCallId != toolCallId) {
      throw ArgumentError.value(
        update.toolCallId,
        'update.toolCallId',
        'Tool-call updates must be merged into the matching call.',
      );
    }
    return AcpToolCallState(
      toolCallId: toolCallId,
      title: update.title ?? title,
      kind: update.kind ?? kind,
      status: update.status ?? status,
      content: update.content == null
          ? content
          : List.unmodifiable(update.content!),
      locations: update.locations == null
          ? locations
          : List.unmodifiable(update.locations!),
      rawInput: update.rawInput ?? rawInput,
      rawOutput: update.rawOutput ?? rawOutput,
    );
  }
}

const _unsetAcpValue = Object();

/// Immutable state owned by one active ACP session.
final class AcpSessionState {
  const AcpSessionState({
    required this.sessionId,
    required this.cwd,
    this.additionalDirectories = const [],
    this.mcpServers = const [],
    this.modes,
    this.configOptions = const [],
    this.messages = const [],
    this.toolCalls = const {},
    this.plan,
    this.availableCommands = const [],
    this.title,
    this.updatedAt,
    this.usage,
    this.pendingPermission,
    this.isPrompting = false,
  });

  final String sessionId;
  final String cwd;
  final List<String> additionalDirectories;
  final List<McpServer> mcpServers;
  final SessionModeState? modes;
  final List<SessionConfigOption> configOptions;
  final List<AcpChatMessage> messages;
  final Map<String, AcpToolCallState> toolCalls;
  final Plan? plan;
  final List<AvailableCommand> availableCommands;
  final String? title;
  final String? updatedAt;
  final UsageUpdate? usage;
  final AcpPermissionPrompt? pendingPermission;
  final bool isPrompting;

  AcpSessionState copyWith({
    String? sessionId,
    String? cwd,
    List<String>? additionalDirectories,
    List<McpServer>? mcpServers,
    Object? modes = _unsetAcpValue,
    List<SessionConfigOption>? configOptions,
    List<AcpChatMessage>? messages,
    Map<String, AcpToolCallState>? toolCalls,
    Object? plan = _unsetAcpValue,
    List<AvailableCommand>? availableCommands,
    Object? title = _unsetAcpValue,
    Object? updatedAt = _unsetAcpValue,
    Object? usage = _unsetAcpValue,
    Object? pendingPermission = _unsetAcpValue,
    bool? isPrompting,
  }) {
    return AcpSessionState(
      sessionId: sessionId ?? this.sessionId,
      cwd: cwd ?? this.cwd,
      additionalDirectories: List.unmodifiable(
        additionalDirectories ?? this.additionalDirectories,
      ),
      mcpServers: List.unmodifiable(mcpServers ?? this.mcpServers),
      modes: identical(modes, _unsetAcpValue)
          ? this.modes
          : modes as SessionModeState?,
      configOptions: List.unmodifiable(configOptions ?? this.configOptions),
      messages: List.unmodifiable(messages ?? this.messages),
      toolCalls: Map.unmodifiable(toolCalls ?? this.toolCalls),
      plan: identical(plan, _unsetAcpValue) ? this.plan : plan as Plan?,
      availableCommands: List.unmodifiable(
        availableCommands ?? this.availableCommands,
      ),
      title: identical(title, _unsetAcpValue) ? this.title : title as String?,
      updatedAt: identical(updatedAt, _unsetAcpValue)
          ? this.updatedAt
          : updatedAt as String?,
      usage: identical(usage, _unsetAcpValue)
          ? this.usage
          : usage as UsageUpdate?,
      pendingPermission: identical(pendingPermission, _unsetAcpValue)
          ? this.pendingPermission
          : pendingPermission as AcpPermissionPrompt?,
      isPrompting: isPrompting ?? this.isPrompting,
    );
  }
}

enum AcpAuthStatus {
  unavailable,
  available,
  required,
  authenticating,
  authenticated,
  loggingOut,
}

enum AcpBusyAction {
  authenticate,
  logout,
  createSession,
  loadSession,
  resumeSession,
  closeSession,
  deleteSession,
  listSessions,
  setMode,
  setConfig,
}

/// Default inputs used when the user creates the next ACP session.
final class AcpSessionSpec {
  const AcpSessionSpec({
    required this.cwd,
    this.additionalDirectories = const [],
    this.mcpServers = const [],
  });

  final String cwd;
  final List<String> additionalDirectories;
  final List<McpServer> mcpServers;
}

sealed class AcpAgentState {
  const AcpAgentState();
}

final class AcpDisconnected extends AcpAgentState {
  const AcpDisconnected();
}

final class AcpConnecting extends AcpAgentState {
  const AcpConnecting();
}

/// A live ACP connection, optionally with one selected active session.
final class AcpConnected extends AcpAgentState {
  const AcpConnected({
    required this.agentInfo,
    required this.protocolVersion,
    required this.capabilities,
    this.authMethods = const [],
    this.authStatus = AcpAuthStatus.unavailable,
    this.sessionDefaults,
    this.activeSession,
    this.recentSessions = const [],
    this.nextSessionCursor,
    this.busy,
    this.lastError,
  });

  final Implementation agentInfo;
  final ProtocolVersion protocolVersion;
  final AgentCapabilities capabilities;
  final List<AuthMethod> authMethods;
  final AcpAuthStatus authStatus;
  final AcpSessionSpec? sessionDefaults;
  final AcpSessionState? activeSession;
  final List<SessionInfo> recentSessions;
  final String? nextSessionCursor;
  final AcpBusyAction? busy;
  final String? lastError;

  String? get sessionId => activeSession?.sessionId;
  List<SessionMode> get modes =>
      activeSession?.modes?.availableModes ?? const [];
  List<AcpChatMessage> get messages => activeSession?.messages ?? const [];
  AcpPermissionPrompt? get pendingPermission =>
      activeSession?.pendingPermission;
  bool get isPrompting => activeSession?.isPrompting ?? false;
  bool get canLoadSessions => capabilities.loadSession;
  bool get canListSessions => capabilities.sessionCapabilities?.list != null;
  bool get canDeleteSessions =>
      capabilities.sessionCapabilities?.delete != null;
  bool get canResumeSessions =>
      capabilities.sessionCapabilities?.resume != null;
  bool get canCloseSessions => capabilities.sessionCapabilities?.close != null;
  bool get canLogout => capabilities.auth?.logout != null;

  AcpConnected copyWith({
    Implementation? agentInfo,
    ProtocolVersion? protocolVersion,
    AgentCapabilities? capabilities,
    List<AuthMethod>? authMethods,
    AcpAuthStatus? authStatus,
    Object? sessionDefaults = _unsetAcpValue,
    Object? activeSession = _unsetAcpValue,
    List<SessionInfo>? recentSessions,
    Object? nextSessionCursor = _unsetAcpValue,
    Object? busy = _unsetAcpValue,
    Object? lastError = _unsetAcpValue,
  }) {
    return AcpConnected(
      agentInfo: agentInfo ?? this.agentInfo,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      capabilities: capabilities ?? this.capabilities,
      authMethods: List.unmodifiable(authMethods ?? this.authMethods),
      authStatus: authStatus ?? this.authStatus,
      sessionDefaults: identical(sessionDefaults, _unsetAcpValue)
          ? this.sessionDefaults
          : sessionDefaults as AcpSessionSpec?,
      activeSession: identical(activeSession, _unsetAcpValue)
          ? this.activeSession
          : activeSession as AcpSessionState?,
      recentSessions: List.unmodifiable(recentSessions ?? this.recentSessions),
      nextSessionCursor: identical(nextSessionCursor, _unsetAcpValue)
          ? this.nextSessionCursor
          : nextSessionCursor as String?,
      busy: identical(busy, _unsetAcpValue)
          ? this.busy
          : busy as AcpBusyAction?,
      lastError: identical(lastError, _unsetAcpValue)
          ? this.lastError
          : lastError as String?,
    );
  }
}

final class AcpError extends AcpAgentState {
  const AcpError(this.message);

  final String message;
}
