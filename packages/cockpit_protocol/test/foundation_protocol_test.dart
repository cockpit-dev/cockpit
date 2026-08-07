import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_protocol/src/foundation/cockpit_foundation_constraints.dart';
import 'package:cockpit_protocol/src/foundation/cockpit_foundation_value_reader.dart';
import 'package:test/test.dart';

void main() {
  group('cockpit.foundation/v2 models', () {
    test('resource and discovery contracts round-trip', () {
      final startedAt = DateTime.utc(2026, 7, 20);
      final server = CockpitServerInfo(
        instanceId: 'supervisorA',
        apiVersion: CockpitApiVersion(major: 2, minor: 1),
        engineVersion: '2.0.0',
        startedAt: startedAt,
        features: _features(),
      );
      _expectRoundTrip(server, CockpitServerInfo.fromJson);
      final negotiation = CockpitProtocolNegotiator.negotiate(
        request: CockpitNegotiationRequest(
          apiVersion: CockpitApiVersion(major: 2, minor: 1),
          requiredFeatures: <String>[
            CockpitFoundationFeature.additiveResponseFields.id,
          ],
        ),
        server: server,
      );
      _expectRoundTrip(negotiation, CockpitNegotiationResult.fromJson);

      final root = CockpitRootResource(
        rootId: 'rootA',
        canonicalPath: '/tmp/cockpit-root',
        filesystemIdentity: 'dev:1:inode:2',
        state: CockpitRootState.active,
        registeredAt: startedAt,
        updatedAt: startedAt,
      );
      _expectRoundTrip(root, CockpitRootResource.fromJson);
      _expectRoundTrip(
        CockpitRootRegistration(
          path: '/tmp/cockpit-root',
          label: 'Development',
        ),
        CockpitRootRegistration.fromJson,
      );
      _expectRoundTrip(
        CockpitRootRemoval(force: true, drainTimeoutMs: 1000),
        CockpitRootRemoval.fromJson,
      );

      final marker = CockpitWorkspaceMarker(
        workspaceId: 'workspaceA',
        projectId: 'projectA',
        checkoutId: 'checkoutA',
        createdAt: startedAt,
      );
      _expectRoundTrip(marker, CockpitWorkspaceMarker.fromJson);
      final workspace = CockpitWorkspaceResource(
        workspaceId: marker.workspaceId,
        projectId: marker.projectId,
        checkoutId: marker.checkoutId,
        rootId: root.rootId,
        canonicalPath: '/tmp/cockpit-root/app',
        filesystemIdentity: 'dev:1:inode:3',
        state: CockpitWorkspaceState.active,
        registeredAt: startedAt,
        updatedAt: startedAt,
      );
      _expectRoundTrip(workspace, CockpitWorkspaceResource.fromJson);
      _expectRoundTrip(
        CockpitWorkspaceRegistration(
          rootId: root.rootId,
          path: workspace.canonicalPath,
        ),
        CockpitWorkspaceRegistration.fromJson,
      );
      _expectRoundTrip(
        CockpitWorkspaceRebind(
          path: '/tmp/cockpit-root/moved-app',
          expectedCheckoutId: marker.checkoutId,
        ),
        CockpitWorkspaceRebind.fromJson,
      );
      _expectRoundTrip(
        CockpitWorkspaceRemoval(drainTimeoutMs: 2500),
        CockpitWorkspaceRemoval.fromJson,
      );
      _expectRoundTrip(
        CockpitAutomationTargetResource(
          targetId: 'targetA',
          workspaceId: workspace.workspaceId,
          platform: 'android',
          deviceId: 'emulator-5554',
          targetKind: CockpitTargetKind.nativeApp,
          mode: CockpitAutomationTargetMode.automation,
          environment: CockpitAutomationTargetEnvironment.staging,
          appId: 'com.example.app',
        ),
        CockpitAutomationTargetResource.fromJson,
      );

      final document = CockpitDocumentResource(
        documentId: 'documentA',
        workspaceId: workspace.workspaceId,
        relativePath: 'test/e2e/login.cockpit.yaml',
        sha256: _hash('a'),
        modifiedAt: startedAt,
        kind: CockpitIndexedDocumentKind.testCase,
        authoredId: 'loginCase',
        cases: <CockpitCaseIndexEntry>[
          CockpitCaseIndexEntry(caseId: 'loginCase', title: 'Login'),
        ],
      );
      _expectRoundTrip(document, CockpitDocumentResource.fromJson);
      _expectRoundTrip(
        CockpitCaseIndexEntry(
          caseId: 'loginCase',
          documentId: document.documentId,
          relativePath: document.relativePath,
          title: 'Login',
        ),
        CockpitCaseIndexEntry.fromJson,
      );
      final reference = CockpitIndexedCaseReference(
        documentId: document.documentId,
        caseId: document.cases.single.caseId,
        documentSha256: document.sha256,
      );
      _expectRoundTrip(reference, CockpitIndexedCaseReference.fromJson);
      _expectRoundTrip(
        CockpitDocumentValidationRequest(
          format: CockpitDocumentFormat.yaml,
          sourceText: '',
          relativePath: document.relativePath,
        ),
        CockpitDocumentValidationRequest.fromJson,
      );

      final descriptor = _runDescriptor();
      _expectRoundTrip(descriptor, CockpitOperationDescriptor.fromJson);
      final capabilities = CockpitCapabilityDocument(
        apiVersion: server.apiVersion,
        features: server.features,
        operations: <CockpitOperationDescriptor>[descriptor],
        resources: <CockpitResourceDescriptor>[
          CockpitResourceDescriptor(
            kind: 'workspace.runs',
            scope: CockpitOperationScope.workspace,
            uriTemplate: '/api/v2/workspaces/{workspaceId}/runs',
            mediaType: 'application/json',
          ),
        ],
      );
      _expectRoundTrip(capabilities, CockpitCapabilityDocument.fromJson);
      final page = CockpitPage<CockpitWorkspaceResource>(
        items: <CockpitWorkspaceResource>[workspace],
        nextCursor: 'bmV4dA',
        totalCount: 2,
      );
      final pageJson = page.toJson((item) => item.toJson());
      expect(
        CockpitPage.fromJson<CockpitWorkspaceResource>(
          pageJson,
          (value, path, policy) => CockpitWorkspaceResource.fromJson(
            value,
            path: path,
            decodePolicy: policy,
          ),
        ).toJson((item) => item.toJson()),
        pageJson,
      );
    });

    test(
      'execution, error, event, artifact, and lease contracts round-trip',
      () {
        final submittedAt = DateTime.utc(2026, 7, 20, 1);
        final startedAt = submittedAt.add(const Duration(seconds: 1));
        final finishedAt = startedAt.add(const Duration(seconds: 2));
        final testCase = _testCase();
        _expectRoundTrip(
          CockpitDocumentValidationResult(
            valid: true,
            sourceSha256: _hash('a'),
            document: testCase,
          ),
          CockpitDocumentValidationResult.fromJson,
        );

        final submission = CockpitRunSubmission(
          workspaceId: 'workspaceA',
          source: CockpitInlineCaseSource(
            testCase: testCase,
            sourceSha256: _hash('a'),
          ),
          idempotencyKey: CockpitIdempotencyKey('run:login:1'),
          inputs: const <String, Object?>{'username': 'tester@example.com'},
          targetId: 'deviceA',
          timeoutMs: 1800000,
        );
        _expectRoundTrip(submission, CockpitRunSubmission.fromJson);
        _expectRoundTrip(
          CockpitRunAccepted(
            workspaceId: submission.workspaceId,
            runId: 'runA',
            statusUrl: '/api/v2/runs/runA',
            eventsUrl: '/api/v2/runs/runA/events',
            submittedAt: submittedAt,
            replayed: false,
          ),
          CockpitRunAccepted.fromJson,
        );
        _expectRoundTrip(
          CockpitRunCancellationRequest(
            idempotencyKey: CockpitIdempotencyKey('cancel:runA:1'),
            reason: 'CI timeout',
          ),
          CockpitRunCancellationRequest.fromJson,
        );
        _expectRoundTrip(
          CockpitRunCancellation(
            runId: 'runA',
            requestedAt: finishedAt,
            replayed: true,
          ),
          CockpitRunCancellation.fromJson,
        );

        final primary = CockpitApiError(
          code: CockpitErrorCode.driverUnavailable,
          category: CockpitErrorCategory.driver,
          message: 'Driver disconnected.',
          retryable: true,
          responsibleLayer: CockpitResponsibleLayer.driver,
          redactedDetails: const <String, Object?>{'transport': 'stdio'},
        );
        final cleanup = CockpitApiWarning(
          stage: CockpitWarningStage.cleanup,
          error: CockpitApiError(
            code: 'cleanupFailed',
            category: CockpitErrorCategory.resource,
            message: 'Device cleanup failed.',
            retryable: false,
            responsibleLayer: CockpitResponsibleLayer.worker,
          ),
        );
        final evidence = CockpitApiWarning(
          stage: CockpitWarningStage.evidence,
          error: CockpitApiError(
            code: CockpitErrorCode.evidenceFailed,
            category: CockpitErrorCategory.evidence,
            message: 'Final screenshot failed.',
            retryable: true,
            responsibleLayer: CockpitResponsibleLayer.worker,
          ),
        );
        final failure = CockpitFailure(
          primary: primary,
          warnings: <CockpitApiWarning>[cleanup, evidence],
        );
        _expectRoundTrip(
          CockpitApiErrorResponse(
            requestId: 'requestA',
            timestamp: finishedAt,
            failure: failure,
          ),
          CockpitApiErrorResponse.fromJson,
        );

        final invocation = CockpitOperationInvocation(
          kind: 'case.run',
          workspaceId: submission.workspaceId,
          idempotencyKey: submission.idempotencyKey,
          input: submission.toJson(),
        );
        _expectRoundTrip(invocation, CockpitOperationInvocation.fromJson);
        expect(
          CockpitOperationCatalog(<CockpitOperationContract<Object?>>[
                _runContract(),
              ])
              .admit(
                invocation,
                negotiatedFeatureIds: _features().map((feature) => feature.id),
              )
              .kind,
          invocation.kind,
        );
        _expectRoundTrip(
          CockpitOperationResult(
            operationId: 'operationA',
            kind: invocation.kind,
            workspaceId: submission.workspaceId,
            lifecycle: CockpitOperationLifecycle.completed,
            outcome: CockpitOperationOutcome.failed,
            submittedAt: submittedAt,
            startedAt: startedAt,
            finishedAt: finishedAt,
            failure: failure,
          ),
          CockpitOperationResult.fromJson,
        );

        final artifact = CockpitArtifactResource(
          artifactId: 'artifactA',
          workspaceId: submission.workspaceId,
          runId: 'runA',
          attemptId: 'attemptA',
          stepExecutionId: 'main/goBack',
          kind: 'evidence.screenshot',
          relativePath: 'artifacts/final.png',
          mediaType: 'image/png',
          sizeBytes: 1024,
          sha256: _hash('b'),
          createdAt: finishedAt,
          downloadUrl: '/api/v2/runs/runA/artifacts/artifactA',
        );
        _expectRoundTrip(artifact, CockpitArtifactResource.fromJson);
        final run = CockpitRunResource(
          projectId: 'projectA',
          workspaceId: submission.workspaceId,
          runId: artifact.runId,
          documentKind: CockpitRunDocumentKind.testCase,
          documentId: testCase.id,
          sourceSha256: _hash('a'),
          lifecycle: CockpitRunLifecycle.completed,
          outcome: CockpitRunOutcome.passed,
          stability: CockpitRunStability.stable,
          submittedAt: submittedAt,
          startedAt: startedAt,
          finishedAt: finishedAt,
          caseIds: <String>[testCase.id],
        );
        _expectRoundTrip(run, CockpitRunResource.fromJson);
        _expectRoundTrip(
          CockpitRunCaseResource(
            runId: run.runId,
            caseId: run.documentId,
            sourceSha256: run.sourceSha256,
            attemptIds: const <String>['attemptA'],
            outcome: run.outcome,
            stability: run.stability,
          ),
          CockpitRunCaseResource.fromJson,
        );
        final event = CockpitRunEvent(
          eventId: 'eventA',
          sequence: 1,
          timestamp: finishedAt,
          kind: 'run.completed',
          entityKind: CockpitRunEventEntityKind.run,
          projectId: run.projectId,
          workspaceId: run.workspaceId,
          runId: run.runId,
          lifecycle: run.lifecycle,
          outcome: run.outcome,
          stability: run.stability,
          targetId: 'deviceA',
          requestedPlane: CockpitTestPlane.semantic,
          actualPlane: CockpitTestPlane.semantic,
          driverId: 'flutterDriver',
          artifacts: <CockpitArtifactReference>[artifact.reference],
        );
        _expectRoundTrip(event, CockpitRunEvent.fromJson);
        CockpitRunEvent.validateSequence(<CockpitRunEvent>[event]);
        final stepEvent = CockpitRunEvent(
          eventId: 'stepEventA',
          sequence: 2,
          timestamp: finishedAt,
          kind: 'step.completed',
          entityKind: CockpitRunEventEntityKind.step,
          projectId: run.projectId,
          workspaceId: run.workspaceId,
          runId: run.runId,
          caseId: run.documentId,
          attemptId: 'attemptA',
          stepExecutionId: 'main/goBack',
          stepStatus: CockpitTestStepStatus.passed,
          sourceLocation: CockpitTestSourceLocation(line: 7, column: 3),
          requestedPlane: CockpitTestPlane.semantic,
          actualPlane: CockpitTestPlane.semantic,
          driverId: 'flutterDriver',
          degradation: 'semanticTargetRecovered',
          locatorSummary: const <String, Object?>{
            'matchedKind': 'cockpitId',
            'matchedValue': 'backButton',
          },
          artifacts: <CockpitArtifactReference>[artifact.reference],
        );
        _expectRoundTrip(stepEvent, CockpitRunEvent.fromJson);
        expect(stepEvent.toJson(), containsPair('status', 'passed'));
        expect(stepEvent.toJson(), isNot(contains('lifecycle')));
        expect(stepEvent.toJson(), isNot(contains('outcome')));
        _expectRoundTrip(
          CockpitRunEvent(
            eventId: 'caseEventA',
            sequence: 1,
            timestamp: submittedAt,
            kind: 'case.queued',
            entityKind: CockpitRunEventEntityKind.testCase,
            projectId: run.projectId,
            workspaceId: run.workspaceId,
            runId: run.runId,
            caseId: run.documentId,
          ),
          CockpitRunEvent.fromJson,
        );
        _expectRoundTrip(
          CockpitRunEvent(
            eventId: 'attemptEventA',
            sequence: 1,
            timestamp: startedAt,
            kind: 'attempt.running',
            entityKind: CockpitRunEventEntityKind.attempt,
            projectId: run.projectId,
            workspaceId: run.workspaceId,
            runId: run.runId,
            caseId: run.documentId,
            attemptId: 'attemptA',
          ),
          CockpitRunEvent.fromJson,
        );

        _expectRoundTrip(
          CockpitLeaseRequest(
            workspaceId: run.workspaceId,
            resourceKind: CockpitLeaseResourceKind.device,
            resourceId: 'emulator-5554',
            holderId: 'workerA',
            idempotencyKey: CockpitIdempotencyKey('lease:runA:device'),
          ),
          CockpitLeaseRequest.fromJson,
        );
        _expectRoundTrip(
          CockpitLeaseResource(
            leaseId: 'leaseA',
            workspaceId: run.workspaceId,
            resourceKind: CockpitLeaseResourceKind.device,
            resourceId: 'emulator-5554',
            holderId: 'workerA',
            state: CockpitLeaseState.active,
            requestedAt: submittedAt,
            acquiredAt: startedAt,
            expiresAt: finishedAt.add(const Duration(seconds: 30)),
          ),
          CockpitLeaseResource.fromJson,
        );
      },
    );

    test('JSON values freeze iteratively within declared bounds', () {
      final shared = <Object?>[1, 'two'];
      final frozen = CockpitFoundationValueReader.jsonObject(<String, Object?>{
        'first': shared,
        'second': shared,
      }, r'$.payload');
      expect(frozen['first'], <Object?>[1, 'two']);
      expect(frozen['second'], <Object?>[1, 'two']);
      expect(
        () => (frozen['first']! as List<Object?>).add(3),
        throwsUnsupportedError,
      );
      expect(() => frozen['third'] = null, throwsUnsupportedError);

      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      expect(
        () => CockpitFoundationValueReader.jsonObject(cyclic, r'$'),
        throwsA(_formatExceptionAt(r'$.self')),
      );

      final atDepthLimit = CockpitFoundationValueReader.jsonObject(
        _jsonObjectWithContainerDepth(cockpitFoundationJsonMaximumDepth),
        r'$',
      );
      Object? frozenValue = atDepthLimit['value'];
      for (
        var depth = 1;
        depth < cockpitFoundationJsonMaximumDepth;
        depth += 1
      ) {
        frozenValue = (frozenValue! as List<Object?>).single;
      }
      expect(frozenValue, isEmpty);
      expect(
        () => CockpitFoundationValueReader.jsonObject(
          _jsonObjectWithContainerDepth(cockpitFoundationJsonMaximumDepth + 1),
          r'$',
        ),
        throwsA(_formatExceptionAt(r'$.value[')),
      );
      expect(
        () => CockpitFoundationValueReader.jsonObject(<String, Object?>{
          'value': double.nan,
        }, r'$.payload'),
        throwsA(_formatExceptionAt(r'$.payload.value')),
      );
      expect(
        () => CockpitFoundationValueReader.jsonObject(<String, Object?>{
          'value': DateTime.utc(2026),
        }, r'$.payload'),
        throwsA(_formatExceptionAt(r'$.payload.value')),
      );
    });

    test(
      'negotiation, admission, recovery, and state invariants fail closed',
      () {
        final server = CockpitServerInfo(
          instanceId: 'supervisorA',
          apiVersion: CockpitApiVersion(major: 2, minor: 1),
          engineVersion: '2.0.0',
          startedAt: DateTime.utc(2026, 7, 20),
          features: <CockpitFeatureDescriptor>[
            ..._features(),
            CockpitFeatureDescriptor(
              id: 'foundation.minorOne',
              revision: 1,
              minimumApiMinor: 1,
            ),
          ],
        );
        expect(
          () => CockpitProtocolNegotiator.negotiate(
            request: CockpitNegotiationRequest(
              apiVersion: CockpitApiVersion(major: 2, minor: 0),
              requiredFeatures: const <String>['foundation.minorOne'],
            ),
            server: server,
          ),
          throwsA(
            isA<CockpitApiException>().having(
              (error) => error.error.code,
              'code',
              CockpitErrorCode.upgradeRequired,
            ),
          ),
        );
        expect(
          () => CockpitProtocolNegotiator.negotiate(
            request: CockpitNegotiationRequest(
              apiVersion: CockpitApiVersion(major: 3, minor: 0),
            ),
            server: server,
          ),
          throwsA(isA<CockpitApiException>()),
        );

        final futureServer = <String, Object?>{
          ...server.toJson(),
          'futureField': true,
        };
        expect(
          () => CockpitServerInfo.fromJson(futureServer),
          throwsFormatException,
        );
        expect(
          CockpitServerInfo.fromJson(
            futureServer,
            decodePolicy: CockpitDecodePolicy.negotiatedResponse(<String>[
              CockpitFoundationFeature.additiveResponseFields.id,
            ]),
          ).toJson(),
          server.toJson(),
        );

        final futureDescriptor = <String, Object?>{
          ..._runDescriptor().toJson(),
          'safetyEffects': <String>['futureEffect'],
        };
        expect(
          () => CockpitOperationDescriptor.fromJson(futureDescriptor),
          throwsFormatException,
        );
        final decodedFutureDescriptor = CockpitOperationDescriptor.fromJson(
          futureDescriptor,
          decodePolicy: CockpitDecodePolicy.negotiatedResponse(<String>[
            CockpitFoundationFeature.extensibleResponseEnums.id,
          ]),
        );
        expect(
          decodedFutureDescriptor.safetyEffects.single.wireValue,
          'futureEffect',
        );
        expect(decodedFutureDescriptor.safetyEffects.single.isKnown, isFalse);

        final validSubmission = _runSubmission();
        final validInvocation = CockpitOperationInvocation(
          kind: 'case.run',
          workspaceId: 'workspaceA',
          idempotencyKey: validSubmission.idempotencyKey,
          input: validSubmission.toJson(),
        );
        expect(
          () =>
              CockpitOperationContract.custom<CockpitDocumentValidationRequest>(
                descriptor: _runDescriptor(),
                requestSchemaRef: r'#/$defs/RunSubmission',
                inputDecoder: CockpitDocumentValidationRequest.fromJson,
                admissionProjector: (_) =>
                    const CockpitOperationAdmissionProjection.empty(),
              ),
          throwsFormatException,
        );
        expect(
          () =>
              CockpitOperationContract.custom<CockpitDocumentValidationRequest>(
                descriptor: _customDescriptor(
                  requestSchemaRef: r'#/$defs/RunSubmission',
                ),
                requestSchemaRef: r'#/$defs/RunSubmission',
                inputDecoder: CockpitDocumentValidationRequest.fromJson,
                admissionProjector: (_) =>
                    const CockpitOperationAdmissionProjection.empty(),
              ),
          throwsFormatException,
        );
        final customDescriptor = _customDescriptor();
        final customContract =
            CockpitOperationContract.custom<Map<String, Object?>>(
              descriptor: customDescriptor,
              requestSchemaRef: customDescriptor.requestSchemaRef,
              inputDecoder: (input) =>
                  CockpitFoundationValueReader.jsonObject(input, r'$'),
              admissionProjector: (_) =>
                  const CockpitOperationAdmissionProjection.empty(),
            );
        expect(customContract.descriptor, same(customDescriptor));
        expect(
          CockpitOperationCatalog(<CockpitOperationContract<Object?>>[
            customContract,
          ]).admit(
            CockpitOperationInvocation(
              kind: 'custom.execute',
              input: const <String, Object?>{'value': true},
            ),
            negotiatedFeatureIds: const <String>[],
          ),
          same(customDescriptor),
        );
        final validationDescriptor = _documentValidationDescriptor();
        final validationContract = CockpitOperationContract.documentValidation(
          descriptor: validationDescriptor,
        );
        expect(validationContract.descriptor, same(validationDescriptor));
        expect(
          CockpitOperationCatalog(<CockpitOperationContract<Object?>>[
            validationContract,
          ]).admit(
            CockpitOperationInvocation(
              kind: 'case.validate',
              workspaceId: 'workspaceA',
              input: const <String, Object?>{
                'format': 'yaml',
                'sourceText': 'schemaVersion: cockpit.test/v2',
              },
            ),
            negotiatedFeatureIds: const <String>[],
          ),
          same(validationDescriptor),
        );
        final catalog = CockpitOperationCatalog(
          <CockpitOperationContract<Object?>>[_runContract()],
        );
        expect(
          () => catalog.admit(
            CockpitOperationInvocation(
              kind: validInvocation.kind,
              rootId: 'rootA',
              idempotencyKey: validInvocation.idempotencyKey,
              input: validInvocation.input,
            ),
            negotiatedFeatureIds: const <String>[],
          ),
          throwsA(isA<CockpitApiException>()),
        );
        expect(
          () => catalog.admit(
            CockpitOperationInvocation(
              kind: validInvocation.kind,
              workspaceId: 'workspaceA',
              input: validInvocation.input,
            ),
            negotiatedFeatureIds: const <String>[],
          ),
          throwsA(isA<CockpitApiException>()),
        );
        expect(
          () =>
              CockpitOperationCatalog(<CockpitOperationContract<Object?>>[
                _runContract(decodedFutureDescriptor),
              ]).admit(
                validInvocation,
                negotiatedFeatureIds: <String>[
                  CockpitFoundationFeature.extensibleResponseEnums.id,
                ],
              ),
          throwsA(
            isA<CockpitApiException>().having(
              (error) => error.error.code,
              'code',
              CockpitErrorCode.upgradeRequired,
            ),
          ),
        );

        final missingRequiredInput = <String, Object?>{...validInvocation.input}
          ..remove('workspaceId');
        expect(
          () => catalog.admit(
            CockpitOperationInvocation(
              kind: validInvocation.kind,
              workspaceId: validInvocation.workspaceId,
              idempotencyKey: validInvocation.idempotencyKey,
              input: missingRequiredInput,
            ),
            negotiatedFeatureIds: const <String>[],
          ),
          throwsA(_invalidAdmissionError()),
        );
        expect(
          () => catalog.admit(
            CockpitOperationInvocation(
              kind: validInvocation.kind,
              workspaceId: validInvocation.workspaceId,
              idempotencyKey: validInvocation.idempotencyKey,
              input: <String, Object?>{
                ...validInvocation.input,
                'unexpected': true,
              },
            ),
            negotiatedFeatureIds: const <String>[],
          ),
          throwsA(_invalidAdmissionError()),
        );
        expect(
          () => catalog.admit(
            CockpitOperationInvocation(
              kind: validInvocation.kind,
              workspaceId: validInvocation.workspaceId,
              idempotencyKey: validInvocation.idempotencyKey,
              input: <String, Object?>{
                ...validInvocation.input,
                'workspaceId': 'workspaceB',
              },
            ),
            negotiatedFeatureIds: const <String>[],
          ),
          throwsA(_invalidAdmissionError(field: 'workspaceId')),
        );
        expect(
          () => catalog.admit(
            CockpitOperationInvocation(
              kind: validInvocation.kind,
              workspaceId: validInvocation.workspaceId,
              idempotencyKey: validInvocation.idempotencyKey,
              input: <String, Object?>{
                ...validInvocation.input,
                'idempotencyKey': 'run:other:1',
              },
            ),
            negotiatedFeatureIds: const <String>[],
          ),
          throwsA(_invalidAdmissionError(field: 'idempotencyKey')),
        );
        final innerFeature = CockpitFoundationFeature.cleanRetry.id;
        expect(
          () => catalog.admit(
            CockpitOperationInvocation(
              kind: validInvocation.kind,
              workspaceId: validInvocation.workspaceId,
              idempotencyKey: validInvocation.idempotencyKey,
              input: _runSubmission(
                requiredFeatures: <String>[innerFeature],
              ).toJson(),
            ),
            negotiatedFeatureIds: const <String>[],
          ),
          throwsA(
            isA<CockpitApiException>()
                .having(
                  (exception) => exception.error.code,
                  'code',
                  CockpitErrorCode.upgradeRequired,
                )
                .having(
                  (exception) => exception.error.redactedDetails,
                  'redactedDetails',
                  <String, Object?>{
                    'missingFeatures': <String>[innerFeature],
                  },
                ),
          ),
        );

        final retryableDriverError = CockpitApiError(
          code: CockpitErrorCode.driverUnavailable,
          category: CockpitErrorCategory.driver,
          message: 'Driver unavailable.',
          retryable: true,
          responsibleLayer: CockpitResponsibleLayer.driver,
        );
        expect(
          CockpitRecoveryResolver.resolve(retryableDriverError, <String>[
            CockpitFoundationFeature.cleanRetry.id,
          ]),
          CockpitRecoveryClass.cleanRetry,
        );
        expect(
          CockpitRecoveryResolver.resolve(
            CockpitApiError(
              code: retryableDriverError.code,
              category: CockpitErrorCategory.invalidInput,
              message: retryableDriverError.message,
              retryable: false,
              responsibleLayer: retryableDriverError.responsibleLayer,
            ),
            <String>[CockpitFoundationFeature.cleanRetry.id],
          ),
          CockpitRecoveryClass.cleanRetry,
        );
        final stableRecoveryWithoutFeatures = <String, CockpitRecoveryClass>{
          CockpitErrorCode.invalidRequest: CockpitRecoveryClass.abort,
          CockpitErrorCode.authenticationRequired:
              CockpitRecoveryClass.userAction,
          CockpitErrorCode.authorizationDenied: CockpitRecoveryClass.userAction,
          CockpitErrorCode.notFound: CockpitRecoveryClass.abort,
          CockpitErrorCode.conflict: CockpitRecoveryClass.abort,
          CockpitErrorCode.upgradeRequired: CockpitRecoveryClass.upgrade,
          CockpitErrorCode.unsupportedOperation: CockpitRecoveryClass.abort,
          CockpitErrorCode.resourceBusy: CockpitRecoveryClass.waitAndRetry,
          CockpitErrorCode.staleReference: CockpitRecoveryClass.reconfigure,
          CockpitErrorCode.transportFailed: CockpitRecoveryClass.abort,
          CockpitErrorCode.driverUnavailable: CockpitRecoveryClass.abort,
          CockpitErrorCode.locatorNotFound: CockpitRecoveryClass.abort,
          CockpitErrorCode.assertionFailed: CockpitRecoveryClass.abort,
          CockpitErrorCode.applicationFailed: CockpitRecoveryClass.abort,
          CockpitErrorCode.evidenceFailed: CockpitRecoveryClass.abort,
          CockpitErrorCode.cancelled: CockpitRecoveryClass.abort,
          CockpitErrorCode.interrupted: CockpitRecoveryClass.abort,
          CockpitErrorCode.internalError: CockpitRecoveryClass.abort,
        };
        for (final entry in stableRecoveryWithoutFeatures.entries) {
          expect(
            CockpitRecoveryResolver.resolve(
              CockpitApiError(
                code: entry.key,
                category: CockpitErrorCategory.environment,
                message: 'Recovery classification fixture.',
                retryable: true,
                responsibleLayer: CockpitResponsibleLayer.client,
              ),
              const <String>[],
            ),
            entry.value,
            reason: entry.key,
          );
        }
        expect(
          CockpitRecoveryResolver.resolve(
            CockpitApiError(
              code: CockpitErrorCode.locatorNotFound,
              category: CockpitErrorCategory.internal,
              message: 'Locator was not found.',
              retryable: false,
              responsibleLayer: CockpitResponsibleLayer.application,
            ),
            <String>[CockpitFoundationFeature.locatorRetry.id],
          ),
          CockpitRecoveryClass.retry,
        );
        expect(
          CockpitRecoveryResolver.resolve(
            CockpitApiError(
              code: 'futureError',
              category: CockpitErrorCategory.resource,
              message: 'Unknown future error.',
              retryable: true,
              responsibleLayer: CockpitResponsibleLayer.provider,
            ),
            <String>[
              CockpitFoundationFeature.cleanRetry.id,
              CockpitFoundationFeature.locatorRetry.id,
            ],
          ),
          CockpitRecoveryClass.abort,
        );

        expect(
          () => CockpitOperationResult(
            operationId: 'operationA',
            kind: 'case.run',
            lifecycle: CockpitOperationLifecycle.running,
            submittedAt: DateTime.utc(2026, 7, 20),
          ),
          throwsFormatException,
        );
        expect(
          () => CockpitRunResource(
            projectId: 'projectA',
            workspaceId: 'workspaceA',
            runId: 'runA',
            documentKind: CockpitRunDocumentKind.testCase,
            documentId: 'caseA',
            sourceSha256: _hash('a'),
            lifecycle: CockpitRunLifecycle.completed,
            outcome: CockpitRunOutcome.passed,
            stability: CockpitRunStability.stable,
            submittedAt: DateTime.utc(2026, 7, 20),
            finishedAt: DateTime.utc(2026, 7, 20, 0, 0, 1),
            caseIds: const <String>['caseA'],
          ),
          throwsFormatException,
        );
        expect(
          () => CockpitArtifactResource(
            artifactId: 'artifactA',
            workspaceId: 'workspaceA',
            runId: 'runA',
            kind: 'evidence.screenshot',
            relativePath: '../outside.png',
            mediaType: 'image/png',
            sizeBytes: 1,
            sha256: _hash('a'),
            createdAt: DateTime.utc(2026, 7, 20),
            downloadUrl: '/api/v2/runs/runA/artifacts/artifactA',
          ),
          throwsFormatException,
        );
        final primaryArtifact = CockpitArtifactReference(
          artifactId: 'primaryArtifact',
          runId: 'runA',
        );
        final warningArtifact = CockpitArtifactReference(
          artifactId: 'warningArtifact',
          runId: 'runA',
        );
        final failureArtifacts = CockpitFailure(
          primary: _errorWithArtifacts(<CockpitArtifactReference>[
            primaryArtifact,
          ]),
          warnings: <CockpitApiWarning>[
            CockpitApiWarning(
              stage: CockpitWarningStage.evidence,
              error: _errorWithArtifacts(<CockpitArtifactReference>[
                warningArtifact,
              ]),
            ),
          ],
        );
        expect(
          failureArtifacts.artifacts.map((artifact) => artifact.artifactId),
          <String>['primaryArtifact', 'warningArtifact'],
        );
        expect(
          () => failureArtifacts.artifacts.add(primaryArtifact),
          throwsUnsupportedError,
        );
        expect(
          () => CockpitRunResource(
            projectId: 'projectA',
            workspaceId: 'workspaceA',
            runId: 'runA',
            documentKind: CockpitRunDocumentKind.testCase,
            documentId: 'caseA',
            sourceSha256: _hash('a'),
            lifecycle: CockpitRunLifecycle.completed,
            outcome: CockpitRunOutcome.failed,
            stability: CockpitRunStability.stable,
            submittedAt: DateTime.utc(2026, 7, 20),
            finishedAt: DateTime.utc(2026, 7, 20, 0, 0, 1),
            caseIds: const <String>['caseA'],
            failure: CockpitFailure(
              primary: _errorWithArtifacts(<CockpitArtifactReference>[
                CockpitArtifactReference(
                  artifactId: 'foreignPrimary',
                  runId: 'runB',
                ),
              ]),
            ),
          ),
          throwsFormatException,
        );
        expect(
          () => CockpitRunEvent(
            eventId: 'eventA',
            sequence: 1,
            timestamp: DateTime.utc(2026, 7, 20),
            kind: 'run.completed',
            entityKind: CockpitRunEventEntityKind.run,
            projectId: 'projectA',
            workspaceId: 'workspaceA',
            runId: 'runA',
            caseId: 'caseA',
            lifecycle: CockpitRunLifecycle.completed,
            outcome: CockpitRunOutcome.failed,
            stability: CockpitRunStability.stable,
            failure: CockpitFailure(
              primary: _errorWithArtifacts(const <CockpitArtifactReference>[]),
              warnings: <CockpitApiWarning>[
                CockpitApiWarning(
                  stage: CockpitWarningStage.cleanup,
                  error: _errorWithArtifacts(<CockpitArtifactReference>[
                    CockpitArtifactReference(
                      artifactId: 'foreignWarning',
                      runId: 'runB',
                    ),
                  ]),
                ),
              ],
            ),
          ),
          throwsFormatException,
        );
        expect(
          () => CockpitServerInfo(
            instanceId: 'supervisorA',
            apiVersion: CockpitApiVersion(major: 2, minor: 0),
            engineVersion: '2.0.0',
            startedAt: DateTime(2026, 7, 20),
          ),
          throwsFormatException,
        );
        expect(
          CockpitRootStateMachine.canTransition(
            CockpitRootState.retired,
            CockpitRootState.active,
          ),
          isFalse,
        );
        expect(
          CockpitWorkspaceStateMachine.canTransition(
            CockpitWorkspaceState.active,
            CockpitWorkspaceState.draining,
          ),
          isTrue,
        );
        expect(
          () => CockpitRunEvent.validateSequence(<CockpitRunEvent>[
            _event(sequence: 1, eventId: 'eventA'),
            _event(sequence: 3, eventId: 'eventB'),
          ]),
          throwsFormatException,
        );
        CockpitRunEvent.validateSequence(<CockpitRunEvent>[
          _event(sequence: 1, eventId: 'eventA'),
          _event(sequence: 3, eventId: 'eventB'),
        ], contiguous: false);
        for (final changedIdentity in <CockpitRunEvent>[
          _event(sequence: 2, eventId: 'eventB', projectId: 'projectB'),
          _event(sequence: 2, eventId: 'eventB', workspaceId: 'workspaceB'),
          _event(sequence: 2, eventId: 'eventB', runId: 'runB'),
        ]) {
          expect(
            () => CockpitRunEvent.validateSequence(<CockpitRunEvent>[
              _event(sequence: 1, eventId: 'eventA'),
              changedIdentity,
            ]),
            throwsFormatException,
          );
        }
      },
    );
  });
}

List<CockpitFeatureDescriptor> _features() => <CockpitFeatureDescriptor>[
  for (final feature in CockpitFoundationFeature.values)
    CockpitFeatureDescriptor(id: feature.id, revision: 1, minimumApiMinor: 0),
];

Map<String, Object?> _jsonObjectWithContainerDepth(int depth) {
  Object? value = <Object?>[];
  for (var currentDepth = 1; currentDepth < depth; currentDepth += 1) {
    value = <Object?>[value];
  }
  return <String, Object?>{'value': value};
}

CockpitOperationDescriptor _runDescriptor() => CockpitOperationDescriptor(
  kind: 'case.run',
  title: 'Run case',
  description: 'Run one standalone case.',
  scope: CockpitOperationScope.workspace,
  mutationClass: CockpitMutationClass.mutating,
  idempotency: CockpitIdempotencyBehavior.required,
  executionMode: CockpitOperationExecutionMode.job,
  defaultTimeoutMs: 1800000,
  maximumTimeoutMs: 21600000,
  safetyEffects: <CockpitEnumValue<CockpitSafetyEffect>>[
    CockpitEnumValue<CockpitSafetyEffect>.known(CockpitSafetyEffect.capture),
  ],
  requestSchemaRef: r'#/$defs/RunSubmission',
  responseSchemaRef: r'#/$defs/RunAccepted',
);

CockpitOperationContract<CockpitRunSubmission> _runContract([
  CockpitOperationDescriptor? descriptor,
]) {
  final operationDescriptor = descriptor ?? _runDescriptor();
  return CockpitOperationContract.runSubmission(
    descriptor: operationDescriptor,
  );
}

CockpitOperationDescriptor _documentValidationDescriptor() =>
    CockpitOperationDescriptor(
      kind: 'case.validate',
      title: 'Validate case',
      description: 'Compile and validate one standalone case document.',
      scope: CockpitOperationScope.workspace,
      mutationClass: CockpitMutationClass.readOnly,
      idempotency: CockpitIdempotencyBehavior.prohibited,
      executionMode: CockpitOperationExecutionMode.synchronous,
      defaultTimeoutMs: 30000,
      maximumTimeoutMs: 300000,
      requestSchemaRef: r'#/$defs/DocumentValidationRequest',
      responseSchemaRef: r'#/$defs/DocumentValidationResult',
    );

CockpitOperationDescriptor _customDescriptor({
  String requestSchemaRef = r'#/$defs/JsonObject',
}) => CockpitOperationDescriptor(
  kind: 'custom.execute',
  title: 'Custom operation',
  description: 'Execute one application-specific operation.',
  scope: CockpitOperationScope.supervisor,
  mutationClass: CockpitMutationClass.readOnly,
  idempotency: CockpitIdempotencyBehavior.prohibited,
  executionMode: CockpitOperationExecutionMode.synchronous,
  defaultTimeoutMs: 30000,
  maximumTimeoutMs: 300000,
  requestSchemaRef: requestSchemaRef,
  responseSchemaRef: r'#/$defs/JsonObject',
);

CockpitRunSubmission _runSubmission({
  Iterable<String> requiredFeatures = const <String>[],
}) => CockpitRunSubmission(
  workspaceId: 'workspaceA',
  source: CockpitInlineCaseSource(
    testCase: _testCase(),
    sourceSha256: _hash('a'),
  ),
  idempotencyKey: CockpitIdempotencyKey('run:login:1'),
  requiredFeatures: requiredFeatures,
);

Matcher _invalidAdmissionError({String? field}) {
  return isA<CockpitApiException>()
      .having(
        (exception) => exception.error.code,
        'code',
        CockpitErrorCode.invalidRequest,
      )
      .having(
        (exception) => exception.error.category,
        'category',
        CockpitErrorCategory.invalidInput,
      )
      .having(
        (exception) => exception.error.responsibleLayer,
        'responsibleLayer',
        CockpitResponsibleLayer.supervisor,
      )
      .having(
        (exception) => exception.error.redactedDetails,
        'redactedDetails',
        <String, Object?>{
          'kind': 'case.run',
          'requestSchemaRef': r'#/$defs/RunSubmission',
          'field': ?field,
        },
      );
}

CockpitTestCase _testCase() => CockpitTestCase(
  id: 'loginCase',
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

CockpitRunEvent _event({
  required int sequence,
  required String eventId,
  String projectId = 'projectA',
  String workspaceId = 'workspaceA',
  String runId = 'runA',
}) => CockpitRunEvent(
  eventId: eventId,
  sequence: sequence,
  timestamp: DateTime.utc(2026, 7, 20),
  kind: 'run.progress',
  entityKind: CockpitRunEventEntityKind.run,
  projectId: projectId,
  workspaceId: workspaceId,
  runId: runId,
  lifecycle: CockpitRunLifecycle.running,
);

CockpitApiError _errorWithArtifacts(
  Iterable<CockpitArtifactReference> artifacts,
) => CockpitApiError(
  code: CockpitErrorCode.applicationFailed,
  category: CockpitErrorCategory.application,
  message: 'Application failed.',
  retryable: false,
  responsibleLayer: CockpitResponsibleLayer.application,
  artifacts: artifacts,
);

Matcher _formatExceptionAt(String path) => isA<FormatException>().having(
  (error) => error.message.toString(),
  'message',
  contains(path),
);

void _expectRoundTrip<T>(T value, T Function(Object? value) decoder) {
  final json = (value as dynamic).toJson() as Map<String, Object?>;
  expect((decoder(json) as dynamic).toJson(), json);
}

String _hash(String character) => List<String>.filled(64, character).join();
