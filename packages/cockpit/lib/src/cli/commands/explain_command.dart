import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:lon/lon.dart';

import '../../supervisor/cockpit_supervisor_api_client.dart';
import '../cockpit_cli_runtime.dart';

CockpitLeafCommand cockpitExplainCommand(CockpitCliRuntime runtime) =>
    CockpitLeafCommand(
      runtime: runtime,
      name: 'explain',
      description: 'Explain one live operation and its safer task command.',
      invocationSuffix: 'KIND [arguments]',
      example: 'cockpit explain viewport.set',
      configure: (parser) => parser
        ..addOption(
          'workspace-id',
          help: 'Select a registered workspace; current checkout by default.',
        )
        ..addOption(
          'session',
          abbr: 's',
          help: 'Select another session for a session-bound operation.',
        ),
      action: (arguments) async {
        if (arguments.rest.length != 1) {
          throw const FormatException(
            'explain requires exactly one operation kind.',
          );
        }
        final kind = arguments.rest.single;
        final sessionReference = arguments.option('session');
        final session = sessionReference == null
            ? null
            : await runtime.resolveSessionHandle(
                sessionReference,
                explicitWorkspaceId: arguments.option('workspace-id'),
              );
        final client = await runtime.client();
        final global = (await client.operations())
            .where((item) => item.kind == kind)
            .toList(growable: false);
        String? workspaceId;
        List<CockpitOperationDescriptor> matches = global;
        if (matches.isEmpty) {
          workspaceId =
              session?.workspaceId ??
              await runtime.workspaceId(arguments.option('workspace-id'));
          matches = (await client.operations(
            workspaceId: workspaceId,
          )).where((item) => item.kind == kind).toList(growable: false);
        }
        if (matches.length != 1) {
          throw CockpitSupervisorClientException(
            code: CockpitErrorCode.unsupportedOperation,
            message: 'Operation $kind is not advertised in the resolved scope.',
          );
        }
        final descriptor = matches.single;
        final requestSchema = await runtime.operationContract(
          client,
          descriptor.requestSchemaRef,
        );
        final responseSchema = await runtime.operationContract(
          client,
          descriptor.responseSchemaRef,
        );
        final injectsSession = _requestInjectsSession(requestSchema);
        var effectiveSession = session;
        if (injectsSession && effectiveSession == null) {
          try {
            effectiveSession = await runtime.activeDevelopmentSession(
              workspaceId: workspaceId,
            );
          } on FormatException {
            // Explain remains available before a development session starts.
          }
        }
        final op = _opExample(
          kind,
          sessionReference == null ? null : effectiveSession?.handleId,
          requestSchema,
          sessionAvailable: !injectsSession || effectiveSession != null,
        );
        await runtime.success(<String, Object?>{
          'operation': descriptor.toJson(),
          'resolvedScope': descriptor.scope.name,
          'workspaceId': ?workspaceId,
          'session': ?effectiveSession?.handleId,
          'inputContract': <String, Object?>{
            'available': true,
            'schemaRef': descriptor.requestSchemaRef,
            'precision': requestSchema['x-cockpit-precision'],
            'schema': requestSchema,
          },
          'outputContract': <String, Object?>{
            'available': true,
            'schemaRef': descriptor.responseSchemaRef,
            'precision': responseSchema['x-cockpit-precision'],
            'schema': responseSchema,
          },
          'defaults': <String, Object?>{
            'timeoutMs': descriptor.defaultTimeoutMs,
            'maximumTimeoutMs': descriptor.maximumTimeoutMs,
            'idempotency': descriptor.idempotency.name,
          },
          'recommendedCommand': ?_devCommands[kind],
          'op': ?op,
          if (op == null)
            'opUnavailable': injectsSession
                ? 'activeSessionRequired'
                : 'liveInputExampleUnavailable',
        });
        return cockpitSuccessExitCode;
      },
    );

String? _opExample(
  String kind,
  String? session,
  Map<String, Object?> requestSchema, {
  required bool sessionAvailable,
}) {
  if (!sessionAvailable) return null;
  final input = _requiredInputExample(requestSchema);
  if (input == null) return null;
  final encoded = lon.encode(input).replaceAll("'", "'\"'\"'");
  return 'cockpit op run $kind${session == null ? '' : ' --session $session'} '
      "--input '$encoded'";
}

bool _requestInjectsSession(Map<String, Object?> requestSchema) {
  final properties = requestSchema['properties'];
  final session = properties is Map<Object?, Object?>
      ? properties['sessionId']
      : null;
  return session is Map<Object?, Object?> &&
      session['x-cockpit-injected-by'] == '--session';
}

Map<String, Object?>? _requiredInputExample(
  Map<String, Object?> requestSchema,
) {
  final rootExamples = requestSchema['examples'];
  if (rootExamples is List<Object?> && rootExamples.isNotEmpty) {
    final example = rootExamples.first;
    if (example is Map<Object?, Object?>) {
      return Map<String, Object?>.from(example);
    }
  }
  final required = requestSchema['required'];
  final properties = requestSchema['properties'];
  if (required is! List<Object?> || properties is! Map<Object?, Object?>) {
    return const <String, Object?>{};
  }
  final input = <String, Object?>{};
  for (final name in required.whereType<String>()) {
    final property = properties[name];
    if (property is! Map<Object?, Object?>) return null;
    if (property['x-cockpit-injected-by'] != null) continue;
    final example = _propertyExample(property);
    if (example == null) return null;
    input[name] = example;
  }
  return input;
}

Object? _propertyExample(Map<Object?, Object?> schema) {
  if (schema['const'] != null) return schema['const'];
  if (schema['default'] != null) return schema['default'];
  final examples = schema['examples'];
  if (examples is List<Object?> && examples.isNotEmpty) return examples.first;
  final values = schema['enum'];
  if (values is List<Object?> && values.isNotEmpty) return values.first;
  return null;
}

const Map<String, String> _devCommands = <String, String>{
  'ui.inspect': 'cockpit dev inspect',
  'command.run': 'cockpit dev tap "Exact text"',
  'ui.waitIdle': 'cockpit dev wait',
  'viewport.set': 'cockpit dev viewport 800x600',
  'evidence.screenshot.capture': 'cockpit dev screenshot',
  'app.reload': 'cockpit dev reload',
  'app.restart': 'cockpit dev restart',
  'errors.read': 'cockpit dev diagnose',
  'network.read': 'cockpit dev diagnose',
  'network.body': 'cockpit dev network REQUEST --body response',
  'logs.read': 'cockpit dev diagnose',
};
