import 'dart:io';

import 'package:args/args.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../../foundation/cockpit_home.dart';
import '../../supervisor/cockpit_supervisor_api_client.dart';
import '../cockpit_cli_runtime.dart';
import '../cockpit_cli_session_handles.dart';

void cockpitConfigureOperationExecution(ArgParser parser) {
  parser
    ..addOption(
      'workspace-id',
      help: 'Select a registered workspace; current checkout by default.',
    )
    ..addOption('root-id', help: 'Required only for a root-scoped operation.')
    ..addOption(
      'session',
      abbr: 's',
      help: 'Select another session when the schema injects sessionId.',
    )
    ..addOption(
      'input',
      abbr: 'i',
      help: 'Operation input as LON, JSON, or YAML.',
    )
    ..addOption(
      'input-file',
      help: 'Read operation input from a LON, JSON, or YAML file.',
    )
    ..addOption(
      'idempotency-key',
      help: 'Replay key; generated when the operation requires one.',
    )
    ..addMultiOption(
      'required-feature',
      help: 'Require a live advertised feature before execution.',
    );
}

Future<int> cockpitExecuteOperation(
  CockpitCliRuntime runtime,
  ArgResults arguments, {
  required String kind,
}) async {
  final client = await runtime.client();
  final explicitWorkspaceId = arguments.option('workspace-id');
  final sessionReference = arguments.option('session');
  CockpitCliSessionHandle? sessionHandle;
  if (sessionReference != null) {
    sessionHandle = await runtime.resolveSessionHandle(
      sessionReference,
      explicitWorkspaceId: explicitWorkspaceId,
    );
  }
  final globalMatches = (await client.operations())
      .where((item) => item.kind == kind)
      .toList(growable: false);
  late final CockpitOperationDescriptor descriptor;
  String? workspaceId;
  if (globalMatches.length == 1) {
    if (sessionHandle != null) {
      throw const FormatException(
        '--session is only valid for workspace-scoped operations.',
      );
    }
    descriptor = globalMatches.single;
  } else {
    workspaceId =
        sessionHandle?.workspaceId ??
        await runtime.workspaceId(explicitWorkspaceId);
    final matches = (await client.operations(
      workspaceId: workspaceId,
    )).where((item) => item.kind == kind).toList(growable: false);
    if (matches.length != 1) {
      throw CockpitSupervisorClientException(
        code: CockpitErrorCode.unsupportedOperation,
        message: 'Operation $kind is not advertised in the selected scope.',
      );
    }
    descriptor = matches.single;
  }
  runtime.adoptOperationTimeout(descriptor);
  client.requestTimeout = runtime.remainingTimeout;
  return runtime.runTimed(() async {
    final input = runtime.structuredObject(
      arguments.option('input'),
      arguments.option('input-file'),
    );
    final injectsSession = await runtime.operationInjectsSession(
      client,
      descriptor,
    );
    if (injectsSession &&
        sessionHandle == null &&
        input['sessionId'] == null &&
        input['targetId'] == null) {
      sessionHandle = await runtime.activeDevelopmentSession(
        workspaceId: workspaceId,
      );
    }
    if (sessionHandle != null && injectsSession) {
      if (input['targetId'] != null) {
        throw const FormatException(
          '--session cannot be combined with input.targetId.',
        );
      }
      final suppliedSessionId = input['sessionId'];
      if (suppliedSessionId != null &&
          suppliedSessionId != sessionHandle!.sessionId) {
        throw const FormatException(
          '--session conflicts with input.sessionId.',
        );
      }
      input['sessionId'] = sessionHandle!.sessionId;
    }
    final idempotencyKey = runtime.operationIdempotencyKey(
      descriptor,
      arguments.option('idempotency-key'),
    );
    if (descriptor.scope == CockpitOperationScope.root &&
        arguments.option('root-id') == null) {
      throw const FormatException('--root-id is required for this operation.');
    }
    final result = await client.executeAdvertisedOperation(
      CockpitOperationInvocation(
        kind: kind,
        rootId: descriptor.scope == CockpitOperationScope.root
            ? arguments.option('root-id')
            : null,
        workspaceId: descriptor.scope == CockpitOperationScope.workspace
            ? workspaceId
            : null,
        input: input,
        idempotencyKey: idempotencyKey,
        deadline: runtime.timeoutExplicit ? runtime.commandDeadline : null,
        requiredFeatures: arguments.multiOption('required-feature'),
      ),
      descriptor: descriptor,
    );
    final captured = await runtime.captureSessionHandle(
      result,
      workspaceId: workspaceId,
    );
    final effectiveSession = captured ?? sessionHandle;
    var receipt = runtime.operationReceipt(
      result,
      sessionHandle: effectiveSession,
      idempotencyKey: idempotencyKey,
    );
    if (kind == 'system.action' && effectiveSession != null) {
      receipt = await _materializeSystemActionArtifact(
        client,
        receipt,
        effectiveSession,
      );
    }
    await runtime.success(receipt);
    return cockpitExitCodeForOperation(result);
  });
}

Future<Map<String, Object?>> _materializeSystemActionArtifact(
  CockpitSupervisorApiClient client,
  Map<String, Object?> receipt,
  CockpitCliSessionHandle session,
) async {
  final output = _stringMap(receipt['output']);
  final artifact = _stringMap(output?['artifact']);
  final reference = _stringMap(artifact?['artifactRef']);
  final artifactId = reference?['artifactId'];
  final name = reference?['name'];
  final mediaType = reference?['mediaType'];
  if (output == null ||
      artifactId is! String ||
      artifactId.isEmpty ||
      name is! String ||
      name.isEmpty ||
      mediaType is! String ||
      mediaType.isEmpty) {
    return receipt;
  }
  final home = CockpitHome.system();
  final paths = await home.initialize();
  final owner = session.checkoutIdentity ?? session.workspaceId;
  final directory = Directory(
    p.join(
      paths.artifactsDirectory,
      'development',
      _safePathSegment(owner.length > 16 ? owner.substring(0, 16) : owner),
      _safePathSegment(session.handleId),
      'system',
      _safePathSegment(artifactId),
    ),
  );
  await directory.create(recursive: true);
  await home.permissionHardener.hardenDirectory(directory);
  final destination = File(p.join(directory.path, p.basename(name)));
  final downloaded = await client.downloadDevelopmentArtifactToFile(
    workspaceId: session.workspaceId,
    sessionId: session.sessionId,
    artifactId: artifactId,
    mediaType: mediaType,
    destination: destination,
  );
  final canonicalPath = p.normalize(
    await downloaded.file.resolveSymbolicLinks(),
  );
  return <String, Object?>{
    ...receipt,
    'output': <String, Object?>{...output, 'path': canonicalPath}
      ..remove('artifact'),
  };
}

Map<String, Object?>? _stringMap(Object? value) {
  if (value is! Map<Object?, Object?> ||
      value.keys.any((key) => key is! String)) {
    return null;
  }
  return Map<String, Object?>.from(value);
}

String _safePathSegment(String value) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return safe.isEmpty ? 'session' : safe;
}
