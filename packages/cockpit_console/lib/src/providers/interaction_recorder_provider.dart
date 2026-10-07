import 'dart:async';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core_providers.dart';
import 'session_monitor_models.dart';

/// Live-timeline refresh cadence while the recorder page is visible.
const Duration interactionRecorderPollInterval = Duration(seconds: 2);

/// Recorder boundary of one resolved live session, in the payload shapes the
/// page renders. A console-side seam over [CockpitInteractionRecordingService]
/// so the page and its tests share one contract.
abstract interface class InteractionRecorderClient {
  Uri get baseUri;

  Future<Map<String, Object?>> start({String? name});

  Future<Map<String, Object?>> pause();

  Future<Map<String, Object?>> resume();

  Future<Map<String, Object?>> stop();

  Future<Map<String, Object?>> status();

  Future<Map<String, Object?>> steps({int after = 0});

  Future<String> exportCaseYaml();
}

/// Production client over the shared application service.
final class RemoteInteractionRecorderClient
    implements InteractionRecorderClient {
  RemoteInteractionRecorderClient(this.baseUri)
    : _service = CockpitInteractionRecordingService.forBaseUri(baseUri);

  @override
  final Uri baseUri;

  final CockpitInteractionRecordingService _service;

  @override
  Future<Map<String, Object?>> start({String? name}) =>
      _service.start(name: name);

  @override
  Future<Map<String, Object?>> pause() => _service.pause();

  @override
  Future<Map<String, Object?>> resume() => _service.resume();

  @override
  Future<Map<String, Object?>> stop() => _service.stop();

  @override
  Future<Map<String, Object?>> status() => _service.status();

  @override
  Future<Map<String, Object?>> steps({int after = 0}) =>
      _service.steps(after: after);

  @override
  Future<String> exportCaseYaml() async => (await _service.export()).caseYaml;
}

/// Resolves the recorder client of a development session, mirroring the
/// `record` CLI: `session.development.get` proves the session ready and the
/// live bridge base URL is read from its output exactly once.
typedef InteractionRecorderConnector =
    Future<InteractionRecorderClient> Function(SessionMonitorKey key);

Future<InteractionRecorderClient> connectInteractionRecorder(
  Ref ref,
  SessionMonitorKey key,
) async {
  final client = await ref.read(supervisorProvider.notifier).ensureClient();
  final result = await client.executeOperation(
    kind: 'session.development.get',
    workspaceId: key.workspaceId,
    input: <String, Object?>{'sessionId': key.sessionId},
  );
  if (result['outcome'] != 'succeeded') {
    throw StateError(_operationFailure(result));
  }
  final output = result['output'];
  final baseUri = cockpitInteractionRecorderBaseUri(
    output is Map ? Map<String, Object?>.from(output) : null,
  );
  return RemoteInteractionRecorderClient(baseUri);
}

final interactionRecorderConnectorProvider =
    Provider<InteractionRecorderConnector>(
      (ref) =>
          (key) => connectInteractionRecorder(ref, key),
    );

// ── State ─────────────────────────────────────────────────────────────────

final class InteractionRecorderState {
  const InteractionRecorderState({
    this.selected,
    this.endpoint,
    this.connecting = false,
    this.connectionError,
    this.phase = CockpitRecorderPhase.idle,
    this.sessionId,
    this.stepCount = 0,
    this.unresolvedCount = 0,
    this.steps = const <CockpitInteractionStep>[],
    this.commandBusy = false,
    this.commandError,
    this.exporting = false,
    this.document,
  });

  final SessionMonitorKey? selected;
  final Uri? endpoint;
  final bool connecting;
  final String? connectionError;
  final CockpitRecorderPhase phase;
  final String? sessionId;
  final int stepCount;
  final int unresolvedCount;
  final List<CockpitInteractionStep> steps;
  final bool commandBusy;
  final String? commandError;
  final bool exporting;
  final String? document;

  bool get canStart =>
      phase == CockpitRecorderPhase.idle ||
      phase == CockpitRecorderPhase.stopped;

  bool get canPause => phase == CockpitRecorderPhase.recording;

  bool get canResume => phase == CockpitRecorderPhase.paused;

  bool get canStop =>
      phase == CockpitRecorderPhase.recording ||
      phase == CockpitRecorderPhase.paused;

  bool get canExport => sessionId != null;

  InteractionRecorderState copyWith({
    SessionMonitorKey? selected,
    Uri? endpoint,
    bool? connecting,
    Object? connectionError = _unset,
    CockpitRecorderPhase? phase,
    Object? sessionId = _unset,
    int? stepCount,
    int? unresolvedCount,
    List<CockpitInteractionStep>? steps,
    bool? commandBusy,
    Object? commandError = _unset,
    bool? exporting,
    Object? document = _unset,
  }) => InteractionRecorderState(
    selected: selected ?? this.selected,
    endpoint: endpoint ?? this.endpoint,
    connecting: connecting ?? this.connecting,
    connectionError: connectionError == _unset
        ? this.connectionError
        : connectionError as String?,
    phase: phase ?? this.phase,
    sessionId: sessionId == _unset ? this.sessionId : sessionId as String?,
    stepCount: stepCount ?? this.stepCount,
    unresolvedCount: unresolvedCount ?? this.unresolvedCount,
    steps: steps ?? this.steps,
    commandBusy: commandBusy ?? this.commandBusy,
    commandError: commandError == _unset
        ? this.commandError
        : commandError as String?,
    exporting: exporting ?? this.exporting,
    document: document == _unset ? this.document : document as String?,
  );

  static const Object _unset = Object();
}

// ── Notifier ──────────────────────────────────────────────────────────────

/// Live state of the interaction recorder bound to one monitored session.
///
/// Polling follows the session monitor's lifecycle: the page starts it when
/// it becomes visible and stops it on dispose; each tick reads the session
/// status and drains steps after the consumed-step cursor.
final class InteractionRecorderNotifier
    extends Notifier<InteractionRecorderState> {
  Timer? _pollTimer;
  bool _polling = false;
  InteractionRecorderClient? _client;
  int _cursor = 0;
  String? _consumedSessionId;
  int _connectGeneration = 0;

  @override
  InteractionRecorderState build() {
    ref.onDispose(() => _pollTimer?.cancel());
    return const InteractionRecorderState();
  }

  void startPolling() {
    if (_pollTimer != null) return;
    unawaited(poll());
    _pollTimer = Timer.periodic(
      interactionRecorderPollInterval,
      (_) => unawaited(poll()),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Binds the page to [key], resetting any recording view of the previous
  /// session, and resolves its live recorder endpoint.
  void select(SessionMonitorKey key) {
    if (key == state.selected && _client != null) return;
    _connectGeneration++;
    _client = null;
    _cursor = 0;
    _consumedSessionId = null;
    state = InteractionRecorderState(selected: key);
    unawaited(connect());
  }

  /// (Re)resolves the endpoint of the selected session. A selection change
  /// while an attempt is in flight supersedes it: the stale result is
  /// discarded so the page never adopts another session's endpoint.
  Future<void> connect() async {
    final key = state.selected;
    if (key == null || state.connecting) return;
    final generation = ++_connectGeneration;
    state = state.copyWith(connecting: true, connectionError: null);
    try {
      final client = await ref.read(interactionRecorderConnectorProvider)(key);
      if (!ref.mounted || generation != _connectGeneration) return;
      _client = client;
      _cursor = 0;
      _consumedSessionId = null;
      state = state.copyWith(
        connecting: false,
        endpoint: client.baseUri,
        steps: const <CockpitInteractionStep>[],
        document: null,
      );
      unawaited(poll());
    } on Object catch (error) {
      if (!ref.mounted || generation != _connectGeneration) return;
      _client = null;
      state = state.copyWith(connecting: false, connectionError: '$error');
    }
  }

  Future<void> start({String? name}) async =>
      _command((client) => client.start(name: name));

  Future<void> pause() async => _command((client) => client.pause());

  Future<void> resume() async => _command((client) => client.resume());

  Future<void> stop() async => _command((client) => client.stop());

  Future<void> _command(
    Future<Map<String, Object?>> Function(InteractionRecorderClient) run,
  ) async {
    final client = _client;
    if (client == null || state.commandBusy) return;
    state = state.copyWith(commandBusy: true, commandError: null);
    try {
      await run(client);
    } on Object catch (error) {
      if (!ref.mounted) return;
      // A selection change always resets the busy flag; an error only
      // belongs to the session the command was issued against.
      state = state.copyWith(
        commandBusy: false,
        commandError: identical(client, _client) ? '$error' : null,
      );
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(commandBusy: false);
    if (identical(client, _client)) await poll();
  }

  /// Reads the session status and drains newly settled steps.
  Future<void> poll() async {
    final client = _client;
    if (client == null || _polling) return;
    _polling = true;
    try {
      final status = await client.status();
      // The bound session may have changed while awaiting; the stale read
      // must not leak into the new session's timeline, and a provider
      // disposed with its page must not receive state at all.
      if (!ref.mounted || !identical(client, _client)) return;
      final sessionId = status['sessionId'] as String?;
      // A sessionId the page has not consumed yet means a new recording
      // session started on the app; the timeline restarts from its steps.
      final newSession = sessionId != null && sessionId != _consumedSessionId;
      if (newSession) {
        _cursor = 0;
        _consumedSessionId = sessionId;
      }
      final drained = await client.steps(after: _cursor);
      if (!ref.mounted || !identical(client, _client)) return;
      final rawSteps = drained['steps'];
      final appended = rawSteps is List<Object?>
          ? <CockpitInteractionStep>[
              for (final step in rawSteps)
                CockpitInteractionStep.fromJson(step),
            ]
          : const <CockpitInteractionStep>[];
      final total = drained['total'];
      if (total is int) _cursor = total;
      state = state.copyWith(
        connectionError: null,
        phase: CockpitRecorderPhase.fromJson(status['phase']),
        sessionId: sessionId,
        stepCount: sessionId == null ? 0 : status['stepCount'] as int? ?? 0,
        unresolvedCount: sessionId == null
            ? 0
            : status['unresolvedCount'] as int? ?? 0,
        steps: newSession
            ? appended
            : appended.isEmpty
            ? state.steps
            : <CockpitInteractionStep>[...state.steps, ...appended],
      );
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(connectionError: '$error');
      }
    } finally {
      _polling = false;
    }
  }

  /// Exports the current recording as case YAML for the preview pane.
  Future<void> export() async {
    final client = _client;
    if (client == null || state.exporting) return;
    state = state.copyWith(exporting: true, commandError: null);
    try {
      final yaml = await client.exportCaseYaml();
      if (!ref.mounted) return;
      // A stale export must not preview another session's document.
      state = state.copyWith(
        exporting: false,
        document: identical(client, _client) ? yaml : null,
      );
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        exporting: false,
        commandError: identical(client, _client) ? '$error' : null,
      );
    }
  }
}

final interactionRecorderProvider =
    NotifierProvider<InteractionRecorderNotifier, InteractionRecorderState>(
      InteractionRecorderNotifier.new,
    );

String _operationFailure(Map<String, Object?> result) {
  final failure = result['failure'];
  if (failure is Map) {
    final primary = failure['primary'];
    if (primary is Map) {
      final message = primary['message'];
      if (message is String && message.isNotEmpty) return message;
      final code = primary['code'];
      if (code is String && code.isNotEmpty) return code;
    }
  }
  return '${result['kind'] ?? 'Operation'} failed.';
}
