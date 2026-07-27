import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_authorization.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_operation_catalog.dart';
import 'package:cockpit/src/test/cockpit_test_safety_policy.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('operation catalog publishes execution and timeout policies', () {
    final launch = CockpitSupervisorOperationCatalog.require(
      'target.launch',
    ).descriptor;
    final testCase = CockpitSupervisorOperationCatalog.require(
      'case.run',
    ).descriptor;
    final suite = CockpitSupervisorOperationCatalog.require(
      'suite.run',
    ).descriptor;

    expect(launch.executionMode, CockpitOperationExecutionMode.synchronous);
    expect(launch.defaultTimeoutMs, 600000);
    expect(launch.maximumTimeoutMs, 1860000);
    expect(testCase.executionMode, CockpitOperationExecutionMode.job);
    expect(testCase.defaultTimeoutMs, 1800000);
    expect(testCase.maximumTimeoutMs, 21600000);
    expect(suite.executionMode, CockpitOperationExecutionMode.job);
    expect(suite.defaultTimeoutMs, 7200000);
    expect(suite.maximumTimeoutMs, 86400000);
  });

  test(
    'persisted policy explicitly authorizes production automation',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-authorization-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final store = CockpitSupervisorAuthorizationPolicyStore(
        path: p.join(temporary.path, 'authorization.json'),
        permissionHardener: const _NoopPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
      );
      final policy = CockpitSupervisorAuthorizationPolicy(
        allowedDangerousOperations: const <String>{'target.launch'},
        allowedOperationSafetyEffects: const <CockpitSafetyEffect>{
          CockpitSafetyEffect.externalSideEffect,
        },
        allowedTargetEnvironments: const <CockpitTestTargetEnvironment>{
          CockpitTestTargetEnvironment.production,
          CockpitTestTargetEnvironment.unknown,
        },
        allowedSafetyEffects: const <CockpitTestSafetyEffect>{
          CockpitTestSafetyEffect.destructive,
          CockpitTestSafetyEffect.credentialSensitive,
        },
        allowedEnvironmentSecretNames: const <String>{'E2E_PASSWORD'},
      );

      await store.replace(policy);
      final recovered = await CockpitSupervisorAuthorizationPolicyStore(
        path: p.join(temporary.path, 'authorization.json'),
        permissionHardener: const _NoopPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
      ).read();

      expect(recovered.toJson(), policy.toJson());
      expect(
        CockpitSupervisorAuthorizationPolicy.fromJson(
          recovered.toJson(),
        ).toJson(),
        policy.toJson(),
      );
      expect(
        () => recovered.authorizeOperation(
          CockpitSupervisorOperationCatalog.require('target.launch'),
          CockpitOperationInvocation(
            kind: 'target.launch',
            workspaceId: 'workspaceOne',
            input: const <String, Object?>{'targetEnvironment': 'production'},
          ),
        ),
        returnsNormally,
      );
    },
  );

  test('default policy keeps dangerous operations denied', () {
    final policy = CockpitSupervisorAuthorizationPolicy();
    expect(
      () => policy.authorizeOperation(
        CockpitSupervisorOperationCatalog.require('system.action'),
        CockpitOperationInvocation(
          kind: 'system.action',
          workspaceId: 'workspaceOne',
        ),
      ),
      throwsA(
        isA<CockpitApiException>().having(
          (error) => error.error.code,
          'code',
          'operationNotAuthorized',
        ),
      ),
    );
  });

  test('yolo mode grants every operation and test safety capability', () {
    final policy = CockpitSupervisorAuthorizationPolicy(
      mode: CockpitAuthorizationMode.yolo,
    );

    expect(
      () => policy.authorizeOperation(
        CockpitSupervisorOperationCatalog.require('system.action'),
        CockpitOperationInvocation(
          kind: 'system.action',
          workspaceId: 'workspaceOne',
          input: const <String, Object?>{'targetEnvironment': 'production'},
        ),
      ),
      returnsNormally,
    );
    expect(
      policy.effectiveAllowedTargetEnvironments,
      CockpitTestTargetEnvironment.values.toSet(),
    );
    expect(
      policy.effectiveAllowedSafetyEffects,
      CockpitTestSafetyEffect.values.toSet(),
    );
    expect(policy.allowsEnvironmentSecretName('ANY_SECRET'), isTrue);
  });
}

final class _NoopPermissionHardener implements CockpitPermissionHardener {
  const _NoopPermissionHardener();

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {}

  @override
  Future<void> hardenFile(File file) async {}
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
