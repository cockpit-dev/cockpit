import 'dart:async';
import 'dart:io';

import 'package:acpd/acpd.dart';
import 'package:acpd_io/acpd_io.dart';

Future<void> main(List<String> args) async {
  const sessionId = 'message-stream-session';
  final limitedPromptCapabilities = args.contains('--limited-prompts');
  final fullLifecycle = args.contains('--full-lifecycle');
  final failFirstNewSession = args.contains('--fail-first-new-session');
  var authenticated = !fullLifecycle;
  var sessionCwd = Directory.current.path;
  var nextSessionNumber = 0;
  var newSessionAttempts = 0;
  final sessions = <String, _FixtureSession>{};
  final cancelled = Completer<void>();
  final transport = StdioTransport.stdio();
  final agent = AgentRole()
      .onInitialize((context, request, cancellation) {
        return InitializeResponse(
          protocolVersion: ProtocolVersion.v1,
          agentInfo: Implementation(
            name: 'message-stream-agent',
            version: '1.0.0',
          ),
          agentCapabilities: AgentCapabilities(
            promptCapabilities: PromptCapabilities(
              image: !limitedPromptCapabilities,
              audio: !limitedPromptCapabilities,
              embeddedContext: !limitedPromptCapabilities,
            ),
            loadSession: fullLifecycle,
            sessionCapabilities: fullLifecycle
                ? const SessionCapabilities(
                    list: SessionListCapabilities(),
                    delete: SessionDeleteCapabilities(),
                    additionalDirectories:
                        SessionAdditionalDirectoriesCapabilities(),
                    resume: SessionResumeCapabilities(),
                    close: SessionCloseCapabilities(),
                  )
                : null,
            auth: fullLifecycle
                ? const AgentAuthCapabilities(logout: LogoutCapabilities())
                : null,
          ),
          authMethods: fullLifecycle
              ? const [
                  AgentAuthMethod(
                    AuthMethodAgent(
                      id: 'local-auth',
                      name: 'Local test authentication',
                    ),
                  ),
                ]
              : const [],
        );
      })
      .onAuthenticate((context, request, cancellation) {
        if (!fullLifecycle || request.methodId != 'local-auth') {
          throw const RpcError(
            code: -32602,
            message: 'Unknown authentication method.',
          );
        }
        authenticated = true;
        return const AuthenticateResponse();
      })
      .onLogout((context, request, cancellation) {
        _requireAuthenticated(fullLifecycle, authenticated);
        authenticated = false;
        return const LogoutResponse();
      })
      .onNewSession((context, request, cancellation) {
        _requireAuthenticated(fullLifecycle, authenticated);
        newSessionAttempts++;
        if (failFirstNewSession && newSessionAttempts == 1) {
          throw const RpcError(
            code: -32603,
            message: 'Fixture rejected the first session creation.',
          );
        }
        sessionCwd = request.cwd;
        if (fullLifecycle && sessions.isEmpty) {
          for (var index = 1; index <= 3; index++) {
            final archivedId = 'archived-$index';
            sessions[archivedId] = _FixtureSession(
              sessionId: archivedId,
              cwd: request.cwd,
              additionalDirectories: request.additionalDirectories,
              title: 'Archived session $index',
              updatedAt: '2026-08-0${index}T12:00:00Z',
              includeSelectConfig: true,
            );
          }
        }
        final createdId = fullLifecycle
            ? 'lifecycle-${++nextSessionNumber}'
            : sessionId;
        final created = _FixtureSession(
          sessionId: createdId,
          cwd: request.cwd,
          additionalDirectories: request.additionalDirectories,
          title: fullLifecycle ? 'Lifecycle session' : 'Message stream session',
          includeSelectConfig: fullLifecycle,
        );
        sessions[createdId] = created;
        return created.newSessionResponse;
      })
      .onLoadSession((context, request, cancellation) {
        _requireAuthenticated(fullLifecycle, authenticated);
        final session = _requireSession(sessions, request.sessionId)
          ..cwd = request.cwd
          ..additionalDirectories = request.additionalDirectories;
        sessionCwd = request.cwd;
        return session.loadSessionResponse;
      })
      .onResumeSession((context, request, cancellation) {
        _requireAuthenticated(fullLifecycle, authenticated);
        final session = _requireSession(sessions, request.sessionId)
          ..cwd = request.cwd
          ..additionalDirectories = request.additionalDirectories;
        sessionCwd = request.cwd;
        return session.loadSessionResponse;
      })
      .onListSessions((context, request, cancellation) {
        _requireAuthenticated(fullLifecycle, authenticated);
        final matching = sessions.values
            .where(
              (session) => request.cwd == null || session.cwd == request.cwd,
            )
            .map((session) => session.info)
            .toList(growable: false);
        final start = request.cursor == 'page-2' ? 2 : 0;
        if (start >= matching.length) {
          return const ListSessionsResponse(sessions: []);
        }
        final end = start + 2 < matching.length ? start + 2 : matching.length;
        return ListSessionsResponse(
          sessions: matching.sublist(start, end),
          nextCursor: end < matching.length ? 'page-2' : null,
        );
      })
      .onCloseSession((context, request, cancellation) {
        _requireAuthenticated(fullLifecycle, authenticated);
        _requireSession(sessions, request.sessionId).closed = true;
        return const CloseSessionResponse();
      })
      .onDeleteSession((context, request, cancellation) {
        _requireAuthenticated(fullLifecycle, authenticated);
        if (sessions.remove(request.sessionId) == null) {
          throw const RpcError(code: -32602, message: 'Unknown session.');
        }
        return const DeleteSessionResponse();
      })
      .onSetSessionMode((context, request, cancellation) {
        _requireAuthenticated(fullLifecycle, authenticated);
        final session = _requireSession(sessions, request.sessionId);
        if (request.modeId != 'code' && request.modeId != 'plan') {
          throw const RpcError(code: -32602, message: 'Unknown mode.');
        }
        session.currentModeId = request.modeId;
        return const SetSessionModeResponse();
      })
      .onSetSessionConfigOption((context, request, cancellation) {
        _requireAuthenticated(fullLifecycle, authenticated);
        final session = _requireSession(sessions, request.sessionId);
        switch (request) {
          case SetBooleanConfigOption(:final configId, :final value)
              when configId == 'verbose':
            session.verbose = value;
          case SetValueIdConfigOption(:final configId, :final value)
              when configId == 'model' &&
                  (value == 'fast' || value == 'accurate'):
            session.model = value;
          default:
            throw const RpcError(
              code: -32602,
              message: 'Invalid configuration value.',
            );
        }
        return SetSessionConfigOptionResponse(
          configOptions: session.configOptions,
        );
      })
      .onSessionCancel((context, notification) {
        if (!cancelled.isCompleted) {
          cancelled.complete();
        }
      })
      .onPrompt((context, request, cancellation) async {
        _requireAuthenticated(fullLifecycle, authenticated);
        final prompt = request.prompt.whereType<TextContentBlock>().first.text;
        if (prompt == 'exit-agent') {
          exit(23);
        }
        if (prompt == 'wait-for-cancel') {
          await cancelled.future;
          context.sessionUpdate(
            sessionId: request.sessionId,
            update: AgentMessageChunk(
              chunk: const ContentChunk(
                content: TextContentBlock(text: 'Cancelled by client'),
                messageId: 'cancelled-message',
              ),
            ),
          );
          return const PromptResponse(stopReason: StopReason.cancelled);
        }
        if (prompt == 'request-permission') {
          context.sessionUpdate(
            sessionId: request.sessionId,
            update: ToolCallUpdateSession(
              toolCall: const ToolCall(
                toolCallId: 'permission-tool',
                title: 'Write generated file',
                status: ToolCallStatus.pending,
              ),
            ),
          );
          final outcome = await context.requestPermission(
            RequestPermissionRequest(
              sessionId: request.sessionId,
              toolCall: const ToolCallUpdate(
                toolCallId: 'permission-tool',
                title: 'Write generated file',
              ),
              options: const [
                PermissionOption(
                  optionId: 'allow-once',
                  name: 'Allow once',
                  kind: PermissionOptionKind.allowOnce,
                ),
                PermissionOption(
                  optionId: 'reject-once',
                  name: 'Reject',
                  kind: PermissionOptionKind.rejectOnce,
                ),
              ],
            ),
            timeout: const Duration(seconds: 10),
          );
          final selected = outcome is PermissionSelected
              ? outcome.optionId
              : 'cancelled';
          context
            ..sessionUpdate(
              sessionId: request.sessionId,
              update: ToolCallStatusUpdate(
                update: ToolCallUpdate(
                  toolCallId: 'permission-tool',
                  status: outcome is PermissionSelected
                      ? ToolCallStatus.completed
                      : ToolCallStatus.failed,
                ),
              ),
            )
            ..sessionUpdate(
              sessionId: request.sessionId,
              update: AgentMessageChunk(
                chunk: ContentChunk(
                  content: TextContentBlock(text: 'permission:$selected'),
                  messageId: 'permission-result',
                ),
              ),
            );
          return const PromptResponse(stopReason: StopReason.endTurn);
        }
        if (prompt == 'exercise-client') {
          final read = await context.readTextFile(
            ReadTextFileRequest(
              sessionId: request.sessionId,
              path: 'client-input.txt',
            ),
            timeout: const Duration(seconds: 10),
          );
          await context.writeTextFile(
            WriteTextFileRequest(
              sessionId: request.sessionId,
              path: 'client-output.txt',
              content: 'written-by-agent',
            ),
            timeout: const Duration(seconds: 10),
          );
          final terminal = await context.createTerminal(
            CreateTerminalRequest(
              sessionId: request.sessionId,
              command: Platform.resolvedExecutable,
              args: const ['--version'],
              cwd: sessionCwd,
              outputByteLimit: 4096,
            ),
            timeout: const Duration(seconds: 10),
          );
          final exit = await context.waitForTerminalExit(
            WaitForTerminalExitRequest(
              sessionId: request.sessionId,
              terminalId: terminal.terminalId,
            ),
            timeout: const Duration(seconds: 10),
          );
          final output = await context.terminalOutput(
            TerminalOutputRequest(
              sessionId: request.sessionId,
              terminalId: terminal.terminalId,
            ),
            timeout: const Duration(seconds: 10),
          );
          await context.releaseTerminal(
            ReleaseTerminalRequest(
              sessionId: request.sessionId,
              terminalId: terminal.terminalId,
            ),
            timeout: const Duration(seconds: 10),
          );
          context.sessionUpdate(
            sessionId: request.sessionId,
            update: AgentMessageChunk(
              chunk: ContentChunk(
                content: TextContentBlock(
                  text:
                      'read:${read.content};exit:${exit.exitCode};'
                      'output:${output.output.trim()}',
                ),
                messageId: 'client-result',
              ),
            ),
          );
          return const PromptResponse(stopReason: StopReason.endTurn);
        }
        if (prompt == 'all-updates') {
          _sendAllUpdates(context, request.sessionId);
          return const PromptResponse(stopReason: StopReason.endTurn);
        }
        context
          ..sessionUpdate(
            sessionId: request.sessionId,
            update: AgentMessageChunk(
              chunk: const ContentChunk(
                content: TextContentBlock(text: 'First'),
                messageId: 'assistant-1',
              ),
            ),
          )
          ..sessionUpdate(
            sessionId: request.sessionId,
            update: AgentMessageChunk(
              chunk: const ContentChunk(
                content: TextContentBlock(text: ' message'),
                messageId: 'assistant-1',
              ),
            ),
          )
          ..sessionUpdate(
            sessionId: request.sessionId,
            update: AgentMessageChunk(
              chunk: const ContentChunk(
                content: TextContentBlock(text: 'Second message'),
                messageId: 'assistant-2',
              ),
            ),
          )
          ..sessionUpdate(
            sessionId: request.sessionId,
            update: ToolCallUpdateSession(
              toolCall: const ToolCall(
                toolCallId: 'tool-2',
                title: 'Inspect second message',
                status: ToolCallStatus.inProgress,
              ),
            ),
          );
        return const PromptResponse(stopReason: StopReason.endTurn);
      })
      .connect(transport);

  await agent.closed;
}

void _sendAllUpdates(AgentContext context, String sessionId) {
  context
    ..sessionUpdate(
      sessionId: sessionId,
      update: UserMessageChunk(
        chunk: const ContentChunk(
          content: TextContentBlock(text: 'Canonical user prompt'),
          messageId: 'user-canonical',
        ),
      ),
    )
    ..sessionUpdate(
      sessionId: sessionId,
      update: AgentThoughtChunk(
        chunk: const ContentChunk(
          content: TextContentBlock(text: 'Inspecting state'),
          messageId: 'thought-1',
        ),
      ),
    )
    ..sessionUpdate(
      sessionId: sessionId,
      update: ToolCallUpdateSession(
        toolCall: const ToolCall(
          toolCallId: 'all-tool',
          title: 'Inspect project',
          status: ToolCallStatus.inProgress,
        ),
      ),
    )
    ..sessionUpdate(
      sessionId: sessionId,
      update: ToolCallStatusUpdate(
        update: const ToolCallUpdate(
          toolCallId: 'all-tool',
          status: ToolCallStatus.completed,
          rawOutput: {'files': 3},
        ),
      ),
    )
    ..sessionUpdate(
      sessionId: sessionId,
      update: PlanUpdate(
        plan: const Plan(
          entries: [
            PlanEntry(
              content: 'Inspect project',
              priority: PlanEntryPriority.high,
              status: PlanEntryStatus.completed,
            ),
          ],
        ),
      ),
    )
    ..sessionUpdate(
      sessionId: sessionId,
      update: AvailableCommandsSessionUpdate(
        update: const AvailableCommandsUpdate(
          availableCommands: [
            AvailableCommand(
              name: 'inspect',
              description: 'Inspect the current project',
            ),
          ],
        ),
      ),
    )
    ..sessionUpdate(
      sessionId: sessionId,
      update: CurrentModeSessionUpdate(currentModeId: 'plan'),
    )
    ..sessionUpdate(
      sessionId: sessionId,
      update: ConfigOptionSessionUpdate(
        configOptions: const [
          SessionConfigBooleanOption(
            id: 'verbose',
            name: 'Verbose',
            currentValue: true,
          ),
        ],
      ),
    )
    ..sessionUpdate(
      sessionId: sessionId,
      update: SessionInfoSessionUpdate(
        title: 'Validated session',
        updatedAt: '2026-08-09T12:00:00Z',
      ),
    )
    ..sessionUpdate(
      sessionId: sessionId,
      update: UsageSessionUpdate(
        used: 120,
        size: 4096,
        cost: const Cost(amount: 0.02, currency: 'USD'),
      ),
    )
    ..sessionUpdate(
      sessionId: sessionId,
      update: AgentMessageChunk(
        chunk: const ContentChunk(
          content: TextContentBlock(text: 'All updates complete'),
          messageId: 'all-updates-result',
        ),
      ),
    );
}

void _requireAuthenticated(bool required, bool authenticated) {
  if (required && !authenticated) {
    throw const RpcError(code: -32000, message: 'Authentication is required.');
  }
}

_FixtureSession _requireSession(
  Map<String, _FixtureSession> sessions,
  String sessionId,
) {
  final session = sessions[sessionId];
  if (session == null) {
    throw const RpcError(code: -32602, message: 'Unknown session.');
  }
  return session;
}

final class _FixtureSession {
  _FixtureSession({
    required this.sessionId,
    required this.cwd,
    required this.additionalDirectories,
    required this.title,
    required this.includeSelectConfig,
    this.updatedAt = '2026-08-09T12:00:00Z',
  });

  final String sessionId;
  String cwd;
  List<String> additionalDirectories;
  final String title;
  final bool includeSelectConfig;
  final String updatedAt;
  String currentModeId = 'code';
  bool verbose = false;
  String model = 'fast';
  bool closed = false;

  SessionInfo get info => SessionInfo(
    sessionId: sessionId,
    cwd: cwd,
    additionalDirectories: additionalDirectories,
    title: title,
    updatedAt: updatedAt,
  );

  SessionModeState get modes => SessionModeState(
    currentModeId: currentModeId,
    availableModes: const [
      SessionMode(id: 'code', name: 'Code'),
      SessionMode(id: 'plan', name: 'Plan'),
    ],
  );

  List<SessionConfigOption> get configOptions => [
    SessionConfigBooleanOption(
      id: 'verbose',
      name: 'Verbose',
      currentValue: verbose,
    ),
    if (includeSelectConfig)
      SessionConfigSelectOptionValue(
        id: 'model',
        name: 'Model',
        currentValue: model,
        options: const SessionConfigUngroupedOptions([
          SessionConfigSelectOption(value: 'fast', name: 'Fast'),
          SessionConfigSelectOption(value: 'accurate', name: 'Accurate'),
        ]),
      ),
  ];

  NewSessionResponse get newSessionResponse => NewSessionResponse(
    sessionId: sessionId,
    modes: modes,
    configOptions: configOptions,
  );

  LoadSessionResponse get loadSessionResponse =>
      LoadSessionResponse(modes: modes, configOptions: configOptions);
}
