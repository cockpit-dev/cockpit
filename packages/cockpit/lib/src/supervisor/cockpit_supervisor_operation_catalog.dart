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
          _mutation(
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

  static List<CockpitOperationDescriptor> get workspaceOperations =>
      _operations.values
          .where(
            (metadata) =>
                metadata.descriptor.scope == CockpitOperationScope.workspace,
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
) {
  final help = _operationHelp[kind];
  if (help == null) {
    throw StateError('Missing public operation help: $kind.');
  }
  return CockpitSupervisorOperationMetadata(
    descriptor: CockpitOperationDescriptor(
      kind: kind,
      title: help.title,
      description: help.description,
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
}

const Map<String, ({String title, String description})>
_operationHelp = <String, ({String title, String description})>{
  'target.discover': (
    title: 'Discover targets',
    description: 'Discover host, simulator, emulator, and device targets.',
  ),
  'lease.list': (
    title: 'List leases',
    description: 'List the newest resource leases with bounded pagination.',
  ),
  'lease.recover': (
    title: 'Recover lease',
    description: 'Verify and recover one stale or quarantined lease.',
  ),
  'system.capabilities': (
    title: 'Inspect system capabilities',
    description: 'Describe native control available for one platform target.',
  ),
  'system.diagnostics': (
    title: 'Read system diagnostics',
    description: 'Read bounded Supervisor health and resource diagnostics.',
  ),
  'project.create': (
    title: 'Create project',
    description: 'Create a production Dart CLI or Flutter application.',
  ),
  'package.search': (
    title: 'Search packages',
    description: 'Search pub.dev packages with bounded result metadata.',
  ),
  'document.index': (
    title: 'Index documents',
    description: 'Refresh the workspace document index with optional filters.',
  ),
  'document.list': (
    title: 'List documents',
    description: 'List indexed workspace documents with bounded pagination.',
  ),
  'case.validate': (
    title: 'Validate case',
    description: 'Validate one inline Cockpit case without running it.',
  ),
  'case.run': (
    title: 'Run case',
    description: 'Submit one indexed or inline case as a durable run.',
  ),
  'suite.run': (
    title: 'Run suite',
    description: 'Submit one indexed or inline suite as a durable run.',
  ),
  'analyze.files': (
    title: 'Analyze files',
    description:
        'Analyze selected indexed Dart files with bounded diagnostics.',
  ),
  'analyze.workspace': (
    title: 'Analyze workspace',
    description: 'Run static analysis for the registered workspace.',
  ),
  'fix.workspace': (
    title: 'Apply Dart fixes',
    description: 'Apply safe Dart fixes across the registered workspace.',
  ),
  'format.workspace': (
    title: 'Format workspace',
    description: 'Format the workspace or selected indexed documents.',
  ),
  'test.workspace': (
    title: 'Test workspace',
    description: 'Run bounded Dart or Flutter tests for selected paths.',
  ),
  'package.pub': (
    title: 'Run Pub command',
    description: 'Run an allowed dependency-management command through Pub.',
  ),
  'lsp.request': (
    title: 'Query language server',
    description: 'Run one bounded Dart language-server query.',
  ),
  'package.uris.read': (
    title: 'Read package URI',
    description: 'Read bounded text or archive metadata for a package URI.',
  ),
  'package.uris.grep': (
    title: 'Search package URIs',
    description: 'Search dependency sources without unrelated file scans.',
  ),
  'app.list': (
    title: 'List applications',
    description: 'List applications owned by the current workspace.',
  ),
  'app.get': (
    title: 'Inspect application',
    description: 'Read one application and its current live Flutter state.',
  ),
  'target.list': (
    title: 'List workspace targets',
    description: 'List registered targets isolated to the current workspace.',
  ),
  'target.get': (
    title: 'Get target',
    description: 'Read one registered target without launching it.',
  ),
  'target.inspect': (
    title: 'Inspect target',
    description: 'Read live target capabilities, surface, and selected state.',
  ),
  'target.register': (
    title: 'Register target',
    description:
        'Register a Flutter, native, browser, device, or system target.',
  ),
  'app.launch': (
    title: 'Launch application',
    description: 'Launch one registered target as a managed application.',
  ),
  'target.launch': (
    title: 'Launch target',
    description: 'Launch one target in the requested execution mode.',
  ),
  'app.stop': (
    title: 'Stop application',
    description: 'Stop exactly one managed application by application ID.',
  ),
  'session.remote.launch': (
    title: 'Launch remote session',
    description: 'Launch a Flutter bridge session for one registered target.',
  ),
  'session.remote.get': (
    title: 'Get remote session',
    description: 'Read one remote session identity and connection state.',
  ),
  'session.remote.status': (
    title: 'Read remote status',
    description: 'Read live bridge status with an optional bounded snapshot.',
  ),
  'snapshot.remote.read': (
    title: 'Read remote snapshot',
    description: 'Read and optionally compare one bounded Flutter snapshot.',
  ),
  'snapshot.remote.collect': (
    title: 'Collect remote snapshot',
    description: 'Collect a protocol snapshot and artifact references.',
  ),
  'command.remote.execute': (
    title: 'Execute remote command',
    description: 'Execute one typed Flutter command through a remote session.',
  ),
  'command.remote.batch': (
    title: 'Execute remote batch',
    description: 'Execute an ordered batch of typed Flutter commands.',
  ),
  'ui.remote.waitIdle': (
    title: 'Wait for remote UI',
    description:
        'Wait for Flutter UI quiet, optionally including network idle.',
  ),
  'session.development.launch': (
    title: 'Launch development session',
    description:
        'Launch a resident Flutter development session for one target.',
  ),
  'session.development.get': (
    title: 'Get development session',
    description: 'Read one development session and its launch identity.',
  ),
  'session.development.reload': (
    title: 'Reload development session',
    description: 'Hot reload or hot restart exactly one development session.',
  ),
  'session.development.stop': (
    title: 'Stop development session',
    description: 'Stop exactly one managed Flutter development session.',
  ),
  'development.probe.collect': (
    title: 'Collect development probe',
    description: 'Capture bounded UI, runtime, log, and network state.',
  ),
  'development.probe.compare': (
    title: 'Compare development probes',
    description: 'Compare two retained probes from the same session.',
  ),
  'ui.inspect': (
    title: 'Inspect UI',
    description: 'Inspect Flutter UI with optional snapshot comparison.',
  ),
  'surface.inspect': (
    title: 'Inspect surface',
    description:
        'Inspect the current route, viewport, overlays, and visible UI.',
  ),
  'logs.read': (
    title: 'Read application logs',
    description: 'Read a bounded tail of application runtime logs.',
  ),
  'network.read': (
    title: 'Read network index',
    description: 'Read a bounded, filterable network activity index.',
  ),
  'network.body': (
    title: 'Export network body',
    description:
        'Export selected request or response bodies to artifact files.',
  ),
  'errors.read': (
    title: 'Read runtime errors',
    description: 'Read a bounded list of captured application errors.',
  ),
  'session.logs.read': (
    title: 'Read session logs',
    description: 'Read a bounded log tail for one exact session.',
  ),
  'evidence.screenshot.capture': (
    title: 'Capture screenshot evidence',
    description: 'Capture current UI using the requested source policy.',
  ),
  'command.run': (
    title: 'Run interactive command',
    description: 'Execute one command with compact AI-oriented output.',
  ),
  'command.batch': (
    title: 'Run interactive batch',
    description: 'Execute a command batch with recording and final snapshot.',
  ),
  'shell.run': (
    title: 'Run shell command',
    description: 'Run one argv-safe process inside the workspace boundary.',
  ),
  'system.action': (
    title: 'Run system action',
    description: 'Run one native action for an exact session or target.',
  ),
  'app.reload': (
    title: 'Reload application',
    description: 'Hot reload the application bound to one exact session.',
  ),
  'app.restart': (
    title: 'Restart application',
    description: 'Hot restart the application bound to one exact session.',
  ),
  'ui.waitIdle': (
    title: 'Wait for UI',
    description: 'Wait for UI quiet through the interactive session path.',
  ),
  'viewport.set': (
    title: 'Set viewport',
    description: 'Resize one Flutter session to an exact logical viewport.',
  ),
  'recording.start': (
    title: 'Start recording',
    description: 'Start one bounded recording for an exact session.',
  ),
  'recording.stop': (
    title: 'Stop recording',
    description: 'Stop one recording and finalize its artifact metadata.',
  ),
};
