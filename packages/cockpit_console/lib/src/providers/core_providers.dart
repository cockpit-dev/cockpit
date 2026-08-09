import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/navigation/console_nav.dart';

/// Keeps asynchronous reads responsive while honoring Cockpit's authoritative
/// retryability contract. Permanent protocol failures surface immediately;
/// transient failures receive two short retries before the UI offers an
/// explicit retry action.
Duration? consoleProviderRetry(int retryCount, Object error) {
  if (error is CockpitApiException && !error.error.retryable) return null;
  if (error is CockpitSupervisorClientException &&
      error.apiError?.retryable == false) {
    return null;
  }
  return ProviderContainer.defaultRetry(
    retryCount,
    error,
    maxRetries: 2,
    minDelay: const Duration(milliseconds: 250),
    maxDelay: const Duration(seconds: 1),
  );
}

/// Thin console adapter over the canonical [CockpitSupervisorApiClient].
///
/// Console flows speak the provider-facing shapes they always have (raw maps
/// and JSON event lines); this adapter translates those into the typed
/// protocol requests the production client validates, and back into the shapes
/// the data providers already consume. There is no hand-written REST, SSE, or
/// daemon discovery here — all of that lives in the canonical client.
final class ConsoleSupervisorClient {
  ConsoleSupervisorClient._(this._api);

  final CockpitSupervisorApiClient _api;

  /// The canonical lifecycle client, exposed for daemon lifecycle providers.
  CockpitDaemonLifecycleClient get lifecycle => _api.lifecycle;

  Future<CockpitServerInfo> server() => _api.server();

  Future<CockpitCapabilityDocument> capabilities() => _api.capabilities();

  Future<List<CockpitRootResource>> roots() => _api.roots();

  Future<CockpitRootResource> registerRoot({
    required String path,
    String? label,
  }) => _api.registerRoot(CockpitRootRegistration(path: path, label: label));

  /// Retires a registered root via the canonical retirement endpoint.
  Future<void> removeRoot({required String rootId, bool force = false}) async {
    await _api.removeRoot(rootId, CockpitRootRemoval(force: force));
  }

  Future<List<CockpitWorkspaceResource>> workspaces() => _api.workspaces();

  Future<CockpitWorkspaceResource> registerWorkspace({
    required String rootId,
    required String path,
  }) => _api.registerWorkspace(
    CockpitWorkspaceRegistration(rootId: rootId, path: path),
  );

  Future<CockpitWorkspaceResource> rebindWorkspace({
    required String workspaceId,
    required String path,
    required String expectedCheckoutId,
  }) => _api.rebindWorkspace(
    workspaceId,
    CockpitWorkspaceRebind(path: path, expectedCheckoutId: expectedCheckoutId),
  );

  /// Retires a registered workspace via the canonical retirement endpoint.
  Future<void> removeWorkspace({
    required String workspaceId,
    bool force = false,
  }) async {
    await _api.removeWorkspace(
      workspaceId,
      CockpitWorkspaceRemoval(force: force),
    );
  }

  Future<List<CockpitAutomationTargetResource>> targets(String workspaceId) =>
      _api.targets(workspaceId);

  Future<List<CockpitOperationDescriptor>> operations({String? workspaceId}) =>
      _api.operations(workspaceId: workspaceId);

  /// Invokes an advertised operation, returning its full typed result envelope.
  ///
  /// The scope identity is explicit: [rootId] for root-scoped operations,
  /// [workspaceId] for workspace-scoped operations, and neither for
  /// supervisor-scoped operations. The typed [CockpitOperationInvocation]
  /// performs the scope and idempotency validation; [idempotencyKey] rides the
  /// invocation envelope directly, so it is never lifted from or stripped out
  /// of [input]. The request body matches the production CLI exactly.
  Future<Map<String, Object?>> executeOperation({
    required String kind,
    String? rootId,
    String? workspaceId,
    Map<String, Object?> input = const {},
    String? idempotencyKey,
  }) async {
    final invocation = CockpitOperationInvocation(
      kind: kind,
      input: input,
      rootId: rootId,
      workspaceId: workspaceId,
      idempotencyKey: idempotencyKey == null || idempotencyKey.isEmpty
          ? null
          : CockpitIdempotencyKey(idempotencyKey),
    );
    final result = await _api.executeOperation(invocation);
    return result.toJson();
  }

  Future<List<CockpitDocumentResource>> documents(
    String workspaceId, {
    CockpitIndexedDocumentKind? kind,
    bool authoredOnly = false,
  }) => _api.documents(workspaceId, kind: kind, authoredOnly: authoredOnly);

  Future<List<CockpitCaseIndexEntry>> cases(String workspaceId) =>
      _api.cases(workspaceId);

  /// Validates an inline document, mapping the console's loose map shape into
  /// the typed [CockpitDocumentValidationRequest] and the typed result back
  /// into the map the document editor consumes (`valid`, `diagnostics`).
  Future<Map<String, Object?>> validateDocument(
    String workspaceId, {
    required String sourceText,
    required String relativePath,
    String format = 'yaml',
  }) async {
    final result = await _api.validateCaseDocument(
      workspaceId,
      CockpitDocumentValidationRequest(
        format: CockpitDocumentFormat.values.byName(format),
        sourceText: sourceText,
        relativePath: relativePath,
      ),
    );
    return result.toJson();
  }

  /// Submits a typed case or suite source through the canonical client.
  Future<Map<String, Object?>> submitRun(
    String workspaceId, {
    required CockpitRunSubmissionSource source,
    required String idempotencyKey,
    Map<String, Object?>? inputs,
    String? targetId,
    int? timeoutMs,
  }) async {
    final submission = CockpitRunSubmission(
      workspaceId: workspaceId,
      source: source,
      idempotencyKey: CockpitIdempotencyKey(idempotencyKey),
      inputs: inputs ?? const <String, Object?>{},
      targetId: targetId,
      timeoutMs: timeoutMs,
    );
    final accepted = await _api.submitRun(submission);
    return accepted.toJson();
  }

  /// Fetches a run resource as the JSON map the runs screen renders.
  Future<Map<String, Object?>> getRun(String runId) async =>
      (await _api.run(runId)).toJson();

  /// Cancels a run via the typed cancellation request.
  Future<Map<String, Object?>> cancelRun(
    String runId, {
    required String idempotencyKey,
    String? reason,
  }) async {
    final cancellation = await _api.cancelRun(
      runId,
      CockpitRunCancellationRequest(
        idempotencyKey: CockpitIdempotencyKey(idempotencyKey),
        reason: reason,
      ),
    );
    return cancellation.toJson();
  }

  Future<List<CockpitArtifactResource>> artifacts(String runId) =>
      _api.artifacts(runId);

  /// Downloads an artifact to [destination], inheriting the canonical client's
  /// atomic write, size, digest, and media-type integrity verification. Throws
  /// if [destination] already exists or verification fails.
  Future<void> downloadArtifactToFile({
    required CockpitArtifactResource artifact,
    required File destination,
  }) async {
    await _api.downloadArtifactToFile(
      artifact: artifact,
      destination: destination,
    );
  }

  /// Canonical run event stream mapped into the JSON strings the run provider
  /// consumes. Each event item yields the full run-event JSON
  /// (`kind`, `sequence`, `lifecycle`, `entityKind`, `outcome`, …); terminal,
  /// gap, and disconnection items yield a recognizable `kind` marker so the
  /// run provider can surface them. SSE framing, resume, and bounds are owned
  /// entirely by the canonical client.
  Stream<String> events(String runId, {int afterSequence = 0}) async* {
    await for (final item in _api.events(runId, afterSequence: afterSequence)) {
      switch (item) {
        case CockpitRunStreamEvent():
          yield jsonEncode(item.event.toJson());
        case CockpitRunStreamGap():
          yield jsonEncode(<String, Object?>{
            'kind': 'gap',
            ...item.boundary.toJson(),
          });
        case CockpitRunStreamTerminal():
          yield jsonEncode(<String, Object?>{
            'kind': 'terminal',
            'afterSequence': item.afterSequence,
          });
        case CockpitRunStreamDisconnected():
          yield jsonEncode(<String, Object?>{
            'kind': 'disconnected',
            'afterSequence': item.afterSequence,
          });
      }
    }
  }
}

/// Creates a [ConsoleSupervisorClient] over a canonical supervisor client.
///
/// Unlike a silent daemon launch, this inspects lifecycle status first and
/// surfaces a stopped or unhealthy daemon as an explicit error so connection
/// failures become provider state instead of a surprise spawn.
Future<ConsoleSupervisorClient> createConsoleSupervisorClient() async {
  final api = await createCockpitSupervisorApiClient();
  final status = await api.lifecycle.status();
  if (!status.running || !status.healthy) {
    throw Exception(_describeDaemonStatus(status));
  }
  return ConsoleSupervisorClient._(api);
}

String _describeDaemonStatus(CockpitDaemonStatus status) {
  if (!status.running) {
    return 'Cockpit daemon is not running. '
        'Start it with: cockpit daemon start --yolo';
  }
  return 'Cockpit daemon is unhealthy (${status.diagnostic ?? 'unavailable'}). '
      'Restart it with: cockpit daemon restart --yolo';
}

// ── Connection state ─────────────────────────────────────────────────────

sealed class SupervisorState {
  const SupervisorState();
}

final class SupervisorInitial extends SupervisorState {
  const SupervisorInitial();
}

final class SupervisorConnecting extends SupervisorState {
  const SupervisorConnecting();
}

final class SupervisorConnected extends SupervisorState {
  const SupervisorConnected({required this.server, required this.capabilities});

  final CockpitServerInfo server;
  final CockpitCapabilityDocument capabilities;
}

final class SupervisorDisconnected extends SupervisorState {
  const SupervisorDisconnected(this.message);
  final String message;
}

/// Race-safe supervisor connection controller.
///
/// Connection is single-flight (concurrent [connect] calls share one attempt)
/// and generation-guarded so a stale connect that completes after a
/// disconnect, reconnect, or superseding connect can never overwrite the newer
/// state. A failed candidate is discarded rather than retained.
final class SupervisorNotifier extends Notifier<SupervisorState> {
  ConsoleSupervisorClient? _client;
  Future<void>? _connectFuture;
  int _generation = 0;

  @override
  SupervisorState build() {
    ref.onDispose(_reset);
    return const SupervisorInitial();
  }

  /// The connected client, or `null` when not connected.
  ConsoleSupervisorClient? get client => _client;

  /// Returns the connected client, throwing if not connected.
  ConsoleSupervisorClient requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Supervisor client is not connected.');
    }
    return client;
  }

  /// Resolves a connected client, connecting first if necessary. Throws on
  /// connection failure rather than returning a stale or absent client.
  Future<ConsoleSupervisorClient> ensureClient() async {
    final existing = _client;
    if (existing != null) return existing;
    await connect();
    final client = _client;
    if (client == null) {
      throw StateError('Supervisor client is not connected.');
    }
    return client;
  }

  /// Connects to the supervisor, single-flight and race-safe.
  Future<void> connect() async {
    final pending = _connectFuture;
    if (pending != null) {
      await pending;
      return;
    }
    final generation = ++_generation;
    state = const SupervisorConnecting();
    final attempt = _connect(generation);
    _connectFuture = attempt;
    try {
      await attempt;
    } finally {
      if (identical(_connectFuture, attempt)) _connectFuture = null;
    }
  }

  Future<void> _connect(int generation) async {
    try {
      final candidate = await createConsoleSupervisorClient();
      final server = await candidate.server();
      final capabilities = await candidate.capabilities();
      if (generation != _generation) return;
      _client = candidate;
      state = SupervisorConnected(server: server, capabilities: capabilities);
    } on Object catch (error) {
      if (generation != _generation) return;
      _client = null;
      state = SupervisorDisconnected('$error');
    }
  }

  /// Refreshes server info and capabilities on an existing connection, or
  /// connects if none exists.
  Future<void> refresh() async {
    final client = _client;
    if (client == null) {
      await connect();
      return;
    }
    final generation = _generation;
    try {
      final server = await client.server();
      final capabilities = await client.capabilities();
      if (generation != _generation) return;
      state = SupervisorConnected(server: server, capabilities: capabilities);
    } on Object catch (error) {
      if (generation != _generation) return;
      _client = null;
      state = SupervisorDisconnected('$error');
    }
  }

  /// Forces the connection into an explicit unavailable state. Used by the
  /// daemon lifecycle provider when a daemon mutation takes the supervisor
  /// offline; any in-flight connect is invalidated.
  void markUnavailable(String message) {
    _generation++;
    _connectFuture = null;
    _client = null;
    state = SupervisorDisconnected(message);
  }

  /// Resets the connection to its initial, never-tried state.
  void disconnect() {
    _generation++;
    _connectFuture = null;
    _client = null;
    state = const SupervisorInitial();
  }

  void _reset() {
    _generation++;
    _connectFuture = null;
    _client = null;
  }
}

final supervisorProvider =
    NotifierProvider<SupervisorNotifier, SupervisorState>(
      SupervisorNotifier.new,
    );

// ── Daemon lifecycle ─────────────────────────────────────────────────────

final class DaemonState {
  const DaemonState({
    this.running = false,
    this.healthy = false,
    this.busy = false,
    this.error,
  });

  final bool running;
  final bool healthy;
  final bool busy;
  final String? error;

  DaemonState copyWith({
    bool? running,
    bool? healthy,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return DaemonState(
      running: running ?? this.running,
      healthy: healthy ?? this.healthy,
      busy: busy ?? this.busy,
      error: clearError ? null : error ?? this.error,
    );
  }
}

/// Real daemon lifecycle controller backed by [CockpitDaemonLifecycleClient].
///
/// Refresh/start/stop/restart perform actual lifecycle mutations using the
/// restricted authorization default, and synchronize supervisor connection
/// state after each mutation so the UI reflects reality.
final class DaemonNotifier extends Notifier<DaemonState> {
  CockpitDaemonLifecycleClient? _lifecycle;
  int _generation = 0;

  @override
  DaemonState build() {
    ref.onDispose(() => _lifecycle = null);
    return const DaemonState();
  }

  /// Resolves the canonical lifecycle client, reusing the same home/package
  /// resolution as the supervisor client factory.
  Future<CockpitDaemonLifecycleClient> _client() async {
    final cached = _lifecycle;
    if (cached != null) return cached;
    final api = await createCockpitSupervisorApiClient();
    return _lifecycle = api.lifecycle;
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final lifecycle = await _client();
      final status = await lifecycle.status();
      if (generation != _generation) return;
      state = DaemonState(
        running: status.running,
        healthy: status.healthy,
        busy: false,
      );
      _syncSupervisor(status);
    } on Object catch (error) {
      if (generation != _generation) return;
      state = DaemonState(busy: false, error: '$error');
    }
  }

  Future<void> start() async {
    final generation = ++_generation;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final lifecycle = await _client();
      await lifecycle.start();
      final status = await lifecycle.status();
      if (generation != _generation) return;
      state = DaemonState(
        running: status.running,
        healthy: status.healthy,
        busy: false,
      );
      _syncSupervisor(status, forceReconnect: true);
    } on Object catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(busy: false, error: '$error');
    }
  }

  Future<void> stop() async {
    final generation = ++_generation;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final lifecycle = await _client();
      await lifecycle.stop();
      final status = await lifecycle.status();
      if (generation != _generation) return;
      state = DaemonState(
        running: status.running,
        healthy: status.healthy,
        busy: false,
      );
      _syncSupervisor(status);
    } on Object catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(busy: false, error: '$error');
    }
  }

  Future<void> restart() async {
    final generation = ++_generation;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final lifecycle = await _client();
      final previous = await lifecycle.status();
      await lifecycle.scheduleRestart(
        authorizationMode:
            previous.authorizationMode ?? CockpitAuthorizationMode.restricted,
      );
      final status = await _waitForRestart(
        lifecycle,
        previousProcessId: previous.processId,
      );
      if (generation != _generation) return;
      state = DaemonState(
        running: status.running,
        healthy: status.healthy,
        busy: false,
      );
      _syncSupervisor(status, forceReconnect: true);
    } on Object catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(busy: false, error: '$error');
    }
  }

  Future<CockpitDaemonStatus> _waitForRestart(
    CockpitDaemonLifecycleClient lifecycle, {
    required int? previousProcessId,
  }) async {
    final deadline = DateTime.now().add(lifecycle.startTimeout);
    var observedUnavailable = previousProcessId == null;
    while (DateTime.now().isBefore(deadline)) {
      final status = await lifecycle.status();
      if (!status.running || !status.healthy) observedUnavailable = true;
      if (status.running &&
          status.healthy &&
          (observedUnavailable || status.processId != previousProcessId)) {
        return status;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const CockpitDaemonException(
      'daemonStartTimeout',
      'Scheduled daemon restart did not publish a healthy replacement.',
    );
  }

  /// Reconciles the supervisor connection with the live daemon status.
  void _syncSupervisor(
    CockpitDaemonStatus status, {
    bool forceReconnect = false,
  }) {
    final supervisor = ref.read(supervisorProvider.notifier);
    if (!status.running || !status.healthy) {
      supervisor.markUnavailable('Daemon is not available.');
      return;
    }
    if (forceReconnect) supervisor.disconnect();
    if (forceReconnect ||
        ref.read(supervisorProvider) is! SupervisorConnected) {
      unawaited(supervisor.connect());
    }
  }
}

final daemonProvider = NotifierProvider<DaemonNotifier, DaemonState>(
  DaemonNotifier.new,
);

// ── Theme mode ───────────────────────────────────────────────────────────

final class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void toggle(Brightness effectiveBrightness) {
    state = effectiveBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  void set(ThemeMode mode) {
    state = mode;
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);

// ── Navigation ───────────────────────────────────────────────────────────

final class NavNotifier extends Notifier<ConsoleNavDestination> {
  @override
  ConsoleNavDestination build() => ConsoleNavDestination.dashboard;

  void go(ConsoleNavDestination dest) {
    state = dest;
  }
}

final navProvider = NotifierProvider<NavNotifier, ConsoleNavDestination>(
  NavNotifier.new,
);

// ── Selected workspace ───────────────────────────────────────────────────

final class _WorkspaceIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) {
    state = id;
  }
}

final selectedWorkspaceIdProvider =
    NotifierProvider<_WorkspaceIdNotifier, String?>(_WorkspaceIdNotifier.new);
