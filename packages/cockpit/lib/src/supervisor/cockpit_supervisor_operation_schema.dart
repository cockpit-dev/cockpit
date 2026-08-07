import 'cockpit_supervisor_operation_catalog.dart';

final class CockpitSupervisorOperationSchema {
  CockpitSupervisorOperationSchema._();

  static Map<String, Object?> document() {
    final definitions = <String, Object?>{};
    for (final descriptor in CockpitSupervisorOperationCatalog.allOperations) {
      definitions['${descriptor.kind}.request'] =
          _requestSchemas[descriptor.kind] ?? _genericRequest(descriptor.kind);
      definitions['${descriptor.kind}.response'] = _genericResponse(
        descriptor.kind,
      );
    }
    return <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      r'$id': 'cockpit://operations/schema',
      'title': 'Cockpit live operation contracts',
      r'$defs': definitions,
    };
  }
}

Map<String, Object?> _object({
  Map<String, Object?> properties = const <String, Object?>{},
  List<String> required = const <String>[],
  String precision = 'exact',
  String? description,
}) => <String, Object?>{
  'type': 'object',
  'properties': properties,
  if (required.isNotEmpty) 'required': required,
  'additionalProperties': false,
  'x-cockpit-precision': precision,
  'description': ?description,
};

Map<String, Object?> _genericRequest(String kind) => <String, Object?>{
  'type': 'object',
  'additionalProperties': true,
  'x-cockpit-precision': 'generic',
  'description':
      'The live runtime advertises $kind, but its field-level request schema '
      'is not yet published. Prefer a task-oriented command.',
};

Map<String, Object?> _genericResponse(String kind) => <String, Object?>{
  'type': 'object',
  'additionalProperties': true,
  'x-cockpit-precision': 'generic',
  'description': 'Successful $kind operation output.',
};

const Map<String, Object?> _id = <String, Object?>{
  'type': 'string',
  'pattern': r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',
};
const Map<String, Object?> _networkRequestId = <String, Object?>{
  'type': 'string',
  'pattern': r'^[1-9][0-9]{0,18}$',
};
const Map<String, Object?> _positiveTimeout = <String, Object?>{
  'type': 'integer',
  'minimum': 1,
  'maximum': 1800000,
};
const Map<String, Object?> _profile = <String, Object?>{
  'type': 'string',
  'enum': <String>['minimal', 'locate', 'standard', 'inspect', 'evidence'],
};
const Map<String, Object?> _sessionId = <String, Object?>{
  ..._id,
  'description': 'Injected automatically by --session for Cockpit CLI calls.',
  'x-cockpit-injected-by': '--session',
};
const Map<String, Object?> _launchConfiguration = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'dartDefines': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string', 'minLength': 3},
    },
    'dartDefineFromFiles': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string', 'minLength': 1},
    },
    'flutterArgs': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string', 'minLength': 1},
    },
    'environment': <String, Object?>{
      'type': 'object',
      'additionalProperties': <String, Object?>{'type': 'string'},
    },
  },
  'additionalProperties': false,
};

final Map<String, Map<String, Object?>> _requestSchemas =
    <String, Map<String, Object?>>{
      for (final kind in <String>['app.list', 'target.list']) kind: _object(),
      for (final kind in <String>[
        'app.reload',
        'app.restart',
        'session.development.get',
        'session.development.stop',
      ])
        kind: _object(
          properties: const <String, Object?>{'sessionId': _sessionId},
          required: const <String>['sessionId'],
        ),
      'target.inspect': _object(
        properties: const <String, Object?>{
          'targetId': _id,
          'profile': _profile,
          'snapshotOptions': <String, Object?>{'type': 'object'},
        },
        required: const <String>['targetId'],
      ),
      for (final kind in <String>['ui.inspect', 'surface.inspect'])
        kind: _object(
          properties: const <String, Object?>{
            'sessionId': _sessionId,
            'profile': _profile,
            'snapshotOptions': <String, Object?>{'type': 'object'},
            'compareAgainstSnapshotRef': _id,
          },
          required: const <String>['sessionId'],
        ),
      'logs.read': _sessionReadSchema(<String, Object?>{
        'maxLines': const <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 10000,
        },
      }),
      'errors.read': _sessionReadSchema(<String, Object?>{
        'maxErrors': const <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 10000,
        },
      }),
      'network.read': _sessionReadSchema(<String, Object?>{
        'id': _networkRequestId,
        'before': _networkRequestId,
        'includeEntries': const <String, Object?>{'type': 'boolean'},
        'onlyFailures': const <String, Object?>{'type': 'boolean'},
        'method': const <String, Object?>{
          'type': 'string',
          'minLength': 1,
          'maxLength': 32,
        },
        'uriContains': const <String, Object?>{
          'type': 'string',
          'minLength': 1,
          'maxLength': 512,
        },
        'statusCodeAtLeast': const <String, Object?>{
          'type': 'integer',
          'minimum': 100,
          'maximum': 599,
        },
        'maxEntries': const <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 1000,
        },
        'maxEndpointSummaries': const <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 1000,
        },
      }),
      'network.body': _object(
        properties: const <String, Object?>{
          'sessionId': _sessionId,
          'requestId': _networkRequestId,
          'body': <String, Object?>{
            'type': 'string',
            'enum': <String>['request', 'response', 'both'],
          },
          'raw': <String, Object?>{'type': 'boolean', 'default': false},
        },
        required: const <String>['sessionId', 'requestId', 'body'],
      ),
      for (final kind in <String>['ui.waitIdle', 'ui.remote.waitIdle'])
        kind: _object(
          properties: const <String, Object?>{
            'sessionId': _sessionId,
            'quietWindowMs': <String, Object?>{
              'type': 'integer',
              'minimum': 50,
              'maximum': 60000,
              'default': 500,
            },
            'timeoutMs': <String, Object?>{
              'type': 'integer',
              'minimum': 1,
              'maximum': 300000,
              'default': 30000,
            },
            'includeNetworkIdle': <String, Object?>{
              'type': 'boolean',
              'default': false,
            },
          },
          required: const <String>['sessionId'],
        ),
      'viewport.set': _object(
        properties: const <String, Object?>{
          'sessionId': _sessionId,
          'width': <String, Object?>{
            'type': 'integer',
            'minimum': 200,
            'maximum': 8192,
            'examples': <int>[800],
          },
          'height': <String, Object?>{
            'type': 'integer',
            'minimum': 200,
            'maximum': 8192,
            'examples': <int>[600],
          },
        },
        required: const <String>['sessionId', 'width', 'height'],
      ),
      'evidence.screenshot.capture': _object(
        properties: const <String, Object?>{
          'sessionId': _sessionId,
          'name': <String, Object?>{
            'type': 'string',
            'minLength': 1,
            'maxLength': 128,
          },
        },
        required: const <String>['sessionId'],
      ),
      'command.run': _object(
        properties: const <String, Object?>{
          'sessionId': _sessionId,
          'command': <String, Object?>{'type': 'object'},
          'profile': _profile,
        },
        required: const <String>['sessionId', 'command'],
        precision: 'structural',
      ),
      for (final kind in <String>[
        'app.launch',
        'target.launch',
        'session.development.launch',
        'session.remote.launch',
      ])
        kind: _object(
          properties: const <String, Object?>{
            'targetId': _id,
            'mode': <String, Object?>{
              'type': 'string',
              'enum': <String>['development', 'automation'],
            },
            'launchTimeoutMs': _positiveTimeout,
            'launchConfiguration': _launchConfiguration,
          },
          required: const <String>['targetId'],
        ),
    };

Map<String, Object?> _sessionReadSchema(Map<String, Object?> extraProperties) =>
    _object(
      properties: <String, Object?>{
        'sessionId': _sessionId,
        ...extraProperties,
      },
      required: const <String>['sessionId'],
    );
