import 'package:cockpit/src/test/cockpit_test_safety_policy.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('parses explicit worker safety authority', () {
    final configuration = CockpitWorkerRuntimeConfiguration.parse(<String>[
      ..._baseArguments,
      '--allow-target-environment=development',
      '--allow-target-environment=production',
      '--allow-target-environment=unknown',
      '--allow-safety-effect=credentialSensitive',
    ]);

    expect(configuration.allowedTargetEnvironments, <Object?>{
      CockpitTestTargetEnvironment.development,
      CockpitTestTargetEnvironment.production,
      CockpitTestTargetEnvironment.unknown,
    });
    expect(configuration.allowedSafetyEffects, <Object?>{
      CockpitTestSafetyEffect.credentialSensitive,
    });
  });

  test('rejects unknown and duplicate safety authority values', () {
    for (final extra in <List<String>>[
      <String>['--allow-target-environment=Development'],
      <String>['--allow-safety-effect=credential'],
      <String>[
        '--allow-target-environment=development',
        '--allow-target-environment=development',
      ],
      <String>[
        '--allow-safety-effect=credentialSensitive',
        '--allow-safety-effect=credentialSensitive',
      ],
    ]) {
      expect(
        () => CockpitWorkerRuntimeConfiguration.parse(<String>[
          ..._baseArguments,
          ...extra,
        ]),
        throwsFormatException,
        reason: '$extra',
      );
    }
  });
}

const List<String> _baseArguments = <String>[
  '--workspace-id=workspaceA',
  '--project-id=projectA',
  '--engine-version=engineA',
  '--workspace-root=/workspace/workspaceA',
  '--state-root=/state/workspaceA',
  '--worker-owner-id=worker_A',
  '--process-start-identity=process_A',
  '--auth=restricted',
];
