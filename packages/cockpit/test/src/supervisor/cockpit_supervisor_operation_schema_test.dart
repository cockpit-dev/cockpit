import 'dart:convert';

import 'package:cockpit/src/supervisor/cockpit_supervisor_operation_catalog.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_operation_schema.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_runtime.dart';
import 'package:cockpit/src/system_control/cockpit_system_control_profile.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

void main() {
  test('every advertised HTTP resource is documented in OpenAPI', () {
    final openApi = jsonDecode(cockpitV2OpenApiJson) as Map<String, Object?>;
    final paths = openApi['paths']! as Map<String, Object?>;

    for (final resource in cockpitSupervisorResourceDescriptors) {
      expect(paths, contains(resource.uriTemplate), reason: resource.kind);
      final path = paths[resource.uriTemplate]! as Map<String, Object?>;
      final operations = path.entries.where(
        (entry) => const <String>{'get', 'post', 'delete'}.contains(entry.key),
      );
      final exposesMediaType = operations.any((entry) {
        final operation = entry.value! as Map<String, Object?>;
        final responses = operation['responses']! as Map<String, Object?>;
        return responses.values.whereType<Map<String, Object?>>().any((value) {
          final content = value['content'];
          return content is Map<String, Object?> &&
              content.containsKey(resource.mediaType);
        });
      });
      expect(exposesMediaType, isTrue, reason: resource.kind);
    }
  });

  test('every operation exposes concise discovery help', () {
    for (final descriptor in CockpitSupervisorOperationCatalog.allOperations) {
      expect(descriptor.title, isNot(descriptor.kind), reason: descriptor.kind);
      expect(descriptor.title.length, lessThanOrEqualTo(64));
      expect(descriptor.description, isNotEmpty, reason: descriptor.kind);
      expect(
        descriptor.description,
        isNot('Cockpit ${descriptor.kind} operation.'),
        reason: descriptor.kind,
      );
    }
  });

  test('every advertised operation schema reference resolves', () {
    final document = CockpitSupervisorOperationSchema.document();
    final definitions = Map<String, Object?>.from(
      document[r'$defs']! as Map<Object?, Object?>,
    );

    for (final descriptor in CockpitSupervisorOperationCatalog.allOperations) {
      final request = Map<String, Object?>.from(
        definitions['${descriptor.kind}.request']! as Map<Object?, Object?>,
      );
      final response = Map<String, Object?>.from(
        definitions['${descriptor.kind}.response']! as Map<Object?, Object?>,
      );
      expect(
        definitions,
        contains('${descriptor.kind}.request'),
        reason: descriptor.requestSchemaRef,
      );
      expect(
        definitions,
        contains('${descriptor.kind}.response'),
        reason: descriptor.responseSchemaRef,
      );
      expect(request['x-cockpit-precision'], isNot('generic'));
      expect(response['x-cockpit-precision'], isNot('generic'));
      expect(() => JsonSchema.create(request), returnsNormally);
      expect(() => JsonSchema.create(response), returnsNormally);
      for (final example
          in (request['examples'] as List<Object?>?) ?? const <Object?>[]) {
        expect(
          JsonSchema.create(request).validate(example).isValid,
          isTrue,
          reason: '${descriptor.kind} request example: $example',
        );
      }
    }
  });

  test('lease listing schema keeps every response page bounded', () {
    final definitions = Map<String, Object?>.from(
      CockpitSupervisorOperationSchema.document()[r'$defs']!
          as Map<Object?, Object?>,
    );
    final request = Map<String, Object?>.from(
      definitions['lease.list.request']! as Map<Object?, Object?>,
    );
    final response = Map<String, Object?>.from(
      definitions['lease.list.response']! as Map<Object?, Object?>,
    );
    final properties = Map<String, Object?>.from(
      request['properties']! as Map<Object?, Object?>,
    );
    final state = Map<String, Object?>.from(
      properties['state']! as Map<Object?, Object?>,
    );
    final limit = Map<String, Object?>.from(
      properties['limit']! as Map<Object?, Object?>,
    );

    expect(
      (state['enum']! as List<Object?>).cast<String>(),
      CockpitLeaseState.values.map((value) => value.name),
    );
    expect(limit['default'], 50);
    expect(limit['maximum'], 200);
    expect(
      JsonSchema.create(request).validate(<String, Object?>{}).isValid,
      isTrue,
    );
    expect(
      JsonSchema.create(request).validate(<String, Object?>{
        'state': 'queued',
        'limit': 200,
        'before': 'lease-1',
      }).isValid,
      isTrue,
    );
    expect(
      JsonSchema.create(
        request,
      ).validate(<String, Object?>{'limit': 201}).isValid,
      isFalse,
    );
    expect(
      JsonSchema.create(response).validate(<String, Object?>{
        'items': <Object?>[
          for (var index = 0; index < 200; index += 1) <String, Object?>{},
        ],
        'total': 3113,
        'next': 'lease-200',
      }).isValid,
      isTrue,
    );
    expect(
      JsonSchema.create(response).validate(<String, Object?>{
        'items': <Object?>[
          for (var index = 0; index < 201; index += 1) <String, Object?>{},
        ],
        'total': 3113,
      }).isValid,
      isFalse,
    );
  });

  test('snapshot options schema matches the public protocol model', () {
    final definitions = Map<String, Object?>.from(
      CockpitSupervisorOperationSchema.document()[r'$defs']!
          as Map<Object?, Object?>,
    );
    final schema = JsonSchema.create(
      Map<String, Object?>.from(
        definitions['snapshot.remote.collect.request']!
            as Map<Object?, Object?>,
      ),
    );
    final options = const CockpitSnapshotOptions.forensic().copyWith(
      networkQuery: const CockpitNetworkQuery(
        id: '37',
        before: '36',
        method: 'POST',
        uriContains: '/sync',
        onlyFailures: true,
        statusCodeAtLeast: 500,
      ),
      runtimeQuery: const CockpitRuntimeQuery(
        onlyErrors: true,
        messageContains: 'RenderFlex',
      ),
    );

    expect(
      schema.validate(<String, Object?>{
        'sessionId': 'session-1',
        'snapshotOptions': options.toJson(),
      }).isValid,
      isTrue,
    );
    expect(
      schema.validate(<String, Object?>{
        'sessionId': 'session-1',
        'snapshotOptions': const <String, Object?>{'includeSemantics': true},
      }).isValid,
      isFalse,
    );
  });

  test('recording schema matches the public protocol model', () {
    final definitions = Map<String, Object?>.from(
      CockpitSupervisorOperationSchema.document()[r'$defs']!
          as Map<Object?, Object?>,
    );
    final schema = JsonSchema.create(
      Map<String, Object?>.from(
        definitions['recording.start.request']! as Map<Object?, Object?>,
      ),
    );
    final request = CockpitRecordingRequest(
      purpose: CockpitRecordingPurpose.acceptance,
      name: 'release-proof',
      mode: CockpitRecordingMode.full,
      layer: CockpitRecordingLayer.system,
      allowFallback: false,
      attachToStep: true,
      tailStabilizationDelay: const Duration(milliseconds: 1600),
    );

    expect(
      schema.validate(<String, Object?>{
        'sessionId': 'session-1',
        'recording': request.toJson(),
      }).isValid,
      isTrue,
    );
    expect(
      schema.validate(<String, Object?>{
        'sessionId': 'session-1',
        'recording': <String, Object?>{...request.toJson(), 'mode': 'maximum'},
      }).isValid,
      isFalse,
    );
  });

  test('system actions select exactly one target identity', () {
    final definitions = Map<String, Object?>.from(
      CockpitSupervisorOperationSchema.document()[r'$defs']!
          as Map<Object?, Object?>,
    );
    final schema = JsonSchema.create(
      Map<String, Object?>.from(
        definitions['system.action.request']! as Map<Object?, Object?>,
      ),
    );

    expect(
      schema.validate(<String, Object?>{
        'sessionId': 'session-1',
        'action': 'dismissSystemDialog',
      }).isValid,
      isTrue,
    );
    expect(
      schema.validate(<String, Object?>{
        'targetId': 'target-1',
        'action': 'dismissSystemDialog',
      }).isValid,
      isTrue,
    );
    expect(
      schema.validate(<String, Object?>{
        'sessionId': 'session-1',
        'targetId': 'target-1',
        'action': 'dismissSystemDialog',
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate(<String, Object?>{
        'action': 'dismissSystemDialog',
      }).isValid,
      isFalse,
    );
    final actionSchema =
        (Map<String, Object?>.from(
                  definitions['system.action.request']!
                      as Map<Object?, Object?>,
                )['properties']!
                as Map<String, Object?>)['action']!
            as Map<String, Object?>;
    expect(
      (actionSchema['enum']! as List<Object?>).cast<String>(),
      CockpitSystemControlAction.values
          .map((action) => action.name)
          .toList(growable: false),
    );
  });

  test('target registration schema matches worker admission', () {
    final definitions = Map<String, Object?>.from(
      CockpitSupervisorOperationSchema.document()[r'$defs']!
          as Map<Object?, Object?>,
    );
    final schema = JsonSchema.create(
      Map<String, Object?>.from(
        definitions['target.register.request']! as Map<Object?, Object?>,
      ),
    );
    final valid = <String, Object?>{
      'platform': 'ios',
      'deviceId': 'simulator-1',
      'targetKind': 'nativeApp',
      'appId': 'com.example.app',
      'wdaUrl': 'http://127.0.0.1:8100',
    };

    expect(schema.validate(valid).isValid, isTrue);
    expect(
      schema.validate(<String, Object?>{...valid}..remove('appId')).isValid,
      isFalse,
    );
    expect(
      schema.validate(<String, Object?>{
        ...valid,
        'platform': 'p' * 33,
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate(<String, Object?>{...valid, 'appId': '   '}).isValid,
      isFalse,
    );
    expect(
      schema.validate(<String, Object?>{
        ...valid,
        'wdaUrl': 'ftp://127.0.0.1:8100',
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate(<String, Object?>{
        'platform': 'web',
        'deviceId': 'chrome',
        'targetKind': 'browserPage',
        'appId': 'Google Chrome',
        'cdpUrl': 'ws://127.0.0.1:9222/devtools/page/1',
      }).isValid,
      isTrue,
    );
    expect(
      schema.validate(<String, Object?>{
        'platform': 'web',
        'deviceId': 'chrome',
        'targetKind': 'browserPage',
        'appId': 'Google Chrome',
        'cdpUrl': 'ftp://127.0.0.1/page/1',
      }).isValid,
      isFalse,
    );
  });

  test('run operation schema keeps envelope identities out of input', () {
    final definitions = Map<String, Object?>.from(
      CockpitSupervisorOperationSchema.document()[r'$defs']!
          as Map<Object?, Object?>,
    );
    for (final kind in <String>['case.run', 'suite.run']) {
      final schema = JsonSchema.create(
        Map<String, Object?>.from(
          definitions['$kind.request']! as Map<Object?, Object?>,
        ),
      );
      final documentField = kind == 'case.run' ? 'caseId' : 'suiteId';
      final valid = <String, Object?>{
        'source': <String, Object?>{
          'kind': 'indexed',
          'reference': <String, Object?>{
            'documentId': 'document-1',
            documentField: 'authored-1',
            'documentSha256': '0' * 64,
          },
        },
        'inputs': <String, Object?>{},
      };
      expect(schema.validate(valid).isValid, isTrue, reason: kind);
      expect(
        schema.validate(<String, Object?>{
          ...valid,
          'workspaceId': 'workspace-1',
        }).isValid,
        isFalse,
        reason: kind,
      );
      expect(
        schema.validate(<String, Object?>{
          ...valid,
          'idempotencyKey': 'duplicate-envelope-value',
        }).isValid,
        isFalse,
        reason: kind,
      );
    }
  });

  test('Flutter viewport schema exposes and enforces exact bounds', () {
    final document = CockpitSupervisorOperationSchema.document();
    final definitions = Map<String, Object?>.from(
      document[r'$defs']! as Map<Object?, Object?>,
    );
    final schema = Map<String, Object?>.from(
      definitions['viewport.set.request']! as Map<Object?, Object?>,
    );
    final compiled = JsonSchema.create(schema);

    expect(schema['x-cockpit-precision'], 'exact');
    expect(
      compiled.validate(<String, Object?>{
        'sessionId': 'session-1',
        'width': 800,
        'height': 600,
      }).isValid,
      isTrue,
    );
    expect(
      compiled.validate(<String, Object?>{
        'sessionId': 'session-1',
        'width': 199,
        'height': 600,
      }).isValid,
      isFalse,
    );
    expect(
      compiled.validate(<String, Object?>{
        'sessionId': 'session-1',
        'width': 800,
        'height': 600,
        'guessedField': true,
      }).isValid,
      isFalse,
    );
  });

  test('network schemas accept numeric IDs and every bounded query field', () {
    final definitions = Map<String, Object?>.from(
      CockpitSupervisorOperationSchema.document()[r'$defs']!
          as Map<Object?, Object?>,
    );
    final read = JsonSchema.create(
      Map<String, Object?>.from(
        definitions['network.read.request']! as Map<Object?, Object?>,
      ),
    );
    final body = JsonSchema.create(
      Map<String, Object?>.from(
        definitions['network.body.request']! as Map<Object?, Object?>,
      ),
    );

    expect(
      read.validate(<String, Object?>{
        'sessionId': 'session-1',
        'id': '37',
        'includeEntries': true,
        'maxEntries': 12,
        'maxEndpointSummaries': 8,
      }).isValid,
      isTrue,
    );
    expect(
      body.validate(<String, Object?>{
        'sessionId': 'session-1',
        'requestId': '37',
        'body': 'both',
        'raw': false,
      }).isValid,
      isTrue,
    );
    expect(
      read.validate(<String, Object?>{
        'sessionId': 'session-1',
        'id': 'request-37',
      }).isValid,
      isFalse,
    );
  });

  test('wait idle schema matches the task command timeout contract', () {
    final definitions = Map<String, Object?>.from(
      CockpitSupervisorOperationSchema.document()[r'$defs']!
          as Map<Object?, Object?>,
    );
    for (final kind in <String>['ui.waitIdle', 'ui.remote.waitIdle']) {
      final descriptor = CockpitSupervisorOperationCatalog.allOperations
          .singleWhere((item) => item.kind == kind);
      final schema = Map<String, Object?>.from(
        definitions['$kind.request']! as Map<Object?, Object?>,
      );
      final properties = Map<String, Object?>.from(
        schema['properties']! as Map<Object?, Object?>,
      );
      final timeout = Map<String, Object?>.from(
        properties['timeoutMs']! as Map<Object?, Object?>,
      );
      final quiet = Map<String, Object?>.from(
        properties['quietWindowMs']! as Map<Object?, Object?>,
      );

      expect(descriptor.defaultTimeoutMs, 30000, reason: kind);
      expect(descriptor.maximumTimeoutMs, 300000, reason: kind);
      expect(timeout['default'], 30000, reason: kind);
      expect(timeout['maximum'], 300000, reason: kind);
      expect(quiet['default'], 500, reason: kind);
      expect(quiet['minimum'], 50, reason: kind);
      expect(quiet['maximum'], 60000, reason: kind);
      expect(
        JsonSchema.create(schema).validate(<String, Object?>{
          'sessionId': 'session-1',
          'quietWindowMs': 60000,
          'timeoutMs': 120000,
          'includeNetworkIdle': false,
        }).isValid,
        isTrue,
        reason: kind,
      );
      expect(
        JsonSchema.create(schema).validate(<String, Object?>{
          'sessionId': 'session-1',
          'timeoutMs': 300001,
        }).isValid,
        isFalse,
        reason: kind,
      );
    }
  });
}
