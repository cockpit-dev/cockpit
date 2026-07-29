import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

typedef CockpitDemoAcceptanceProgress =
    void Function(Map<String, Object?> event);

final class CockpitDemoAcceptanceRequest {
  CockpitDemoAcceptanceRequest({
    required this.projectDirectory,
    required this.platform,
    required this.entrypoint,
    required this.suitePath,
    required this.outputRoot,
    required this.discoveryTimeout,
    required this.launchTimeout,
    required this.runTimeout,
    this.rootDirectory,
    this.deviceId,
    this.wdaUrl,
    this.visualProfile,
    this.stopDaemon = false,
    this.requireRecording = false,
    this.requireNativeLocator = false,
  }) {
    if (!const <String>{
      'android',
      'ios',
      'linux',
      'macos',
      'web',
      'windows',
    }.contains(platform)) {
      throw FormatException('Unsupported acceptance platform: $platform.');
    }
    if (discoveryTimeout <= Duration.zero ||
        launchTimeout <= Duration.zero ||
        runTimeout <= Duration.zero) {
      throw const FormatException('Acceptance timeouts must be positive.');
    }
    _requireRelativePath(entrypoint, 'entrypoint');
    _requireRelativePath(suitePath, 'suitePath');
  }

  final String projectDirectory;
  final String? rootDirectory;
  final String platform;
  final String? deviceId;
  final String? wdaUrl;
  final String? visualProfile;
  final String entrypoint;
  final String suitePath;
  final String outputRoot;
  final Duration discoveryTimeout;
  final Duration launchTimeout;
  final Duration runTimeout;
  final bool stopDaemon;
  final bool requireRecording;
  final bool requireNativeLocator;
}

final class CockpitDemoAcceptanceResult {
  const CockpitDemoAcceptanceResult({
    required this.success,
    required this.stage,
    required this.platform,
    required this.deviceId,
    required this.outputDirectory,
    required this.eventCount,
    required this.artifactCount,
    required this.cleanupFailures,
    this.rootId,
    this.workspaceId,
    this.targetId,
    this.nativeTargetId,
    this.runId,
    this.outcome,
    this.stability,
    this.counts,
    this.recordingSupported,
    this.mixedPlaneSupported,
    this.visualRegressionSupported,
    this.locationTravelSupported,
    this.nativeBlackBoxSupported,
    this.nativeLocatorSupported,
    this.systemControlAdapter,
    this.recordingLimitations = const <String>[],
    this.failure,
  });

  final bool success;
  final String stage;
  final String platform;
  final String? deviceId;
  final String outputDirectory;
  final String? rootId;
  final String? workspaceId;
  final String? targetId;
  final String? nativeTargetId;
  final String? runId;
  final String? outcome;
  final String? stability;
  final int eventCount;
  final int artifactCount;
  final Map<String, Object?>? counts;
  final bool? recordingSupported;
  final bool? mixedPlaneSupported;
  final bool? visualRegressionSupported;
  final bool? locationTravelSupported;
  final bool? nativeBlackBoxSupported;
  final bool? nativeLocatorSupported;
  final String? systemControlAdapter;
  final List<String> recordingLimitations;
  final Map<String, Object?>? failure;
  final List<Map<String, Object?>> cleanupFailures;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 'cockpit.demo.acceptance/v2',
    'success': success,
    'stage': stage,
    'platform': platform,
    if (deviceId != null) 'deviceId': deviceId,
    'outputDirectory': outputDirectory,
    if (rootId != null) 'rootId': rootId,
    if (workspaceId != null) 'workspaceId': workspaceId,
    if (targetId != null) 'targetId': targetId,
    if (nativeTargetId != null) 'nativeTargetId': nativeTargetId,
    if (runId != null) 'runId': runId,
    if (outcome != null) 'outcome': outcome,
    if (stability != null) 'stability': stability,
    'eventCount': eventCount,
    'artifactCount': artifactCount,
    if (counts != null) 'counts': counts,
    if (recordingSupported != null) 'recordingSupported': recordingSupported,
    if (mixedPlaneSupported != null) 'mixedPlaneSupported': mixedPlaneSupported,
    if (visualRegressionSupported != null)
      'visualRegressionSupported': visualRegressionSupported,
    if (locationTravelSupported != null)
      'locationTravelSupported': locationTravelSupported,
    if (nativeBlackBoxSupported != null)
      'nativeBlackBoxSupported': nativeBlackBoxSupported,
    if (nativeLocatorSupported != null)
      'nativeLocatorSupported': nativeLocatorSupported,
    if (systemControlAdapter != null)
      'systemControlAdapter': systemControlAdapter,
    if (recordingLimitations.isNotEmpty)
      'recordingLimitations': recordingLimitations,
    if (failure != null) 'failure': failure,
    'cleanupFailures': cleanupFailures,
  };
}

final class CockpitDemoAcceptanceRunner {
  const CockpitDemoAcceptanceRunner({this.progress});

  final CockpitDemoAcceptanceProgress? progress;

  Future<CockpitDemoAcceptanceResult> run(
    CockpitDemoAcceptanceRequest request,
  ) async {
    final projectDirectory = await _canonicalDirectory(
      request.projectDirectory,
    );
    final requestedRoot = request.rootDirectory == null
        ? projectDirectory
        : await _canonicalDirectory(request.rootDirectory!);
    if (!_contains(requestedRoot, projectDirectory)) {
      throw const FormatException('The project is outside the requested root.');
    }
    await _workspaceFile(projectDirectory, request.entrypoint);
    final suiteFile = await _workspaceFile(projectDirectory, request.suitePath);
    final invocationId = _invocationId(request.platform);
    final outputRoot = p.normalize(
      p.isAbsolute(request.outputRoot)
          ? request.outputRoot
          : p.join(projectDirectory, request.outputRoot),
    );
    final outputDirectory = p.join(outputRoot, invocationId);
    await Directory(outputDirectory).create(recursive: true);

    CockpitSupervisorApiClient? api;
    CockpitRootResource? root;
    CockpitWorkspaceResource? workspace;
    CockpitAutomationTargetResource? target;
    CockpitAutomationTargetResource? nativeTarget;
    CockpitRunResource? run;
    CockpitTestSuiteReport? report;
    CockpitTestSuite? validatedSuite;
    CockpitTestSuite? effectiveSuite;
    CockpitRecordingCapabilities? recordingCapabilities;
    bool? unattendedRecordingSupported;
    bool? mixedPlaneSupported;
    bool? visualRegressionSupported;
    bool? locationTravelSupported;
    bool? nativeBlackBoxSupported;
    bool? nativeLocatorSupported;
    _CockpitDemoVisualBaseline? visualBaseline;
    String? systemControlAdapter;
    String? deviceId;
    String? appId;
    String? platformAppId;
    String? runId;
    IOSink? eventSink;
    var launched = false;
    var primaryPassed = false;
    var eventCount = 0;
    var stage = 'bootstrap';
    Map<String, Object?>? failure;
    final artifacts = <CockpitArtifactResource>[];
    final downloadedArtifacts = <Map<String, Object?>>[];
    final cleanupFailures = <Map<String, Object?>>[];

    void advance(String next, String message) {
      stage = next;
      progress?.call(<String, Object?>{
        'stage': next,
        'message': message,
        'platform': request.platform,
        'runId': ?runId,
      });
    }

    try {
      advance('bootstrap', 'Connecting to the Cockpit Supervisor.');
      api = await createCockpitSupervisorApiClient(
        requiredFeatures: const <String>[
          'automationTargets',
          'digestCheckedArtifacts',
          'durableRunEvents',
          'suiteRuns',
        ],
      );
      await api.server();

      advance('workspace', 'Resolving root and workspace identity.');
      root = await _resolveRoot(api, projectDirectory, requestedRoot);
      workspace = await _resolveWorkspace(api, root.rootId, projectDirectory);

      advance('documents', 'Indexing and validating the acceptance suite.');
      final documents = await api.documents(workspace.workspaceId);
      final entrypointDocument = _requireDocument(
        documents,
        request.entrypoint,
        CockpitIndexedDocumentKind.source,
      );
      final suiteDocument = _requireDocument(
        documents,
        request.suitePath,
        CockpitIndexedDocumentKind.suite,
      );
      final validation = await api.validateCaseDocument(
        workspace.workspaceId,
        CockpitDocumentValidationRequest(
          format: _documentFormat(request.suitePath),
          sourceText: await suiteFile.readAsString(),
          relativePath: _protocolPath(request.suitePath),
        ),
      );
      if (!validation.valid ||
          validation.document is! CockpitTestSuite ||
          validation.sourceSha256 != suiteDocument.sha256 ||
          validation.document!.id != suiteDocument.authoredId) {
        throw FormatException(
          'Acceptance suite validation failed: '
          '${validation.diagnostics.map((item) => item.message).join('; ')}',
        );
      }
      validatedSuite = validation.document! as CockpitTestSuite;
      final nativeBlackBoxTemplate = await _loadAcceptanceCase(
        projectDirectory,
        'e2e/cases/native_black_box.case.yaml',
        'demoNativeBlackBox',
      );
      final mixedPlaneEvidenceTemplate = await _loadAcceptanceCase(
        projectDirectory,
        'e2e/cases/mixed_plane_black_box_evidence.case.yaml',
        'demoMixedPlaneBlackBox',
      );
      final nativeBlackBoxEvidenceTemplate = await _loadAcceptanceCase(
        projectDirectory,
        'e2e/cases/native_black_box_evidence.case.yaml',
        'demoNativeBlackBoxEvidence',
      );
      final recordingLifecycleTemplate = await _loadAcceptanceCase(
        projectDirectory,
        'e2e/cases/recording_lifecycle.case.yaml',
        'demoRecordingLifecycle',
      );

      advance('target', 'Discovering and registering the Flutter target.');
      final discoveredDevice = await _resolveDevice(api, request);
      deviceId = discoveredDevice.id;
      final launchMode = cockpitDemoLaunchModeForPlatform(request.platform);
      target = await _resolveTarget(
        api: api,
        workspaceId: workspace.workspaceId,
        platform: request.platform,
        deviceId: deviceId,
        mode: launchMode,
        entrypointDocument: entrypointDocument,
        wdaUrl: request.wdaUrl,
        registrationTimeout: request.discoveryTimeout,
      );

      advance('launch', 'Launching the target in $launchMode mode.');
      final launch = await _operation(
        api,
        CockpitOperationInvocation(
          kind: 'target.launch',
          workspaceId: workspace.workspaceId,
          idempotencyKey: CockpitIdempotencyKey('$invocationId-launch'),
          deadline: DateTime.now().toUtc().add(
            request.launchTimeout + const Duration(seconds: 30),
          ),
          input: <String, Object?>{
            'targetId': target.targetId,
            'mode': launchMode,
            'launchTimeoutMs': request.launchTimeout.inMilliseconds,
            'launchConfiguration': <String, Object?>{
              'dartDefines': <String>[
                'COCKPIT_DEMO_ACCEPTANCE=true',
                'COCKPIT_DEMO_ACCEPTANCE_PLATFORM=${request.platform}',
              ],
              'dartDefineFromFiles': const <String>['e2e/launch.ci.json'],
              'flutterArgs': const <String>['--no-pub'],
              'environment': <String, String>{
                'COCKPIT_ACCEPTANCE_PLATFORM': request.platform,
                'COCKPIT_ACCEPTANCE_INVOCATION': invocationId,
              },
            },
          },
        ),
      );
      launched = true;
      appId = launch.output?['appId'] as String?;
      platformAppId = launch.output?['platformAppId'] as String?;
      final sessionId = launch.output?['sessionId'];
      if (sessionId is! String || sessionId.isEmpty) {
        throw const FormatException(
          'Target launch returned no remote session identity.',
        );
      }
      final status = await _operation(
        api,
        CockpitOperationInvocation(
          kind: 'session.remote.status',
          workspaceId: workspace.workspaceId,
          deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
          input: <String, Object?>{
            'sessionId': sessionId,
            'profile': 'minimal',
          },
        ),
      );
      final statusOutput = status.output;
      if (statusOutput == null) {
        throw const FormatException('Remote session status is unavailable.');
      }
      final rawRecordingCapabilities = statusOutput['recordingCapabilities'];
      if (rawRecordingCapabilities is! Map<Object?, Object?>) {
        throw const FormatException(
          'Remote session recording capabilities are unavailable.',
        );
      }
      recordingCapabilities = CockpitRecordingCapabilities.fromJson(
        Map<String, Object?>.from(rawRecordingCapabilities),
      );
      advance(
        'capabilities',
        'Inspecting the secondary black-box system control plane.',
      );
      final inspectedTarget = await _operation(
        api,
        CockpitOperationInvocation(
          kind: 'target.inspect',
          workspaceId: workspace.workspaceId,
          deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
          input: <String, Object?>{
            'targetId': target.targetId,
            'profile': 'minimal',
          },
        ),
      );
      final rawSystemControl = inspectedTarget.output?['systemControl'];
      final systemControlProfile = rawSystemControl is Map<Object?, Object?>
          ? Map<String, Object?>.from(rawSystemControl)
          : null;
      final rawAvailableActions = systemControlProfile?['availableActions'];
      if (systemControlProfile == null ||
          rawAvailableActions is! List<Object?> ||
          !rawAvailableActions.every((action) => action is String)) {
        throw const FormatException(
          'System control capabilities are unavailable.',
        );
      }
      final availableSystemActions = rawAvailableActions.cast<String>();
      final recordingSupport = _recordingSupport(
        recordingCapabilities: recordingCapabilities,
        availableSystemActions: availableSystemActions,
      );
      unattendedRecordingSupported = recordingSupport.supported;
      if (request.requireRecording && !unattendedRecordingSupported) {
        throw FormatException(
          'The ${request.platform} test target does not support unattended '
          'recording through either its application or system driver. '
          'Application limitations: '
          '${recordingCapabilities.recordingLimitations.join('; ')}; '
          'system actions: $availableSystemActions',
        );
      }
      systemControlAdapter = systemControlProfile['adapter'] as String?;
      mixedPlaneSupported =
          request.platform != 'web' &&
          availableSystemActions.contains('recoverToApp');
      visualBaseline = _visualBaselineForTarget(
        platform: request.platform,
        device: discoveredDevice,
        profile: request.visualProfile,
      );
      visualRegressionSupported = visualBaseline != null;
      locationTravelSupported = availableSystemActions.contains('setLocation');
      final nativeLocatorAdvertised = const <String>{
        'readUiTree',
        'tap',
      }.every(availableSystemActions.contains);
      nativeBlackBoxSupported =
          request.platform != 'web' &&
          platformAppId != null &&
          platformAppId.isNotEmpty &&
          const <String>{
            'recoverToApp',
            'captureScreenshot',
          }.every(availableSystemActions.contains);
      if (request.platform != 'web' && !mixedPlaneSupported) {
        throw FormatException(
          'The ${request.platform} release target does not advertise '
          'recoverToApp for mixed-plane black-box validation.',
        );
      }
      if (request.platform != 'web' && !nativeBlackBoxSupported) {
        throw FormatException(
          'The ${request.platform} release target cannot run independent '
          'native black-box validation. platformAppId=$platformAppId; '
          'availableActions=$availableSystemActions',
        );
      }
      if (nativeBlackBoxSupported) {
        nativeTarget = await _resolveNativeTarget(
          api: api,
          workspaceId: workspace.workspaceId,
          platform: request.platform,
          deviceId: deviceId,
          appId: platformAppId,
          wdaUrl: request.wdaUrl,
          registrationTimeout: request.discoveryTimeout,
        );
      }
      if (request.platform == 'macos') {
        await _dismissDevelopmentSystemDialogs(
          api: api,
          workspaceId: workspace.workspaceId,
          targetId: target.targetId,
        );
      }
      nativeLocatorSupported =
          nativeLocatorAdvertised &&
          await _probeNativeLocator(
            api: api,
            workspaceId: workspace.workspaceId,
            targetId: target.targetId,
            probeId: invocationId,
          );
      if (request.requireNativeLocator && !nativeLocatorSupported) {
        throw FormatException(
          'The ${request.platform} release target did not prove native '
          'locator control. Inspect the target systemControl profile and '
          'platform driver environment before retrying.',
        );
      }
      effectiveSuite = _suiteForRuntime(
        validatedSuite,
        recordingCapabilities: recordingCapabilities,
        systemControlProfile: systemControlProfile,
        mixedPlaneSupported: mixedPlaneSupported,
        visualBaseline: visualBaseline?.path,
        visualProfile: visualBaseline?.profile,
        visualCaptureProfile: visualBaseline?.captureProfile,
        taskTitle: 'Cockpit $invocationId',
        launchConfigurationLabel: _launchConfigurationLabel(
          platform: request.platform,
          invocationId: invocationId,
        ),
        mixedPlaneEvidenceTemplate: mixedPlaneEvidenceTemplate,
        nativeBlackBoxTemplate: nativeBlackBoxTemplate,
        nativeBlackBoxEvidenceTemplate: nativeBlackBoxEvidenceTemplate,
        recordingLifecycleTemplate: recordingLifecycleTemplate,
        nativeTargetId: nativeTarget?.targetId,
        platformAppId: platformAppId,
        nativeLocatorSupported: nativeLocatorSupported,
      );

      advance('run', 'Submitting the indexed regression suite.');
      final accepted = await api.submitRun(
        CockpitRunSubmission(
          workspaceId: workspace.workspaceId,
          targetId: target.targetId,
          source: CockpitInlineSuiteSource(
            suite: effectiveSuite,
            sourceSha256: _canonicalSha256(effectiveSuite.toJson()),
          ),
          idempotencyKey: CockpitIdempotencyKey('$invocationId-run'),
          timeoutMs: request.runTimeout.inMilliseconds,
          requiredFeatures: const <String>[
            'digestCheckedArtifacts',
            'durableRunEvents',
            'suiteRuns',
          ],
        ),
      );
      runId = accepted.runId;
      eventSink = File(p.join(outputDirectory, 'events.jsonl')).openWrite();
      eventCount = await _consumeEvents(
        api: api,
        runId: runId,
        deadline: DateTime.now().toUtc().add(
          request.runTimeout + const Duration(seconds: 30),
        ),
        sink: eventSink,
        progress: progress,
      );
      await eventSink.flush();
      await eventSink.close();
      eventSink = null;

      advance('report', 'Reading the terminal run and canonical report.');
      run = await api.run(runId);
      report = await api.report(runId);
      await _writeJson(File(p.join(outputDirectory, 'run.json')), run.toJson());
      await _writeJson(
        File(p.join(outputDirectory, 'report.json')),
        report.toJson(),
      );

      advance('artifacts', 'Downloading and verifying all run artifacts.');
      artifacts.addAll(await api.artifacts(runId));
      for (final artifact in artifacts) {
        final destination = _artifactDestination(outputDirectory, artifact);
        final receipt = await api.downloadArtifactToFile(
          artifact: artifact,
          destination: destination,
        );
        downloadedArtifacts.add(<String, Object?>{
          ...artifact.toJson(),
          'localPath': p.relative(receipt.file.path, from: outputDirectory),
        });
      }
      await _writeJson(
        File(p.join(outputDirectory, 'artifacts.json')),
        <String, Object?>{'items': downloadedArtifacts},
      );
      _verifyAcceptanceReport(
        report,
        effectiveSuite,
        recordingSupported: unattendedRecordingSupported,
        visualRegressionSupported: visualRegressionSupported,
        locationTravelSupported: locationTravelSupported,
        nativeBlackBoxSupported: nativeBlackBoxSupported,
        platform: request.platform,
      );
      await _verifyOfflineReportBundle(
        outputDirectory: outputDirectory,
        report: report,
        recordingSupported: unattendedRecordingSupported,
        visualRegressionSupported: visualRegressionSupported,
        locationTravelSupported: locationTravelSupported,
        nativeBlackBoxSupported: nativeBlackBoxSupported,
        nativeLocatorSupported: nativeLocatorSupported,
        nativeTargetId: nativeTarget?.targetId,
        platform: request.platform,
      );
      primaryPassed =
          run.outcome == CockpitRunOutcome.passed &&
          report.outcome == CockpitRunOutcome.passed &&
          report.complete;
      if (!primaryPassed) {
        failure =
            run.failure?.toJson() ??
            report.failure?.toJson() ??
            <String, Object?>{
              'code': 'acceptanceFailed',
              'message': 'The regression suite did not pass.',
            };
      }
      advance('completed', 'Acceptance execution reached terminal state.');
    } on Object catch (error) {
      failure = _failure(error, stage);
      progress?.call(<String, Object?>{
        'stage': 'failed',
        'failedStage': stage,
        'message': failure['message'],
        'runId': ?runId,
      });
    } finally {
      await _closeEventSink(eventSink, cleanupFailures);
      if (api != null && runId != null && failure != null) {
        await _cancelActiveRun(api, runId, invocationId, cleanupFailures);
      }
      if (api != null && workspace != null && target != null && launched) {
        await _stopTargetApp(
          api: api,
          workspaceId: workspace.workspaceId,
          targetId: target.targetId,
          appId: appId,
          idempotencyKey: '$invocationId-stop',
          failures: cleanupFailures,
        );
      }
      if (api != null && request.stopDaemon) {
        try {
          await api.lifecycle.stop(mode: CockpitDaemonShutdownMode.drain);
        } on Object catch (error) {
          cleanupFailures.add(_failure(error, 'daemonStop'));
        }
      }
    }

    final result = CockpitDemoAcceptanceResult(
      success: primaryPassed && failure == null && cleanupFailures.isEmpty,
      stage: stage,
      platform: request.platform,
      deviceId: deviceId,
      outputDirectory: outputDirectory,
      rootId: root?.rootId,
      workspaceId: workspace?.workspaceId,
      targetId: target?.targetId,
      nativeTargetId: nativeTarget?.targetId,
      runId: runId,
      outcome: run?.outcome?.name,
      stability: run?.stability?.name,
      eventCount: eventCount,
      artifactCount: artifacts.length,
      counts: report?.counts.toJson(),
      recordingSupported: unattendedRecordingSupported,
      mixedPlaneSupported: mixedPlaneSupported,
      visualRegressionSupported: visualRegressionSupported,
      locationTravelSupported: locationTravelSupported,
      nativeBlackBoxSupported: nativeBlackBoxSupported,
      nativeLocatorSupported: nativeLocatorSupported,
      systemControlAdapter: systemControlAdapter,
      recordingLimitations:
          recordingCapabilities?.recordingLimitations ?? const <String>[],
      failure: failure,
      cleanupFailures: List<Map<String, Object?>>.unmodifiable(cleanupFailures),
    );
    await _writeJson(
      File(p.join(outputDirectory, 'summary.json')),
      <String, Object?>{
        ...result.toJson(),
        if (run != null) 'run': run.toJson(),
        if (report != null) 'report': report.toJson(),
        'artifacts': downloadedArtifacts,
      },
    );
    return result;
  }
}

CockpitTestSuite _suiteForRuntime(
  CockpitTestSuite suite, {
  required CockpitRecordingCapabilities recordingCapabilities,
  required Map<String, Object?> systemControlProfile,
  required bool mixedPlaneSupported,
  required String? visualBaseline,
  required String? visualProfile,
  required String? visualCaptureProfile,
  required String taskTitle,
  required String launchConfigurationLabel,
  required CockpitTestCase mixedPlaneEvidenceTemplate,
  required CockpitTestCase nativeBlackBoxTemplate,
  required CockpitTestCase nativeBlackBoxEvidenceTemplate,
  required CockpitTestCase recordingLifecycleTemplate,
  required String? nativeTargetId,
  required String? platformAppId,
  required bool nativeLocatorSupported,
}) {
  final json = Map<String, Object?>.from(suite.toJson());
  final rawCases = json['cases'];
  if (rawCases is! List<Object?>) {
    throw const FormatException('Acceptance suite cases are unavailable.');
  }
  final platform = systemControlProfile['platform'] as String;
  final availableSystemActions =
      (systemControlProfile['availableActions']! as List<Object?>)
          .cast<String>();
  final visualRegressionSupported = visualBaseline != null;
  final locationTravelSupported = availableSystemActions.contains(
    'setLocation',
  );
  final nativeBlackBoxSupported =
      nativeTargetId != null && platformAppId != null;
  final recordingSupport = _recordingSupport(
    recordingCapabilities: recordingCapabilities,
    availableSystemActions: availableSystemActions,
  );
  var taskInputBound = false;
  var visualInputBound = false;
  var nativeBlackBoxBound = false;
  var recordingLifecycleBound = false;
  json['cases'] = <Object?>[
    for (final rawCase in rawCases)
      if (rawCase case final Map<Object?, Object?> values)
        () {
          final entry = <String, Object?>{
            for (final value in values.entries)
              if (value.key is String) value.key! as String: value.value,
          };
          if (entry['id'] == 'taskEditorValidation') {
            final rawInputs = entry['inputs'];
            entry['inputs'] = <String, Object?>{
              if (rawInputs is Map<Object?, Object?>)
                for (final input in rawInputs.entries)
                  if (input.key is String) input.key! as String: input.value,
              'taskTitle': taskTitle,
              'launchConfigurationLabel': launchConfigurationLabel,
            };
            taskInputBound = true;
          }
          if (entry['id'] == 'visualRegression' && visualBaseline != null) {
            final rawInputs = entry['inputs'];
            entry['inputs'] = <String, Object?>{
              if (rawInputs is Map<Object?, Object?>)
                for (final input in rawInputs.entries)
                  if (input.key is String) input.key! as String: input.value,
              'visualBaseline': visualBaseline,
              'visualCaptureOptions': <String, Object?>{
                'profile': visualCaptureProfile,
                'allowFallback': false,
              },
            };
            visualInputBound = true;
          }
          if (entry['id'] == 'visualRegression' && !visualRegressionSupported) {
            entry['source'] = <String, Object?>{
              'kind': 'file',
              'relativePath': 'e2e/cases/visual_capture_fallback.case.yaml',
              'caseId': 'demoVisualCaptureFallback',
            };
          }
          if (entry['id'] == 'mixedPlaneBlackBox' &&
              mixedPlaneSupported &&
              !nativeLocatorSupported) {
            entry['source'] = <String, Object?>{
              'kind': 'inline',
              'case': mixedPlaneEvidenceTemplate.toJson(),
            };
          }
          if (entry['id'] == 'nativeBlackBox' && nativeBlackBoxSupported) {
            final template = nativeLocatorSupported
                ? nativeBlackBoxTemplate
                : nativeBlackBoxEvidenceTemplate;
            final caseJson = Map<String, Object?>.from(template.toJson());
            final rawTarget = caseJson['target'];
            if (rawTarget is! Map<Object?, Object?>) {
              throw const FormatException(
                'Native black-box case target is unavailable.',
              );
            }
            caseJson['target'] = <String, Object?>{
              for (final value in rawTarget.entries)
                if (value.key is String) value.key! as String: value.value,
              'platform': platform,
              'targetKind': 'nativeApp',
              'plane': 'native',
              'appId': platformAppId,
            };
            entry['source'] = <String, Object?>{
              'kind': 'inline',
              'case': caseJson,
            };
            entry['targetIds'] = <String>[nativeTargetId];
            nativeBlackBoxBound = true;
          }
          if (entry['id'] == 'recordingLifecycle' &&
              recordingSupport.supported) {
            entry['source'] = <String, Object?>{
              'kind': 'inline',
              'case': _recordingCaseForRuntime(
                recordingLifecycleTemplate,
                useSystemDriver: recordingSupport.system,
              ).toJson(),
            };
            recordingLifecycleBound = true;
          }
          return entry;
        }()
      else
        throw const FormatException('Acceptance suite case is malformed.'),
  ];
  if (!taskInputBound) {
    throw const FormatException(
      'Acceptance suite does not declare taskEditorValidation.',
    );
  }
  if (visualRegressionSupported && !visualInputBound) {
    throw const FormatException(
      'Acceptance suite does not declare visualRegression.',
    );
  }
  if (nativeBlackBoxSupported && !nativeBlackBoxBound) {
    throw const FormatException(
      'Acceptance suite does not declare nativeBlackBox.',
    );
  }
  if (recordingSupport.supported && !recordingLifecycleBound) {
    throw const FormatException(
      'Acceptance suite does not declare recordingLifecycle.',
    );
  }
  final excludedTags = <String>{...suite.excludeTags};
  final recordingSupported = recordingSupport.supported;
  if (!recordingSupported) excludedTags.add('requires-recording');
  if (!mixedPlaneSupported) excludedTags.add('requires-system-control');
  if (!nativeBlackBoxSupported) {
    excludedTags.add('requires-native-black-box');
  }
  if (!locationTravelSupported) {
    excludedTags.add('requires-location-travel');
  }
  if (excludedTags.isEmpty) {
    json.remove('excludeTags');
  } else {
    json['excludeTags'] = excludedTags.toList(growable: false)..sort();
  }
  json['x-runtime-recording'] = <String, Object?>{
    'executed': recordingSupported,
    'implementation': !recordingSupported
        ? 'unavailable'
        : recordingSupport.system
        ? 'system'
        : 'application',
    'stepPlane': recordingSupport.plane.name,
    'applicationSupported': recordingSupport.remote,
    'systemSupported': recordingSupport.system,
    ...recordingCapabilities.toJson(),
  };
  json['x-runtime-system-control'] = <String, Object?>{
    'executed': mixedPlaneSupported,
    'platform': systemControlProfile['platform'],
    'adapter': systemControlProfile['adapter'],
    'availableActions': systemControlProfile['availableActions'],
  };
  json['x-runtime-capability-coverage'] = <String, Object?>{
    'visualRegression': <String, Object?>{
      'supported': visualRegressionSupported,
      'execution': visualRegressionSupported
          ? 'baselineAssertion'
          : 'semanticCaptureFallback',
      'baseline': ?visualBaseline,
      'profile': ?visualProfile,
      'captureProfile': ?visualCaptureProfile,
    },
    'locationTravel': <String, Object?>{'supported': locationTravelSupported},
    'mixedPlane': <String, Object?>{
      'supported': mixedPlaneSupported,
      'locatorValidation': nativeLocatorSupported,
      'execution': nativeLocatorSupported
          ? 'nativeLocatorActionAssertionEvidence'
          : 'nativeControlEvidenceFallback',
    },
    'nativeBlackBox': <String, Object?>{
      'supported': nativeBlackBoxSupported,
      'targetId': ?nativeTargetId,
      'locatorValidation': nativeLocatorSupported,
      'execution': nativeLocatorSupported
          ? 'nativeLocatorActionAssertionEvidence'
          : 'nativeControlEvidenceFallback',
    },
    'recording': <String, Object?>{
      'supported': recordingSupported,
      'implementation': !recordingSupported
          ? 'unavailable'
          : recordingSupport.system
          ? 'system'
          : 'application',
      'stepPlane': recordingSupport.plane.name,
    },
  };
  return CockpitTestSuite.fromJson(json);
}

typedef _CockpitDemoVisualBaseline = ({
  String profile,
  String path,
  String captureProfile,
});

_CockpitDemoVisualBaseline? _visualBaselineForTarget({
  required String platform,
  required _CockpitDemoDiscoveredTarget device,
  required String? profile,
}) {
  if (profile == null) return null;
  final baseline = switch ((platform, profile)) {
    ('android', 'pixel-7-api-34-1080x2400')
        when device.sdk?.contains('(API 34)') ?? false =>
      (
        profile: profile,
        path: 'e2e/baselines/android/settings.png',
        captureProfile: 'nativePreferred',
      ),
    ('ios', 'iphone-16-pro-1206x2622') when device.name == 'iPhone 16 Pro' => (
      profile: profile,
      path: 'e2e/baselines/ios/settings.png',
      captureProfile: 'nativePreferred',
    ),
    ('linux', 'linux-1280x720') => (
      profile: profile,
      path: 'e2e/baselines/linux/settings.png',
      captureProfile: 'flutterPreferred',
    ),
    ('macos', 'macos-800x600') => (
      profile: profile,
      path: 'e2e/baselines/macos/settings.png',
      captureProfile: 'flutterPreferred',
    ),
    ('windows', 'windows-1028x681') => (
      profile: profile,
      path: 'e2e/baselines/windows/settings.png',
      captureProfile: 'flutterPreferred',
    ),
    _ => null,
  };
  if (baseline == null) {
    throw FormatException(
      'Visual profile $profile does not match the discovered $platform '
      'target ${device.name} (${device.sdk ?? 'unknown SDK'}).',
    );
  }
  return baseline;
}

String _launchConfigurationLabel({
  required String platform,
  required String invocationId,
}) => <String>[
  'Cockpit launch configuration',
  'platform=$platform',
  'defineFile=ci',
  if (const <String>{
    'linux',
    'macos',
    'windows',
  }.contains(platform)) ...<String>[
    'environmentPlatform=$platform',
    'environmentInvocation=$invocationId',
  ],
].join(' ');

typedef _CockpitDemoRecordingSupport = ({
  bool supported,
  bool system,
  bool remote,
  CockpitTestPlane plane,
});

_CockpitDemoRecordingSupport _recordingSupport({
  required CockpitRecordingCapabilities recordingCapabilities,
  required List<String> availableSystemActions,
}) {
  final remote = _supportsUnattendedRecording(recordingCapabilities);
  final system = const <String>{
    'startRecording',
    'stopRecording',
  }.every(availableSystemActions.contains);
  return (
    supported: system || remote,
    system: system,
    remote: remote,
    plane: system ? CockpitTestPlane.native : CockpitTestPlane.semantic,
  );
}

CockpitTestCase _recordingCaseForRuntime(
  CockpitTestCase template, {
  required bool useSystemDriver,
}) {
  Object? bind(Object? value) {
    if (value is List<Object?>) {
      return value.map(bind).toList(growable: false);
    }
    if (value is! Map<Object?, Object?>) return value;
    final result = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key! as String: bind(entry.value),
    };
    if (result.containsKey('startRecording') ||
        result.containsKey('stopRecording')) {
      result['plane'] = useSystemDriver ? 'native' : 'semantic';
    }
    final rawStart = result['startRecording'];
    if (rawStart is Map<Object?, Object?>) {
      final start = Map<String, Object?>.from(rawStart);
      if (useSystemDriver) {
        start['layer'] = 'system';
      } else {
        start.remove('layer');
      }
      result['startRecording'] = start;
    }
    return result;
  }

  return CockpitTestCase.fromJson(
    Map<String, Object?>.from(
      bind(template.toJson())! as Map<Object?, Object?>,
    ),
  );
}

bool _supportsUnattendedRecording(CockpitRecordingCapabilities capabilities) {
  if (!capabilities.supportsNativeRecording) return false;
  return !capabilities.recordingLimitations.any((limitation) {
    final normalized = limitation.toLowerCase();
    return normalized.contains('consent') ||
        normalized.contains('permission') ||
        normalized.contains('unavailable');
  });
}

void _verifyAcceptanceReport(
  CockpitTestSuiteReport report,
  CockpitTestSuite effectiveSuite, {
  required bool recordingSupported,
  required bool visualRegressionSupported,
  required bool locationTravelSupported,
  required bool nativeBlackBoxSupported,
  required String platform,
}) {
  if (!report.complete ||
      report.definition.id != effectiveSuite.id ||
      _canonicalJson(report.definition.toJson()) !=
          _canonicalJson(effectiveSuite.toJson()) ||
      report.execution.maxConcurrency != 1 ||
      report.execution.failFast ||
      report.definition.fixtures.length != 2 ||
      report.matrixAxes['variant']?.length != 2) {
    throw const FormatException(
      'Acceptance report does not preserve the complex suite definition.',
    );
  }
  final expected = <String, (int, CockpitRunOutcome)>{
    'taskEditorValidation': (1, CockpitRunOutcome.passed),
    'settingsNavigation': (1, CockpitRunOutcome.passed),
    'visualRegression': (1, CockpitRunOutcome.passed),
    'commandGestureCoverage': (1, CockpitRunOutcome.passed),
    'commandSemanticCoverage': (1, CockpitRunOutcome.passed),
    'mixedPlaneBlackBox': (
      1,
      platform == 'web' ? CockpitRunOutcome.skipped : CockpitRunOutcome.passed,
    ),
    'locationTravel': (
      1,
      locationTravelSupported
          ? CockpitRunOutcome.passed
          : CockpitRunOutcome.skipped,
    ),
    'matrixEvidence': (2, CockpitRunOutcome.passed),
    'nativeBlackBox': (
      1,
      nativeBlackBoxSupported
          ? CockpitRunOutcome.passed
          : CockpitRunOutcome.skipped,
    ),
    'recordingLifecycle': (
      1,
      recordingSupported ? CockpitRunOutcome.passed : CockpitRunOutcome.skipped,
    ),
  };
  for (final entry in expected.entries) {
    final rows = report.cases
        .where((testCase) => testCase.entryId == entry.key)
        .toList(growable: false);
    if (rows.length != entry.value.$1 ||
        rows.any((row) => row.outcome != entry.value.$2)) {
      throw FormatException(
        'Acceptance case ${entry.key} did not produce its expected rows.',
      );
    }
  }
  final variants = report.cases
      .where((testCase) => testCase.entryId == 'matrixEvidence')
      .map((testCase) => testCase.matrix['variant'])
      .toSet();
  if (variants.length != 2 ||
      !variants.containsAll(const <String>{'primary', 'alternate'})) {
    throw const FormatException('Acceptance matrix rows are incomplete.');
  }
}

Future<void> _verifyOfflineReportBundle({
  required String outputDirectory,
  required CockpitTestSuiteReport report,
  required bool recordingSupported,
  required bool visualRegressionSupported,
  required bool locationTravelSupported,
  required bool nativeBlackBoxSupported,
  required bool nativeLocatorSupported,
  required String? nativeTargetId,
  required String platform,
}) async {
  final root = p.normalize(p.join(outputDirectory, 'cockpit-report'));
  final manifestFile = File(p.join(root, 'manifest.json'));
  if (await FileSystemEntity.type(manifestFile.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('Offline report manifest is missing.');
  }
  final manifest = CockpitTestReportBundleManifest.fromJson(
    jsonDecode(await manifestFile.readAsString()),
  );
  if (manifest.runId != report.runId) {
    throw const FormatException('Offline report manifest run is incorrect.');
  }
  const requiredPaths = <String>{
    'report.json',
    'junit.xml',
    'index.html',
    'summary.md',
    'run/run.json',
    'run/events.jsonl',
  };
  final declaredPaths = manifest.files
      .map((entry) => entry.relativePath)
      .toSet();
  if (!declaredPaths.containsAll(requiredPaths)) {
    throw const FormatException('Offline report exports are incomplete.');
  }

  final actualPaths = <String>{};
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.directory) continue;
    if (type != FileSystemEntityType.file) {
      throw const FormatException(
        'Offline report contains an unsupported filesystem entry.',
      );
    }
    final relativePath = p
        .relative(entity.path, from: root)
        .replaceAll('\\', '/');
    if (relativePath != 'manifest.json') actualPaths.add(relativePath);
  }
  if (actualPaths.length != declaredPaths.length ||
      !actualPaths.containsAll(declaredPaths)) {
    throw const FormatException(
      'Offline report manifest does not cover every exported file.',
    );
  }
  for (final declaration in manifest.files) {
    final path = p.normalize(
      p.joinAll(<String>[root, ...p.posix.split(declaration.relativePath)]),
    );
    if (!p.isWithin(root, path)) {
      throw const FormatException('Offline report path escapes its bundle.');
    }
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() != declaration.sizeBytes ||
        (await sha256.bind(file.openRead()).first).toString() !=
            declaration.sha256) {
      throw FormatException(
        'Offline report file ${declaration.relativePath} failed integrity verification.',
      );
    }
  }

  final bundle = CockpitTestReportBundle.fromJson(
    jsonDecode(await File(p.join(root, 'report.json')).readAsString()),
  );
  if (!bundle.complete ||
      bundle.report.runId != report.runId ||
      bundle.executions.isEmpty) {
    throw const FormatException('Canonical offline report is incomplete.');
  }
  final steps = <CockpitTestStepResult>[
    for (final execution in bundle.executions) ...execution.result.steps,
  ];
  final operations = steps.map((step) => step.operation).whereType<String>();
  const capabilityDependentActions = <CockpitTestActionKind>{
    CockpitTestActionKind.assertScreenshot,
    CockpitTestActionKind.travel,
    CockpitTestActionKind.system,
  };
  final requiredOperations = <String>{
    for (final action in CockpitTestActionKind.values)
      if (!capabilityDependentActions.contains(action)) 'action.${action.name}',
    'control.if',
    'control.retry',
    'control.loop',
  };
  final operationSet = operations.toSet();
  final mixedPlaneExecutions = bundle.executions
      .where((execution) => execution.entryId == 'mixedPlaneBlackBox')
      .toList(growable: false);
  final hasConjunctiveLocatorEvidence = steps.any((step) {
    final signals = step.locatorResolution?.matchedSignals;
    return signals?['text'] == 'Save task' &&
        signals?['type'] == 'FilledButton';
  });
  if (!operationSet.containsAll(requiredOperations) ||
      !bundle.executions.any(
        (execution) => execution.role == CockpitTestReportExecutionRole.fixture,
      ) ||
      !steps.any((step) => step.section == 'setup') ||
      !steps.any((step) => step.section == 'main') ||
      !steps.any((step) => step.section == 'finally') ||
      !steps.any((step) => step.occurrence.callPath.isNotEmpty) ||
      !hasConjunctiveLocatorEvidence ||
      !steps.any(
        (step) =>
            step.timeoutMs != null &&
            step.description != null &&
            step.definitionPath != null,
      ) ||
      !steps.any((step) => step.evidence.isNotEmpty)) {
    throw const FormatException(
      'Canonical report does not prove the required workflow capabilities.',
    );
  }
  if (platform != 'web') {
    final mixedPlaneSteps = <CockpitTestStepResult>[
      for (final execution in mixedPlaneExecutions) ...execution.result.steps,
    ];
    final nativeLocatorProof = mixedPlaneSteps.any(
      (step) =>
          step.operation == 'action.tap' &&
          step.requestedPlane == CockpitTestPlane.native &&
          step.actualPlane == CockpitTestPlane.native &&
          step.locatorResolution != null,
    );
    final nativeCaptureProof = mixedPlaneSteps.any(
      (step) =>
          step.operation == 'action.captureScreenshot' &&
          step.requestedPlane == CockpitTestPlane.native &&
          step.actualPlane == CockpitTestPlane.native &&
          step.evidence.isNotEmpty,
    );
    if (mixedPlaneExecutions.length != 1 ||
        !operationSet.contains('action.system') ||
        !mixedPlaneSteps.any(
          (step) =>
              step.operation == 'action.system' &&
              step.requestedPlane == CockpitTestPlane.native &&
              step.actualPlane == CockpitTestPlane.native,
        ) ||
        (nativeLocatorSupported ? !nativeLocatorProof : !nativeCaptureProof) ||
        !mixedPlaneSteps.any(
          (step) =>
              step.requestedPlane == CockpitTestPlane.semantic &&
              step.actualPlane == CockpitTestPlane.semantic,
        ) ||
        !mixedPlaneSteps.any((step) => step.evidence.isNotEmpty)) {
      throw const FormatException(
        'Canonical report does not prove mixed-plane black-box execution.',
      );
    }
  }
  final nativeBlackBoxExecutions = bundle.executions
      .where((execution) => execution.entryId == 'nativeBlackBox')
      .toList(growable: false);
  if (nativeBlackBoxSupported) {
    final nativeSteps = <CockpitTestStepResult>[
      for (final execution in nativeBlackBoxExecutions)
        ...execution.result.steps,
    ];
    final nativeArtifacts = <CockpitTestReportArtifact>[
      for (final execution in nativeBlackBoxExecutions) ...execution.artifacts,
    ];
    if (nativeTargetId == null ||
        nativeBlackBoxExecutions.length != 1 ||
        nativeBlackBoxExecutions.single.result.targetId != nativeTargetId ||
        nativeBlackBoxExecutions.single.result.platform != platform ||
        nativeBlackBoxExecutions.single.result.requestedPlane !=
            CockpitTestPlane.native ||
        !nativeSteps.any(
          (step) =>
              step.operation == 'action.system' &&
              step.requestedPlane == CockpitTestPlane.native &&
              step.actualPlane == CockpitTestPlane.native,
        ) ||
        !nativeSteps.any(
          (step) => step.operation == 'action.captureScreenshot',
        ) ||
        !nativeArtifacts.any(
          (artifact) => artifact.mediaType.startsWith('image/'),
        )) {
      throw const FormatException(
        'Canonical report does not prove independent native black-box execution.',
      );
    }
    if (nativeLocatorSupported &&
        (!nativeSteps.any(
              (step) =>
                  step.operation == 'action.tap' &&
                  step.requestedPlane == CockpitTestPlane.native &&
                  step.actualPlane == CockpitTestPlane.native &&
                  step.locatorResolution != null,
            ) ||
            !nativeSteps.any(
              (step) =>
                  step.operation == 'action.assertVisible' &&
                  step.requestedPlane == CockpitTestPlane.native &&
                  step.actualPlane == CockpitTestPlane.native &&
                  step.locatorResolution != null,
            ))) {
      throw const FormatException(
        'Native-tree runtime did not preserve black-box locator and assertion proof.',
      );
    }
  } else if (nativeBlackBoxExecutions.isNotEmpty) {
    throw const FormatException(
      'Unsupported runtime unexpectedly executed native black-box coverage.',
    );
  }
  if (visualRegressionSupported) {
    final visualExecutions = bundle.executions
        .where((execution) => execution.entryId == 'visualRegression')
        .toList(growable: false);
    final visualArtifacts = <CockpitTestReportArtifact>[
      for (final execution in visualExecutions) ...execution.artifacts,
    ];
    final visualArtifactKinds = visualArtifacts
        .map((artifact) => artifact.kind)
        .toSet();
    if (!operationSet.contains('action.assertScreenshot') ||
        visualExecutions.length != 1 ||
        !visualArtifactKinds.containsAll(const <String>{
          'screenshotActual',
          'screenshotBaseline',
          'screenshotDiff',
        })) {
      throw const FormatException(
        'Visual regression did not preserve actual, baseline, and diff evidence.',
      );
    }
  } else {
    final fallbackSteps = <CockpitTestStepResult>[
      for (final execution in bundle.executions.where(
        (execution) => execution.entryId == 'visualRegression',
      ))
        ...execution.result.steps,
    ];
    if (!fallbackSteps.any(
      (step) => step.operation == 'action.captureScreenshot',
    )) {
      throw const FormatException(
        'Runtime without visual assertions produced no screenshot fallback.',
      );
    }
  }
  if (locationTravelSupported && !operationSet.contains('action.travel')) {
    throw const FormatException(
      'Location-capable runtime did not execute the travel action.',
    );
  }
  if (recordingSupported &&
      (!operationSet.contains('recording.start') ||
          !operationSet.contains('recording.stop') ||
          !bundle.executions.any(
            (execution) => execution.artifacts.any(
              (artifact) => artifact.mediaType.startsWith('video/'),
            ),
          ))) {
    throw const FormatException(
      'Recording-capable runtime produced no verified recording evidence.',
    );
  }

  final html = await File(p.join(root, 'index.html')).readAsString();
  if (!const <String>[
        'data-lens="summary"',
        'data-lens="coverage"',
        'data-lens="executions"',
        'data-lens="evidence"',
        'data-lens="diagnostics"',
        'data-lens="environment"',
        'id="cockpit-report-data"',
        'data-filter-input',
        'Effective configuration',
      ].every(html.contains) ||
      html.contains('<script src=') ||
      html.contains('<link rel="stylesheet"') ||
      html.contains('fetch(') ||
      html.contains('src="http') ||
      html.contains('href="http') ||
      html.contains('@import')) {
    throw const FormatException('HTML report is not complete and offline.');
  }
}

String _canonicalSha256(Object? value) =>
    sha256.convert(utf8.encode(_canonicalJson(value))).toString();

String _canonicalJson(Object? value) => jsonEncode(_sortJson(value));

Object? _sortJson(Object? value) => switch (value) {
  Map<Object?, Object?> map => <String, Object?>{
    for (final key in map.keys.cast<String>().toList()..sort())
      key: _sortJson(map[key]),
  },
  List<Object?> list => list.map(_sortJson).toList(growable: false),
  _ => value,
};

void _requireRelativePath(String value, String name) {
  final normalized = p.normalize(value);
  if (value.trim().isEmpty ||
      p.isAbsolute(value) ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      normalized.startsWith('..${p.separator}')) {
    throw FormatException('$name must be a confined relative path.');
  }
}

Future<String> _canonicalDirectory(String path) async {
  final normalized = p.normalize(p.absolute(path));
  if (await FileSystemEntity.type(normalized, followLinks: true) !=
      FileSystemEntityType.directory) {
    throw FileSystemException('Directory does not exist.', normalized);
  }
  return p.normalize(await Directory(normalized).resolveSymbolicLinks());
}

Future<File> _workspaceFile(String workspace, String relativePath) async {
  _requireRelativePath(relativePath, 'workspace file');
  final candidate = p.normalize(p.join(workspace, relativePath));
  if (!p.isWithin(workspace, candidate) ||
      await FileSystemEntity.type(candidate, followLinks: false) !=
          FileSystemEntityType.file) {
    throw FileSystemException(
      'Workspace file is missing or is not a regular file.',
      candidate,
    );
  }
  final canonical = p.normalize(await File(candidate).resolveSymbolicLinks());
  if (!p.equals(candidate, canonical) || !p.isWithin(workspace, canonical)) {
    throw FileSystemException('Workspace file must not be a link.', candidate);
  }
  return File(canonical);
}

Future<CockpitTestCase> _loadAcceptanceCase(
  String workspace,
  String relativePath,
  String expectedId,
) async {
  final file = await _workspaceFile(workspace, relativePath);
  final compiled = const CockpitTestDocumentCompiler()
      .compile(await file.readAsString())
      .requireCase();
  if (compiled.testCase.id != expectedId) {
    throw FormatException(
      'Acceptance case $relativePath has id ${compiled.testCase.id}; '
      'expected $expectedId.',
    );
  }
  return compiled.testCase;
}

bool _contains(String root, String candidate) =>
    p.equals(root, candidate) || p.isWithin(root, candidate);

String _protocolPath(String value) => p.normalize(value).replaceAll('\\', '/');

String cockpitDemoLaunchModeForPlatform(String platform) =>
    platform == 'web' ? 'development' : 'automation';

CockpitDocumentFormat _documentFormat(String path) =>
    p.extension(path).toLowerCase() == '.json'
    ? CockpitDocumentFormat.json
    : CockpitDocumentFormat.yaml;

Future<CockpitRootResource> _resolveRoot(
  CockpitSupervisorApiClient api,
  String projectDirectory,
  String requestedRoot,
) async {
  final containing =
      (await api.roots())
          .where(
            (root) =>
                root.state == CockpitRootState.active &&
                _contains(root.canonicalPath, projectDirectory),
          )
          .toList(growable: false)
        ..sort(
          (left, right) =>
              right.canonicalPath.length.compareTo(left.canonicalPath.length),
        );
  if (containing.isNotEmpty) return containing.first;
  return api.registerRoot(CockpitRootRegistration(path: requestedRoot));
}

Future<CockpitWorkspaceResource> _resolveWorkspace(
  CockpitSupervisorApiClient api,
  String rootId,
  String projectDirectory,
) async {
  final matches = (await api.workspaces())
      .where(
        (workspace) =>
            workspace.state == CockpitWorkspaceState.active &&
            p.equals(workspace.canonicalPath, projectDirectory),
      )
      .toList(growable: false);
  if (matches.length > 1) {
    throw const FormatException(
      'Multiple active workspaces resolve to the project directory.',
    );
  }
  if (matches.isNotEmpty) return matches.single;
  return api.registerWorkspace(
    CockpitWorkspaceRegistration(rootId: rootId, path: projectDirectory),
  );
}

CockpitDocumentResource _requireDocument(
  List<CockpitDocumentResource> documents,
  String relativePath,
  CockpitIndexedDocumentKind kind,
) {
  final expectedPath = _protocolPath(relativePath);
  final matches = documents
      .where(
        (document) =>
            _protocolPath(document.relativePath) == expectedPath &&
            document.kind == kind,
      )
      .toList(growable: false);
  if (matches.length != 1) {
    throw FormatException(
      'Expected one indexed ${kind.name} document at $expectedPath; '
      'found ${matches.length}.',
    );
  }
  return matches.single;
}

typedef _CockpitDemoDiscoveredTarget = ({String id, String? name, String? sdk});

_CockpitDemoDiscoveredTarget _discoveredTarget(Map<String, Object?> target) => (
  id: target['id']! as String,
  name: target['name'] as String?,
  sdk: target['sdk'] as String?,
);

Future<_CockpitDemoDiscoveredTarget> _resolveDevice(
  CockpitSupervisorApiClient api,
  CockpitDemoAcceptanceRequest request,
) async {
  final discovery = await _operation(
    api,
    CockpitOperationInvocation(
      kind: 'target.discover',
      deadline: DateTime.now().toUtc().add(
        request.discoveryTimeout + const Duration(seconds: 30),
      ),
      input: <String, Object?>{
        'timeoutMs': request.discoveryTimeout.inMilliseconds,
      },
    ),
  );
  final rawTargets = discovery.output?['targets'];
  if (rawTargets is! List<Object?>) {
    throw const FormatException('Target discovery returned no target list.');
  }
  final candidates = <Map<String, Object?>>[
    for (final value in rawTargets)
      if (value is Map<Object?, Object?> &&
          value.keys.every((key) => key is String))
        Map<String, Object?>.from(value),
  ].where((value) => value['platform'] == request.platform).toList();
  final requested = request.deviceId?.trim();
  if (requested != null && requested.isNotEmpty) {
    final matches = candidates.where((value) => value['id'] == requested);
    if (matches.length != 1) {
      throw FormatException(
        'Device $requested is not an available ${request.platform} target.',
      );
    }
    return _discoveredTarget(matches.single);
  }
  if (candidates.length == 1) return _discoveredTarget(candidates.single);
  final stable = candidates
      .where((value) => value['ephemeral'] == false)
      .toList(growable: false);
  if (stable.length == 1) return _discoveredTarget(stable.single);
  if (candidates.isEmpty) {
    throw FormatException(
      'No connected Flutter target is available for ${request.platform}.',
    );
  }
  throw FormatException(
    'Multiple ${request.platform} targets are available; pass --device-id.',
  );
}

Future<CockpitAutomationTargetResource> _resolveTarget({
  required CockpitSupervisorApiClient api,
  required String workspaceId,
  required String platform,
  required String deviceId,
  required String mode,
  required CockpitDocumentResource entrypointDocument,
  required String? wdaUrl,
  required Duration registrationTimeout,
}) async {
  final targetMode = CockpitAutomationTargetMode.values.byName(mode);
  final matches = (await api.targets(workspaceId))
      .where(
        (target) =>
            target.platform == platform &&
            target.deviceId == deviceId &&
            target.targetKind == CockpitTargetKind.flutterApp &&
            target.mode == targetMode &&
            target.environment == CockpitAutomationTargetEnvironment.test &&
            target.entrypoint == entrypointDocument.relativePath &&
            target.entrypointSha256 == entrypointDocument.sha256 &&
            target.flavor == null &&
            target.appId == null,
      )
      .toList(growable: false);
  if (wdaUrl == null && matches.isNotEmpty) return matches.last;

  final identity = jsonEncode(<String, Object?>{
    'workspaceId': workspaceId,
    'platform': platform,
    'deviceId': deviceId,
    'entrypoint': entrypointDocument.relativePath,
    'sha256': entrypointDocument.sha256,
    'mode': mode,
    'environment': 'test',
    'wdaUrl': ?wdaUrl,
  });
  final digest = sha256.convert(utf8.encode(identity)).toString();
  final registration = await _operation(
    api,
    CockpitOperationInvocation(
      kind: 'target.register',
      workspaceId: workspaceId,
      idempotencyKey: CockpitIdempotencyKey(
        'demo-target-${digest.substring(0, 32)}',
      ),
      deadline: DateTime.now().toUtc().add(registrationTimeout),
      input: <String, Object?>{
        'platform': platform,
        'deviceId': deviceId,
        'entrypointDocumentId': entrypointDocument.documentId,
        'targetKind': 'flutterApp',
        'mode': mode,
        'environment': 'test',
        'wdaUrl': ?wdaUrl,
      },
    ),
  );
  final targetId = registration.output?['targetId'];
  if (targetId is! String) {
    throw const FormatException('Target registration returned no target id.');
  }
  return api.target(workspaceId, targetId);
}

Future<CockpitAutomationTargetResource> _resolveNativeTarget({
  required CockpitSupervisorApiClient api,
  required String workspaceId,
  required String platform,
  required String deviceId,
  required String appId,
  required String? wdaUrl,
  required Duration registrationTimeout,
}) async {
  final matches = (await api.targets(workspaceId))
      .where(
        (target) =>
            target.platform == platform &&
            target.deviceId == deviceId &&
            target.targetKind == CockpitTargetKind.nativeApp &&
            target.mode == CockpitAutomationTargetMode.automation &&
            target.environment == CockpitAutomationTargetEnvironment.test &&
            target.appId == appId,
      )
      .toList(growable: false);
  if (wdaUrl == null && matches.isNotEmpty) return matches.last;

  final identity = jsonEncode(<String, Object?>{
    'workspaceId': workspaceId,
    'platform': platform,
    'deviceId': deviceId,
    'appId': appId,
    'targetKind': 'nativeApp',
    'mode': 'automation',
    'environment': 'test',
    'wdaUrl': ?wdaUrl,
  });
  final digest = sha256.convert(utf8.encode(identity)).toString();
  final registration = await _operation(
    api,
    CockpitOperationInvocation(
      kind: 'target.register',
      workspaceId: workspaceId,
      idempotencyKey: CockpitIdempotencyKey(
        'demo-native-target-${digest.substring(0, 32)}',
      ),
      deadline: DateTime.now().toUtc().add(registrationTimeout),
      input: <String, Object?>{
        'platform': platform,
        'deviceId': deviceId,
        'appId': appId,
        'targetKind': 'nativeApp',
        'mode': 'automation',
        'environment': 'test',
        'wdaUrl': ?wdaUrl,
      },
    ),
  );
  final targetId = registration.output?['targetId'];
  if (targetId is! String) {
    throw const FormatException(
      'Native target registration returned no target id.',
    );
  }
  return api.target(workspaceId, targetId);
}

Future<CockpitOperationResult> _operation(
  CockpitSupervisorApiClient api,
  CockpitOperationInvocation invocation,
) async {
  final result = await api.executeOperation(invocation);
  if (result.lifecycle != CockpitOperationLifecycle.completed ||
      result.outcome != CockpitOperationOutcome.succeeded) {
    throw CockpitSupervisorClientException(
      code: result.failure?.primary.code ?? 'operationFailed',
      message:
          result.failure?.primary.message ??
          'Operation ${invocation.kind} failed.',
    );
  }
  return result;
}

Future<bool> _probeNativeLocator({
  required CockpitSupervisorApiClient api,
  required String workspaceId,
  required String targetId,
  required String probeId,
}) async {
  for (var attempt = 1; attempt <= 3; attempt += 1) {
    try {
      final result = await _operation(
        api,
        CockpitOperationInvocation(
          kind: 'system.action',
          workspaceId: workspaceId,
          idempotencyKey: CockpitIdempotencyKey(
            'demo-native-probe-${_stableIdSuffix(targetId)}-'
            '${_stableIdSuffix(probeId)}-$attempt',
          ),
          deadline: DateTime.now().toUtc().add(const Duration(seconds: 25)),
          input: <String, Object?>{
            'targetId': targetId,
            'action': 'readUiTree',
            'parameters': <String, Object?>{'maxDepth': 16, 'maxNodes': 2000},
            'timeoutMs': 20000,
          },
        ),
      );
      final output = result.output;
      final raw = output?['stdout'];
      if (output?['success'] == true &&
          raw is String &&
          raw.trim().isNotEmpty) {
        final snapshot = CockpitNativeUiSnapshot.parse(raw);
        if (snapshot
                .resolve(
                  CockpitTestLocator(label: 'New task'),
                  flutterAware: true,
                )
                .found ||
            snapshot
                .resolve(
                  CockpitTestLocator(text: 'New task'),
                  flutterAware: true,
                )
                .found) {
          return true;
        }
      }
    } on Object {
      if (attempt == 3) return false;
    }
    if (attempt < 3) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  return false;
}

Future<void> _dismissDevelopmentSystemDialogs({
  required CockpitSupervisorApiClient api,
  required String workspaceId,
  required String targetId,
}) async {
  for (var attempt = 0; attempt < 2; attempt += 1) {
    try {
      await _operation(
        api,
        CockpitOperationInvocation(
          kind: 'system.action',
          workspaceId: workspaceId,
          idempotencyKey: CockpitIdempotencyKey(
            'demo-dismiss-dialog-$attempt-${_stableIdSuffix(targetId)}',
          ),
          deadline: DateTime.now().toUtc().add(const Duration(seconds: 15)),
          input: <String, Object?>{
            'targetId': targetId,
            'action': 'dismissSystemDialog',
            'timeoutMs': 10000,
          },
        ),
      );
    } on Object {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

String _stableIdSuffix(String value) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, 20);

Future<int> _consumeEvents({
  required CockpitSupervisorApiClient api,
  required String runId,
  required DateTime deadline,
  required IOSink sink,
  required CockpitDemoAcceptanceProgress? progress,
}) async {
  var afterSequence = 0;
  var eventCount = 0;
  String? lastEventId;
  while (DateTime.now().toUtc().isBefore(deadline)) {
    var disconnected = false;
    final remaining = deadline.difference(DateTime.now().toUtc());
    try {
      await for (final item
          in api
              .events(
                runId,
                afterSequence: afterSequence,
                lastEventId: lastEventId,
              )
              .timeout(remaining)) {
        if (item is CockpitRunStreamEvent) {
          final event = item.event;
          afterSequence = event.sequence;
          lastEventId = event.eventId;
          eventCount += 1;
          sink.writeln(jsonEncode(event.toJson()));
          progress?.call(<String, Object?>{
            'stage': 'run',
            'runId': runId,
            'sequence': event.sequence,
            'kind': event.kind,
            if (event.lifecycle != null) 'lifecycle': event.lifecycle!.name,
            if (event.outcome != null) 'outcome': event.outcome!.name,
          });
          continue;
        }
        if (item is CockpitRunStreamGap) {
          throw CockpitSupervisorClientException(
            code: 'eventReplayGap',
            message:
                'Run events are no longer complete: '
                '${jsonEncode(item.boundary.toJson())}',
          );
        }
        if (item is CockpitRunStreamTerminal) {
          return eventCount;
        }
        if (item is CockpitRunStreamDisconnected) {
          afterSequence = item.afterSequence;
          disconnected = true;
        }
      }
    } on CockpitSupervisorClientException catch (error) {
      if (error.code != CockpitErrorCode.transportFailed) rethrow;
      disconnected = true;
      progress?.call(<String, Object?>{
        'stage': 'run',
        'runId': runId,
        'message': 'Event stream disconnected; resuming from $afterSequence.',
      });
    }
    if (!disconnected) {
      throw const CockpitSupervisorClientException(
        code: 'eventStreamEnded',
        message: 'Run event stream ended without a terminal marker.',
      );
    }
    final delay = deadline.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) break;
    await Future<void>.delayed(
      delay < const Duration(milliseconds: 250)
          ? delay
          : const Duration(milliseconds: 250),
    );
  }
  throw TimeoutException(
    'Acceptance run $runId did not finish.',
    Duration.zero,
  );
}

File _artifactDestination(
  String outputDirectory,
  CockpitArtifactResource artifact,
) {
  final components = p.posix.split(artifact.relativePath);
  if (components.length < 3 || components.first != 'artifacts') {
    throw const FormatException('Artifact path has no bundle authority.');
  }
  final insideBundle = components.skip(2).join(p.separator);
  final root = p.normalize(
    artifact.attemptId == null
        ? p.join(outputDirectory, 'cockpit-report')
        : p.join(
            outputDirectory,
            'source-artifacts',
            _safePathComponent(artifact.attemptId!),
          ),
  );
  final relative = p.normalize(insideBundle);
  final destination = p.normalize(p.join(root, relative));
  if (p.isAbsolute(relative) || !p.isWithin(root, destination)) {
    throw const FormatException('Artifact path escapes the output directory.');
  }
  return File(destination);
}

String _safePathComponent(String value) {
  final normalized = value
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (normalized.isEmpty) return 'attempt';
  return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
}

Future<void> _cancelActiveRun(
  CockpitSupervisorApiClient api,
  String runId,
  String invocationId,
  List<Map<String, Object?>> failures,
) async {
  try {
    final current = await api.run(runId);
    if (current.lifecycle == CockpitRunLifecycle.completed) return;
    await api.cancelRun(
      runId,
      CockpitRunCancellationRequest(
        idempotencyKey: CockpitIdempotencyKey('$invocationId-cancel'),
        reason: 'Acceptance runner cleanup after an incomplete execution.',
      ),
    );
  } on Object catch (error) {
    failures.add(_failure(error, 'runCancel'));
  }
}

Future<void> _stopTargetApp({
  required CockpitSupervisorApiClient api,
  required String workspaceId,
  required String targetId,
  required String? appId,
  required String idempotencyKey,
  required List<Map<String, Object?>> failures,
}) async {
  try {
    var resolvedAppId = appId;
    if (resolvedAppId == null) {
      final listed = await _operation(
        api,
        CockpitOperationInvocation(kind: 'app.list', workspaceId: workspaceId),
      );
      final rawApps = listed.output?['apps'];
      final matches = rawApps is List<Object?>
          ? rawApps
                .whereType<Map<Object?, Object?>>()
                .where((app) => app['targetId'] == targetId)
                .toList(growable: false)
          : const <Map<Object?, Object?>>[];
      if (matches.isEmpty) return;
      if (matches.length != 1 || matches.single['appId'] is! String) {
        throw const FormatException(
          'Cannot identify one launched app for target cleanup.',
        );
      }
      resolvedAppId = matches.single['appId']! as String;
    }
    await _operation(
      api,
      CockpitOperationInvocation(
        kind: 'app.stop',
        workspaceId: workspaceId,
        idempotencyKey: CockpitIdempotencyKey(idempotencyKey),
        deadline: DateTime.now().toUtc().add(const Duration(minutes: 2)),
        input: <String, Object?>{'appId': resolvedAppId},
      ),
    );
  } on Object catch (error) {
    failures.add(_failure(error, 'appStop'));
  }
}

Future<void> _closeEventSink(
  IOSink? sink,
  List<Map<String, Object?>> failures,
) async {
  if (sink == null) return;
  try {
    await sink.close();
  } on Object catch (error) {
    failures.add(_failure(error, 'eventLogClose'));
  }
}

Future<void> _writeJson(File file, Object? value) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    flush: true,
  );
}

Map<String, Object?> _failure(Object error, String stage) {
  if (error is CockpitSupervisorClientException) {
    return <String, Object?>{
      'code': error.code,
      'message': _boundedError(error.message),
      'stage': stage,
      if (error.apiError != null) 'apiError': error.apiError!.toJson(),
    };
  }
  return <String, Object?>{
    'code': error.runtimeType.toString(),
    'message': _boundedError('$error'),
    'stage': stage,
  };
}

String _boundedError(String value) {
  final normalized = value
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('\t', ' ')
      .trim();
  return normalized.length <= 2048
      ? normalized
      : '${normalized.substring(0, 2048)}...';
}

String _invocationId(String platform) =>
    'acceptance-$platform-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';
