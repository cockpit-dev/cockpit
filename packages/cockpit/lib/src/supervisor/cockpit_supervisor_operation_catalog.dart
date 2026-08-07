import 'package:cockpit_protocol/cockpit_protocol.dart';

final class CockpitSupervisorOperationMetadata {
  const CockpitSupervisorOperationMetadata({
    required this.descriptor,
    required this.requiresExplicitAuthorization,
  });

  final CockpitOperationDescriptor descriptor;
  final bool requiresExplicitAuthorization;
}

final class CockpitSupervisorOperationCatalog {
  CockpitSupervisorOperationCatalog._();

  static final Map<String, CockpitSupervisorOperationMetadata> _operations =
      Map<String, CockpitSupervisorOperationMetadata>.unmodifiable({
        for (final metadata in <CockpitSupervisorOperationMetadata>[
          _read(
            'target.discover',
            CockpitOperationScope.supervisor,
            defaultTimeout: const Duration(minutes: 2),
            maximumTimeout: const Duration(minutes: 10),
          ),
          _read('lease.list', CockpitOperationScope.supervisor),
          _mutation(
            'lease.recover',
            CockpitOperationScope.supervisor,
            effects: const <CockpitSafetyEffect>[CockpitSafetyEffect.reset],
          ),
          _read('system.capabilities', CockpitOperationScope.supervisor),
          _read('system.diagnostics', CockpitOperationScope.supervisor),
          _mutation(
            'project.create',
            CockpitOperationScope.root,
            defaultTimeout: const Duration(minutes: 10),
            maximumTimeout: const Duration(minutes: 30),
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.shell,
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _read('package.search', CockpitOperationScope.root),
          _read(
            'document.index',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 5),
            maximumTimeout: const Duration(minutes: 15),
          ),
          _read('document.list', CockpitOperationScope.workspace),
          _read('case.validate', CockpitOperationScope.workspace),
          _job(
            'case.run',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 30),
            maximumTimeout: const Duration(hours: 6),
          ),
          _job(
            'suite.run',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(hours: 2),
            maximumTimeout: const Duration(hours: 24),
          ),
          _read(
            'analyze.files',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 5),
            maximumTimeout: const Duration(minutes: 30),
          ),
          _read(
            'analyze.workspace',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 10),
            maximumTimeout: const Duration(hours: 1),
          ),
          _mutation(
            'fix.workspace',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 10),
            maximumTimeout: const Duration(minutes: 30),
          ),
          _mutation(
            'format.workspace',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 10),
            maximumTimeout: const Duration(minutes: 30),
          ),
          _mutation(
            'test.workspace',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 30),
            maximumTimeout: const Duration(hours: 4),
          ),
          _mutation(
            'package.pub',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 30),
            maximumTimeout: const Duration(hours: 2),
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _read('lsp.request', CockpitOperationScope.workspace),
          _read('package.uris.read', CockpitOperationScope.workspace),
          _read('package.uris.grep', CockpitOperationScope.workspace),
          _read('app.list', CockpitOperationScope.workspace),
          _read('app.get', CockpitOperationScope.workspace),
          _read('target.list', CockpitOperationScope.workspace),
          _read('target.get', CockpitOperationScope.workspace),
          _read('target.inspect', CockpitOperationScope.workspace),
          _mutation(
            'target.register',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 5),
            maximumTimeout: const Duration(minutes: 15),
          ),
          _mutation(
            'app.launch',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 10),
            maximumTimeout: const Duration(minutes: 31),
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _mutation(
            'target.launch',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 10),
            maximumTimeout: const Duration(minutes: 31),
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _mutation(
            'app.stop',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _mutation(
            'session.remote.launch',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 10),
            maximumTimeout: const Duration(minutes: 31),
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _read('session.remote.get', CockpitOperationScope.workspace),
          _read('session.remote.status', CockpitOperationScope.workspace),
          _read('snapshot.remote.read', CockpitOperationScope.workspace),
          _mutation(
            'snapshot.remote.collect',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[CockpitSafetyEffect.capture],
          ),
          _mutation(
            'command.remote.execute',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _mutation(
            'command.remote.batch',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _mutation(
            'ui.remote.waitIdle',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(seconds: 30),
            maximumTimeout: const Duration(minutes: 5),
          ),
          _mutation(
            'session.development.launch',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 10),
            maximumTimeout: const Duration(minutes: 31),
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _read('session.development.get', CockpitOperationScope.workspace),
          _mutation(
            'session.development.reload',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _mutation(
            'session.development.stop',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _mutation(
            'development.probe.collect',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[CockpitSafetyEffect.capture],
          ),
          _read('development.probe.compare', CockpitOperationScope.workspace),
          _read('ui.inspect', CockpitOperationScope.workspace),
          _read('surface.inspect', CockpitOperationScope.workspace),
          _read('logs.read', CockpitOperationScope.workspace),
          _read('network.read', CockpitOperationScope.workspace),
          _mutation(
            'network.body',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[CockpitSafetyEffect.capture],
          ),
          _read('errors.read', CockpitOperationScope.workspace),
          _read('session.logs.read', CockpitOperationScope.workspace),
          _mutation(
            'evidence.screenshot.capture',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[CockpitSafetyEffect.capture],
          ),
          _mutation(
            'command.run',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 5),
            maximumTimeout: const Duration(minutes: 30),
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _mutation(
            'command.batch',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 5),
            maximumTimeout: const Duration(minutes: 30),
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _mutation(
            'shell.run',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(minutes: 5),
            maximumTimeout: const Duration(minutes: 30),
            effects: const <CockpitSafetyEffect>[CockpitSafetyEffect.shell],
          ),
          _mutation(
            'system.action',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.system,
              CockpitSafetyEffect.reset,
              CockpitSafetyEffect.permission,
              CockpitSafetyEffect.capture,
              CockpitSafetyEffect.recording,
            ],
          ),
          _mutation(
            'app.reload',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _mutation(
            'app.restart',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[
              CockpitSafetyEffect.externalSideEffect,
            ],
          ),
          _mutation(
            'ui.waitIdle',
            CockpitOperationScope.workspace,
            defaultTimeout: const Duration(seconds: 30),
            maximumTimeout: const Duration(minutes: 5),
          ),
          _mutation('viewport.set', CockpitOperationScope.workspace),
          _mutation(
            'recording.start',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[CockpitSafetyEffect.recording],
          ),
          _mutation(
            'recording.stop',
            CockpitOperationScope.workspace,
            effects: const <CockpitSafetyEffect>[CockpitSafetyEffect.recording],
          ),
        ])
          metadata.descriptor.kind: metadata,
      });

  static List<CockpitOperationDescriptor> get supervisorOperations =>
      _operations.values
          .where(
            (metadata) =>
                metadata.descriptor.scope != CockpitOperationScope.workspace,
          )
          .map((metadata) => metadata.descriptor)
          .toList(growable: false)
        ..sort((left, right) => left.kind.compareTo(right.kind));

  static List<CockpitOperationDescriptor> get allOperations =>
      _operations.values.map((metadata) => metadata.descriptor).toList()
        ..sort((left, right) => left.kind.compareTo(right.kind));

  static CockpitSupervisorOperationMetadata require(String kind) {
    final metadata = _operations[kind];
    if (metadata == null) {
      throw CockpitApiException(
        CockpitApiError(
          code: CockpitErrorCode.unsupportedOperation,
          category: CockpitErrorCategory.unsupported,
          message: 'Operation $kind is not supported.',
          retryable: false,
          responsibleLayer: CockpitResponsibleLayer.supervisor,
        ),
      );
    }
    return metadata;
  }

  static List<CockpitOperationDescriptor> workspaceDescriptors(
    Iterable<String> kinds,
  ) => kinds
      .map((kind) {
        final descriptor = require(kind).descriptor;
        if (descriptor.scope != CockpitOperationScope.workspace) {
          throw StateError('Worker advertised non-workspace operation $kind.');
        }
        return descriptor;
      })
      .toList(growable: false);
}

CockpitSupervisorOperationMetadata _read(
  String kind,
  CockpitOperationScope scope, {
  Duration defaultTimeout = const Duration(seconds: 30),
  Duration maximumTimeout = const Duration(minutes: 5),
}) => _metadata(
  kind,
  scope,
  CockpitMutationClass.readOnly,
  CockpitIdempotencyBehavior.optional,
  CockpitOperationExecutionMode.synchronous,
  const <CockpitSafetyEffect>[],
  defaultTimeout,
  maximumTimeout,
);

CockpitSupervisorOperationMetadata _mutation(
  String kind,
  CockpitOperationScope scope, {
  List<CockpitSafetyEffect> effects = const <CockpitSafetyEffect>[],
  Duration defaultTimeout = const Duration(minutes: 2),
  Duration maximumTimeout = const Duration(minutes: 10),
}) => _metadata(
  kind,
  scope,
  CockpitMutationClass.mutating,
  CockpitIdempotencyBehavior.required,
  CockpitOperationExecutionMode.synchronous,
  effects,
  defaultTimeout,
  maximumTimeout,
);

CockpitSupervisorOperationMetadata _job(
  String kind,
  CockpitOperationScope scope, {
  required Duration defaultTimeout,
  required Duration maximumTimeout,
}) => _metadata(
  kind,
  scope,
  CockpitMutationClass.mutating,
  CockpitIdempotencyBehavior.required,
  CockpitOperationExecutionMode.job,
  const <CockpitSafetyEffect>[],
  defaultTimeout,
  maximumTimeout,
);

CockpitSupervisorOperationMetadata _metadata(
  String kind,
  CockpitOperationScope scope,
  CockpitMutationClass mutationClass,
  CockpitIdempotencyBehavior idempotency,
  CockpitOperationExecutionMode executionMode,
  List<CockpitSafetyEffect> effects,
  Duration defaultTimeout,
  Duration maximumTimeout,
) => CockpitSupervisorOperationMetadata(
  descriptor: CockpitOperationDescriptor(
    kind: kind,
    title: kind,
    description: 'Cockpit $kind operation.',
    scope: scope,
    mutationClass: mutationClass,
    idempotency: idempotency,
    executionMode: executionMode,
    defaultTimeoutMs: defaultTimeout.inMilliseconds,
    maximumTimeoutMs: maximumTimeout.inMilliseconds,
    requestSchemaRef: 'cockpit://operations/schema#/\$defs/$kind.request',
    responseSchemaRef: 'cockpit://operations/schema#/\$defs/$kind.response',
    safetyEffects: effects
        .map(CockpitEnumValue<CockpitSafetyEffect>.known)
        .toList(growable: false),
  ),
  requiresExplicitAuthorization: effects.isNotEmpty,
);
