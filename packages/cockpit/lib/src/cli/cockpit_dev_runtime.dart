import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_ids.dart';
import '../supervisor/cockpit_supervisor_api_client.dart';
import 'cockpit_cli_runtime.dart';
import 'cockpit_cli_output.dart';
import 'cockpit_cli_session_handles.dart';

typedef CockpitDevOperationInvoker =
    Future<CockpitOperationResult> Function(
      CockpitCliSessionHandle session,
      String kind,
      Map<String, Object?> input,
    );

typedef CockpitDevArtifactDownloader =
    Future<String> Function(
      CockpitCliSessionHandle session, {
      required String artifactId,
      required String name,
      required String mediaType,
    });

final class CockpitDevSessionResolution {
  const CockpitDevSessionResolution({
    required this.session,
    required this.ready,
    required this.changed,
    this.state,
    this.errors = const <Object?>[],
  });

  final CockpitCliSessionHandle session;
  final bool ready;
  final String changed;
  final Object? state;
  final List<Object?> errors;
}

final class CockpitDevRuntime {
  CockpitDevRuntime(
    this.runtime, {
    CockpitDevOperationInvoker? operationInvoker,
    CockpitDevArtifactDownloader? artifactDownloader,
  }) : _operationInvoker = operationInvoker,
       _artifactDownloader = artifactDownloader;

  final CockpitCliRuntime runtime;
  final CockpitDevOperationInvoker? _operationInvoker;
  final CockpitDevArtifactDownloader? _artifactDownloader;
  final Map<String, Future<List<CockpitOperationDescriptor>>>
  _workspaceDescriptors = <String, Future<List<CockpitOperationDescriptor>>>{};

  bool operationSucceeded(CockpitOperationResult result) =>
      _operationSucceeded(result);

  List<Object?> operationErrors(Iterable<CockpitOperationResult> results) =>
      _operationErrors(results);

  Future<CockpitDevSessionResolution> reconcile(
    CockpitCliSessionHandle session, {
    required bool allowRelaunch,
  }) async {
    if (session.lifecycle == 'stopped') {
      return CockpitDevSessionResolution(
        session: session,
        ready: false,
        changed: 'none',
        state: const <String, Object?>{'lifecycle': 'stopped'},
      );
    }

    final queried = await invoke(
      session,
      'session.development.get',
      <String, Object?>{'sessionId': session.sessionId},
    );
    if (_operationSucceeded(queried)) {
      final resolved = await _bindQueriedSession(session, queried.output);
      if (resolved.lifecycle == 'ready') {
        return CockpitDevSessionResolution(
          session: resolved,
          ready: true,
          changed: _identitiesChanged(session, resolved)
              ? 'reconnected'
              : 'none',
          state: queried.output,
        );
      }
      if (!allowRelaunch) {
        return CockpitDevSessionResolution(
          session: resolved,
          ready: false,
          changed: 'none',
          state: queried.output,
          errors: <Object?>[
            <String, Object?>{
              'code': resolved.lifecycle == 'stopped'
                  ? 'developmentSessionStopped'
                  : 'developmentSessionCrashed',
            },
          ],
        );
      }
      return _relaunch(resolved, priorState: queried.output);
    }

    final rebound = await _rebindLatestTargetSession(session);
    if (rebound != null) return rebound;
    if (allowRelaunch) {
      return _relaunch(session, priorState: queried.output);
    }
    final crashed = await _setLifecycle(session, 'crashed');
    return CockpitDevSessionResolution(
      session: crashed,
      ready: false,
      changed: 'none',
      state: queried.output,
      errors: _operationErrors(<CockpitOperationResult>[queried]),
    );
  }

  Future<CockpitCliSessionHandle> _bindQueriedSession(
    CockpitCliSessionHandle previous,
    Map<String, Object?>? output,
  ) async {
    final status = output?['status'];
    final statusMap = status is Map<Object?, Object?> ? status : null;
    final state = statusMap?['state'];
    final ready =
        state == 'ready' &&
        statusMap?['appReachable'] == true &&
        statusMap?['remoteSessionReachable'] == true;
    final lifecycle = ready
        ? 'ready'
        : state == 'stopped'
        ? 'stopped'
        : 'crashed';
    final sessionId = output?['sessionId'] as String? ?? previous.sessionId;
    final targetId = output?['targetId'] as String? ?? previous.targetId!;
    final appId = output?['appId'] as String? ?? previous.appId!;
    if (previous.sessionId == sessionId &&
        previous.targetId == targetId &&
        previous.appId == appId &&
        previous.lifecycle == lifecycle) {
      return previous;
    }
    return runtime.updateDevelopmentSession(
      previous: previous,
      workspaceId: previous.workspaceId,
      sessionId: sessionId,
      targetId: targetId,
      appId: appId,
      lifecycle: lifecycle,
    );
  }

  Future<CockpitDevSessionResolution?> _rebindLatestTargetSession(
    CockpitCliSessionHandle previous,
  ) async {
    final results = await Future.wait(<Future<CockpitOperationResult>>[
      invoke(previous, 'target.list', const <String, Object?>{}),
      invoke(previous, 'app.list', const <String, Object?>{}),
    ]);
    if (!results.every(_operationSucceeded)) return null;
    final target = _objectRows(
      results[0].output?['targets'],
    ).where((row) => row['targetId'] == previous.targetId).firstOrNull;
    final apps = _objectRows(results[1].output?['apps'])
        .where((row) => row['targetId'] == previous.targetId)
        .toList(growable: false);
    final sessionId = target?['sessionId'];
    final appId = apps.firstOrNull?['appId'];
    if (sessionId is! String || appId is! String) return null;
    if (sessionId == previous.sessionId && appId == previous.appId) return null;

    final rebound = await runtime.updateDevelopmentSession(
      previous: previous,
      workspaceId: previous.workspaceId,
      sessionId: sessionId,
      targetId: previous.targetId!,
      appId: appId,
      lifecycle: 'connecting',
    );
    final queried = await invoke(
      rebound,
      'session.development.get',
      <String, Object?>{'sessionId': rebound.sessionId},
    );
    if (!_operationSucceeded(queried)) return null;
    final resolved = await _bindQueriedSession(rebound, queried.output);
    if (resolved.lifecycle != 'ready') return null;
    return CockpitDevSessionResolution(
      session: resolved,
      ready: true,
      changed: 'reconnected',
      state: queried.output,
    );
  }

  Future<CockpitDevSessionResolution> _relaunch(
    CockpitCliSessionHandle previous, {
    required Object? priorState,
  }) async {
    if (!previous.recoverable) {
      final unavailable = previous.lifecycle == 'stopped'
          ? previous
          : await _setLifecycle(previous, 'crashed');
      return CockpitDevSessionResolution(
        session: unavailable,
        ready: false,
        changed: 'none',
        state: priorState,
        errors: <Object?>[
          <String, Object?>{
            'code': 'explicitRestartRequired',
            'message':
                'This session used custom Flutter launch values, which are '
                'not stored. Re-run `cockpit dev start --session '
                '${previous.handleId}` with the original launch options; '
                'Cockpit will reuse the same handle.',
          },
        ],
      );
    }
    final launched = await invoke(previous, 'target.launch', <String, Object?>{
      'targetId': previous.targetId,
      'mode': 'development',
      'launchTimeoutMs': previous.launchTimeoutMilliseconds,
    });
    if (!_operationSucceeded(launched)) {
      final crashed = await _setLifecycle(previous, 'crashed');
      return CockpitDevSessionResolution(
        session: crashed,
        ready: false,
        changed: 'none',
        state: <String, Object?>{
          'previous': priorState,
          'relaunch': launched.output,
        },
        errors: _operationErrors(<CockpitOperationResult>[launched]),
      );
    }
    final output = launched.output ?? const <String, Object?>{};
    final resolved = await runtime.updateDevelopmentSession(
      previous: previous,
      workspaceId: previous.workspaceId,
      sessionId: output['sessionId'] as String,
      targetId: output['targetId'] as String? ?? previous.targetId!,
      appId: output['appId'] as String,
      lifecycle: 'ready',
      recoverable: previous.recoverable,
      launchTimeoutMilliseconds: previous.launchTimeoutMilliseconds,
    );
    return CockpitDevSessionResolution(
      session: resolved,
      ready: true,
      changed: 'relaunched',
      state: output,
    );
  }

  Future<CockpitDevSessionResolution> relaunch(
    CockpitCliSessionHandle session,
  ) => _relaunch(
    session,
    priorState: <String, Object?>{'lifecycle': session.lifecycle},
  );

  Future<CockpitCliSessionHandle> _setLifecycle(
    CockpitCliSessionHandle previous,
    String lifecycle,
  ) async {
    return runtime.updateDevelopmentSession(
      previous: previous,
      workspaceId: previous.workspaceId,
      sessionId: previous.sessionId,
      targetId: previous.targetId!,
      appId: previous.appId!,
      lifecycle: lifecycle,
    );
  }

  Future<CockpitOperationResult> invoke(
    CockpitCliSessionHandle session,
    String kind,
    Map<String, Object?> input,
  ) async {
    final injected = _operationInvoker;
    if (injected != null) return injected(session, kind, input);
    var client = await runtime.client();
    final descriptors = await _workspaceDescriptors.putIfAbsent(
      session.workspaceId,
      () => client.operations(workspaceId: session.workspaceId),
    );
    final matches = descriptors.where((item) => item.kind == kind).toList();
    if (matches.length != 1) {
      throw CockpitSupervisorClientException(
        code: CockpitErrorCode.unsupportedOperation,
        message: 'Required development capability $kind is not advertised.',
      );
    }
    final descriptor = matches.single;
    if (descriptor.mutationClass == CockpitMutationClass.mutating) {
      client = await runtime.developmentClient();
    }
    return client.executeAdvertisedOperation(
      CockpitOperationInvocation(
        kind: kind,
        workspaceId: session.workspaceId,
        input: input,
        idempotencyKey: runtime.operationIdempotencyKey(descriptor, null),
        deadline: runtime.operationDeadline(descriptor),
      ),
      descriptor: descriptor,
    );
  }

  Future<int> status(
    CockpitCliSessionHandle session, {
    bool diagnose = false,
  }) async {
    if (session.lifecycle == 'stopped') {
      return writeEnvelope(
        action: diagnose ? 'diagnose' : 'status',
        session: session,
        ok: true,
        state: <String, Object?>{
          'lifecycle': 'stopped',
          ..._sessionIdentity(session),
        },
        changed: 'none',
        next: 'cockpit dev start',
      );
    }
    if (diagnose) return _diagnose(session);
    final resolution = await reconcile(session, allowRelaunch: false);
    session = resolution.session;
    if (!resolution.ready) {
      return writeUnavailable(
        action: diagnose ? 'diagnose' : 'status',
        resolution: resolution,
      );
    }
    if (!diagnose) {
      final queried = resolution.state;
      final queriedMap = queried is Map<Object?, Object?> ? queried : null;
      final status = queriedMap?['status'];
      return writeEnvelope(
        action: 'status',
        session: session,
        ok: true,
        state: <String, Object?>{
          'lifecycle': session.lifecycle,
          ..._sessionIdentity(session),
          if (status is Map<Object?, Object?>)
            'connection': <String, Object?>{
              if (status['appReachable'] is bool) 'app': status['appReachable'],
              if (status['remoteSessionReachable'] is bool)
                'bridge': status['remoteSessionReachable'],
              if (status['generation'] is num)
                'generation': status['generation'],
              if (status['reloadOk'] is bool) 'reloadOk': status['reloadOk'],
            },
        },
        changed: resolution.changed,
        failureExitCode: cockpitTemporaryExitCode,
      );
    }
    final results = await Future.wait(<Future<CockpitOperationResult>>[
      invoke(session, 'target.inspect', <String, Object?>{
        'targetId': session.targetId,
        'profile': 'minimal',
      }),
      invoke(session, 'ui.inspect', <String, Object?>{
        'sessionId': session.sessionId,
        'profile': 'minimal',
      }),
      invoke(session, 'errors.read', <String, Object?>{
        'sessionId': session.sessionId,
        'maxErrors': diagnose ? 32 : 8,
      }),
      invoke(session, 'network.read', <String, Object?>{
        'sessionId': session.sessionId,
        'onlyFailures': !diagnose,
        'maxEntries': diagnose ? 64 : 12,
      }),
      invoke(session, 'logs.read', <String, Object?>{
        'sessionId': session.sessionId,
        'maxLines': 120,
      }),
    ]);
    final target = results[0];
    final ui = results[1];
    final errors = results[2];
    final network = results[3];
    final logs = results[4];
    final ok = results.every(_operationSucceeded);
    return writeEnvelope(
      action: diagnose ? 'diagnose' : 'status',
      session: session,
      ok: ok,
      state: <String, Object?>{
        'lifecycle': session.lifecycle,
        ..._sessionIdentity(session),
        'target': target.output,
        'ui': ui.output,
        'runtimeErrors': errors.output,
        'network': network.output,
        'logs': logs.output,
      },
      changed: resolution.changed,
      errors: _operationErrors(results),
      next: ok ? null : 'cockpit dev diagnose --session ${session.handleId}',
      failureExitCode: cockpitTemporaryExitCode,
    );
  }

  Future<int> _diagnose(CockpitCliSessionHandle session) async {
    var results = await _diagnosticReads(session);
    if (!results.every(_diagnosticReadSucceeded)) {
      final resolution = await reconcile(session, allowRelaunch: false);
      if (!resolution.ready) {
        return writeUnavailable(action: 'diagnose', resolution: resolution);
      }
      session = resolution.session;
      results = await _diagnosticReads(session);
      if (!results.every(_diagnosticReadSucceeded)) {
        return writeEnvelope(
          action: 'diagnose',
          session: session,
          ok: false,
          state: <String, Object?>{
            ..._sessionIdentity(session),
            'target': results[0].output,
            'ui': results[1].output,
          },
          changed: resolution.changed,
          errors: _diagnosticReadErrors(results),
          next: 'cockpit dev diagnose --session ${session.handleId}',
          failureExitCode: cockpitTemporaryExitCode,
        );
      }
    }

    final state = _diagnosticState(session, results);
    final runtimeErrors = state['runtimeErrors'];
    final network = state['network'];
    final runtimeErrorCount = _diagnosticErrorCount(runtimeErrors);
    final networkFailureCount = _diagnosticFailureCount(network);
    final ok = runtimeErrorCount == 0 && networkFailureCount == 0;
    return writeEnvelope(
      action: 'diagnose',
      session: session,
      ok: ok,
      state: state,
      changed: 'none',
      errors: <Object?>[
        if (runtimeErrorCount > 0)
          <String, Object?>{
            'code': 'runtimeErrors',
            'count': runtimeErrorCount,
          },
        if (networkFailureCount > 0)
          <String, Object?>{
            'code': 'networkFailures',
            'count': networkFailureCount,
          },
      ],
      next: ok ? null : 'cockpit dev inspect',
      failureExitCode: cockpitTemporaryExitCode,
    );
  }

  Future<List<CockpitOperationResult>> _diagnosticReads(
    CockpitCliSessionHandle session,
  ) => Future.wait(<Future<CockpitOperationResult>>[
    invoke(session, 'target.inspect', <String, Object?>{
      'targetId': session.targetId,
      'profile': 'minimal',
    }),
    invoke(session, 'ui.inspect', <String, Object?>{
      'sessionId': session.sessionId,
      'profile': 'standard',
      'snapshotOptions': const CockpitSnapshotOptions(
        profile: CockpitSnapshotProfile.investigate,
        maxTargets: 32,
        maxAncestorsPerTarget: 1,
        maxPropertiesPerTarget: 6,
        includeRebuildActivity: true,
        maxRebuildEntries: 32,
        includeAccessibilitySummary: true,
        maxAccessibilityEntries: 32,
      ).toJson(),
    }),
    invoke(session, 'errors.read', <String, Object?>{
      'sessionId': session.sessionId,
      'maxErrors': 32,
    }),
    invoke(session, 'network.read', <String, Object?>{
      'sessionId': session.sessionId,
      'onlyFailures': false,
      'maxEntries': 64,
    }),
    invoke(session, 'logs.read', <String, Object?>{
      'sessionId': session.sessionId,
      'maxLines': 120,
    }),
  ]);

  Map<String, Object?> _diagnosticState(
    CockpitCliSessionHandle session,
    List<CockpitOperationResult> results,
  ) {
    final uiOutput = results[1].output ?? const <String, Object?>{};
    final route = uiOutput['routeName'];
    return <String, Object?>{
      'lifecycle': session.lifecycle,
      ..._sessionIdentity(session),
      'target': results[0].output,
      'ui': <String, Object?>{
        ...uiOutput,
        ..._optionalMapEntry('routeName', route),
      },
      'runtimeErrors': results[2].output,
      'network': results[3].output,
      'logs': results[4].output,
    };
  }

  Future<int> inspect(CockpitCliSessionHandle session, {String? query}) async {
    final resolution = await reconcile(session, allowRelaunch: false);
    if (!resolution.ready) {
      return writeUnavailable(action: 'inspect', resolution: resolution);
    }
    session = resolution.session;
    final normalizedQuery = query?.trim();
    final hasQuery = normalizedQuery != null && normalizedQuery.isNotEmpty;
    final result = await invoke(session, 'ui.inspect', <String, Object?>{
      'sessionId': session.sessionId,
      'profile': 'locate',
      'snapshotOptions': CockpitSnapshotOptions(
        profile: CockpitSnapshotProfile.baseline,
        maxTargets: hasQuery ? 10000 : 160,
        maxAncestorsPerTarget: 8,
        artifact: CockpitSnapshotArtifactMode.large,
      ).copyWith(query: normalizedQuery).toJson(),
    });
    final output = result.output ?? const <String, Object?>{};
    final state = _operationSucceeded(result) ? _locatorResult(output) : output;
    return writeOperation(
      action: 'inspect',
      session: session,
      result: result,
      state: state,
      changed: resolution.changed,
    );
  }

  Future<int> tree(CockpitCliSessionHandle session, {int? maxNodes}) async {
    final resolution = await reconcile(session, allowRelaunch: false);
    if (!resolution.ready) {
      return writeUnavailable(action: 'tree', resolution: resolution);
    }
    session = resolution.session;
    final view = runtime.outputSelection.view;
    if (view == CockpitCliOutputView.brief) {
      final result = await invoke(session, 'ui.inspect', <String, Object?>{
        'sessionId': session.sessionId,
        'profile': 'locate',
        'snapshotOptions': const CockpitSnapshotOptions(
          profile: CockpitSnapshotProfile.baseline,
          maxTargets: 160,
          maxAncestorsPerTarget: 8,
          artifact: CockpitSnapshotArtifactMode.large,
        ).toJson(),
      });
      final output = result.output ?? const <String, Object?>{};
      final targetIndex = _locatorResult(output);
      return writeOperation(
        action: 'tree',
        session: session,
        result: result,
        state: _operationSucceeded(result)
            ? <String, Object?>{'profile': 'brief', ...targetIndex}
            : output,
        changed: resolution.changed,
      );
    }
    var treeOptions = switch (view) {
      CockpitCliOutputView.brief => throw StateError('Unreachable tree view.'),
      CockpitCliOutputView.more => const CockpitWidgetTreeOptions.standard(),
      CockpitCliOutputView.full => const CockpitWidgetTreeOptions.full(),
    };
    if (maxNodes != null) {
      treeOptions = treeOptions.copyWith(maxNodes: maxNodes);
    }
    final result = await invoke(session, 'ui.inspect', <String, Object?>{
      'sessionId': session.sessionId,
      'profile': 'tree',
      'snapshotOptions': CockpitSnapshotOptions(
        profile: CockpitSnapshotProfile.baseline,
        maxTargets: 1,
        maxAncestorsPerTarget: 0,
        artifact: CockpitSnapshotArtifactMode.always,
        tree: treeOptions,
      ).toJson(),
    });
    if (!_operationSucceeded(result)) {
      return writeOperation(
        action: 'tree',
        session: session,
        result: result,
        state: result.output,
        changed: resolution.changed,
      );
    }

    final output = result.output ?? const <String, Object?>{};
    final snapshot = _objectMap(output['snapshot']);
    final tree = _objectMap(snapshot?['tree']);
    final artifact = _treeArtifact(output);
    if (artifact == null) {
      return writeEnvelope(
        action: 'tree',
        session: session,
        ok: false,
        state: const <String, Object?>{'reason': 'treeArtifactUnavailable'},
        changed: resolution.changed,
        errors: const <Object?>[
          <String, Object?>{
            'code': 'treeArtifactUnavailable',
            'message': 'Flutter did not return the requested tree artifact.',
          },
        ],
        next: 'cockpit dev diagnose --session ${session.handleId}',
      );
    }
    final path = await (_artifactDownloader ?? _downloadTreeArtifact)(
      session,
      artifactId: artifact.artifactId,
      name: artifact.name,
      mediaType: artifact.mediaType,
    );
    final state = <String, Object?>{
      'profile': tree?['profile'] ?? treeOptions.profile.jsonValue,
      if (tree?['total'] != null) 'total': tree!['total'],
      if (tree?['visible'] != null) 'visible': tree!['visible'],
      if (tree?['emitted'] != null) 'emitted': tree!['emitted'],
      if (tree?['truncated'] != null) 'truncated': tree!['truncated'],
      'path': path,
    };
    return writeEnvelope(
      action: 'tree',
      session: session,
      ok: true,
      state: state,
      changed: resolution.changed,
      evidence: <String, Object?>{'tree': path},
    );
  }

  Future<String> _downloadTreeArtifact(
    CockpitCliSessionHandle session, {
    required String artifactId,
    required String name,
    required String mediaType,
  }) async {
    final home = CockpitHome.system();
    final homePaths = await home.initialize();
    final directory = Directory(
      p.join(
        homePaths.artifactsDirectory,
        'development',
        session.checkoutIdentity!.substring(0, 16),
        session.handleId,
        'trees',
        CockpitSecureTokenGenerator().nextResourceIdToken(),
      ),
    );
    await directory.create(recursive: true);
    await home.permissionHardener.hardenDirectory(directory);
    final destination = File(p.join(directory.path, p.basename(name)));
    final receipt = await (await runtime.client())
        .downloadDevelopmentArtifactToFile(
          workspaceId: session.workspaceId,
          sessionId: session.sessionId,
          artifactId: artifactId,
          mediaType: mediaType,
          destination: destination,
        );
    return p.normalize(await receipt.file.resolveSymbolicLinks());
  }

  Future<int> runCommand(
    CockpitCliSessionHandle session, {
    required String action,
    required CockpitCommand command,
  }) async {
    final resolution = await reconcile(session, allowRelaunch: true);
    if (!resolution.ready) {
      return writeUnavailable(action: action, resolution: resolution);
    }
    session = resolution.session;
    final result = await invoke(session, 'command.run', <String, Object?>{
      'sessionId': session.sessionId,
      'command': command.toJson(),
      'profile': 'standard',
    });
    if (!_operationSucceeded(result)) {
      return writeOperation(
        action: action,
        session: session,
        result: result,
        state: result.output,
        changed: null,
      );
    }
    return writeEnvelope(
      action: action,
      session: session,
      ok: true,
      state: result.output,
      changed: resolution.changed == 'none' ? _changed(result.output) : true,
      failureExitCode: cockpitDataExitCode,
    );
  }

  Future<int> waitIdle(
    CockpitCliSessionHandle session, {
    required bool includeNetwork,
    required int quietMilliseconds,
    required int timeoutMilliseconds,
  }) async {
    final resolution = await reconcile(session, allowRelaunch: false);
    if (!resolution.ready) {
      return writeUnavailable(action: 'wait', resolution: resolution);
    }
    session = resolution.session;
    final result = await invoke(session, 'ui.waitIdle', <String, Object?>{
      'sessionId': session.sessionId,
      'includeNetworkIdle': includeNetwork,
      'quietWindowMs': quietMilliseconds,
      'timeoutMs': timeoutMilliseconds,
    });
    return writeOperation(
      action: 'wait',
      session: session,
      result: result,
      state: result.output,
      changed: resolution.changed,
      failureExitCode: cockpitTemporaryExitCode,
    );
  }

  Future<int> resizeViewport(
    CockpitCliSessionHandle session, {
    required int width,
    required int height,
  }) async {
    final resolution = await reconcile(session, allowRelaunch: true);
    if (!resolution.ready) {
      return writeUnavailable(action: 'viewport', resolution: resolution);
    }
    session = resolution.session;
    final result = await invoke(session, 'viewport.set', <String, Object?>{
      'sessionId': session.sessionId,
      'width': width,
      'height': height,
    });
    final output = result.output ?? const <String, Object?>{};
    final operationOk = _operationSucceeded(result);
    final available = output['available'] == true;
    final ok = operationOk && available;
    return writeEnvelope(
      action: 'viewport',
      session: session,
      ok: ok,
      state: output,
      changed: resolution.changed == 'none'
          ? (ok && output['changed'] == true ? 'resized' : 'none')
          : resolution.changed,
      errors: <Object?>[
        if (!operationOk) ..._operationErrors(<CockpitOperationResult>[result]),
        if (operationOk && !available)
          <String, Object?>{
            'code': output['reason'] ?? 'viewportUnavailable',
            if (output['alternatives'] != null)
              'alternatives': output['alternatives'],
          },
      ],
      next: ok ? null : 'cockpit dev diagnose --session ${session.handleId}',
      failureExitCode: available
          ? cockpitDataExitCode
          : cockpitUnavailableExitCode,
    );
  }

  Future<int> lifecycle(CockpitCliSessionHandle session, String action) async {
    CockpitDevSessionResolution? resolution;
    if (action != 'stop') {
      resolution = await reconcile(session, allowRelaunch: true);
      if (!resolution.ready) {
        return writeUnavailable(action: action, resolution: resolution);
      }
      session = resolution.session;
      if (resolution.changed == 'relaunched') {
        return writeEnvelope(
          action: action,
          session: session,
          ok: true,
          state: resolution.state,
          changed: 'relaunched',
        );
      }
    }
    final kind = switch (action) {
      'reload' => 'app.reload',
      'restart' => 'app.restart',
      'stop' => 'session.development.stop',
      _ => throw ArgumentError.value(action, 'action'),
    };
    final result = await invoke(session, kind, <String, Object?>{
      'sessionId': session.sessionId,
    });
    final output = result.output ?? const <String, Object?>{};
    var resolved = session;
    if (_operationSucceeded(result)) {
      resolved = await runtime.updateDevelopmentSession(
        previous: session,
        workspaceId: session.workspaceId,
        sessionId: output['sessionId'] as String? ?? session.sessionId,
        targetId: session.targetId!,
        appId: output['appId'] as String? ?? session.appId!,
        lifecycle: action == 'stop' ? 'stopped' : 'ready',
      );
    }
    final changed = resolution != null && resolution.changed != 'none'
        ? resolution.changed
        : action;
    if (action == 'stop' || !_operationSucceeded(result)) {
      return writeOperation(
        action: action,
        session: resolved,
        result: result,
        state: output,
        changed: changed,
      );
    }

    // Reading the postcondition crosses the Flutter bridge's warm-up frame
    // barrier. A successful lifecycle command therefore guarantees that the
    // next UI action observes the restarted/reloaded tree.
    final postcondition = await invoke(
      resolved,
      'ui.inspect',
      <String, Object?>{'sessionId': resolved.sessionId, 'profile': 'minimal'},
    );
    final ok = _operationSucceeded(postcondition);
    return writeEnvelope(
      action: action,
      session: resolved,
      ok: ok,
      state: <String, Object?>{'lifecycle': output, 'ui': postcondition.output},
      changed: changed,
      errors: _operationErrors(<CockpitOperationResult>[result, postcondition]),
      next: ok ? null : 'cockpit dev diagnose --session ${resolved.handleId}',
      failureExitCode: cockpitTemporaryExitCode,
    );
  }

  Future<int> writeUnavailable({
    required String action,
    required CockpitDevSessionResolution resolution,
  }) {
    final errors = resolution.errors.isEmpty
        ? const <Object?>[
            <String, Object?>{'code': 'developmentSessionUnavailable'},
          ]
        : resolution.errors;
    final launchOptionsRequired = errors.whereType<Map<Object?, Object?>>().any(
      (error) => error['code'] == 'explicitRestartRequired',
    );
    return writeEnvelope(
      action: action,
      session: resolution.session,
      ok: false,
      state: resolution.state,
      changed: resolution.changed,
      errors: errors,
      next: launchOptionsRequired || resolution.session.lifecycle == 'stopped'
          ? 'cockpit dev start --session ${resolution.session.handleId}'
          : 'cockpit dev restart --session ${resolution.session.handleId}',
      failureExitCode: cockpitTemporaryExitCode,
    );
  }

  Future<int> writeOperation({
    required String action,
    required CockpitCliSessionHandle session,
    required CockpitOperationResult result,
    required Object? state,
    required Object? changed,
    int failureExitCode = cockpitDataExitCode,
  }) {
    final ok = _operationSucceeded(result);
    return writeEnvelope(
      action: action,
      session: session,
      ok: ok,
      state: state,
      changed: changed,
      errors: _operationErrors(<CockpitOperationResult>[result]),
      next: ok ? null : 'cockpit dev diagnose --session ${session.handleId}',
      failureExitCode: failureExitCode,
    );
  }

  Future<int> writeEnvelope({
    required String action,
    required CockpitCliSessionHandle session,
    required bool ok,
    required Object? state,
    required Object? changed,
    List<Object?> errors = const <Object?>[],
    Object? evidence,
    String? next,
    int failureExitCode = cockpitDataExitCode,
  }) async {
    if (!ok && runtime.usesPathOutput) {
      final failure = _pathOutputFailure(errors, action: action);
      runtime.error(
        code: failure.code,
        message: failure.message,
        retryable: failure.retryable,
        category: failure.category,
        responsibleLayer: failure.responsibleLayer,
      );
      return failureExitCode;
    }
    await runtime.success(<String, Object?>{
      'ok': ok,
      'action': action,
      'session': session.handleId,
      'state': state,
      'changed': ?changed,
      'evidence': ?evidence,
      if (errors.isNotEmpty) 'errors': errors,
      'next': ?next,
    });
    return ok ? cockpitSuccessExitCode : failureExitCode;
  }

  CockpitCommand command({
    required CockpitCommandType type,
    Duration? timeout,
    CockpitLocator? locator,
    Map<String, Object?> parameters = const <String, Object?>{},
  }) => CockpitCommand(
    commandId: CockpitSecureTokenGenerator().nextResourceId('d'),
    commandType: type,
    locator: locator,
    parameters: parameters,
    capturePolicy: CockpitCapturePolicy.onFailure,
    timeoutMs: (timeout ?? runtime.commandTimeout).inMilliseconds,
  );
}

({
  String code,
  String message,
  bool retryable,
  String? category,
  String? responsibleLayer,
})
_pathOutputFailure(List<Object?> errors, {required String action}) {
  for (final error in errors) {
    final candidate = _firstCliFailureMap(error);
    if (candidate == null) continue;
    final code = candidate['code'];
    final message = candidate['message'];
    if (code is String &&
        code.isNotEmpty &&
        message is String &&
        message.isNotEmpty) {
      return (
        code: code,
        message: message,
        retryable: candidate['retryable'] == true,
        category: candidate['category'] as String?,
        responsibleLayer:
            candidate['responsibleLayer'] as String? ??
            candidate['layer'] as String?,
      );
    }
  }
  return (
    code: 'developmentOperationFailed',
    message: 'The $action operation did not complete.',
    retryable: false,
    category: null,
    responsibleLayer: null,
  );
}

Map<Object?, Object?>? _firstCliFailureMap(Object? value) {
  if (value is Map<Object?, Object?>) {
    if (value['code'] is String && value['message'] is String) return value;
    for (final child in value.values) {
      final nested = _firstCliFailureMap(child);
      if (nested != null) return nested;
    }
  } else if (value is Iterable<Object?>) {
    for (final child in value) {
      final nested = _firstCliFailureMap(child);
      if (nested != null) return nested;
    }
  }
  return null;
}

bool _operationSucceeded(CockpitOperationResult result) =>
    result.lifecycle == CockpitOperationLifecycle.completed &&
    result.outcome == CockpitOperationOutcome.succeeded &&
    !_containsFalseOutcome(result.output) &&
    !_containsDisqualifyingState(result);

bool _diagnosticReadSucceeded(CockpitOperationResult result) =>
    result.lifecycle == CockpitOperationLifecycle.completed &&
    result.outcome == CockpitOperationOutcome.succeeded &&
    !_containsFalseOutcome(result.output);

List<Object?> _diagnosticReadErrors(Iterable<CockpitOperationResult> results) =>
    <Object?>[
      for (final result in results)
        if (!_diagnosticReadSucceeded(result))
          result.failure?.toJson() ?? _productFailure(result),
    ];

bool _containsDisqualifyingState(CockpitOperationResult result) {
  final output = result.output;
  if (output == null) return false;
  if (result.kind == 'errors.read') return output['hasErrors'] == true;
  if (result.kind == 'network.read') {
    final summary = output['summary'];
    return summary is Map<Object?, Object?> &&
        (summary['failureCount'] as num? ?? 0) > 0;
  }
  return false;
}

bool _containsFalseOutcome(Object? value) {
  if (value case final Map<Object?, Object?> map) {
    for (final entry in map.entries) {
      if ((entry.key == 'success' ||
              entry.key == 'idle' ||
              entry.key == 'ok') &&
          entry.value == false) {
        return true;
      }
      if (_containsFalseOutcome(entry.value)) return true;
    }
  } else if (value case final Iterable<Object?> items) {
    return items.any(_containsFalseOutcome);
  }
  return false;
}

List<Object?> _operationErrors(Iterable<CockpitOperationResult> results) =>
    <Object?>[
      for (final result in results)
        if (!_operationSucceeded(result))
          result.failure?.toJson() ?? _productFailure(result),
    ];

Map<String, Object?> _productFailure(CockpitOperationResult result) {
  final output = result.output;
  final command = output?['command'];
  if (command is Map<Object?, Object?>) {
    final error = command['error'];
    if (error is Map<Object?, Object?>) {
      return <String, Object?>{
        ..._pickStringValues(error, const <String>['code', 'message']),
        'operation': result.kind,
      };
    }
  }
  if (result.kind == 'errors.read' && output?['hasErrors'] == true) {
    final errors = output?['errors'];
    return <String, Object?>{
      'code': 'runtimeErrors',
      'count': errors is List<Object?> ? errors.length : 1,
    };
  }
  if (result.kind == 'network.read') {
    final summary = output?['summary'];
    if (summary is Map<Object?, Object?>) {
      return <String, Object?>{
        'code': 'networkFailures',
        'count': summary['failureCount'],
      };
    }
  }
  return <String, Object?>{
    'code': 'productOutcomeFailed',
    'operation': result.kind,
  };
}

Map<String, Object?> _pickStringValues(
  Map<Object?, Object?> source,
  Iterable<String> keys,
) => <String, Object?>{
  for (final key in keys)
    if (source[key] is String) key: source[key],
};

Map<Object?, Object?>? _objectMap(Object? value) {
  if (value is Map<Object?, Object?>) return value;
  if (value is Map) return Map<Object?, Object?>.from(value);
  return null;
}

Map<String, Object?> _locatorResult(Map<String, Object?> output) {
  final locator = output['locator'];
  if (locator is! Map<Object?, Object?>) {
    throw StateError('ui.inspect did not return bounded locator results.');
  }
  return Map<String, Object?>.from(locator);
}

({String artifactId, String name, String mediaType})? _treeArtifact(
  Object? value,
) {
  final output = _objectMap(value);
  final snapshot = _objectMap(output?['snapshot']);
  final treeArtifact = _objectMap(snapshot?['treeArtifactRef']);
  final reference = _objectMap(treeArtifact?['artifactRef']);
  final artifactId = reference?['artifactId'];
  final name = reference?['name'];
  final mediaType = reference?['mediaType'];
  if (artifactId is! String ||
      artifactId.isEmpty ||
      name is! String ||
      name.isEmpty ||
      mediaType is! String ||
      mediaType.isEmpty) {
    return null;
  }
  return (artifactId: artifactId, name: name, mediaType: mediaType);
}

Map<String, Object?> _optionalMapEntry(String key, Object? value) =>
    value == null ? const <String, Object?>{} : <String, Object?>{key: value};

int _diagnosticErrorCount(Object? value) {
  final map = _objectMap(value);
  final errors = map?['errors'];
  return errors is List<Object?> ? errors.length : 0;
}

int _diagnosticFailureCount(Object? value) {
  final map = _objectMap(value);
  final summary = _objectMap(map?['summary']);
  final count = summary?['failureCount'];
  return count is num ? count.toInt() : 0;
}

List<Map<String, Object?>> _objectRows(Object? value) => value is List<Object?>
    ? value
          .whereType<Map<Object?, Object?>>()
          .map(Map<String, Object?>.from)
          .toList(growable: false)
    : const <Map<String, Object?>>[];

Map<String, Object?> _sessionIdentity(CockpitCliSessionHandle session) =>
    <String, Object?>{
      if (session.projectPath != null) 'projectPath': session.projectPath,
      if (session.checkoutPath != null) 'checkoutPath': session.checkoutPath,
      if (session.entrypoint != null) 'entrypoint': session.entrypoint,
      if (session.platform != null) 'platform': session.platform,
      if (session.deviceId != null) 'deviceId': session.deviceId,
      if (session.flavor != null) 'flavor': session.flavor,
    };

bool _identitiesChanged(
  CockpitCliSessionHandle before,
  CockpitCliSessionHandle after,
) =>
    before.sessionId != after.sessionId ||
    before.appId != after.appId ||
    before.targetId != after.targetId;

Object? _changed(Map<String, Object?>? output) {
  if (output == null) return null;
  final command = output['command'];
  if (command is Map<Object?, Object?> && command['success'] == true) {
    return command['changed'];
  }
  return null;
}
