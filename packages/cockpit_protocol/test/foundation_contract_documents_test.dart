import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_protocol/src/foundation/cockpit_foundation_constraints.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/src/foundation_openapi.dart';
import '../tool/src/foundation_schema.dart';

void main() {
  final packageRoot = _packageRoot();
  final foundationSchemaFile = File(
    p.join(packageRoot.path, 'schema', 'cockpit.foundation.v2.schema.json'),
  );
  final openApiFile = File(
    p.join(packageRoot.path, 'openapi', 'cockpit.v2.openapi.json'),
  );
  final testSchemaFile = File(
    p.join(packageRoot.path, 'schema', 'cockpit.test.v2.schema.json'),
  );
  final foundationSchemaText = foundationSchemaFile.readAsStringSync();
  final openApiText = openApiFile.readAsStringSync();
  final foundationSchemaJson =
      jsonDecode(foundationSchemaText) as Map<String, Object?>;
  final openApiJson = jsonDecode(openApiText) as Map<String, Object?>;
  final testSchemaJson =
      jsonDecode(testSchemaFile.readAsStringSync()) as Map<String, Object?>;
  final foundationSchema = JsonSchema.create(
    foundationSchemaJson,
    refProvider: RefProvider.sync((ref) {
      if (ref.contains('cockpit.test.v2.schema.json')) {
        return Map<String, dynamic>.from(testSchemaJson);
      }
      return null;
    }),
  );

  test(
    'published contracts are deterministic and byte-identical to embeds',
    () {
      const encoder = JsonEncoder.withIndent('  ');
      expect(
        foundationSchemaText,
        '${encoder.convert(buildFoundationSchema())}\n',
      );
      expect(openApiText, '${encoder.convert(buildFoundationOpenApi())}\n');
      expect(cockpitFoundationV2SchemaJson, foundationSchemaText);
      expect(cockpitV2OpenApiJson, openApiText);
      expect(
        foundationSchemaJson[r'$schema'],
        'https://json-schema.org/draft/2020-12/schema',
      );
      expect(foundationSchema.schemaVersion, SchemaVersion.draft2020_12);
      expect(openApiJson['openapi'], '3.1.0');
      expect(
        openApiJson['jsonSchemaDialect'],
        foundationSchemaJson[r'$schema'],
      );
    },
  );

  test('every internal OpenAPI reference resolves as a JSON Pointer', () {
    final references = _allMaps(openApiJson)
        .map((map) => map[r'$ref'])
        .whereType<String>()
        .where((reference) => reference.startsWith('#/'))
        .toSet();

    expect(references, isNotEmpty);
    for (final reference in references) {
      expect(
        () => _resolveInternalReference(openApiJson, reference),
        returnsNormally,
        reason: reference,
      );
    }
  });

  test('published contracts avoid IDE-incompatible union type arrays', () {
    for (final document in <Map<String, Object?>>[
      foundationSchemaJson,
      openApiJson,
      testSchemaJson,
    ]) {
      for (final schemaObject in _allMaps(document)) {
        final type = schemaObject['type'];
        if (type != null) {
          expect(type, isNot(isA<List<Object?>>()));
        }
      }
    }
  });

  test('automation target contracts require valid app identity by kind', () {
    final valid = <String, Object?>{
      'targetId': 'targetA',
      'workspaceId': 'workspaceA',
      'platform': 'android',
      'deviceId': 'emulator-5554',
      'targetKind': 'nativeApp',
      'mode': 'automation',
      'environment': 'test',
      'appId': 'com.example.app',
    };
    for (final kind in const <String>[
      'nativeApp',
      'desktopApp',
      'browserPage',
    ]) {
      final withoutAppId = <String, Object?>{...valid, 'targetKind': kind}
        ..remove('appId');
      _expectDefinition(
        foundationSchema,
        'AutomationTargetResource',
        withoutAppId,
        isValid: false,
      );
      expect(
        () => CockpitAutomationTargetResource.fromJson(withoutAppId),
        throwsA(isA<FormatException>()),
      );
    }
    final blankAppId = <String, Object?>{...valid, 'appId': '   '};
    _expectDefinition(
      foundationSchema,
      'AutomationTargetResource',
      blankAppId,
      isValid: false,
    );
    expect(
      () => CockpitAutomationTargetResource.fromJson(blankAppId),
      throwsA(isA<FormatException>()),
    );
    _expectDefinition(
      foundationSchema,
      'AutomationTargetResource',
      valid,
      isValid: true,
    );
  });

  test(
    'Dart resources and schema definitions agree on execution invariants',
    () {
      final now = DateTime.utc(2026, 7, 20);
      final testCase = CockpitTestCase(
        id: 'caseA',
        target: CockpitTestTargetRequirements(
          platform: 'android',
          targetKind: 'flutterApp',
          plane: CockpitTestPlane.semantic,
        ),
        steps: <CockpitTestStepTemplate>[
          CockpitTestStepTemplate(
            stepId: 'goBack',
            operation: CockpitTestActionOperationTemplate(
              CockpitTestActionTemplate(kind: CockpitTestActionKind.back),
            ),
          ),
        ],
      );
      final error = CockpitApiError(
        code: CockpitErrorCode.assertionFailed,
        category: CockpitErrorCategory.assertion,
        message: 'Expected text was absent.',
        retryable: false,
        responsibleLayer: CockpitResponsibleLayer.worker,
      );
      final fixtures = <(String, Map<String, Object?>)>[
        (
          'ServerInfo',
          CockpitServerInfo(
            instanceId: 'supervisorA',
            apiVersion: CockpitApiVersion(major: 2, minor: 0),
            engineVersion: '2.0.0',
            startedAt: now,
          ).toJson(),
        ),
        (
          'RootResource',
          CockpitRootResource(
            rootId: 'rootA',
            canonicalPath: '/tmp/root',
            filesystemIdentity: 'dev:1:inode:2',
            state: CockpitRootState.active,
            registeredAt: now,
            updatedAt: now,
          ).toJson(),
        ),
        (
          'OperationDescriptor',
          CockpitOperationDescriptor(
            kind: 'case.run',
            title: 'Run case',
            description: 'Run one standalone case.',
            scope: CockpitOperationScope.workspace,
            mutationClass: CockpitMutationClass.mutating,
            idempotency: CockpitIdempotencyBehavior.required,
            executionMode: CockpitOperationExecutionMode.job,
            defaultTimeoutMs: 1800000,
            maximumTimeoutMs: 21600000,
            requestSchemaRef: r'#/$defs/RunSubmission',
            responseSchemaRef: r'#/$defs/RunAccepted',
          ).toJson(),
        ),
        (
          'RunSubmission',
          CockpitRunSubmission(
            workspaceId: 'workspaceA',
            source: CockpitInlineCaseSource(
              testCase: testCase,
              sourceSha256: _hash('a'),
            ),
            idempotencyKey: CockpitIdempotencyKey('run:caseA:1'),
          ).toJson(),
        ),
        (
          'RunResource',
          CockpitRunResource(
            projectId: 'projectA',
            workspaceId: 'workspaceA',
            runId: 'runA',
            documentKind: CockpitRunDocumentKind.testCase,
            documentId: testCase.id,
            sourceSha256: _hash('a'),
            lifecycle: CockpitRunLifecycle.completed,
            outcome: CockpitRunOutcome.failed,
            stability: CockpitRunStability.stable,
            submittedAt: now,
            startedAt: now,
            finishedAt: now,
            caseIds: <String>[testCase.id],
            failure: CockpitFailure(primary: error),
          ).toJson(),
        ),
        (
          'RunEvent',
          CockpitRunEvent(
            eventId: 'eventA',
            sequence: 1,
            timestamp: now,
            kind: 'run.completed',
            entityKind: CockpitRunEventEntityKind.run,
            projectId: 'projectA',
            workspaceId: 'workspaceA',
            runId: 'runA',
            lifecycle: CockpitRunLifecycle.completed,
            outcome: CockpitRunOutcome.failed,
            stability: CockpitRunStability.stable,
            failure: CockpitFailure(primary: error),
          ).toJson(),
        ),
        (
          'LeaseResource',
          CockpitLeaseResource(
            leaseId: 'leaseA',
            workspaceId: 'workspaceA',
            resourceKind: CockpitLeaseResourceKind.device,
            resourceId: 'emulator-5554',
            holderId: 'workerA',
            state: CockpitLeaseState.active,
            requestedAt: now,
            acquiredAt: now,
            expiresAt: now.add(const Duration(seconds: 30)),
          ).toJson(),
        ),
      ];
      for (final fixture in fixtures) {
        _expectDefinition(
          foundationSchema,
          fixture.$1,
          fixture.$2,
          isValid: true,
        );
      }

      final invalid = <(String, Map<String, Object?>)>[
        (
          'ServerInfo',
          <String, Object?>{...fixtures.first.$2, 'unknown': true},
        ),
        (
          'RootResource',
          <String, Object?>{...fixtures[1].$2, 'state': 'retired'}
            ..remove('retiredAt'),
        ),
        (
          'RunSubmission',
          <String, Object?>{
            ...fixtures[3].$2,
            'suiteIds': <String>['suiteA'],
          },
        ),
        (
          'RunResource',
          <String, Object?>{
            ...fixtures[4].$2,
            'outcome': 'passed',
            'attemptIds': <String>[],
          }..remove('failure'),
        ),
      ];
      for (final fixture in invalid) {
        _expectDefinition(
          foundationSchema,
          fixture.$1,
          fixture.$2,
          isValid: false,
        );
      }
    },
  );

  test('Dart validators and schema share public wire constraints', () {
    for (final invalidPath in <String>[
      '/tmp/../outside',
      r'C:\tmp\..\outside',
      '/tmp/\u0000outside',
    ]) {
      _expectDefinition(
        foundationSchema,
        'AbsolutePath',
        invalidPath,
        isValid: false,
      );
      expect(
        () => CockpitRootRegistration(path: invalidPath),
        throwsFormatException,
      );
    }
    for (final validWindowsPath in <String>[
      r'C:\tmp\root',
      r'\\server\share\root',
    ]) {
      _expectDefinition(
        foundationSchema,
        'AbsolutePath',
        validWindowsPath,
        isValid: true,
      );
      expect(
        () => CockpitRootRegistration(path: validWindowsPath),
        returnsNormally,
      );
    }

    final now = DateTime.utc(2026, 7, 20);
    final root = CockpitRootResource(
      rootId: 'rootA',
      canonicalPath: '/tmp/root',
      filesystemIdentity: 'dev:1:inode:2',
      state: CockpitRootState.active,
      registeredAt: now,
      updatedAt: now,
    );
    _expectDefinition(foundationSchema, 'RootPage', <String, Object?>{
      'items': List<Object?>.generate(101, (_) => root.toJson()),
    }, isValid: false);
    expect(
      () => CockpitPage<CockpitRootResource>(
        items: List<CockpitRootResource>.filled(101, root),
      ),
      throwsFormatException,
    );

    const nonCanonicalUtc = '2026-07-20T00:00:00+00:00';
    _expectDefinition(
      foundationSchema,
      'UtcTimestamp',
      nonCanonicalUtc,
      isValid: false,
    );
    final serverJson = CockpitServerInfo(
      instanceId: 'supervisorA',
      apiVersion: CockpitApiVersion(major: 2, minor: 0),
      engineVersion: '2.0.0',
      startedAt: now,
    ).toJson()..['startedAt'] = nonCanonicalUtc;
    expect(() => CockpitServerInfo.fromJson(serverJson), throwsFormatException);

    final caseEventJson = CockpitRunEvent(
      eventId: 'caseEventA',
      sequence: 1,
      timestamp: now,
      kind: 'case.queued',
      entityKind: CockpitRunEventEntityKind.testCase,
      projectId: 'projectA',
      workspaceId: 'workspaceA',
      runId: 'runA',
      caseId: 'caseA',
    ).toJson();
    final stepEventJson = CockpitRunEvent(
      eventId: 'stepEventA',
      sequence: 2,
      timestamp: now,
      kind: 'step.completed',
      entityKind: CockpitRunEventEntityKind.step,
      projectId: 'projectA',
      workspaceId: 'workspaceA',
      runId: 'runA',
      caseId: 'caseA',
      attemptId: 'attemptA',
      stepExecutionId: 'main/final',
      stepStatus: CockpitTestStepStatus.passed,
    ).toJson();
    for (final validEvent in <Map<String, Object?>>[
      caseEventJson,
      stepEventJson,
    ]) {
      _expectDefinition(
        foundationSchema,
        'RunEvent',
        validEvent,
        isValid: true,
      );
      expect(() => CockpitRunEvent.fromJson(validEvent), returnsNormally);
    }
    for (final invalidEvent in <Map<String, Object?>>[
      <String, Object?>{...caseEventJson, 'entityKind': 'session'},
      <String, Object?>{...caseEventJson, 'lifecycle': 'running'},
      <String, Object?>{
        ...caseEventJson,
        'kind': 'attempt.running',
        'entityKind': 'attempt',
      },
      <String, Object?>{...stepEventJson, 'outcome': 'passed'},
      <String, Object?>{
        ...caseEventJson,
        'kind': 'artifact.published',
        'entityKind': 'artifact',
        'outcome': 'passed',
      },
      <String, Object?>{...stepEventJson, 'status': 'failed'},
    ]) {
      _expectDefinition(
        foundationSchema,
        'RunEvent',
        invalidEvent,
        isValid: false,
      );
      expect(
        () => CockpitRunEvent.fromJson(invalidEvent),
        throwsFormatException,
      );
    }

    final artifact = CockpitArtifactResource(
      artifactId: 'artifactA',
      workspaceId: 'workspaceA',
      runId: 'runA',
      kind: 'evidence.screenshot',
      relativePath: 'artifacts/final.png',
      mediaType: 'image/png',
      sizeBytes: 1,
      sha256: _hash('a'),
      createdAt: now,
      downloadUrl: '/api/v2/runs/runA/artifacts/artifactA',
    );
    _expectDefinition(foundationSchema, 'ArtifactResource', <String, Object?>{
      ...artifact.toJson(),
      'stepExecutionId': 'main/final',
    }, isValid: false);
    expect(
      () => CockpitArtifactResource(
        artifactId: artifact.artifactId,
        workspaceId: artifact.workspaceId,
        runId: artifact.runId,
        stepExecutionId: 'main/final',
        kind: artifact.kind,
        relativePath: artifact.relativePath,
        mediaType: artifact.mediaType,
        sizeBytes: artifact.sizeBytes,
        sha256: artifact.sha256,
        createdAt: artifact.createdAt,
        downloadUrl: artifact.downloadUrl,
      ),
      throwsFormatException,
    );

    final atDepthLimit = _jsonObjectWithContainerDepth(
      cockpitFoundationJsonMaximumDepth,
    );
    _expectDefinition(
      foundationSchema,
      'JsonObject',
      atDepthLimit,
      isValid: true,
    );
    expect(
      () => CockpitOperationInvocation(
        kind: 'custom.execute',
        input: atDepthLimit,
      ),
      returnsNormally,
    );
    final beyondDepthLimit = _jsonObjectWithContainerDepth(
      cockpitFoundationJsonMaximumDepth + 1,
    );
    _expectDefinition(
      foundationSchema,
      'JsonObject',
      beyondDepthLimit,
      isValid: false,
    );
    expect(
      () => CockpitOperationInvocation(
        kind: 'custom.execute',
        input: beyondDepthLimit,
      ),
      throwsFormatException,
    );

    final wideJsonObject = <String, Object?>{
      'values': List<Object?>.filled(65535, null),
    };
    expect(
      utf8.encode(jsonEncode(wideJsonObject)).length,
      lessThan(cockpitFoundationRequestMaximumBytes),
    );
    final invocation = CockpitOperationInvocation(
      kind: 'case.run',
      input: wideJsonObject,
    );
    expect(invocation.input['values'], hasLength(65535));
    _expectDefinition(
      foundationSchema,
      'JsonObject',
      wideJsonObject,
      isValid: true,
    );
  });

  test('OpenAPI publishes the exact authenticated Workstream 1 surface', () {
    final paths = openApiJson['paths']! as Map<String, Object?>;
    final expectedMethods = <String, Set<String>>{
      '/api/v2/server': <String>{'get'},
      '/api/v2/capabilities': <String>{'get'},
      '/api/v2/roots': <String>{'get', 'post'},
      '/api/v2/roots/{rootId}': <String>{'delete'},
      '/api/v2/operations': <String>{'get', 'post'},
      '/api/v2/operations/schema': <String>{'get'},
      '/api/v2/workspaces': <String>{'get'},
      '/api/v2/workspaces/register': <String>{'post'},
      '/api/v2/workspaces/{workspaceId}/rebind': <String>{'post'},
      '/api/v2/workspaces/{workspaceId}': <String>{'delete'},
      '/api/v2/workspaces/{workspaceId}/targets': <String>{'get'},
      '/api/v2/workspaces/{workspaceId}/targets/{targetId}': <String>{'get'},
      '/api/v2/workspaces/{workspaceId}/documents': <String>{'get'},
      '/api/v2/workspaces/{workspaceId}/documents/validate': <String>{'post'},
      '/api/v2/workspaces/{workspaceId}/cases': <String>{'get'},
      '/api/v2/workspaces/{workspaceId}/operations': <String>{'get', 'post'},
      '/api/v2/workspaces/{workspaceId}/runs': <String>{'post'},
      '/api/v2/runs/{runId}': <String>{'get'},
      '/api/v2/runs/{runId}/cancel': <String>{'post'},
      '/api/v2/runs/{runId}/events': <String>{'get'},
      '/api/v2/runs/{runId}/report': <String>{'get'},
      '/api/v2/runs/{runId}/cases': <String>{'get'},
      '/api/v2/runs/{runId}/artifacts': <String>{'get'},
      '/api/v2/runs/{runId}/artifacts/{artifactId}': <String>{'get'},
    };
    expect(paths.keys.toSet(), expectedMethods.keys.toSet());

    final operationIds = <String>{};
    for (final entry in paths.entries) {
      final pathItem = entry.value! as Map<String, Object?>;
      final operations = pathItem.entries.where(
        (item) => const <String>{'get', 'post', 'delete'}.contains(item.key),
      );
      expect(
        operations.map((operation) => operation.key).toSet(),
        expectedMethods[entry.key],
        reason: entry.key,
      );
      for (final operationEntry in operations) {
        final operation = operationEntry.value! as Map<String, Object?>;
        expect(
          operationIds.add(operation['operationId']! as String),
          isTrue,
          reason: 'duplicate operationId at ${entry.key}',
        );
        final responses = operation['responses']! as Map<String, Object?>;
        expect(responses, contains('401'), reason: entry.key);
        if (entry.key != '/api/v2/server') {
          expect(responses, contains('426'), reason: entry.key);
          final parameters = operation['parameters']! as List<Object?>;
          final refs = parameters
              .whereType<Map<String, Object?>>()
              .map((parameter) => parameter[r'$ref'])
              .whereType<String>()
              .toSet();
          expect(refs, contains('#/components/parameters/ApiVersion'));
          expect(refs, contains('#/components/parameters/RequiredFeatures'));
        }
      }
    }

    final components = openApiJson['components']! as Map<String, Object?>;
    final securitySchemes =
        components['securitySchemes']! as Map<String, Object?>;
    expect(
      (securitySchemes['bearerAuth']! as Map<String, Object?>)['scheme'],
      'bearer',
    );
    expect(openApiJson['security'], <Object?>[
      <String, Object?>{'bearerAuth': <Object?>[]},
    ]);
    expect(
      openApiJson['x-cockpit-request-limit-bytes'],
      cockpitFoundationRequestMaximumBytes,
    );
    expect(
      openApiJson['x-cockpit-json-maximum-depth'],
      cockpitFoundationJsonMaximumDepth,
    );
    expect(
      openApiJson['x-cockpit-json-maximum-nodes'],
      cockpitFoundationJsonMaximumNodes,
    );
    expect(openApiJson['x-cockpit-cors'], 'deny');
    expect(
      (openApiJson['x-cockpit-deferred-capabilities']! as List<Object?>)
          .toSet(),
      <String>{'aiExploration'},
    );
    final definitions = foundationSchemaJson[r'$defs']! as Map<String, Object?>;
    final componentSchemas = components['schemas']! as Map<String, Object?>;
    for (final entry in componentSchemas.entries) {
      final reference =
          (entry.value! as Map<String, Object?>)[r'$ref']! as String;
      final definition = reference.split(r'#/$defs/').last;
      expect(definitions, contains(definition), reason: entry.key);
    }
    final queryTokens = _allMaps(openApiJson).where(
      (map) =>
          map['in'] == 'query' &&
          (map['name'] as String?)?.toLowerCase().contains('token') == true,
    );
    expect(queryTokens, isEmpty);

    final eventOperation =
        (paths['/api/v2/runs/{runId}/events']! as Map<String, Object?>)['get']!
            as Map<String, Object?>;
    final eventParameters = eventOperation['parameters']! as List<Object?>;
    expect(
      eventParameters.whereType<Map<String, Object?>>().map(
        (parameter) => parameter['name'],
      ),
      containsAll(<String>['afterSequence', 'Last-Event-ID']),
    );
    final eventResponse =
        (eventOperation['responses']! as Map<String, Object?>)['200']!
            as Map<String, Object?>;
    expect(eventResponse['content'], contains('text/event-stream'));

    final operationSchemaOperation =
        (paths['/api/v2/operations/schema']! as Map<String, Object?>)['get']!
            as Map<String, Object?>;
    final operationSchemaResponse =
        (operationSchemaOperation['responses']! as Map<String, Object?>)['200']!
            as Map<String, Object?>;
    final operationSchemaContent =
        operationSchemaResponse['content']! as Map<String, Object?>;
    expect(operationSchemaContent, contains('application/schema+json'));
    final operationSchema =
        (operationSchemaContent['application/schema+json']!
                as Map<String, Object?>)['schema']!
            as Map<String, Object?>;
    expect(
      ((operationSchema['properties']! as Map<String, Object?>)[r'$schema']!
          as Map<String, Object?>)['const'],
      'https://json-schema.org/draft/2020-12/schema',
    );

    final artifactOperation =
        (paths['/api/v2/runs/{runId}/artifacts/{artifactId}']!
                as Map<String, Object?>)['get']!
            as Map<String, Object?>;
    final artifactResponse =
        (artifactOperation['responses']! as Map<String, Object?>)['200']!
            as Map<String, Object?>;
    expect(artifactResponse['headers'], contains('Digest'));
  });
}

void _expectDefinition(
  JsonSchema schema,
  String definition,
  Object? instance, {
  required bool isValid,
}) {
  final definitionSchema = schema.resolvePath(
    Uri.parse('#/\$defs/$definition'),
  );
  final result = definitionSchema.validate(instance);
  expect(result.isValid, isValid, reason: '$definition: ${result.errors}');
}

Directory _packageRoot() {
  final current = Directory.current;
  if (File(
    p.join(current.path, 'schema', 'cockpit.foundation.v2.schema.json'),
  ).existsSync()) {
    return current;
  }
  final package = Directory(
    p.join(current.path, 'packages', 'cockpit_protocol'),
  );
  if (File(
    p.join(package.path, 'schema', 'cockpit.foundation.v2.schema.json'),
  ).existsSync()) {
    return package;
  }
  throw StateError('Cannot locate cockpit_protocol.');
}

String _hash(String character) => List<String>.filled(64, character).join();

Map<String, Object?> _jsonObjectWithContainerDepth(int depth) {
  Object? value = <Object?>[];
  for (var currentDepth = 1; currentDepth < depth; currentDepth += 1) {
    value = <Object?>[value];
  }
  return <String, Object?>{'value': value};
}

Iterable<Map<String, Object?>> _allMaps(Object? value) sync* {
  if (value is Map<String, Object?>) {
    yield value;
    for (final child in value.values) {
      yield* _allMaps(child);
    }
  } else if (value is List<Object?>) {
    for (final child in value) {
      yield* _allMaps(child);
    }
  }
}

Object? _resolveInternalReference(Object? document, String reference) {
  final pointer = Uri.decodeComponent(reference.substring(1));
  if (!pointer.startsWith('/')) {
    throw FormatException('Expected an absolute JSON Pointer: $reference');
  }

  Object? current = document;
  for (final encodedToken in pointer.substring(1).split('/')) {
    final token = encodedToken.replaceAll('~1', '/').replaceAll('~0', '~');
    if (current is Map<String, Object?>) {
      if (!current.containsKey(token)) {
        throw FormatException('Missing JSON Pointer token: $token');
      }
      current = current[token];
      continue;
    }
    if (current is List<Object?>) {
      final index = int.tryParse(token);
      if (index == null || index < 0 || index >= current.length) {
        throw FormatException('Invalid JSON Pointer index: $token');
      }
      current = current[index];
      continue;
    }
    throw FormatException('JSON Pointer traverses a scalar at: $token');
  }
  return current;
}
