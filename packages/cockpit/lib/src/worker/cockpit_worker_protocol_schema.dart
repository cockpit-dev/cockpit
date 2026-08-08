import 'package:json_schema/json_schema.dart';

import 'cockpit_worker_value_reader.dart';

final class CockpitWorkerProtocolSchema {
  CockpitWorkerProtocolSchema._();

  static final Map<String, Map<String, Object?>> requestSchemas =
      Map<String, Map<String, Object?>>.unmodifiable(
        <String, Map<String, Object?>>{
          'initialize': _requestSchema(<String, Object?>{
            'engineVersion': _idSchema,
            'workspaceRoot': _stringSchema(32768),
            'supportedFeatures': _uniqueArray(_idSchema, 256),
          }),
          'capabilities': _requestSchema(const <String, Object?>{}),
          'operation': _requestSchema(<String, Object?>{
            'invocation': _objectSchema,
          }),
          'cancel': _requestSchema(<String, Object?>{
            'targetRequestId': _idSchema,
          }),
          'drain': _requestSchema(<String, Object?>{
            'cancellationGraceMs': _integerSchema(0, 300000),
          }),
          'health': _requestSchema(const <String, Object?>{}),
          'shutdown': _requestSchema(<String, Object?>{
            'force': const <String, Object?>{'type': 'boolean'},
          }),
          'replayEvents': _requestSchema(<String, Object?>{
            'runId': _idSchema,
            'afterSequence': _integerSchema(0, 2147483647),
          }),
          'publishEventBatch': _requestSchema(<String, Object?>{
            'runId': _idSchema,
            'afterSequence': _integerSchema(0, 2147483647),
            'events': _array(_objectSchema, 1, 256),
          }),
          'publishArtifactBatch': _artifactPublicationRequestSchema(),
          'readSessionArtifact': _requestSchema(<String, Object?>{
            'sessionId': _idSchema,
            'artifactId': _idSchema,
          }),
        },
      );

  static final Map<String, Map<String, Object?>> resultSchemas =
      Map<String, Map<String, Object?>>.unmodifiable(
        <String, Map<String, Object?>>{
          'initialize': _strictObject(<String, Object?>{
            'protocolVersion': const <String, Object?>{
              'const': cockpitWorkerProtocolVersion,
            },
            'workspaceId': _idSchema,
            'engineVersion': _idSchema,
            'negotiatedFeatures': _uniqueArray(_idSchema, 256),
          }),
          'capabilities': _strictObject(<String, Object?>{
            'workspaceId': _idSchema,
            'operationKinds': _uniqueArray(_kindSchema, 256),
            'resourceKinds': _uniqueArray(_kindSchema, 256),
            'features': _uniqueArray(_idSchema, 256),
          }),
          'operation': _strictObject(<String, Object?>{
            'operation': _objectSchema,
          }),
          'cancel': _strictObject(<String, Object?>{
            'targetRequestId': _idSchema,
            'cancelled': const <String, Object?>{'type': 'boolean'},
            'alreadyTerminal': const <String, Object?>{'type': 'boolean'},
          }),
          'drain': _strictObject(<String, Object?>{
            'draining': const <String, Object?>{'const': true},
            'activeRequestCount': _integerSchema(0, 10000),
          }),
          'health': _strictObject(<String, Object?>{
            'workspaceId': _idSchema,
            'healthy': const <String, Object?>{'type': 'boolean'},
            'draining': const <String, Object?>{'type': 'boolean'},
            'activeRequestCount': _integerSchema(0, 10000),
            'checkedAt': _dateTimeSchema,
          }),
          'shutdown': _strictObject(<String, Object?>{
            'accepted': const <String, Object?>{'type': 'boolean'},
          }),
          'replayEvents': _strictObject(<String, Object?>{
            'runId': _idSchema,
            'afterSequence': _integerSchema(0, 2147483647),
            'events': _array(_objectSchema, 0, 256),
          }),
          'publishEventBatch': _strictObject(
            <String, Object?>{
              'runId': _idSchema,
              'highestContiguousSequence': _integerSchema(0, 2147483647),
              'terminal': const <String, Object?>{'type': 'boolean'},
              'replayAfterSequence': _integerSchema(0, 2147483647),
            },
            required: const <String>{
              'runId',
              'highestContiguousSequence',
              'terminal',
            },
          ),
          'publishArtifactBatch': _strictObject(<String, Object?>{
            'runId': _idSchema,
            'artifactIds': _uniqueArray(_idSchema, 256),
          }),
          'readSessionArtifact': _strictObject(<String, Object?>{
            'sessionId': _idSchema,
            'artifactId': _idSchema,
            'kind': _idSchema,
            'name': _stringSchema(512),
            'mediaType': _stringSchema(128),
            'retainedPath': _stringSchema(32768),
            'sizeBytes': _integerSchema(1, 17179869184),
            'sha256': const <String, Object?>{
              'type': 'string',
              'pattern': r'^[a-f0-9]{64}$',
            },
          }),
        },
      );

  static final Map<String, JsonSchema> _compiledRequests = requestSchemas.map(
    (method, schema) => MapEntry(method, JsonSchema.create(schema)),
  );
  static final Map<String, JsonSchema> _compiledResults = resultSchemas.map(
    (method, schema) => MapEntry(method, JsonSchema.create(schema)),
  );

  static void validateRequest(String method, Object? value) {
    _validate(_compiledRequests, method, value, 'request');
  }

  static void validateResult(String method, Object? value) {
    _validate(_compiledResults, method, value, 'result');
  }

  static void _validate(
    Map<String, JsonSchema> schemas,
    String method,
    Object? value,
    String label,
  ) {
    workerMethod(method, r'$.method');
    final errors = schemas[method]!.validate(value).errors;
    if (errors.isNotEmpty) {
      throw FormatException(
        'Worker $method $label does not match its private schema.',
      );
    }
  }
}

const Map<String, Object?> _idSchema = <String, Object?>{
  'type': 'string',
  'pattern': r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',
};
const Map<String, Object?> _kindSchema = <String, Object?>{
  'type': 'string',
  'pattern': r'^[a-z][a-z0-9]*(?:\.[a-z][a-zA-Z0-9]*)+$',
};
const Map<String, Object?> _dateTimeSchema = <String, Object?>{
  'type': 'string',
  'format': 'date-time',
  'pattern': r'Z$',
};
const Map<String, Object?> _objectSchema = <String, Object?>{'type': 'object'};

Map<String, Object?> _requestSchema(
  Map<String, Object?> methodProperties, {
  Set<String> optional = const <String>{},
}) => _strictObject(
  <String, Object?>{
    'protocolVersion': const <String, Object?>{
      'const': cockpitWorkerProtocolVersion,
    },
    'workspaceId': _idSchema,
    'requestId': _idSchema,
    'deadline': _dateTimeSchema,
    'idempotencyKey': _idSchema,
    ...methodProperties,
  },
  required: <String>{
    'protocolVersion',
    'workspaceId',
    'requestId',
    'deadline',
    'idempotencyKey',
    ...methodProperties.keys.where((key) => !optional.contains(key)),
  },
);

Map<String, Object?> _strictObject(
  Map<String, Object?> properties, {
  Set<String>? required,
}) => <String, Object?>{
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'additionalProperties': false,
  'properties': properties,
  'required': (required ?? properties.keys.toSet()).toList(),
};

Map<String, Object?> _artifactPublicationRequestSchema() {
  final schema = _requestSchema(
    <String, Object?>{
      'projectId': _idSchema,
      'runId': _idSchema,
      'caseId': _idSchema,
      'artifacts': _array(_objectSchema, 1, 256),
    },
    optional: const <String>{'caseId'},
  );
  return <String, Object?>{
    ...schema,
    'allOf': <Object?>[
      <String, Object?>{
        'if': <String, Object?>{
          'required': <String>['caseId'],
        },
        'then': <String, Object?>{
          'properties': <String, Object?>{
            'artifacts': <String, Object?>{
              'items': <String, Object?>{
                'type': 'object',
                'required': <String>['attemptId'],
              },
            },
          },
        },
        'else': <String, Object?>{
          'properties': <String, Object?>{
            'artifacts': <String, Object?>{
              'items': <String, Object?>{
                'type': 'object',
                'not': <String, Object?>{
                  'required': <String>['attemptId'],
                },
              },
            },
          },
        },
      },
    ],
  };
}

Map<String, Object?> _stringSchema(int maximum) => <String, Object?>{
  'type': 'string',
  'minLength': 1,
  'maxLength': maximum,
};

Map<String, Object?> _integerSchema(int minimum, int maximum) =>
    <String, Object?>{
      'type': 'integer',
      'minimum': minimum,
      'maximum': maximum,
    };

Map<String, Object?> _array(
  Map<String, Object?> itemSchema,
  int minimum,
  int maximum,
) => <String, Object?>{
  'type': 'array',
  'items': itemSchema,
  'minItems': minimum,
  'maxItems': maximum,
};

Map<String, Object?> _uniqueArray(
  Map<String, Object?> itemSchema,
  int maximum,
) => <String, Object?>{..._array(itemSchema, 0, maximum), 'uniqueItems': true};
