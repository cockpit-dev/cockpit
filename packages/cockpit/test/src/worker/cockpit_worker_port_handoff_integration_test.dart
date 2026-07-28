import 'dart:async';
import 'dart:io';

import 'package:cockpit/src/supervisor/cockpit_safe_port_allocator.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_worker_endpoint.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_worker_port_bridge.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_port_ownership_inspector.dart';
import 'package:cockpit/src/supervisor/cockpit_worker_resource_authority.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_rpc_forwarded_port_handoff.dart';
import 'package:cockpit/src/worker/cockpit_rpc_resource_authority_client.dart';
import 'package:cockpit/src/worker/cockpit_worker_memory_event_exchange.dart';
import 'package:cockpit/src/worker/cockpit_worker_operation_journal.dart';
import 'package:cockpit/src/worker/cockpit_worker_operation_router.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_result.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_grant.dart';
import 'package:cockpit/src/worker/cockpit_worker_server.dart';
import 'package:cockpit/src/worker/cockpit_worker_value_reader.dart';
import 'package:cockpit/src/worker/cockpit_workspace_operation_registry.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

import '../supervisor/cockpit_lease_test_support.dart';

void main() {
  test(
    'Supervisor hands off an authenticated port without process ancestry',
    () async {
      final fixture = await CockpitLeaseTestFixture.create();
      final channels = _PeerChannels();
      late CockpitJsonRpcPeer supervisorPeer;
      late CockpitJsonRpcPeer workerPeer;
      late CockpitSupervisorWorkerEndpoint endpoint;
      late CockpitWorkerServer server;
      ServerSocket? ownedSocket;
      final ownershipInspector = _PortInspector();
      final bridge = CockpitSupervisorWorkerPortBridge(
        workspaceId: 'workspaceA',
        workerOwnerId: 'workerA',
        workerProcessId: 4242,
        processStartIdentity: 'processA',
        ownershipInspector: ownershipInspector,
        call: ({required method, required params, required deadline}) =>
            supervisorPeer.call(
              method: method,
              params: params,
              deadline: deadline,
            ),
      );
      final authority = CockpitLeaseWorkerResourceAuthority(
        workspaceId: 'workspaceA',
        leases: fixture.registry,
        ports: CockpitSafePortAllocator(leases: fixture.registry),
        portBridge: bridge,
      );
      endpoint = CockpitSupervisorWorkerEndpoint(
        workspaceId: 'workspaceA',
        events: CockpitWorkerMemoryEventExchange(),
        resourceAuthority: authority,
      );
      supervisorPeer = CockpitJsonRpcPeer(
        input: channels.supervisorInput.stream,
        output: channels.workerInput.sink,
        requestHandler: endpoint.handle,
      );
      workerPeer = CockpitJsonRpcPeer(
        input: channels.workerInput.stream,
        output: channels.supervisorInput.sink,
        requestHandler: (request, cancellation) =>
            server.handle(request, cancellation),
      );
      final handoff = CockpitRpcWorkerForwardedPortHandoff(
        workspaceId: 'workspaceA',
        peer: workerPeer,
      );
      final workspaceOperations = CockpitWorkspaceOperationRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: '/workspace/a',
        adapters: <CockpitWorkspaceOperationAdapter>[
          CockpitWorkspaceOperationAdapter(
            kind: 'test.forwarded.launch',
            mutationClass: CockpitMutationClass.mutating,
            resourceKinds: const <String>['test.forwarded'],
            prepare: (context, _) => CockpitPreparedWorkspaceOperation(
              resources: <CockpitWorkerResourceRequest>[
                CockpitWorkerResourceRequest(
                  resourceKind: CockpitLeaseResourceKind.forwardedPort,
                  resourceId: 'workspaceA:app.launch',
                  requiresPort: true,
                ),
              ],
              execute: (grants) async {
                final grant = grants.single;
                final port = await handoff.launchWithGrant<int>(
                  grant: grant,
                  deadline: context.deadline,
                  launch: (port) async {
                    ownedSocket = await ServerSocket.bind(
                      InternetAddress.loopbackIPv4,
                      port,
                      shared: false,
                    );
                    return ownedSocket!.port;
                  },
                );
                return <String, Object?>{
                  'port': port,
                  'resourceId': grant.resourceId,
                  'leaseId': grant.leaseId,
                };
              },
            ),
          ),
        ],
        resourceAuthority: CockpitRpcResourceAuthorityClient(
          workspaceId: 'workspaceA',
          peer: workerPeer,
        ),
        operationJournal: CockpitInMemoryWorkerOperationJournal(),
        terminateUnsafeWorker: workerPeer.close,
      );
      server = CockpitWorkerServer(
        workspaceId: 'workspaceA',
        engineVersion: 'engineA',
        workspaceRoot: '/workspace/a',
        supportedFeatures: const <String>[],
        operations: CockpitWorkerOperationRouter(
          workspaceOperations: workspaceOperations,
          internalDispatchers: <CockpitWorkerInternalOperationDispatcher>[
            handoff,
          ],
        ),
        events: CockpitWorkerMemoryEventExchange(),
      );
      server.bindPeer(workerPeer);
      supervisorPeer.start();
      workerPeer.start();
      addTearDown(() async {
        await ownedSocket?.close();
        await supervisorPeer.close();
        await workerPeer.close(closeOutput: false);
        await fixture.dispose();
      });
      await _initialize(supervisorPeer);
      ownershipInspector.ownedByWorker = false;

      final deadline = _deadline();
      final launched = CockpitWorkerOperationResult.fromJson(
        await supervisorPeer.call(
          method: 'operation',
          params: <String, Object?>{
            'protocolVersion': cockpitWorkerProtocolVersion,
            'workspaceId': 'workspaceA',
            'idempotencyKey': 'registry-port-launch',
            'invocation': CockpitOperationInvocation(
              kind: 'test.forwarded.launch',
              workspaceId: 'workspaceA',
              idempotencyKey: CockpitIdempotencyKey('registry-port-launch'),
              deadline: deadline,
            ).toJson(),
          },
          deadline: deadline,
        ),
      ).result;
      expect(launched.outcome, CockpitOperationOutcome.succeeded);
      expect(launched.output!['port'], ownedSocket!.port);
      expect(launched.output!['resourceId'], 'workspaceA:app.launch');
      expect(
        launched.output!['leaseId'],
        isNot(launched.output!['resourceId']),
      );
      expect(ownedSocket?.address.isLoopback, isTrue);
      expect(
        (await fixture.registry.get(
          launched.output!['leaseId']! as String,
        )).state,
        CockpitLeaseState.released,
      );
      expect(ownedSocket?.port, launched.output!['port']);
    },
  );
}

Future<void> _initialize(CockpitJsonRpcPeer peer) async {
  final result = CockpitWorkerInitializeResult.fromJson(
    await peer.call(
      method: 'initialize',
      params: const <String, Object?>{
        'protocolVersion': cockpitWorkerProtocolVersion,
        'workspaceId': 'workspaceA',
        'idempotencyKey': 'initialize',
        'engineVersion': 'engineA',
        'workspaceRoot': '/workspace/a',
        'supportedFeatures': <String>[],
      },
      deadline: _deadline(),
    ),
  );
  expect(result.workspaceId, 'workspaceA');
}

DateTime _deadline() => DateTime.now().toUtc().add(const Duration(seconds: 5));

final class _PeerChannels {
  final StreamController<List<int>> supervisorInput =
      StreamController<List<int>>();
  final StreamController<List<int>> workerInput = StreamController<List<int>>();
}

final class _PortInspector implements CockpitSupervisorPortOwnershipInspector {
  var ownedByWorker = true;

  @override
  Future<CockpitSupervisorPortOwnershipEvidence?> inspect({
    required InternetAddress address,
    required int port,
    required DateTime deadline,
  }) async => CockpitSupervisorPortOwnershipEvidence(
    listenerProcessId: 4343,
    listenerStartIdentity: 'listener-process-A',
    ownedByWorker: ownedByWorker,
  );
}
