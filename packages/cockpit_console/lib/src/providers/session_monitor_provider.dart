import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'core_providers.dart';
import 'session_monitor_models.dart';

const _summaryRefreshInterval = Duration(seconds: 6);
const _surfaceProbeInterval = Duration(seconds: 15);
const _summaryOperationTimeout = Duration(seconds: 5);
const _remoteStatusTimeout = Duration(seconds: 3);
const _activeActivityLimit = 2000;
const _stoppedActivityLimit = 200;
const _maximumStoppedSessions = 100;
const _workspaceRefreshConcurrency = 6;
const _sessionRefreshConcurrency = 4;

final class SessionMonitorNotifier extends Notifier<SessionMonitorState> {
  Timer? _refreshTimer;
  bool _refreshing = false;
  bool _forceProbePending = false;
  int _generation = 0;
  final Map<SessionMonitorKey, DateTime> _lastProbeAt = {};
  final Set<(SessionMonitorKey, SessionMonitorSection)> _sectionLoads =
      <(SessionMonitorKey, SessionMonitorSection)>{};

  @override
  SessionMonitorState build() {
    ref.onDispose(() => _refreshTimer?.cancel());
    return const SessionMonitorState();
  }

  void start() {
    if (_refreshTimer != null) return;
    unawaited(refresh(forceProbe: true));
    _refreshTimer = Timer.periodic(
      _summaryRefreshInterval,
      (_) => unawaited(refresh()),
    );
  }

  void stop() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _forceProbePending = false;
    _generation++;
  }

  Future<void> refresh({bool forceProbe = false}) async {
    if (_refreshing) {
      if (forceProbe) {
        _forceProbePending = true;
        if (!state.loading) state = state.copyWith(loading: true);
      }
      return;
    }
    _refreshing = true;
    final generation = ++_generation;
    final showLoading = forceProbe || state.sessions.isEmpty;
    if (state.loading != showLoading) {
      state = state.copyWith(loading: showLoading);
    }
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final workspaces = await client.workspaces();
      final activeWorkspaces = workspaces
          .where((workspace) => workspace.state == CockpitWorkspaceState.active)
          .toList(growable: false);
      final targetsByWorkspace = await _mapConcurrent(
        activeWorkspaces,
        concurrency: _workspaceRefreshConcurrency,
        task: (workspace) async {
          try {
            return _WorkspaceTargetRead(
              workspace: workspace,
              targets: await client.targets(workspace.workspaceId),
            );
          } on Object catch (error) {
            return _WorkspaceTargetRead(
              workspace: workspace,
              error: _friendlyError(error),
            );
          }
        },
      );
      if (generation != _generation) return;

      final now = DateTime.now().toUtc();
      final previousByKey = <SessionMonitorKey, MonitoredSession>{
        for (final session in state.sessions) session.key: session,
      };
      final failedWorkspaceIds = <String>{};
      final failedWorkspaceMessages = <String, SessionMonitorMessage>{};
      final discovered = <MonitoredSession>[];
      final details = Map<SessionMonitorKey, SessionMonitorDetail>.of(
        state.details,
      );
      for (final group in targetsByWorkspace) {
        final targets = group.targets;
        if (targets == null) {
          failedWorkspaceIds.add(group.workspace.workspaceId);
          failedWorkspaceMessages[group.workspace.workspaceId] =
              group.error == null
              ? const SessionMonitorMessage.projectRefreshFailed()
              : SessionMonitorMessage.raw(group.error!);
          continue;
        }
        for (final target in targets) {
          final sessionId = target.sessionId;
          if (sessionId == null) continue;
          final key = SessionMonitorKey(
            workspaceId: group.workspace.workspaceId,
            sessionId: sessionId,
          );
          final previous = previousByKey.remove(key);
          final next = MonitoredSession(
            key: key,
            projectPath: group.workspace.canonicalPath,
            projectName: p.basename(group.workspace.canonicalPath),
            targetId: target.targetId,
            platform: target.platform,
            deviceId: target.deviceId,
            targetKind: target.targetKind,
            entrypoint: target.entrypoint,
            flavor: target.flavor,
            appId: target.appId,
            state: previous?.state ?? 'checking',
            lastSeenAt: previous?.lastSeenAt ?? now,
            route: previous?.route,
            appReachable: previous?.appReachable,
            bridgeReachable: previous?.bridgeReachable ?? false,
            reloadGeneration: previous?.reloadGeneration ?? 0,
            runtimeStatusAt: previous?.runtimeStatusAt,
            errorCount: previous?.errorCount ?? 0,
            networkFailureCount: previous?.networkFailureCount ?? 0,
            networkInFlightCount: previous?.networkInFlightCount ?? 0,
            message: previous?.message,
          );
          discovered.add(next);
          if (previous == null) {
            final detail = details[key] ?? const SessionMonitorDetail();
            details[key] = _appendActivity(detail, _changeActivity(null, next));
          }
        }
      }
      for (final missing in previousByKey.values) {
        final refreshFailed = failedWorkspaceIds.contains(
          missing.key.workspaceId,
        );
        final next = missing.copyWith(
          state: refreshFailed ? 'unavailable' : 'stopped',
          appReachable: refreshFailed ? missing.appReachable : false,
          bridgeReachable: refreshFailed ? missing.bridgeReachable : false,
          message: refreshFailed
              ? failedWorkspaceMessages[missing.key.workspaceId]
              : const SessionMonitorMessage.stopped(),
        );
        discovered.add(next);
        if (missing.state != next.state) {
          final detail = details[missing.key] ?? const SessionMonitorDetail();
          details[missing.key] = _appendActivity(
            detail,
            _changeActivity(missing, next),
            limit: refreshFailed ? _activeActivityLimit : _stoppedActivityLimit,
          );
        }
      }
      final retainedSessions = _retainSessions(discovered);
      final retainedKeys = {
        for (final session in retainedSessions) session.key,
      };
      details.removeWhere((key, _) => !retainedKeys.contains(key));
      _lastProbeAt.removeWhere((key, _) => !retainedKeys.contains(key));
      retainedSessions.sort(_compareSessions);
      final selected = _resolveSelection(state.selected, retainedSessions);
      final selectionManual =
          state.selectionManual &&
          state.selected != null &&
          retainedSessions.any((session) => session.key == state.selected);
      final retainedDetails = _retainSelectedDetails(details, selected);
      final nextError = failedWorkspaceIds.isEmpty
          ? null
          : SessionMonitorMessage.refreshFailed(failedWorkspaceIds.length);
      if (!_sameSessions(state.sessions, retainedSessions) ||
          !_sameDetails(state.details, retainedDetails) ||
          state.selected != selected ||
          state.selectionManual != selectionManual ||
          state.loading ||
          !_sameMessage(state.error, nextError)) {
        state = state.copyWith(
          sessions: retainedSessions,
          details: retainedDetails,
          selected: selected,
          selectionManual: selectionManual,
          loading: false,
          error: nextError,
          updatedAt: now,
        );
      }

      final activeSessions = retainedSessions
          .where((session) => session.state != 'stopped')
          .toList(growable: false);
      final probeAt = DateTime.now().toUtc();
      final summaries = await _mapConcurrent(
        activeSessions,
        concurrency: _sessionRefreshConcurrency,
        task: (session) => _readSummary(
          client,
          session,
          probeSurface:
              session.key == selected &&
              (forceProbe || _shouldProbe(session.key, probeAt)),
          probeAt: probeAt,
        ),
      );
      if (generation != _generation) return;
      _applySummaries(summaries);
    } on Object catch (error) {
      if (generation == _generation) {
        state = state.copyWith(
          loading: false,
          error: SessionMonitorMessage.raw('$error'),
        );
      }
    } finally {
      _refreshing = false;
      if (_forceProbePending) {
        _forceProbePending = false;
        unawaited(refresh(forceProbe: true));
      }
    }
  }

  void select(SessionMonitorKey key) {
    if (!state.sessions.any((session) => session.key == key)) return;
    state = state.copyWith(
      selected: key,
      selectionManual: true,
      details: _retainSelectedDetails(state.details, key),
    );
    unawaited(loadSection(key, SessionMonitorSection.overview));
    unawaited(refresh(forceProbe: true));
  }

  bool selectTarget({required String workspaceId, required String targetId}) {
    for (final session in state.sessions) {
      if (session.key.workspaceId == workspaceId &&
          session.targetId == targetId) {
        select(session.key);
        return true;
      }
    }
    return false;
  }

  Future<void> loadSection(
    SessionMonitorKey key,
    SessionMonitorSection section, {
    bool silent = false,
  }) async {
    if (section == SessionMonitorSection.activity) return;
    final loadKey = (key, section);
    if (!_sectionLoads.add(loadKey)) return;
    final current = state.detail(key);
    if (!silent) {
      _setDetail(
        key,
        current.copyWith(
          loadingSections: {...current.loadingSections, section},
          sectionErrors: Map.of(current.sectionErrors)..remove(section),
        ),
      );
    }
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final update = switch (section) {
        SessionMonitorSection.overview => await _loadOverview(client, key),
        SessionMonitorSection.ui => await _loadUi(client, key),
        SessionMonitorSection.logs => await _loadLogs(client, key),
        SessionMonitorSection.network => await _loadNetwork(client, key),
        SessionMonitorSection.diagnostics => await _loadDiagnostics(
          client,
          key,
        ),
        SessionMonitorSection.activity => const _DetailUpdate(),
      };
      if (state.selected != key) return;
      final latest = state.detail(key);
      _setDetail(
        key,
        update.apply(
          latest.copyWith(
            loadingSections: {...latest.loadingSections}..remove(section),
            sectionErrors: Map.of(latest.sectionErrors)..remove(section),
            updatedAt: DateTime.now().toUtc(),
          ),
        ),
      );
    } on Object catch (error) {
      if (state.selected != key) return;
      if (silent) return;
      final latest = state.detail(key);
      _setDetail(
        key,
        latest.copyWith(
          loadingSections: {...latest.loadingSections}..remove(section),
          sectionErrors: {...latest.sectionErrors, section: '$error'},
        ),
      );
    } finally {
      _sectionLoads.remove(loadKey);
    }
  }

  Future<void> loadNetworkBody(
    SessionMonitorKey key, {
    required String requestId,
    required String body,
    bool raw = false,
  }) async {
    final cacheKey = '$requestId:$body:${raw ? 'raw' : 'safe'}';
    final current = state.detail(key);
    if (current.loadingNetworkBodies.contains(cacheKey)) return;
    _setDetail(
      key,
      current.copyWith(
        loadingNetworkBodies: {...current.loadingNetworkBodies, cacheKey},
        networkBodyErrors: Map.of(current.networkBodyErrors)..remove(cacheKey),
      ),
    );
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final output = await _operation(
        client,
        'network.body',
        key,
        input: <String, Object?>{
          'requestId': requestId,
          'body': body,
          'raw': raw,
        },
      );
      final latest = state.detail(key);
      _setDetail(
        key,
        latest.copyWith(
          networkBodies: {...latest.networkBodies, cacheKey: output},
          loadingNetworkBodies: {...latest.loadingNetworkBodies}
            ..remove(cacheKey),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } on Object catch (error) {
      final latest = state.detail(key);
      _setDetail(
        key,
        latest.copyWith(
          loadingNetworkBodies: {...latest.loadingNetworkBodies}
            ..remove(cacheKey),
          networkBodyErrors: {
            ...latest.networkBodyErrors,
            cacheKey: _friendlyError(error),
          },
        ),
      );
    }
  }

  Future<void> loadOlderNetwork(SessionMonitorKey key) async {
    final current = state.detail(key);
    if (current.loading(SessionMonitorSection.network)) return;
    final network = current.network;
    final entries = _mapList(network?['entries']);
    if (network == null || entries.isEmpty) return;
    final before = _entryId(entries.last);
    if (before == null) return;
    _setDetail(
      key,
      current.copyWith(
        loadingSections: {
          ...current.loadingSections,
          SessionMonitorSection.network,
        },
        sectionErrors: Map.of(current.sectionErrors)
          ..remove(SessionMonitorSection.network),
      ),
    );
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final page = await _operation(
        client,
        'network.read',
        key,
        input: <String, Object?>{
          'before': before,
          'includeEntries': true,
          'maxEntries': 1000,
          'maxEndpointSummaries': 1000,
        },
      );
      final merged = <Map<String, Object?>>[...entries];
      final seen = entries.map(_entryId).whereType<String>().toSet();
      for (final entry in _mapList(page['entries'])) {
        final id = _entryId(entry);
        if (id == null || seen.add(id)) merged.add(entry);
      }
      final pageSummary = _map(page['summary']);
      final total = _integer(pageSummary?['totalEntryCount']);
      final mergedSummary = <String, Object?>{
        ...?pageSummary,
        'capturedEntryCount': merged.length,
        'truncated': total > merged.length,
      };
      final latest = state.detail(key);
      _setDetail(
        key,
        latest.copyWith(
          network: <String, Object?>{
            ...page,
            'entries': merged,
            'summary': mergedSummary,
          },
          loadingSections: {...latest.loadingSections}
            ..remove(SessionMonitorSection.network),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } on Object catch (error) {
      final latest = state.detail(key);
      _setDetail(
        key,
        latest.copyWith(
          loadingSections: {...latest.loadingSections}
            ..remove(SessionMonitorSection.network),
          sectionErrors: {
            ...latest.sectionErrors,
            SessionMonitorSection.network: _friendlyError(error),
          },
        ),
      );
    }
  }

  bool _shouldProbe(SessionMonitorKey key, DateTime now) {
    final lastProbe = _lastProbeAt[key];
    if (lastProbe == null) return true;
    return now.difference(lastProbe) >= _surfaceProbeInterval;
  }

  Future<_SessionSummary> _readSummary(
    ConsoleSupervisorClient client,
    MonitoredSession session, {
    required bool probeSurface,
    required DateTime probeAt,
  }) async {
    try {
      final identity = await _operation(
        client,
        'session.development.get',
        session.key,
        timeout: _summaryOperationTimeout,
      );
      final status = _map(identity['status']);
      final lifecycle = _string(status?['state']) ?? 'unavailable';
      final appReachable = status?['appReachable'] as bool?;
      final bridgeReachable = status?['remoteSessionReachable'] == true;
      final reloadGeneration = _integer(status?['reloadGeneration']);
      final runtimeStatusAt = _date(status?['lastStatusAt']);
      final runtimeMessage =
          _string(status?['lastError']) ??
          _string(identity['recommendedNextStep']);
      if (!bridgeReachable) {
        return _SessionSummary(
          key: session.key,
          state: lifecycle,
          route: session.route,
          appReachable: appReachable,
          bridgeReachable: false,
          reloadGeneration: reloadGeneration,
          runtimeStatusAt: runtimeStatusAt,
          errorCount: session.errorCount,
          networkFailureCount: session.networkFailureCount,
          networkInFlightCount: session.networkInFlightCount,
          message: runtimeMessage == null
              ? const SessionMonitorMessage.bridgeReconnecting()
              : SessionMonitorMessage.raw(runtimeMessage),
        );
      }
      if (!probeSurface) {
        return _SessionSummary(
          key: session.key,
          state: lifecycle,
          route: session.route,
          appReachable: appReachable,
          bridgeReachable: true,
          reloadGeneration: reloadGeneration,
          runtimeStatusAt: runtimeStatusAt,
          errorCount: session.errorCount,
          networkFailureCount: session.networkFailureCount,
          networkInFlightCount: session.networkInFlightCount,
          message: null,
        );
      }
      _lastProbeAt[session.key] = probeAt;
      final remoteStatusRead = await _tryOperation(
        client,
        'session.remote.status',
        session.key,
        input: const <String, Object?>{'profile': 'minimal'},
        timeout: _remoteStatusTimeout,
      );
      final remoteStatus = remoteStatusRead.output;
      final snapshot = _map(remoteStatus?['snapshot']);
      final runtime = _map(snapshot?['runtime']);
      final network = _map(snapshot?['network']);
      return _SessionSummary(
        key: session.key,
        state: lifecycle,
        route:
            _string(remoteStatus?['currentRouteName']) ??
            _string(snapshot?['routeName']) ??
            session.route,
        appReachable: appReachable,
        bridgeReachable: true,
        reloadGeneration: reloadGeneration,
        runtimeStatusAt: runtimeStatusAt,
        errorCount: runtime == null
            ? session.errorCount
            : _integer(runtime['errorCount']),
        networkFailureCount: network == null
            ? session.networkFailureCount
            : _integer(network['failureCount']),
        networkInFlightCount: network == null
            ? session.networkInFlightCount
            : _integer(network['inFlightCount']),
        message: remoteStatusRead.error == null
            ? null
            : SessionMonitorMessage.raw(remoteStatusRead.error!),
      );
    } on Object catch (error) {
      return _SessionSummary(
        key: session.key,
        state: 'unavailable',
        route: session.route,
        appReachable: session.appReachable,
        bridgeReachable: false,
        reloadGeneration: session.reloadGeneration,
        runtimeStatusAt: session.runtimeStatusAt,
        errorCount: session.errorCount,
        networkFailureCount: session.networkFailureCount,
        networkInFlightCount: session.networkInFlightCount,
        message: SessionMonitorMessage.raw(_friendlyError(error)),
      );
    }
  }

  void _applySummaries(List<_SessionSummary> summaries) {
    final summariesByKey = {
      for (final summary in summaries) summary.key: summary,
    };
    final updated = <MonitoredSession>[];
    final details = Map<SessionMonitorKey, SessionMonitorDetail>.of(
      state.details,
    );
    final now = DateTime.now().toUtc();
    for (final session in state.sessions) {
      final summary = summariesByKey[session.key];
      if (summary == null) {
        updated.add(session);
        continue;
      }
      final next = _sessionMatchesSummary(session, summary)
          ? session
          : session.copyWith(
              state: summary.state,
              lastSeenAt: now,
              route: summary.route,
              appReachable: summary.appReachable,
              bridgeReachable: summary.bridgeReachable,
              reloadGeneration: summary.reloadGeneration,
              runtimeStatusAt: summary.runtimeStatusAt,
              errorCount: summary.errorCount,
              networkFailureCount: summary.networkFailureCount,
              networkInFlightCount: summary.networkInFlightCount,
              message: summary.message,
            );
      updated.add(next);
      final currentDetail =
          details[session.key] ?? const SessionMonitorDetail();
      var nextDetail = _appendActivity(
        currentDetail,
        _changeActivity(session, next),
      );
      if (!identical(next, session)) {
        nextDetail = nextDetail.copyWith(updatedAt: now);
      }
      details[session.key] = nextDetail;
    }
    updated.sort(_compareSessions);
    final selected = state.selectionManual
        ? state.selected
        : _preferredSelection(updated) ?? state.selected;
    final retainedDetails = _retainSelectedDetails(details, selected);
    if (!_sameSessions(state.sessions, updated) ||
        !_sameDetails(state.details, retainedDetails) ||
        state.selected != selected ||
        state.loading) {
      state = state.copyWith(
        sessions: updated,
        details: retainedDetails,
        selected: selected,
        loading: false,
        updatedAt: now,
      );
    }
  }

  Future<_DetailUpdate> _loadOverview(
    ConsoleSupervisorClient client,
    SessionMonitorKey key,
  ) async => _DetailUpdate(
    identity: await _operation(client, 'session.development.get', key),
  );

  Future<_DetailUpdate> _loadUi(
    ConsoleSupervisorClient client,
    SessionMonitorKey key,
  ) async {
    final values = await Future.wait([
      _operation(
        client,
        'ui.inspect',
        key,
        input: const <String, Object?>{
          'profile': 'tree',
          'snapshotOptions': <String, Object?>{
            'profile': 'forensic',
            'maxTargets': 100000,
            'maxAncestorsPerTarget': 256,
            'maxPropertiesPerTarget': 100000,
            'includeStyleDetails': true,
            'includeDiagnosticProperties': true,
            'artifact': 'large',
            'includeRebuildActivity': true,
            'maxRebuildEntries': 10000,
            'includeNetworkActivity': false,
            'includeRuntimeActivity': false,
            'includeAccessibilitySummary': true,
            'maxAccessibilityEntries': 10000,
          },
        },
      ),
      _operation(
        client,
        'ui.inspect',
        key,
        input: const <String, Object?>{
          'profile': 'tree',
          'snapshotOptions': <String, Object?>{
            'profile': 'forensic',
            'maxTargets': 0,
            'maxAncestorsPerTarget': 0,
            'maxPropertiesPerTarget': 0,
            'artifact': 'large',
            'includeRebuildActivity': false,
            'includeNetworkActivity': false,
            'includeRuntimeActivity': false,
            'includeAccessibilitySummary': false,
            'tree': <String, Object?>{
              'profile': 'full',
              'maxNodes': 500000,
              'maxProps': 256,
            },
          },
        },
      ),
    ]);
    final snapshotOutput = values[0];
    final treeOutput = values[1];
    final snapshot = await _hydrateArtifact(
      snapshotOutput,
      referenceField: 'diagnosticsArtifactRef',
      inlineValue: _map(snapshotOutput['snapshot']),
    );
    final treeSnapshot = _map(treeOutput['snapshot']);
    final tree = await _hydrateArtifact(
      treeOutput,
      referenceField: 'treeArtifactRef',
      inlineValue: _map(treeSnapshot?['tree']),
    );
    final hydratedSnapshot = _map(snapshot.value);
    final hydratedTree = _map(tree.value);
    return _DetailUpdate(
      ui: <String, Object?>{
        ...snapshotOutput,
        'snapshot': ?hydratedSnapshot,
        'fullTree': ?hydratedTree,
        'completeness': <String, Object?>{
          'snapshotLoaded': hydratedSnapshot != null,
          'widgetTreeLoaded': hydratedTree != null,
          if (snapshot.path != null) 'snapshotPath': snapshot.path,
          if (tree.path != null) 'widgetTreePath': tree.path,
          if (snapshot.error != null) 'snapshotError': snapshot.error,
          if (tree.error != null) 'widgetTreeError': tree.error,
        },
      },
    );
  }

  Future<_HydratedArtifact> _hydrateArtifact(
    Map<String, Object?> output, {
    required String referenceField,
    required Map<String, Object?>? inlineValue,
  }) async {
    final snapshot = _map(output['snapshot']);
    final reference = _map(snapshot?[referenceField]);
    final relativePath = _string(reference?['relativePath']);
    final paths = _map(output['artifactSourcePaths']);
    final sourcePath = relativePath == null
        ? null
        : _string(paths?[relativePath]);
    if (sourcePath == null) {
      return _HydratedArtifact(value: inlineValue);
    }
    try {
      final decoded = await Isolate.run<Object?>(() async {
        final source = await File(sourcePath).readAsString();
        return jsonDecode(source);
      });
      return _HydratedArtifact(value: decoded, path: sourcePath);
    } on Object catch (error) {
      return _HydratedArtifact(
        value: inlineValue,
        path: sourcePath,
        error: _friendlyError(error),
      );
    }
  }

  Future<_DetailUpdate> _loadLogs(
    ConsoleSupervisorClient client,
    SessionMonitorKey key,
  ) async {
    final values = await Future.wait([
      _tryOperation(
        client,
        'logs.read',
        key,
        input: const <String, Object?>{'maxLines': 1000},
      ),
      _tryOperation(
        client,
        'session.logs.read',
        key,
        input: const <String, Object?>{'maxLines': 1000},
      ),
    ]);
    final appLogs = values[0];
    final sessionLogs = values[1];
    return _DetailUpdate(
      logs:
          appLogs.output ??
          <String, Object?>{
            'available': false,
            'missingReason': appLogs.error ?? 'Application logs unavailable.',
            'lines': const <String>[],
          },
      sessionLogs:
          sessionLogs.output ??
          <String, Object?>{
            'available': false,
            'missingReason':
                sessionLogs.error ?? 'Session logs are unavailable.',
            'lines': const <String>[],
          },
    );
  }

  Future<_DetailUpdate> _loadNetwork(
    ConsoleSupervisorClient client,
    SessionMonitorKey key,
  ) async => _DetailUpdate(
    network: await _operation(
      client,
      'network.read',
      key,
      input: const <String, Object?>{
        'includeEntries': true,
        'maxEntries': 1000,
        'maxEndpointSummaries': 1000,
      },
    ),
  );

  Future<_DetailUpdate> _loadDiagnostics(
    ConsoleSupervisorClient client,
    SessionMonitorKey key,
  ) async {
    final values = await Future.wait([
      _tryOperation(
        client,
        'errors.read',
        key,
        input: const <String, Object?>{'maxErrors': 1000},
      ),
      _tryOperation(
        client,
        'session.logs.read',
        key,
        input: const <String, Object?>{'maxLines': 5000},
      ),
    ]);
    final errors = values[0];
    if (errors.output == null) {
      throw StateError(errors.error ?? 'Runtime errors are unavailable.');
    }
    final sessionLogs = values[1];
    return _DetailUpdate(
      errors: errors.output,
      sessionLogs:
          sessionLogs.output ??
          <String, Object?>{
            'available': false,
            'missingReason':
                sessionLogs.error ?? 'Session logs are unavailable.',
            'lines': const <String>[],
          },
    );
  }

  Future<Map<String, Object?>> _operation(
    ConsoleSupervisorClient client,
    String kind,
    SessionMonitorKey key, {
    Map<String, Object?> input = const <String, Object?>{},
    Duration? timeout,
  }) async {
    final result = await client.executeOperation(
      kind: kind,
      workspaceId: key.workspaceId,
      input: <String, Object?>{'sessionId': key.sessionId, ...input},
      timeout: timeout,
    );
    if (result['outcome'] != 'succeeded') {
      throw StateError(_operationFailure(result));
    }
    final output = result['output'];
    if (output is! Map) {
      throw StateError('$kind returned no structured output.');
    }
    return Map<String, Object?>.from(output);
  }

  Future<_OperationRead> _tryOperation(
    ConsoleSupervisorClient client,
    String kind,
    SessionMonitorKey key, {
    Map<String, Object?> input = const <String, Object?>{},
    Duration? timeout,
  }) async {
    try {
      return _OperationRead(
        output: await _operation(
          client,
          kind,
          key,
          input: input,
          timeout: timeout,
        ),
      );
    } on Object catch (error) {
      return _OperationRead(error: _friendlyError(error));
    }
  }

  void _setDetail(SessionMonitorKey key, SessionMonitorDetail detail) {
    if (state.selected != key) return;
    state = state.copyWith(details: {...state.details, key: detail});
  }
}

final sessionMonitorProvider =
    NotifierProvider<SessionMonitorNotifier, SessionMonitorState>(
      SessionMonitorNotifier.new,
    );

final class _SessionSummary {
  const _SessionSummary({
    required this.key,
    required this.state,
    required this.route,
    required this.appReachable,
    required this.bridgeReachable,
    required this.reloadGeneration,
    required this.runtimeStatusAt,
    required this.errorCount,
    required this.networkFailureCount,
    required this.networkInFlightCount,
    required this.message,
  });

  final SessionMonitorKey key;
  final String state;
  final String? route;
  final bool? appReachable;
  final bool bridgeReachable;
  final int reloadGeneration;
  final DateTime? runtimeStatusAt;
  final int errorCount;
  final int networkFailureCount;
  final int networkInFlightCount;
  final SessionMonitorMessage? message;
}

final class _OperationRead {
  const _OperationRead({this.output, this.error});

  final Map<String, Object?>? output;
  final String? error;
}

final class _HydratedArtifact {
  const _HydratedArtifact({this.value, this.path, this.error});

  final Object? value;
  final String? path;
  final String? error;
}

final class _WorkspaceTargetRead {
  const _WorkspaceTargetRead({
    required this.workspace,
    this.targets,
    this.error,
  });

  final CockpitWorkspaceResource workspace;
  final List<CockpitAutomationTargetResource>? targets;
  final String? error;
}

final class _DetailUpdate {
  const _DetailUpdate({
    this.identity,
    this.ui,
    this.logs,
    this.network,
    this.errors,
    this.sessionLogs,
  });

  final Map<String, Object?>? identity;
  final Map<String, Object?>? ui;
  final Map<String, Object?>? logs;
  final Map<String, Object?>? network;
  final Map<String, Object?>? errors;
  final Map<String, Object?>? sessionLogs;

  SessionMonitorDetail apply(SessionMonitorDetail detail) => detail.copyWith(
    identity: identity ?? detail.identity,
    ui: ui ?? detail.ui,
    logs: logs ?? detail.logs,
    network: network ?? detail.network,
    errors: errors ?? detail.errors,
    sessionLogs: sessionLogs ?? detail.sessionLogs,
  );
}

SessionMonitorKey? _resolveSelection(
  SessionMonitorKey? selected,
  List<MonitoredSession> sessions,
) {
  if (selected != null && sessions.any((session) => session.key == selected)) {
    return selected;
  }
  for (final session in sessions) {
    if (session.state != 'stopped') return session.key;
  }
  return sessions.firstOrNull?.key;
}

SessionMonitorKey? _preferredSelection(List<MonitoredSession> sessions) {
  for (final session in sessions) {
    if (session.healthy) return session.key;
  }
  for (final session in sessions) {
    if (session.live) return session.key;
  }
  return sessions.firstOrNull?.key;
}

List<MonitoredSession> _retainSessions(List<MonitoredSession> sessions) {
  final active = <MonitoredSession>[];
  final stopped = <MonitoredSession>[];
  for (final session in sessions) {
    (session.state == 'stopped' ? stopped : active).add(session);
  }
  stopped.sort((left, right) => right.lastSeenAt.compareTo(left.lastSeenAt));
  return <MonitoredSession>[
    ...active,
    ...stopped.take(_maximumStoppedSessions),
  ];
}

int _compareSessions(MonitoredSession left, MonitoredSession right) {
  final stateCompare = _stateRank(
    left.state,
  ).compareTo(_stateRank(right.state));
  if (stateCompare != 0) return stateCompare;
  final projectCompare = left.projectPath.compareTo(right.projectPath);
  if (projectCompare != 0) return projectCompare;
  return left.key.sessionId.compareTo(right.key.sessionId);
}

int _stateRank(String state) => switch (state) {
  'ready' => 0,
  'starting' || 'reloading' || 'restarting' || 'checking' => 1,
  'unavailable' || 'failed' => 2,
  'stopped' => 3,
  _ => 2,
};

List<SessionMonitorActivity> _changeActivity(
  MonitoredSession? previous,
  MonitoredSession next,
) {
  if (previous == null) {
    return <SessionMonitorActivity>[
      SessionMonitorActivity(
        at: next.lastSeenAt,
        kind: SessionMonitorActivityKind.discovered,
        severity: SessionMonitorSeverity.info,
        platform: next.platform,
        device: next.deviceId,
      ),
    ];
  }
  final changes = <SessionMonitorActivity>[];
  if (previous.state != next.state) {
    changes.add(
      SessionMonitorActivity(
        at: next.lastSeenAt,
        kind: next.state == 'ready'
            ? SessionMonitorActivityKind.connected
            : SessionMonitorActivityKind.changed,
        severity: next.state == 'ready'
            ? SessionMonitorSeverity.success
            : next.state == 'failed'
            ? SessionMonitorSeverity.error
            : SessionMonitorSeverity.warning,
        from: previous.state,
        to: next.state,
      ),
    );
  }
  if (previous.appReachable != next.appReachable) {
    changes.add(
      SessionMonitorActivity(
        at: next.lastSeenAt,
        kind: next.appReachable == false
            ? SessionMonitorActivityKind.appUnavailable
            : SessionMonitorActivityKind.appReachable,
        severity: next.appReachable == false
            ? SessionMonitorSeverity.warning
            : SessionMonitorSeverity.success,
        value: next.platform,
      ),
    );
  }
  if (previous.bridgeReachable != next.bridgeReachable) {
    changes.add(
      SessionMonitorActivity(
        at: next.lastSeenAt,
        kind: next.bridgeReachable
            ? SessionMonitorActivityKind.bridgeConnected
            : SessionMonitorActivityKind.bridgeDisconnected,
        severity: next.bridgeReachable
            ? SessionMonitorSeverity.success
            : SessionMonitorSeverity.warning,
        value: next.key.sessionId,
      ),
    );
  }
  if (previous.route != next.route && next.route != null) {
    changes.add(
      SessionMonitorActivity(
        at: next.lastSeenAt,
        kind: SessionMonitorActivityKind.routeChanged,
        severity: SessionMonitorSeverity.info,
        from: previous.route,
        to: next.route,
      ),
    );
  }
  if (next.errorCount > previous.errorCount) {
    changes.add(
      SessionMonitorActivity(
        at: next.lastSeenAt,
        kind: SessionMonitorActivityKind.runtimeError,
        severity: SessionMonitorSeverity.error,
        count: next.errorCount,
      ),
    );
  }
  if (next.networkFailureCount > previous.networkFailureCount) {
    changes.add(
      SessionMonitorActivity(
        at: next.lastSeenAt,
        kind: SessionMonitorActivityKind.networkFailure,
        severity: SessionMonitorSeverity.warning,
        count: next.networkFailureCount,
      ),
    );
  }
  return changes;
}

SessionMonitorDetail _appendActivity(
  SessionMonitorDetail detail,
  List<SessionMonitorActivity> additions, {
  int limit = _activeActivityLimit,
}) {
  if (additions.isEmpty && detail.activity.length <= limit) return detail;
  final window = retainSessionActivity(
    existing: detail.activity,
    dropped: detail.activityDropped,
    additions: additions,
    limit: limit,
  );
  return detail.copyWith(
    activity: window.entries,
    activityDropped: window.dropped,
  );
}

Map<SessionMonitorKey, SessionMonitorDetail> _retainSelectedDetails(
  Map<SessionMonitorKey, SessionMonitorDetail> details,
  SessionMonitorKey? selected,
) => <SessionMonitorKey, SessionMonitorDetail>{
  for (final entry in details.entries)
    entry.key: entry.key == selected
        ? entry.value
        : _summaryDetail(entry.value),
};

SessionMonitorDetail _summaryDetail(SessionMonitorDetail detail) {
  if (detail.ui == null &&
      detail.logs == null &&
      detail.network == null &&
      detail.errors == null &&
      detail.sessionLogs == null &&
      detail.networkBodies.isEmpty &&
      detail.loadingNetworkBodies.isEmpty &&
      detail.networkBodyErrors.isEmpty &&
      detail.loadingSections.isEmpty &&
      detail.sectionErrors.isEmpty) {
    return detail;
  }
  return SessionMonitorDetail(
    identity: detail.identity,
    activity: detail.activity,
    activityDropped: detail.activityDropped,
    updatedAt: detail.updatedAt,
  );
}

bool _sessionMatchesSummary(
  MonitoredSession session,
  _SessionSummary summary,
) =>
    session.state == summary.state &&
    session.route == summary.route &&
    session.appReachable == summary.appReachable &&
    session.bridgeReachable == summary.bridgeReachable &&
    session.reloadGeneration == summary.reloadGeneration &&
    session.runtimeStatusAt == summary.runtimeStatusAt &&
    session.errorCount == summary.errorCount &&
    session.networkFailureCount == summary.networkFailureCount &&
    session.networkInFlightCount == summary.networkInFlightCount &&
    _sameMessage(session.message, summary.message);

bool _sameSessions(List<MonitoredSession> left, List<MonitoredSession> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (!_sameSession(left[index], right[index])) return false;
  }
  return true;
}

bool _sameSession(MonitoredSession left, MonitoredSession right) =>
    left.key == right.key &&
    left.projectPath == right.projectPath &&
    left.projectName == right.projectName &&
    left.targetId == right.targetId &&
    left.platform == right.platform &&
    left.deviceId == right.deviceId &&
    left.targetKind == right.targetKind &&
    left.entrypoint == right.entrypoint &&
    left.flavor == right.flavor &&
    left.appId == right.appId &&
    left.state == right.state &&
    left.lastSeenAt == right.lastSeenAt &&
    left.route == right.route &&
    left.appReachable == right.appReachable &&
    left.bridgeReachable == right.bridgeReachable &&
    left.reloadGeneration == right.reloadGeneration &&
    left.runtimeStatusAt == right.runtimeStatusAt &&
    left.errorCount == right.errorCount &&
    left.networkFailureCount == right.networkFailureCount &&
    left.networkInFlightCount == right.networkInFlightCount &&
    _sameMessage(left.message, right.message);

bool _sameMessage(SessionMonitorMessage? left, SessionMonitorMessage? right) =>
    identical(left, right) ||
    left != null &&
        right != null &&
        left.kind == right.kind &&
        left.raw == right.raw &&
        left.count == right.count;

bool _sameDetails(
  Map<SessionMonitorKey, SessionMonitorDetail> left,
  Map<SessionMonitorKey, SessionMonitorDetail> right,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!identical(entry.value, right[entry.key])) return false;
  }
  return true;
}

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

String _friendlyError(Object error) {
  final text = '$error';
  return text.startsWith('Bad state: ') ? text.substring(11) : text;
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int _integer(Object? value) => value is int ? value : 0;

Map<String, Object?>? _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : null;

List<Map<String, Object?>> _mapList(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) Map<String, Object?>.from(item),
      ]
    : const <Map<String, Object?>>[];

String? _entryId(Map<String, Object?> entry) {
  final value = entry['requestId'];
  return value is String || value is num ? '$value' : null;
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

Future<List<R>> _mapConcurrent<T, R>(
  List<T> items, {
  required int concurrency,
  required Future<R> Function(T item) task,
}) async {
  if (items.isEmpty) return <R>[];
  final results = List<R?>.filled(items.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      final index = nextIndex++;
      if (index >= items.length) return;
      results[index] = await task(items[index]);
    }
  }

  await Future.wait(
    List<Future<void>>.generate(
      concurrency.clamp(1, items.length),
      (_) => worker(),
      growable: false,
    ),
  );
  return results.cast<R>();
}
