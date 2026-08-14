import 'foundation_schema_helpers.dart';

Map<String, Object?> foundationExecutionDefinitions() => <String, Object?>{
  'OperationDescriptor': objectSchema(
    <String, Object?>{
      'kind': schemaRef('Kind'),
      'title': stringSchema(maxLength: 128),
      'description': stringSchema(maxLength: 1024),
      'scope': stringSchema(
        values: const <String>['supervisor', 'root', 'workspace'],
      ),
      'mutationClass': stringSchema(
        values: const <String>['readOnly', 'mutating'],
      ),
      'idempotency': stringSchema(
        values: const <String>['prohibited', 'optional', 'required'],
      ),
      'executionMode': stringSchema(
        values: const <String>['synchronous', 'job'],
      ),
      'defaultTimeoutMs': integerSchema(minimum: 1, maximum: 86400000),
      'maximumTimeoutMs': integerSchema(minimum: 1, maximum: 86400000),
      'safetyEffects': arraySchema(
        stringSchema(
          values: const <String>[
            'shell',
            'system',
            'reset',
            'permission',
            'externalSideEffect',
            'capture',
            'recording',
          ],
        ),
        unique: true,
      ),
      'requestSchemaRef': schemaRef('SchemaReference'),
      'responseSchemaRef': schemaRef('SchemaReference'),
      'requiredFeatures': arraySchema(schemaRef('Identifier'), unique: true),
    },
    extra: <String, Object?>{
      'if': <String, Object?>{
        'properties': <String, Object?>{
          'mutationClass': <String, Object?>{'const': 'readOnly'},
        },
      },
      'then': <String, Object?>{
        'properties': <String, Object?>{
          'safetyEffects': <String, Object?>{'maxItems': 0},
        },
      },
    },
  ),
  'OperationInvocation': objectSchema(
    <String, Object?>{
      'kind': schemaRef('Kind'),
      'input': schemaRef('JsonObject'),
      'rootId': schemaRef('Identifier'),
      'workspaceId': schemaRef('Identifier'),
      'idempotencyKey': schemaRef('IdempotencyKey'),
      'deadline': schemaRef('UtcTimestamp'),
      'requiredFeatures': arraySchema(schemaRef('Identifier'), unique: true),
    },
    optional: const <String>{
      'rootId',
      'workspaceId',
      'idempotencyKey',
      'deadline',
    },
    extra: <String, Object?>{
      'not': <String, Object?>{
        'required': <String>['rootId', 'workspaceId'],
      },
    },
  ),
  'OperationResult': _operationResultSchema(),
  'ResourceDescriptor': objectSchema(<String, Object?>{
    'kind': schemaRef('Kind'),
    'scope': stringSchema(
      values: const <String>['supervisor', 'root', 'workspace'],
    ),
    'uriTemplate': schemaRef('ApiTemplate'),
    'mediaType': stringSchema(
      pattern: r'^[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+$',
      maxLength: 127,
    ),
    'requiredFeatures': arraySchema(schemaRef('Identifier'), unique: true),
  }),
  'CapabilityDocument': objectSchema(<String, Object?>{
    'schemaVersion': stringSchema(constant: 'cockpit.foundation/v2'),
    'apiVersion': schemaRef('ApiVersion'),
    'features': arraySchema(schemaRef('FeatureDescriptor'), unique: true),
    'operations': arraySchema(schemaRef('OperationDescriptor'), unique: true),
    'resources': arraySchema(schemaRef('ResourceDescriptor'), unique: true),
  }),
  'InlineCaseSource': objectSchema(<String, Object?>{
    'kind': stringSchema(constant: 'inline'),
    'case': externalRef('cockpit.test.v2.schema.json#/\$defs/case'),
    'sourceSha256': schemaRef('Sha256'),
  }),
  'IndexedCaseSource': objectSchema(<String, Object?>{
    'kind': stringSchema(constant: 'indexed'),
    'reference': schemaRef('IndexedCaseReference'),
  }),
  'CaseSubmissionSource': oneOfSchema(<Map<String, Object?>>[
    schemaRef('InlineCaseSource'),
    schemaRef('IndexedCaseSource'),
  ]),
  'InlineSuiteSource': objectSchema(<String, Object?>{
    'kind': stringSchema(constant: 'inline'),
    'suite': externalRef('cockpit.test.v2.schema.json#/\$defs/suite'),
    'sourceSha256': schemaRef('Sha256'),
  }),
  'IndexedSuiteSource': objectSchema(<String, Object?>{
    'kind': stringSchema(constant: 'indexed'),
    'reference': schemaRef('IndexedSuiteReference'),
  }),
  'SuiteSubmissionSource': oneOfSchema(<Map<String, Object?>>[
    schemaRef('InlineSuiteSource'),
    schemaRef('IndexedSuiteSource'),
  ]),
  'RunSubmissionSource': oneOfSchema(<Map<String, Object?>>[
    schemaRef('CaseSubmissionSource'),
    schemaRef('SuiteSubmissionSource'),
  ]),
  'RunSubmission': objectSchema(
    <String, Object?>{
      'workspaceId': schemaRef('Identifier'),
      'source': schemaRef('RunSubmissionSource'),
      'idempotencyKey': schemaRef('IdempotencyKey'),
      'inputs': schemaRef('JsonObject'),
      'targetId': schemaRef('Identifier'),
      'timeoutMs': integerSchema(minimum: 1, maximum: 86400000),
      'requiredFeatures': arraySchema(schemaRef('Identifier'), unique: true),
    },
    optional: const <String>{'targetId', 'timeoutMs'},
  ),
  'RunAccepted': objectSchema(<String, Object?>{
    'workspaceId': schemaRef('Identifier'),
    'runId': schemaRef('Identifier'),
    'statusUrl': schemaRef('ApiPath'),
    'eventsUrl': schemaRef('ApiPath'),
    'submittedAt': schemaRef('UtcTimestamp'),
    'replayed': booleanSchema(),
  }),
  'RunCancellationRequest': objectSchema(
    <String, Object?>{
      'idempotencyKey': schemaRef('IdempotencyKey'),
      'reason': stringSchema(maxLength: 512),
    },
    optional: const <String>{'reason'},
  ),
  'RunCancellation': objectSchema(<String, Object?>{
    'runId': schemaRef('Identifier'),
    'requestedAt': schemaRef('UtcTimestamp'),
    'replayed': booleanSchema(),
  }),
  'RunResource': _runResourceSchema(),
  'RunCaseResource': objectSchema(
    <String, Object?>{
      'runId': schemaRef('Identifier'),
      'caseId': schemaRef('Identifier'),
      'sourceSha256': schemaRef('Sha256'),
      'attemptIds': arraySchema(schemaRef('Identifier'), unique: true),
      'outcome': _runOutcome(),
      'stability': _runStability(),
    },
    optional: const <String>{'outcome', 'stability'},
    extra: <String, Object?>{
      'dependentRequired': <String, Object?>{
        'outcome': <String>['stability'],
        'stability': <String>['outcome'],
      },
    },
  ),
  'RunEvent': _runEventSchema(),
  'EventCursor': objectSchema(
    <String, Object?>{
      'afterSequence': integerSchema(minimum: 0),
      'lastEventId': schemaRef('Identifier'),
    },
    optional: const <String>{'lastEventId'},
  ),
  'EventReplayBoundary': objectSchema(<String, Object?>{
    'requestedAfterSequence': integerSchema(minimum: 0),
    'earliestAvailableSequence': integerSchema(minimum: 1),
    'latestAvailableSequence': integerSchema(minimum: 1),
    'hasGap': booleanSchema(),
  }),
  'LeaseRequest': objectSchema(<String, Object?>{
    'workspaceId': schemaRef('Identifier'),
    'resourceKind': _leaseResourceKind(),
    'resourceId': stringSchema(maxLength: 512),
    'holderId': schemaRef('Identifier'),
    'idempotencyKey': schemaRef('IdempotencyKey'),
    'waitTimeoutMs': integerSchema(minimum: 0, maximum: 300000),
    'ttlMs': integerSchema(minimum: 1000, maximum: 300000),
  }),
  'LeaseResource': _leaseResourceSchema(),
  'OperationPage': pageSchema('OperationDescriptor'),
  'RunPage': pageSchema('RunResource'),
  'RunCasePage': pageSchema('RunCaseResource'),
  'RunEventPage': pageSchema('RunEvent'),
  'LeasePage': pageSchema('LeaseResource'),
};

Map<String, Object?> _operationResultSchema() => objectSchema(
  <String, Object?>{
    'operationId': schemaRef('Identifier'),
    'kind': schemaRef('Kind'),
    'rootId': schemaRef('Identifier'),
    'workspaceId': schemaRef('Identifier'),
    'lifecycle': stringSchema(
      values: const <String>['queued', 'running', 'completed'],
    ),
    'outcome': stringSchema(
      values: const <String>[
        'succeeded',
        'failed',
        'blocked',
        'cancelled',
        'interrupted',
      ],
    ),
    'submittedAt': schemaRef('UtcTimestamp'),
    'startedAt': schemaRef('UtcTimestamp'),
    'finishedAt': schemaRef('UtcTimestamp'),
    'output': schemaRef('JsonObject'),
    'failure': schemaRef('Failure'),
  },
  optional: const <String>{
    'rootId',
    'workspaceId',
    'outcome',
    'startedAt',
    'finishedAt',
    'output',
    'failure',
  },
  extra: <String, Object?>{
    'not': <String, Object?>{
      'required': <String>['rootId', 'workspaceId'],
    },
    'allOf': <Object?>[
      _completedStateRule(),
      _startStateRule(),
      _successFailureRule('succeeded'),
    ],
  },
);

Map<String, Object?> _runResourceSchema() => objectSchema(
  <String, Object?>{
    'projectId': schemaRef('Identifier'),
    'workspaceId': schemaRef('Identifier'),
    'runId': schemaRef('Identifier'),
    'documentKind': stringSchema(values: const <String>['case', 'suite']),
    'documentId': schemaRef('Identifier'),
    'sourceSha256': schemaRef('Sha256'),
    'lifecycle': stringSchema(
      values: const <String>['queued', 'running', 'finalizing', 'completed'],
    ),
    'outcome': _runOutcome(),
    'stability': _runStability(),
    'submittedAt': schemaRef('UtcTimestamp'),
    'startedAt': schemaRef('UtcTimestamp'),
    'finishedAt': schemaRef('UtcTimestamp'),
    'caseIds': arraySchema(schemaRef('Identifier'), unique: true),
    'activeAttemptIds': arraySchema(schemaRef('Identifier'), unique: true),
    'failure': schemaRef('Failure'),
  },
  optional: const <String>{
    'outcome',
    'stability',
    'startedAt',
    'finishedAt',
    'failure',
  },
  extra: <String, Object?>{
    'allOf': <Object?>[
      _completedStateRule(extraRequired: const <String>{'stability'}),
      _startStateRule(),
      _successFailureRule('passed'),
      <String, Object?>{
        'if': <String, Object?>{
          'properties': <String, Object?>{
            'outcome': <String, Object?>{'const': 'passed'},
          },
          'required': <String>['outcome'],
        },
        'then': <String, Object?>{
          'required': <String>['startedAt'],
          'properties': <String, Object?>{
            'caseIds': <String, Object?>{'minItems': 1},
          },
        },
      },
      <String, Object?>{
        'if': <String, Object?>{
          'properties': <String, Object?>{
            'lifecycle': <String, Object?>{'const': 'completed'},
          },
        },
        'then': <String, Object?>{
          'properties': <String, Object?>{
            'activeAttemptIds': <String, Object?>{'maxItems': 0},
          },
        },
      },
    ],
  },
);

Map<String, Object?> _runEventSchema() => objectSchema(
  <String, Object?>{
    'eventId': schemaRef('Identifier'),
    'sequence': integerSchema(minimum: 1),
    'timestamp': schemaRef('UtcTimestamp'),
    'kind': schemaRef('Kind'),
    'entityKind': stringSchema(
      values: const <String>[
        'run',
        'suite',
        'case',
        'attempt',
        'step',
        'report',
        'artifact',
      ],
    ),
    'projectId': schemaRef('Identifier'),
    'workspaceId': schemaRef('Identifier'),
    'runId': schemaRef('Identifier'),
    'caseId': schemaRef('Identifier'),
    'attemptId': schemaRef('Identifier'),
    'stepExecutionId': stringSchema(maxLength: 512),
    'status': stringSchema(
      values: const <String>[
        'passed',
        'failed',
        'blocked',
        'cancelled',
        'skipped',
      ],
    ),
    'lifecycle': stringSchema(
      values: const <String>['queued', 'running', 'finalizing', 'completed'],
    ),
    'outcome': _runOutcome(),
    'stability': _runStability(),
    'sourceLocation': schemaRef('SourceLocation'),
    'targetId': schemaRef('Identifier'),
    'requestedPlane': _testPlane(),
    'actualPlane': _testPlane(),
    'driverId': schemaRef('Identifier'),
    'degradation': stringSchema(maxLength: 512),
    'locatorSummary': schemaRef('JsonObject'),
    'failure': schemaRef('Failure'),
    'artifacts': arraySchema(schemaRef('ArtifactReference'), unique: true),
  },
  optional: const <String>{
    'caseId',
    'attemptId',
    'stepExecutionId',
    'status',
    'lifecycle',
    'outcome',
    'stability',
    'sourceLocation',
    'targetId',
    'requestedPlane',
    'actualPlane',
    'driverId',
    'degradation',
    'locatorSummary',
    'failure',
    'artifacts',
  },
  extra: <String, Object?>{
    'allOf': <Object?>[
      <String, Object?>{
        'if': _entityKindCondition('run'),
        'then': <String, Object?>{
          'required': <String>['lifecycle'],
          'dependentRequired': <String, Object?>{
            'outcome': <String>['stability'],
            'stability': <String>['outcome'],
          },
          'allOf': <Object?>[
            _forbidEventFields(const <String>['status']),
            <String, Object?>{
              'if': <String, Object?>{
                'properties': <String, Object?>{
                  'lifecycle': <String, Object?>{'const': 'completed'},
                },
              },
              'then': <String, Object?>{
                'required': <String>['outcome', 'stability'],
              },
              'else': _forbidEventFields(const <String>[
                'outcome',
                'stability',
              ]),
            },
            _successFailureRule('passed', requireOutcome: false),
          ],
        },
        'else': <String, Object?>{
          'if': _entityKindCondition('case'),
          'then': <String, Object?>{
            'dependentRequired': <String, Object?>{
              'outcome': <String>['stability'],
              'stability': <String>['outcome'],
            },
            'allOf': <Object?>[
              _forbidEventFields(const <String>['lifecycle', 'status']),
              _successFailureRule('passed', requireOutcome: false),
            ],
          },
          'else': <String, Object?>{
            'if': _entityKindCondition('attempt'),
            'then': <String, Object?>{
              'required': <String>['attemptId'],
              'allOf': <Object?>[
                _forbidEventFields(const <String>[
                  'lifecycle',
                  'stability',
                  'status',
                ]),
                _successFailureRule('passed', requireOutcome: false),
              ],
            },
            'else': <String, Object?>{
              'if': _entityKindCondition('step'),
              'then': <String, Object?>{
                'required': <String>['attemptId', 'stepExecutionId', 'status'],
                'allOf': <Object?>[
                  _forbidEventFields(const <String>[
                    'lifecycle',
                    'outcome',
                    'stability',
                  ]),
                  _stepStatusFailureRule(),
                ],
              },
              'else': _forbidEventFields(const <String>[
                'lifecycle',
                'outcome',
                'stability',
                'status',
                'failure',
              ]),
            },
          },
        },
      },
    ],
  },
);

Map<String, Object?> _entityKindCondition(String value) => <String, Object?>{
  'properties': <String, Object?>{
    'entityKind': <String, Object?>{'const': value},
  },
  'required': <String>['entityKind'],
};

Map<String, Object?> _forbidEventFields(Iterable<String> fields) =>
    <String, Object?>{
      'not': <String, Object?>{
        'anyOf': <Object?>[
          for (final field in fields)
            <String, Object?>{
              'required': <String>[field],
            },
        ],
      },
    };

Map<String, Object?> _stepStatusFailureRule() => <String, Object?>{
  'if': <String, Object?>{
    'properties': <String, Object?>{
      'status': <String, Object?>{
        'enum': <String>['failed', 'blocked', 'cancelled'],
      },
    },
    'required': <String>['status'],
  },
  'then': <String, Object?>{
    'required': <String>['failure'],
  },
  'else': _forbidEventFields(const <String>['failure']),
};

Map<String, Object?> _leaseResourceSchema() => objectSchema(
  <String, Object?>{
    'leaseId': schemaRef('Identifier'),
    'workspaceId': schemaRef('Identifier'),
    'resourceKind': _leaseResourceKind(),
    'resourceId': stringSchema(maxLength: 512),
    'holderId': schemaRef('Identifier'),
    'state': stringSchema(
      values: const <String>[
        'queued',
        'active',
        'releasing',
        'released',
        'expired',
        'quarantined',
      ],
    ),
    'requestedAt': schemaRef('UtcTimestamp'),
    'acquiredAt': schemaRef('UtcTimestamp'),
    'expiresAt': schemaRef('UtcTimestamp'),
    'releasedAt': schemaRef('UtcTimestamp'),
    'queuePosition': integerSchema(minimum: 0),
    'failure': schemaRef('Failure'),
  },
  optional: const <String>{
    'acquiredAt',
    'expiresAt',
    'releasedAt',
    'queuePosition',
    'failure',
  },
  extra: <String, Object?>{
    'allOf': <Object?>[
      <String, Object?>{
        'if': <String, Object?>{
          'properties': <String, Object?>{
            'state': <String, Object?>{'const': 'queued'},
          },
        },
        'then': <String, Object?>{
          'required': <String>['queuePosition'],
        },
        'else': <String, Object?>{
          'not': <String, Object?>{
            'required': <String>['queuePosition'],
          },
        },
      },
      <String, Object?>{
        'if': <String, Object?>{
          'properties': <String, Object?>{
            'state': <String, Object?>{'const': 'quarantined'},
          },
        },
        'then': <String, Object?>{
          'required': <String>['acquiredAt', 'expiresAt', 'failure'],
        },
        'else': <String, Object?>{
          'not': <String, Object?>{
            'required': <String>['failure'],
          },
        },
      },
      <String, Object?>{
        'if': <String, Object?>{
          'properties': <String, Object?>{
            'state': <String, Object?>{
              'enum': <String>['active', 'releasing', 'expired', 'quarantined'],
            },
          },
        },
        'then': <String, Object?>{
          'required': <String>['acquiredAt', 'expiresAt'],
        },
      },
      <String, Object?>{
        'if': <String, Object?>{
          'properties': <String, Object?>{
            'state': <String, Object?>{'const': 'released'},
          },
        },
        'then': <String, Object?>{
          'required': <String>['releasedAt'],
        },
        'else': <String, Object?>{
          'not': <String, Object?>{
            'required': <String>['releasedAt'],
          },
        },
      },
    ],
  },
);

Map<String, Object?> _completedStateRule({
  Set<String> extraRequired = const <String>{},
}) => <String, Object?>{
  'if': <String, Object?>{
    'properties': <String, Object?>{
      'lifecycle': <String, Object?>{'const': 'completed'},
    },
  },
  'then': <String, Object?>{
    'required': <String>['outcome', 'finishedAt', ...extraRequired],
  },
  'else': <String, Object?>{
    'not': <String, Object?>{
      'anyOf': <Object?>[
        <String, Object?>{
          'required': <String>['outcome'],
        },
        <String, Object?>{
          'required': <String>['finishedAt'],
        },
        for (final field in extraRequired)
          <String, Object?>{
            'required': <String>[field],
          },
      ],
    },
  },
};

Map<String, Object?> _successFailureRule(
  String successValue, {
  bool requireOutcome = true,
}) => <String, Object?>{
  'if': <String, Object?>{
    'properties': <String, Object?>{
      'outcome': <String, Object?>{'const': successValue},
    },
    if (requireOutcome) 'required': <String>['outcome'],
  },
  'then': <String, Object?>{
    'not': <String, Object?>{
      'required': <String>['failure'],
    },
  },
  'else': <String, Object?>{
    'if': <String, Object?>{
      'required': <String>['outcome'],
    },
    'then': <String, Object?>{
      'required': <String>['failure'],
    },
    'else': <String, Object?>{
      'not': <String, Object?>{
        'required': <String>['failure'],
      },
    },
  },
};

Map<String, Object?> _startStateRule() => <String, Object?>{
  'if': <String, Object?>{
    'properties': <String, Object?>{
      'lifecycle': <String, Object?>{'const': 'running'},
    },
  },
  'then': <String, Object?>{
    'required': <String>['startedAt'],
  },
  'else': <String, Object?>{
    'if': <String, Object?>{
      'properties': <String, Object?>{
        'lifecycle': <String, Object?>{'const': 'queued'},
      },
    },
    'then': <String, Object?>{
      'not': <String, Object?>{
        'required': <String>['startedAt'],
      },
    },
  },
};

Map<String, Object?> _runOutcome() => stringSchema(
  values: const <String>[
    'passed',
    'failed',
    'blocked',
    'skipped',
    'cancelled',
    'interrupted',
    'internalError',
  ],
);

Map<String, Object?> _runStability() =>
    stringSchema(values: const <String>['stable', 'flaky', 'unknown']);

Map<String, Object?> _testPlane() => stringSchema(
  values: const <String>['semantic', 'native', 'visual', 'coordinate'],
);

Map<String, Object?> _leaseResourceKind() => stringSchema(
  values: const <String>[
    'run',
    'device',
    'session',
    'browserContext',
    'desktopInput',
    'desktopWindow',
    'capture',
    'recording',
    'forwardedPort',
    'workspaceMutation',
  ],
);
