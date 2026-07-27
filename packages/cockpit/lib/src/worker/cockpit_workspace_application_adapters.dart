import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_value_reader.dart';
import 'cockpit_workspace_operation_registry.dart';

abstract interface class CockpitWorkerApplicationBackend {
  Future<Map<String, Object?>> execute({
    required String kind,
    required Map<String, Object?> input,
    required CockpitWorkspaceOperationContext context,
    required List<CockpitWorkerResourceGrant> grants,
  });
}

abstract interface class CockpitWorkerApplicationResourceResolver {
  Future<CockpitWorkerApplicationResourcePlan> resolveApplicationResourcePlan({
    required String kind,
    required Map<String, Object?> input,
  });
}

final class CockpitWorkerApplicationResourcePlan {
  CockpitWorkerApplicationResourcePlan({
    required this.primaryResourceId,
    this.deviceResourceId,
    this.requiresPort = true,
  }) {
    workerString(primaryResourceId, r'$.primaryResourceId', maximum: 512);
    if (deviceResourceId != null) {
      workerString(deviceResourceId, r'$.deviceResourceId', maximum: 512);
      if (deviceResourceId == primaryResourceId) {
        throw const FormatException(
          'An additional device resource must not duplicate the primary resource.',
        );
      }
    }
  }

  final String primaryResourceId;
  final String? deviceResourceId;
  final bool requiresPort;
}

final class CockpitWorkspaceApplicationAdapters {
  CockpitWorkspaceApplicationAdapters({
    required this.workspaceId,
    required CockpitWorkerApplicationBackend backend,
    required CockpitWorkerApplicationResourceResolver resourceResolver,
  }) : _backend = backend,
       _resourceResolver = resourceResolver {
    workerId(workspaceId, r'$.workspaceId');
  }

  final String workspaceId;
  final CockpitWorkerApplicationBackend _backend;
  final CockpitWorkerApplicationResourceResolver _resourceResolver;

  List<CockpitWorkspaceOperationAdapter> create() => <_OperationSpec>[
    const _OperationSpec.read('app.list', 'workspace.apps'),
    const _OperationSpec.leasedRead(
      'app.get',
      'workspace.app',
      CockpitLeaseResourceKind.session,
      idField: 'appId',
    ),
    const _OperationSpec.leasedRead(
      'target.inspect',
      'workspace.target',
      CockpitLeaseResourceKind.device,
      idField: 'targetId',
    ),
    const _OperationSpec.read('target.list', 'workspace.targets'),
    const _OperationSpec.read(
      'target.get',
      'workspace.target',
      idField: 'targetId',
    ),
    const _OperationSpec.mutate(
      'app.launch',
      'workspace.apps',
      CockpitLeaseResourceKind.device,
      idField: 'targetId',
      requiresPort: true,
    ),
    const _OperationSpec.mutate(
      'target.launch',
      'workspace.target',
      CockpitLeaseResourceKind.device,
      idField: 'targetId',
      requiresPort: true,
    ),
    const _OperationSpec.mutate(
      'app.stop',
      'workspace.apps',
      CockpitLeaseResourceKind.session,
      idField: 'appId',
    ),
    const _OperationSpec.mutate(
      'session.remote.launch',
      'workspace.sessions',
      CockpitLeaseResourceKind.device,
      idField: 'targetId',
      requiresPort: true,
    ),
    const _OperationSpec.leasedRead(
      'session.remote.get',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.leasedRead(
      'session.remote.status',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.leasedRead(
      'snapshot.remote.read',
      'workspace.snapshots',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'snapshot.remote.collect',
      'workspace.snapshots',
      CockpitLeaseResourceKind.capture,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'command.remote.execute',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'command.remote.batch',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'ui.remote.waitIdle',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'session.development.launch',
      'workspace.sessions',
      CockpitLeaseResourceKind.device,
      idField: 'targetId',
      requiresPort: true,
    ),
    const _OperationSpec.leasedRead(
      'session.development.get',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'session.development.reload',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'session.development.stop',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'development.probe.collect',
      'workspace.probes',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.read(
      'development.probe.compare',
      'workspace.probes',
      idField: 'sessionId',
    ),
    const _OperationSpec.leasedRead(
      'ui.inspect',
      'workspace.ui',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.leasedRead(
      'surface.inspect',
      'workspace.ui',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.leasedRead(
      'logs.read',
      'workspace.logs',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.leasedRead(
      'network.read',
      'workspace.network',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.leasedRead(
      'errors.read',
      'workspace.errors',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.leasedRead(
      'session.logs.read',
      'workspace.sessionLogs',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'evidence.screenshot.capture',
      'workspace.artifacts',
      CockpitLeaseResourceKind.capture,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'command.run',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'command.batch',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'shell.run',
      'workspace.tooling',
      CockpitLeaseResourceKind.workspaceMutation,
    ),
    const _OperationSpec.mutate(
      'system.action',
      'workspace.target',
      CockpitLeaseResourceKind.device,
      idField: 'targetId',
    ),
    const _OperationSpec.mutate(
      'app.reload',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'app.restart',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'ui.waitIdle',
      'workspace.sessions',
      CockpitLeaseResourceKind.session,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'recording.start',
      'workspace.recordings',
      CockpitLeaseResourceKind.recording,
      idField: 'sessionId',
    ),
    const _OperationSpec.mutate(
      'recording.stop',
      'workspace.recordings',
      CockpitLeaseResourceKind.recording,
      idField: 'recordingId',
    ),
  ].map(_adapter).toList(growable: false);

  CockpitWorkspaceOperationAdapter _adapter(_OperationSpec spec) =>
      CockpitWorkspaceOperationAdapter(
        kind: spec.kind,
        mutationClass: spec.mutationClass,
        resourceKinds: <String>[spec.resourceKind],
        prepare: (context, input) async {
          rejectCockpitWorkerHostPathInputs(
            input,
            allowedKeys: _allowedWorkerPathKeys(spec.kind),
          );
          if (spec.idField != null) {
            workerId(input[spec.idField], '\$.input.${spec.idField}');
          }
          final resourcePlan = spec.leaseKind == null
              ? null
              : await _resourceResolver.resolveApplicationResourcePlan(
                  kind: spec.kind,
                  input: input,
                );
          return CockpitPreparedWorkspaceOperation(
            resources: resourcePlan == null
                ? const <CockpitWorkerResourceRequest>[]
                : <CockpitWorkerResourceRequest>[
                    if (spec.requiresPort && resourcePlan.requiresPort)
                      CockpitWorkerResourceRequest(
                        resourceKind: CockpitLeaseResourceKind.forwardedPort,
                        resourceId:
                            '${resourcePlan.primaryResourceId}:${spec.kind}',
                        requiresPort: true,
                        ttl: _portGrantTtl(context),
                      ),
                    if (resourcePlan.deviceResourceId != null)
                      CockpitWorkerResourceRequest(
                        resourceKind: CockpitLeaseResourceKind.device,
                        resourceId: resourcePlan.deviceResourceId!,
                        ttl: _grantTtl(context),
                      ),
                    CockpitWorkerResourceRequest(
                      resourceKind: spec.leaseKind!,
                      resourceId: resourcePlan.primaryResourceId,
                      ttl: _grantTtl(context),
                    ),
                  ],
            execute: (grants) => _backend.execute(
              kind: spec.kind,
              input: Map<String, Object?>.unmodifiable(input),
              context: context,
              grants: grants,
            ),
          );
        },
      );

  Duration _grantTtl(CockpitWorkspaceOperationContext context) {
    final remaining = context.deadline.difference(DateTime.now().toUtc());
    if (remaining < const Duration(seconds: 1)) {
      return const Duration(seconds: 1);
    }
    return remaining > const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : remaining;
  }

  Duration _portGrantTtl(CockpitWorkspaceOperationContext context) {
    final remaining = context.deadline.difference(DateTime.now().toUtc());
    if (remaining < const Duration(seconds: 1)) {
      return const Duration(seconds: 1);
    }
    const maximum = Duration(milliseconds: cockpitMaximumLeaseTtlMs);
    return remaining > maximum ? maximum : remaining;
  }
}

final class _OperationSpec {
  const _OperationSpec.read(this.kind, this.resourceKind, {this.idField})
    : mutationClass = CockpitMutationClass.readOnly,
      leaseKind = null,
      requiresPort = false;

  const _OperationSpec.leasedRead(
    this.kind,
    this.resourceKind,
    this.leaseKind, {
    this.idField,
  }) : mutationClass = CockpitMutationClass.readOnly,
       requiresPort = false;

  const _OperationSpec.mutate(
    this.kind,
    this.resourceKind,
    this.leaseKind, {
    this.idField,
    this.requiresPort = false,
  }) : mutationClass = CockpitMutationClass.mutating;

  final String kind;
  final String resourceKind;
  final CockpitMutationClass mutationClass;
  final CockpitLeaseResourceKind? leaseKind;
  final String? idField;
  final bool requiresPort;
}

const Set<String> _pathInputSegments = <String>{
  'path',
  'paths',
  'root',
  'roots',
  'dir',
  'dirs',
  'directory',
  'directories',
  'file',
  'files',
};

const List<String> _camelCasePathSuffixes = <String>[
  'Path',
  'Paths',
  'Root',
  'Roots',
  'Dir',
  'Dirs',
  'Directory',
  'Directories',
  'File',
  'Files',
];

const Set<String> _remoteSystemActionPathKeys = <String>{
  'deviceSourcePath',
  'deviceDestinationPath',
  'containerSourcePath',
  'containerDestinationPath',
};

const Set<String> _flutterLaunchPathKeys = <String>{'dartDefineFromFiles'};

Set<String> _allowedWorkerPathKeys(String operationKind) =>
    switch (operationKind) {
      'system.action' => _remoteSystemActionPathKeys,
      'app.launch' ||
      'target.launch' ||
      'session.remote.launch' ||
      'session.development.launch' => _flutterLaunchPathKeys,
      _ => const <String>{},
    };

void rejectCockpitWorkerHostPathInputs(
  Object? value, {
  String? key,
  required Set<String> allowedKeys,
}) {
  if (key != null && !allowedKeys.contains(key) && _isPathInputKey(key)) {
    throw FormatException(
      'Worker operation paths must be represented by opaque ids: $key.',
    );
  }
  if (value is Map<Object?, Object?>) {
    for (final entry in value.entries) {
      rejectCockpitWorkerHostPathInputs(
        entry.value,
        key: '${entry.key}',
        allowedKeys: allowedKeys,
      );
    }
  } else if (value is Iterable<Object?>) {
    for (final item in value) {
      rejectCockpitWorkerHostPathInputs(item, allowedKeys: allowedKeys);
    }
  }
}

bool _isPathInputKey(String key) {
  final normalized = key.replaceAll('-', '_').toLowerCase();
  final lastSegment = normalized.split('_').last;
  return _pathInputSegments.contains(lastSegment) ||
      _camelCasePathSuffixes.any(key.endsWith);
}
