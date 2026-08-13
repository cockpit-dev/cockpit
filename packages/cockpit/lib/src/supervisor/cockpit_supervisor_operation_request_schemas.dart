part of 'cockpit_supervisor_operation_schema.dart';

final Map<String, Object?> _networkQuery = _object(
  properties: <String, Object?>{
    'id': _networkRequestId,
    'before': _networkRequestId,
    'method': _nonBlankBoundedString(32),
    'uriContains': _nonBlankBoundedString(512),
    'onlyFailures': _boolean,
    'statusCodeAtLeast': _boundedInteger(100, 599),
  },
);

final Map<String, Object?> _runtimeQuery = _object(
  properties: <String, Object?>{
    'onlyErrors': _boolean,
    'messageContains': _nonBlankBoundedString(1024),
  },
);

final Map<String, Object?> _widgetTreeOptions = _object(
  properties: <String, Object?>{
    'profile': _enum(<String>['minimal', 'standard', 'full']),
    'maxNodes': _boundedInteger(1, 500000, value: 800),
    'maxProps': _boundedInteger(0, 256, value: 0),
  },
);

final Map<String, Object?> _snapshotOptions = _object(
  properties: <String, Object?>{
    'profile': _enum(<String>[
      'live',
      'baseline',
      'investigate',
      'forensic',
    ], defaultValue: 'live'),
    'query': _nonBlankBoundedString(512),
    'maxTargets': _boundedInteger(0, 100000, value: 25),
    'maxAncestorsPerTarget': _boundedInteger(0, 256, value: 0),
    'maxPropertiesPerTarget': _boundedInteger(0, 100000, value: 0),
    'includeStyleDetails': _boolean,
    'includeDiagnosticProperties': _boolean,
    'artifact': _enum(<String>['inline', 'large', 'always']),
    'includeRebuildActivity': _boolean,
    'maxRebuildEntries': _boundedInteger(0, 10000, value: 8),
    'includeNetworkActivity': _boolean,
    'maxNetworkEntries': _boundedInteger(0, 10000, value: 8),
    'networkQuery': _networkQuery,
    'includeRuntimeActivity': _boolean,
    'maxRuntimeEntries': _boundedInteger(0, 10000, value: 8),
    'runtimeQuery': _runtimeQuery,
    'includeAccessibilitySummary': _boolean,
    'maxAccessibilityEntries': _boundedInteger(0, 10000, value: 8),
    'tree': _widgetTreeOptions,
  },
);

final Map<String, Object?> _recordingRequest = _object(
  properties: <String, Object?>{
    'purpose': _enum(<String>['acceptance', 'repro']),
    'name': _boundedString(128),
    'mode': _enum(<String>['auto', 'cheap', 'native', 'full']),
    'layer': _enum(<String>['flutter', 'app-window', 'host-screen', 'system']),
    'allowFallback': _boolean,
    'attachToStep': _boolean,
    'tailStabilizationMs': _boundedInteger(0, 60000),
  },
  required: const <String>['purpose', 'name'],
);

final Map<String, Object?> _commandBatchItem = _object(
  properties: <String, Object?>{
    'command': _jsonObject,
    'profile': _profile,
    'snapshotOptions': _snapshotOptions,
    'compareAgainstSnapshotRef': _id,
  },
  required: const <String>['command'],
  precision: 'structural',
);

Map<String, Object?> _runSource(String documentKind) {
  final idField = documentKind == 'case' ? 'caseId' : 'suiteId';
  return <String, Object?>{
    'oneOf': <Map<String, Object?>>[
      _object(
        properties: <String, Object?>{
          'kind': <String, Object?>{'const': 'indexed'},
          'reference': _object(
            properties: <String, Object?>{
              'documentId': _id,
              idField: _id,
              'documentSha256': _sha256,
            },
            required: <String>['documentId', idField, 'documentSha256'],
          ),
        },
        required: const <String>['kind', 'reference'],
      ),
      _object(
        properties: <String, Object?>{
          'kind': <String, Object?>{'const': 'inline'},
          documentKind: _jsonObject,
          'sourceSha256': _sha256,
        },
        required: <String>['kind', documentKind, 'sourceSha256'],
        precision: 'structural',
      ),
    ],
  };
}

Map<String, Object?> _runRequest(String documentKind, int maximumTimeoutMs) =>
    _object(
      properties: <String, Object?>{
        'source': _runSource(documentKind),
        'inputs': _jsonObject,
        'targetId': _id,
        'timeoutMs': _boundedInteger(1, maximumTimeoutMs),
      },
      required: const <String>['source'],
      precision: 'structural',
      examples: <Map<String, Object?>>[
        <String, Object?>{
          'source': <String, Object?>{
            'kind': 'indexed',
            'reference': <String, Object?>{
              'documentId': 'doc-example',
              documentKind == 'case' ? 'caseId' : 'suiteId':
                  documentKind == 'case' ? 'exampleCase' : 'exampleSuite',
              'documentSha256': '0' * 64,
            },
          },
        },
      ],
    );

final Map<String, Map<String, Object?>>
_requestSchemas = <String, Map<String, Object?>>{
  'target.discover': _object(
    properties: <String, Object?>{'timeoutMs': _boundedInteger(1, 300000)},
  ),
  'lease.list': _object(
    properties: <String, Object?>{
      'workspaceId': _id,
      'resourceKind': _boundedString(64),
      'resourceId': _boundedString(512),
      'state': _enum(<String>['active', 'released', 'expired', 'quarantined']),
    },
  ),
  'lease.recover': _object(
    properties: <String, Object?>{
      'leaseId': _id,
      'workspaceId': _id,
      'resourceKind': _boundedString(64),
      'resourceId': _boundedString(512),
      'holderId': _id,
      'forceRelease': _boolean,
    },
    required: const <String>[
      'leaseId',
      'workspaceId',
      'resourceKind',
      'resourceId',
      'holderId',
      'forceRelease',
    ],
  ),
  'system.capabilities': _object(
    properties: <String, Object?>{
      'platform': _boundedString(64),
      'deviceId': _boundedString(256),
      'appId': _boundedString(512),
      'processId': _boundedInteger(1, 0x7fffffff),
      'metadata': _jsonObject,
    },
    required: const <String>['platform'],
    precision: 'structural',
  ),
  'system.diagnostics': _object(),
  'project.create': _object(
    properties: <String, Object?>{
      'parentDirectory': _boundedString(32768),
      'projectName': <String, Object?>{
        'type': 'string',
        'pattern': r'^[a-z][a-z0-9_]{0,127}$',
      },
      'template': _enum(<String>['dartCli', 'flutterApp']),
      'organization': _boundedString(256),
      'platforms': _array(_boundedString(64), maximum: 16, unique: true),
      'timeoutMs': _boundedInteger(1, 600000),
    },
    required: const <String>['projectName', 'template'],
  ),
  'package.search': _object(
    properties: <String, Object?>{
      'query': _boundedString(32768),
      'maxResults': _boundedInteger(1, 50),
      'timeoutMs': _boundedInteger(1, 120000),
    },
    required: const <String>['query'],
  ),
  'document.index': _object(
    properties: <String, Object?>{
      'kind': _enum(<String>['source', 'case', 'suite', 'project']),
      'relativePath': _boundedString(32768),
    },
  ),
  'document.list': _object(
    properties: <String, Object?>{
      'kind': _enum(<String>['source', 'case', 'suite', 'project', 'authored']),
      'relativePath': _boundedString(32768),
      'offset': _boundedInteger(0, 10000),
      'limit': _boundedInteger(1, 100),
    },
    required: const <String>['offset', 'limit'],
  ),
  'case.validate': _object(
    properties: <String, Object?>{
      'format': _enum(<String>['lon', 'json', 'yaml']),
      'sourceText': _boundedString(1048576),
      'relativePath': _boundedString(32768),
    },
    required: const <String>['format', 'sourceText'],
  ),
  'case.run': _runRequest('case', 21600000),
  'suite.run': _runRequest('suite', 86400000),
  'analyze.files': _object(
    properties: <String, Object?>{
      'documentIds': _array(_id, maximum: 512, unique: true),
      'maxDiagnostics': _boundedInteger(1, 1000),
      'maxOutputChars': _boundedInteger(100, 20000),
    },
    required: const <String>['documentIds'],
  ),
  'analyze.workspace': _object(),
  'fix.workspace': _object(),
  'format.workspace': _object(
    properties: <String, Object?>{
      'documentIds': _array(_id, maximum: 512, unique: true),
    },
  ),
  'test.workspace': _object(
    properties: <String, Object?>{
      'paths': _array(_boundedString(32768), maximum: 512),
      'name': _boundedString(1024),
    },
  ),
  'package.pub': _object(
    properties: <String, Object?>{
      'command': _enum(<String>[
        'add',
        'deps',
        'get',
        'outdated',
        'remove',
        'upgrade',
      ]),
      'packages': _array(_boundedString(256), maximum: 100),
      'maxOutputChars': _boundedInteger(100, 20000),
    },
    required: const <String>['command', 'packages'],
  ),
  'lsp.request': _object(
    properties: <String, Object?>{
      'command': _enum(<String>[
        'hover',
        'definition',
        'signatureHelp',
        'documentSymbols',
        'workspaceSymbols',
      ]),
      'documentId': _id,
      'line': _integer,
      'column': _integer,
      'query': _boundedString(512),
      'maxResults': _boundedInteger(1, 1000),
      'maxChars': _boundedInteger(100, 20000),
    },
    required: const <String>['command'],
  ),
  'package.uris.read': _object(
    properties: <String, Object?>{
      'uri': _boundedString(4096),
      'maxPreviewChars': _boundedInteger(100, 20000),
      'maxEntries': _boundedInteger(1, 1000),
      'includeFullText': _boolean,
    },
    required: const <String>['uri'],
  ),
  'package.uris.grep': _object(
    properties: <String, Object?>{
      'packageNames': _array(_id, maximum: 100, unique: true),
      'query': _boundedString(1024),
      'useRegex': _boolean,
      'caseSensitive': _boolean,
      'maxMatches': _boundedInteger(1, 1000),
    },
    required: const <String>['packageNames', 'query'],
  ),
  ..._applicationRequestSchemas,
};

final Map<String, Map<String, Object?>> _applicationRequestSchemas =
    <String, Map<String, Object?>>{
      'app.list': _object(),
      'app.get': _object(
        properties: <String, Object?>{
          'appId': _id,
          'profile': _profile,
          'snapshotOptions': _snapshotOptions,
        },
        required: const <String>['appId'],
        precision: 'structural',
      ),
      'target.list': _object(),
      'target.get': _object(
        properties: const <String, Object?>{'targetId': _id},
        required: const <String>['targetId'],
      ),
      'target.inspect': _object(
        properties: <String, Object?>{
          'targetId': _id,
          'profile': _profile,
          'snapshotOptions': _snapshotOptions,
        },
        required: const <String>['targetId'],
        precision: 'structural',
      ),
      'target.register': _object(
        properties: <String, Object?>{
          'platform': _boundedString(32),
          'deviceId': _boundedString(256),
          'entrypointDocumentId': _id,
          'flavor': _boundedString(128),
          'appId': <String, Object?>{..._boundedString(512), 'pattern': r'\S'},
          'wdaUrl': _absoluteHttpUrl,
          'cdpUrl': _absoluteWebSocketOrHttpUrl,
          'targetKind': _enum(<String>[
            'flutterApp',
            'nativeApp',
            'desktopApp',
            'browserPage',
            'systemSurface',
            'device',
            'hostWorkspace',
          ], defaultValue: 'flutterApp'),
          'mode': _enum(<String>[
            'development',
            'automation',
          ], defaultValue: 'development'),
          'environment': _enum(<String>[
            'development',
            'test',
            'staging',
            'production',
            'unknown',
          ], defaultValue: 'unknown'),
        },
        required: const <String>['platform', 'deviceId'],
        precision: 'structural',
        allOf: const <Map<String, Object?>>[
          <String, Object?>{
            'if': <String, Object?>{
              'properties': <String, Object?>{
                'targetKind': <String, Object?>{
                  'enum': <String>['nativeApp', 'desktopApp', 'browserPage'],
                },
              },
            },
            'then': <String, Object?>{
              'required': <String>['appId'],
            },
          },
        ],
      ),
      for (final kind in <String>['app.launch', 'target.launch'])
        kind: _launchRequest(allowMode: true),
      'session.remote.launch': _launchRequest(),
      'session.development.launch': _launchRequest(),
      'app.stop': _object(
        properties: const <String, Object?>{'appId': _id},
        required: const <String>['appId'],
      ),
      'session.remote.get': _sessionRequest(),
      'session.remote.status': _sessionRequest(
        properties: <String, Object?>{
          'profile': _profile,
          'snapshotOptions': _snapshotOptions,
        },
        precision: 'structural',
      ),
      'snapshot.remote.read': _sessionRequest(
        properties: <String, Object?>{
          'profile': _profile,
          'snapshotOptions': _snapshotOptions,
          'compareAgainstSnapshotRef': _id,
        },
        precision: 'structural',
      ),
      'snapshot.remote.collect': _sessionRequest(
        properties: <String, Object?>{
          'snapshotOptions': _snapshotOptions,
          'downloadDiagnosticsArtifacts': _boolean,
        },
        precision: 'structural',
      ),
      for (final kind in <String>['command.remote.execute', 'command.run'])
        kind: _sessionRequest(
          properties: <String, Object?>{
            'command': _jsonObject,
            'timeoutMs': _boundedInteger(1, 300000),
            'profile': _profile,
            'snapshotOptions': _snapshotOptions,
            'compareAgainstSnapshotRef': _id,
          },
          required: const <String>['command'],
          precision: 'structural',
        ),
      for (final kind in <String>['command.remote.batch', 'command.batch'])
        kind: _sessionRequest(
          properties: <String, Object?>{
            'commands': _array(_commandBatchItem, minimum: 1, maximum: 1000),
            'timeoutMs': _boundedInteger(1, 300000),
            'profile': _profile,
            'failFast': <String, Object?>{'type': 'boolean', 'default': true},
            'recording': _recordingRequest,
            'finalSnapshotProfile': _profile,
            'finalSnapshotOptions': _snapshotOptions,
          },
          required: const <String>['commands'],
          precision: 'structural',
        ),
      for (final kind in <String>['ui.remote.waitIdle', 'ui.waitIdle'])
        kind: _sessionRequest(
          properties: <String, Object?>{
            'quietWindowMs': _boundedInteger(50, 60000, value: 500),
            'timeoutMs': _boundedInteger(1, 300000, value: 30000),
            'includeNetworkIdle': <String, Object?>{
              'type': 'boolean',
              'default': false,
            },
          },
        ),
      'session.development.get': _sessionRequest(),
      'session.development.reload': _sessionRequest(
        properties: <String, Object?>{
          'mode': _enum(<String>[
            'hot_reload',
            'hot_restart',
          ], defaultValue: 'hot_reload'),
        },
      ),
      'session.development.stop': _sessionRequest(),
      'development.probe.collect': _sessionRequest(
        properties: <String, Object?>{
          'profile': _enum(<String>[
            'quick',
            'interactive',
            'diagnostic',
            'forensic',
          ], defaultValue: 'quick'),
          'reason': _enum(<String>[
            'manual',
            'post_reload',
            'post_action',
            'failure',
          ], defaultValue: 'manual'),
          'checkpoint': _boundedString(256),
        },
      ),
      'development.probe.compare': _sessionRequest(
        properties: const <String, Object?>{
          'fromProbeId': _id,
          'toProbeId': _id,
        },
        required: const <String>['fromProbeId', 'toProbeId'],
      ),
      for (final kind in <String>['ui.inspect', 'surface.inspect'])
        kind: _sessionRequest(
          properties: <String, Object?>{
            'profile': _profile,
            'snapshotOptions': _snapshotOptions,
            'compareAgainstSnapshotRef': _id,
          },
          precision: 'structural',
        ),
      for (final kind in <String>['logs.read', 'session.logs.read'])
        kind: _sessionRequest(
          properties: <String, Object?>{'maxLines': _boundedInteger(1, 5000)},
        ),
      'network.read': _sessionRequest(
        properties: <String, Object?>{
          'id': _networkRequestId,
          'before': _networkRequestId,
          'includeEntries': _boolean,
          'onlyFailures': _boolean,
          'method': _nonBlankBoundedString(32),
          'uriContains': _nonBlankBoundedString(512),
          'statusCodeAtLeast': _boundedInteger(100, 599),
          'maxEntries': _boundedInteger(1, 1000),
          'maxEndpointSummaries': _boundedInteger(1, 1000),
        },
      ),
      'network.body': _sessionRequest(
        properties: <String, Object?>{
          'requestId': _networkRequestId,
          'body': _enum(<String>['request', 'response', 'both']),
          'raw': <String, Object?>{'type': 'boolean', 'default': false},
        },
        required: const <String>['requestId', 'body'],
      ),
      'errors.read': _sessionRequest(
        properties: <String, Object?>{'maxErrors': _boundedInteger(1, 1000)},
      ),
      'evidence.screenshot.capture': _sessionRequest(
        properties: <String, Object?>{
          'name': _boundedString(128),
          'reason': _enum(<String>[
            'baseline',
            'before_action',
            'after_action',
            'assertion_failure',
            'acceptance',
          ], defaultValue: 'acceptance'),
          'includeSnapshot': _boolean,
          'attachToStep': _boolean,
          'captureProfile': _enum(<String>[
            'diagnostic',
            'acceptance',
            'flutterPreferred',
            'nativePreferred',
          ]),
          'allowFallback': _boolean,
          'profile': _profile,
          'timeoutMs': _boundedInteger(1, 300000),
        },
      ),
      'shell.run': _object(
        properties: <String, Object?>{
          'command': _array(_boundedString(4096), minimum: 1, maximum: 128),
          'timeoutMs': _boundedInteger(1, 300000),
        },
        required: const <String>['command'],
      ),
      'system.action': _object(
        properties: <String, Object?>{
          'sessionId': _sessionId,
          'targetId': _id,
          'action': _enum(_systemActionNames),
          'parameters': _jsonObject,
          'timeoutMs': _boundedInteger(1, 120000),
        },
        required: const <String>['action'],
        precision: 'structural',
        oneOf: const <Map<String, Object?>>[
          <String, Object?>{
            'required': <String>['sessionId'],
          },
          <String, Object?>{
            'required': <String>['targetId'],
          },
        ],
        examples: const <Map<String, Object?>>[
          <String, Object?>{
            'sessionId': 'session-example',
            'action': 'dismissSystemDialog',
          },
        ],
      ),
      for (final kind in <String>['app.reload', 'app.restart'])
        kind: _sessionRequest(),
      'viewport.set': _sessionRequest(
        properties: <String, Object?>{
          'width': <String, Object?>{
            ..._boundedInteger(200, 8192),
            'examples': <int>[800],
          },
          'height': <String, Object?>{
            ..._boundedInteger(200, 8192),
            'examples': <int>[600],
          },
        },
        required: const <String>['width', 'height'],
      ),
      'recording.start': _sessionRequest(
        properties: <String, Object?>{'recording': _recordingRequest},
        precision: 'structural',
      ),
      'recording.stop': _object(
        properties: const <String, Object?>{'recordingId': _id},
        required: const <String>['recordingId'],
      ),
    };

Map<String, Object?> _launchRequest({bool allowMode = false}) => _object(
  properties: <String, Object?>{
    'targetId': _id,
    if (allowMode) 'mode': _enum(<String>['development', 'automation']),
    'launchTimeoutMs': _positiveTimeout,
    'launchConfiguration': _launchConfiguration,
  },
  required: const <String>['targetId'],
);

final List<String> _systemActionNames = List<String>.unmodifiable(
  CockpitSystemControlAction.values.map((action) => action.name),
);
