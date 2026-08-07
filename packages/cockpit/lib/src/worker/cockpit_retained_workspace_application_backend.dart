import 'dart:async';

import '../application/cockpit_application_service_exception.dart';
import '../application/cockpit_interactive_snapshot_store.dart';
import '../development/cockpit_vm_network_profiler.dart';
import 'cockpit_worker_application_support.dart';
import 'cockpit_worker_development_session_runtime.dart';
import 'cockpit_worker_document_index.dart';
import 'cockpit_worker_forwarded_port_handoff.dart';
import 'cockpit_worker_interactive_operations.dart';
import 'cockpit_worker_lifecycle_operations.dart';
import 'cockpit_worker_process_manager.dart';
import 'cockpit_worker_remote_operations.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_runtime_registry.dart';
import 'cockpit_worker_value_reader.dart';
import 'cockpit_workspace_application_adapters.dart';
import 'cockpit_workspace_operation_registry.dart';

final class CockpitRetainedWorkspaceApplicationBackend
    implements CockpitWorkerApplicationBackend {
  factory CockpitRetainedWorkspaceApplicationBackend({
    required String workspaceId,
    required String workspaceRoot,
    required CockpitWorkerRuntimeRegistry registry,
    required CockpitWorkerDocumentIndex documents,
    required String producerRoot,
    required CockpitWorkerForwardedPortHandoff portHandoff,
    required CockpitWorkerDevelopmentSessionRuntime developmentRuntime,
    required CockpitWorkerProcessManager processManager,
    required CockpitWorkerResultSanitizer resultSanitizer,
    CockpitVmNetworkProfiler? networkProfiler,
  }) {
    workerId(workspaceId, r'$.workspaceId');
    workerString(workspaceRoot, r'$.workspaceRoot', maximum: 32768);
    if (registry.workspaceId != workspaceId ||
        registry.workspaceRoot != workspaceRoot) {
      throw ArgumentError(
        'Runtime registry identity does not match the application backend.',
      );
    }
    final snapshots = CockpitInteractiveSnapshotStore();
    return CockpitRetainedWorkspaceApplicationBackend._(
      workspaceId: workspaceId,
      workspaceRoot: workspaceRoot,
      lifecycle: CockpitWorkerLifecycleOperations(
        workspaceId: workspaceId,
        registry: registry,
        targets: registry,
        portHandoff: portHandoff,
        developmentRuntime: developmentRuntime,
      ),
      remote: CockpitWorkerRemoteOperations(
        workspaceId: workspaceId,
        producerRoot: producerRoot,
        registry: registry,
        targets: registry,
        portHandoff: portHandoff,
        snapshotStore: snapshots,
      ),
      interactive: CockpitWorkerInteractiveOperations(
        workspaceId: workspaceId,
        workspaceRoot: workspaceRoot,
        registry: registry,
        developmentRuntime: developmentRuntime,
        documents: documents,
        producerRoot: producerRoot,
        targets: registry,
        processManager: processManager,
        snapshotStore: snapshots,
        networkProfiler: networkProfiler,
      ),
      sanitizer: resultSanitizer,
    );
  }

  const CockpitRetainedWorkspaceApplicationBackend._({
    required this.workspaceId,
    required this.workspaceRoot,
    required CockpitWorkerLifecycleOperations lifecycle,
    required CockpitWorkerRemoteOperations remote,
    required CockpitWorkerInteractiveOperations interactive,
    required CockpitWorkerResultSanitizer sanitizer,
  }) : _lifecycle = lifecycle,
       _remote = remote,
       _interactive = interactive,
       _sanitizer = sanitizer;

  static const Set<String> kinds = <String>{
    ...CockpitWorkerLifecycleOperations.kinds,
    ...CockpitWorkerRemoteOperations.kinds,
    ...CockpitWorkerInteractiveOperations.kinds,
  };

  final String workspaceId;
  final String workspaceRoot;
  final CockpitWorkerLifecycleOperations _lifecycle;
  final CockpitWorkerRemoteOperations _remote;
  final CockpitWorkerInteractiveOperations _interactive;
  final CockpitWorkerResultSanitizer _sanitizer;

  @override
  Future<Map<String, Object?>> execute({
    required String kind,
    required Map<String, Object?> input,
    required CockpitWorkspaceOperationContext context,
    required List<CockpitWorkerResourceGrant> grants,
  }) {
    _validateContext(context);
    if (CockpitWorkerLifecycleOperations.kinds.contains(kind)) {
      return _lifecycle.execute(
        kind: kind,
        input: input,
        context: context,
        grants: grants,
        sanitizer: _sanitizer,
      );
    }
    if (CockpitWorkerRemoteOperations.kinds.contains(kind)) {
      return _remote.execute(
        kind: kind,
        input: input,
        context: context,
        grants: grants,
        sanitizer: _sanitizer,
      );
    }
    if (CockpitWorkerInteractiveOperations.kinds.contains(kind)) {
      return _interactive.execute(
        kind: kind,
        input: input,
        context: context,
        grants: grants,
        sanitizer: _sanitizer,
      );
    }
    throw StateError('Application operation routing is inconsistent: $kind.');
  }

  void _validateContext(CockpitWorkspaceOperationContext context) {
    if (context.workspaceId != workspaceId ||
        context.workspaceRoot != workspaceRoot) {
      throw const CockpitApplicationServiceException(
        code: 'workspaceMismatch',
        message: 'Workspace application context is inconsistent.',
      );
    }
    context.cancellation.throwIfCancelled();
    if (!context.deadline.isAfter(DateTime.now().toUtc())) {
      throw TimeoutException('Workspace operation deadline expired.');
    }
  }
}
