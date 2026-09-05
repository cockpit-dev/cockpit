import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../control/cockpit_command.dart';
import '../control/cockpit_command_execution.dart';
import '../control/cockpit_command_result.dart';
import '../errors/cockpit_command_error.dart';
import '../model/cockpit_artifact_ref.dart';
import '../model/cockpit_artifact_naming.dart';
import '../model/cockpit_step_record.dart';
import '../recording/cockpit_recording_request.dart';
import '../recording/cockpit_recording_result.dart';
import '../recording/cockpit_recording_session.dart';
import '../runtime/cockpit_snapshot.dart';
import '../runtime/cockpit_snapshot_options.dart';
import 'cockpit_remote_artifact_download.dart';
import 'cockpit_remote_command_response.dart';
import 'cockpit_remote_recording_response.dart';
import 'cockpit_remote_session_configuration.dart';
import 'cockpit_remote_session_status.dart';
import 'cockpit_remote_snapshot_response.dart';

typedef CockpitRemoteSessionStatusProvider =
    Future<CockpitRemoteSessionStatus> Function();
typedef CockpitRemoteSessionReadyProvider =
    FutureOr<Map<String, Object?>> Function();
typedef CockpitRemoteSessionSnapshotProvider =
    FutureOr<CockpitSnapshot> Function({
      required CockpitSnapshotOptions options,
    });
typedef CockpitRemoteSessionCommandExecutor =
    Future<CockpitCommandExecution> Function(CockpitCommand command);
typedef CockpitRemoteViewportResizer =
    Future<CockpitViewportResizeResult> Function(
      CockpitViewportResizeRequest request,
    );
typedef CockpitRemoteRuntimeStepDrainer =
    FutureOr<List<CockpitStepRecord>> Function({required bool clear});
typedef CockpitRemoteRecordingStarter =
    Future<CockpitRecordingSession> Function(CockpitRecordingRequest request);
typedef CockpitRemoteRecordingStopper =
    Future<CockpitRecordingResult> Function();
typedef CockpitRemotePerformanceStarter =
    Future<CockpitPerformanceCaptureSession> Function(
      CockpitPerformanceCaptureRequest request,
    );
typedef CockpitRemotePerformanceStopper =
    Future<CockpitPerformanceReport> Function();
typedef CockpitRemoteArtifactTempFileFactory =
    Future<File> Function(String basename);

const Duration _defaultCommandExecutionTimeout = Duration(seconds: 30);
// Strictly larger than the executor's 250ms hard-timeout grace so the
// executor's diagnostic-rich timeout always wins over this generic one.
const Duration _commandExecutionTimeoutGrace = Duration(milliseconds: 600);
const int _snapshotTransportTargetLimit = 24;
const int _snapshotTransportTextLimit = 512;

final class CockpitRemoteSessionEndpointRequest {
  const CockpitRemoteSessionEndpointRequest({
    required this.method,
    required this.uri,
    this.jsonBody = const <String, Object?>{},
  });

  final String method;
  final Uri uri;
  final Map<String, Object?> jsonBody;
}

final class CockpitRemoteSessionEndpointResponse {
  const CockpitRemoteSessionEndpointResponse._({
    required this.statusCode,
    required this.contentType,
    this.jsonBody,
    this.binaryBody,
    this.sourceFilePath,
  });

  const CockpitRemoteSessionEndpointResponse.json(
    Map<String, Object?> body, {
    int statusCode = HttpStatus.ok,
  }) : this._(
         statusCode: statusCode,
         contentType: 'application/json',
         jsonBody: body,
       );

  const CockpitRemoteSessionEndpointResponse.binary(
    List<int> bytes, {
    int statusCode = HttpStatus.ok,
    String contentType = 'application/octet-stream',
  }) : this._(
         statusCode: statusCode,
         contentType: contentType,
         binaryBody: bytes,
       );

  const CockpitRemoteSessionEndpointResponse.binaryFile(
    String sourceFilePath, {
    int statusCode = HttpStatus.ok,
    String contentType = 'application/octet-stream',
  }) : this._(
         statusCode: statusCode,
         contentType: contentType,
         sourceFilePath: sourceFilePath,
       );

  final int statusCode;
  final String contentType;
  final Map<String, Object?>? jsonBody;
  final List<int>? binaryBody;
  final String? sourceFilePath;
}

final class _RemoteArtifactEntry {
  const _RemoteArtifactEntry({
    this.sourceFilePath,
    this.bytes,
    this.deleteOnClose = false,
  });

  final String? sourceFilePath;
  final List<int>? bytes;
  final bool deleteOnClose;
}

final class _CommandArtifactRegistration {
  const _CommandArtifactRegistration({
    required this.downloads,
    required this.inlinePayloads,
  });

  final List<CockpitRemoteArtifactDownload> downloads;
  final Map<String, List<int>> inlinePayloads;
}

final class CockpitRemoteSessionEndpointHandler {
  CockpitRemoteSessionEndpointHandler({
    required CockpitRemoteSessionConfiguration configuration,
    required CockpitRemoteSessionStatusProvider statusProvider,
    CockpitRemoteSessionReadyProvider? readyProvider,
    required CockpitRemoteSessionSnapshotProvider snapshotProvider,
    required CockpitRemoteSessionCommandExecutor commandExecutor,
    CockpitRemoteViewportResizer? viewportResizer,
    CockpitRemoteRuntimeStepDrainer? runtimeStepDrainer,
    required CockpitRemoteRecordingStarter startRecording,
    required CockpitRemoteRecordingStopper stopRecording,
    CockpitRemotePerformanceStarter? startPerformance,
    CockpitRemotePerformanceStopper? stopPerformance,
    CockpitRemoteArtifactTempFileFactory? artifactTempFileFactory,
  }) : _configuration = configuration,
       _statusProvider = statusProvider,
       _readyProvider = readyProvider,
       _snapshotProvider = snapshotProvider,
       _commandExecutor = commandExecutor,
       _viewportResizer = viewportResizer,
       _runtimeStepDrainer = runtimeStepDrainer,
       _startRecording = startRecording,
       _stopRecording = stopRecording,
       _startPerformance = startPerformance,
       _stopPerformance = stopPerformance,
       _artifactTempFileFactory =
           artifactTempFileFactory ?? _defaultArtifactTempFileFactory;

  final CockpitRemoteSessionConfiguration _configuration;
  final CockpitRemoteSessionStatusProvider _statusProvider;
  final CockpitRemoteSessionReadyProvider? _readyProvider;
  final CockpitRemoteSessionSnapshotProvider _snapshotProvider;
  final CockpitRemoteSessionCommandExecutor _commandExecutor;
  final CockpitRemoteViewportResizer? _viewportResizer;
  final CockpitRemoteRuntimeStepDrainer? _runtimeStepDrainer;
  final CockpitRemoteRecordingStarter _startRecording;
  final CockpitRemoteRecordingStopper _stopRecording;
  final CockpitRemotePerformanceStarter? _startPerformance;
  final CockpitRemotePerformanceStopper? _stopPerformance;
  final CockpitRemoteArtifactTempFileFactory _artifactTempFileFactory;
  final Map<String, _RemoteArtifactEntry> _downloadableArtifacts =
      <String, _RemoteArtifactEntry>{};
  CockpitRecordingSession? _activeRecordingSession;
  CockpitPerformanceCaptureSession? _activePerformanceSession;
  bool _recordingStarting = false;
  bool _performanceStarting = false;
  bool _performanceStopping = false;

  Future<void> close() async {
    await _bestEffortStopActiveRecording();
    await _bestEffortStopActivePerformance();
    final artifacts = _downloadableArtifacts.values.toList(growable: false);
    _downloadableArtifacts.clear();
    for (final artifact in artifacts) {
      final sourceFilePath = artifact.sourceFilePath;
      if (!artifact.deleteOnClose ||
          sourceFilePath == null ||
          sourceFilePath.isEmpty) {
        continue;
      }
      try {
        final file = File(sourceFilePath);
        if (await file.exists()) {
          await file.delete();
        }
      } on Object {
        // Best-effort cleanup only for generated diagnostics artifacts.
      }
    }
  }

  Future<CockpitRemoteSessionEndpointResponse> handle(
    CockpitRemoteSessionEndpointRequest request,
  ) async {
    try {
      final routePath = _routePathFor(request.uri.path);
      switch ((request.method, routePath)) {
        case ('GET', '/ping'):
          return CockpitRemoteSessionEndpointResponse.json(_pingPayload());
        case ('GET', '/ready'):
          return CockpitRemoteSessionEndpointResponse.json(
            await _readyPayload(),
          );
        case ('GET', '/health'):
          return CockpitRemoteSessionEndpointResponse.json(
            (await _statusProvider()).toJson(),
          );
        case ('GET', '/snapshot'):
          final snapshotOptions = _snapshotOptionsFromQuery(
            request.uri.queryParameters,
          );
          final snapshot = await _snapshotProvider(options: snapshotOptions);
          final snapshotResponse = await _snapshotResponseFor(
            snapshot,
            options: snapshotOptions,
          );
          return CockpitRemoteSessionEndpointResponse.json(
            snapshotResponse.artifactDownloads.isEmpty
                ? snapshotResponse.snapshot.toJson()
                : snapshotResponse.toJson(),
          );
        case ('GET', '/artifacts/download'):
          return await _artifactResponseFor(request);
        case ('POST', '/commands/execute'):
          final command = _decodePayload(
            () => CockpitCommand.fromJson(request.jsonBody),
          );
          await _drainRuntimeSteps(clear: true);
          final execution = await _executeCommandWithinBudget(command);
          final runtimeSteps = await _drainRuntimeSteps(clear: true);
          final artifactRegistration = await _registerCommandArtifacts(
            execution,
          );
          final responsePayload = CockpitRemoteCommandResponse.fromExecution(
            CockpitCommandExecution(
              result: execution.result,
              artifactPayloads: artifactRegistration.inlinePayloads,
              runtimeSteps: <CockpitStepRecord>[
                ...execution.runtimeSteps,
                ...runtimeSteps,
              ],
            ),
          ).toJson();
          if (artifactRegistration.downloads.isNotEmpty) {
            responsePayload['artifactDownloads'] = artifactRegistration
                .downloads
                .map((download) => download.toJson())
                .toList(growable: false);
          }
          return CockpitRemoteSessionEndpointResponse.json(responsePayload);
        case ('POST', '/viewport'):
          final resizer = _viewportResizer;
          if (resizer == null) {
            return const CockpitRemoteSessionEndpointResponse.json(
              <String, Object?>{
                'error': 'viewportUnavailable',
                'message': 'Viewport control is unavailable in this session.',
              },
              statusCode: HttpStatus.notImplemented,
            );
          }
          final viewportRequest = _decodePayload(
            () => CockpitViewportResizeRequest.fromJson(request.jsonBody),
          );
          return CockpitRemoteSessionEndpointResponse.json(
            (await resizer(viewportRequest)).toJson(),
          );
        case ('POST', '/recording/start'):
          final recordingRequest = _decodePayload(
            () => CockpitRecordingRequest.fromJson(request.jsonBody),
          );
          final recording = await _handleStartRecording(recordingRequest);
          return CockpitRemoteSessionEndpointResponse.json(recording.toJson());
        case ('POST', '/recording/stop'):
          final result = await _handleStopRecording();
          final response = await _recordingResponseFor(result);
          return CockpitRemoteSessionEndpointResponse.json(response.toJson());
        case ('POST', '/performance/start'):
          final starter = _startPerformance;
          if (starter == null) {
            return const CockpitRemoteSessionEndpointResponse.json(<
              String,
              Object?
            >{
              'error': 'performanceUnsupported',
              'message': 'Performance capture is unavailable in this session.',
            }, statusCode: HttpStatus.notImplemented);
          }
          final performanceRequest = _decodePayload(
            () => CockpitPerformanceCaptureRequest.fromJson(request.jsonBody),
          );
          final session = await _handleStartPerformance(performanceRequest);
          return CockpitRemoteSessionEndpointResponse.json(session.toJson());
        case ('POST', '/performance/stop'):
          final result = await _handleStopPerformance();
          return CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
            'report': result.toJson(),
          });
        default:
          return const CockpitRemoteSessionEndpointResponse.json(
            <String, Object?>{
              'error': 'notFound',
              'message': 'Unsupported remote session endpoint.',
            },
            statusCode: HttpStatus.notFound,
          );
      }
    } on FormatException catch (error) {
      return CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'invalidPayload',
        'message': error.message,
      }, statusCode: HttpStatus.badRequest);
    } catch (error) {
      return CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'serverError',
        'message': error.toString(),
      }, statusCode: HttpStatus.internalServerError);
    }
  }

  // Payload decoding errors must surface as 400 invalidPayload while
  // ArgumentErrors thrown later during execution stay internal (500).
  T _decodePayload<T>(T Function() decode) {
    try {
      return decode();
    } on ArgumentError catch (error) {
      throw FormatException('$error');
    }
  }

  Future<CockpitCommandExecution> _executeCommandWithinBudget(
    CockpitCommand command,
  ) async {
    final declaredTimeout = _declaredCommandExecutionTimeout(command);
    final enforcedTimeout = declaredTimeout + _commandExecutionTimeoutGrace;
    try {
      return await _commandExecutor(command).timeout(enforcedTimeout);
    } on TimeoutException {
      return CockpitCommandExecution(
        result: CockpitCommandResult(
          success: false,
          commandId: command.commandId,
          commandType: command.commandType,
          durationMs: declaredTimeout.inMilliseconds,
          error: CockpitCommandError.timeout(
            message:
                'Command execution timed out before the remote endpoint could return a result.',
            details: <String, Object?>{
              'timeoutMs': declaredTimeout.inMilliseconds,
              'enforcedTimeoutMs': enforcedTimeout.inMilliseconds,
              'remoteEndpoint': true,
            },
          ),
        ),
      );
    }
  }

  Duration _declaredCommandExecutionTimeout(CockpitCommand command) {
    final timeoutMs = command.timeoutMs;
    if (timeoutMs != null && timeoutMs > 0) {
      return Duration(milliseconds: timeoutMs);
    }
    return _defaultCommandExecutionTimeout;
  }

  Map<String, Object?> _pingPayload() => <String, Object?>{
    'ok': true,
    'protocolVersion': 1,
    'transportType': 'remoteHttp',
    'routePrefix': _configuration.normalizedRoutePrefix,
  };

  Future<Map<String, Object?>> _readyPayload() async => <String, Object?>{
    ..._pingPayload(),
    ...?await _readyProvider?.call(),
  };

  Future<List<CockpitStepRecord>> _drainRuntimeSteps({
    required bool clear,
  }) async {
    final drainer = _runtimeStepDrainer;
    if (drainer == null) {
      return const <CockpitStepRecord>[];
    }
    return List<CockpitStepRecord>.unmodifiable(
      await Future<List<CockpitStepRecord>>.value(drainer(clear: clear)),
    );
  }

  CockpitSnapshotOptions _snapshotOptionsFromQuery(
    Map<String, String> queryParameters,
  ) {
    if (queryParameters.isEmpty) {
      return const CockpitSnapshotOptions.live();
    }

    final json = <String, Object?>{};
    final query = queryParameters['query'];
    if (query != null) {
      if (query.trim().isEmpty || query.length > 512) {
        throw const FormatException(
          'Query parameter "query" must be a non-empty string of at most 512 characters.',
        );
      }
      json['query'] = query;
    }
    final profile = queryParameters['profile'];
    if (profile != null && profile.isNotEmpty) {
      _validateSnapshotProfileQueryValue(profile);
      json['profile'] = profile;
    }

    final treeProfile = queryParameters['treeProfile'];
    if (treeProfile != null && treeProfile.isNotEmpty) {
      final tree = <String, Object?>{'profile': treeProfile};
      final treeMaxNodes = queryParameters['treeMaxNodes'];
      if (treeMaxNodes != null && treeMaxNodes.isNotEmpty) {
        tree['maxNodes'] = _parsePositiveQueryInt('treeMaxNodes', treeMaxNodes);
      }
      final treeMaxProps = queryParameters['treeMaxProps'];
      if (treeMaxProps != null && treeMaxProps.isNotEmpty) {
        tree['maxProps'] = _parseNonNegativeQueryInt(
          'treeMaxProps',
          treeMaxProps,
        );
      }
      json['tree'] = tree;
    }

    for (final key in <String>[
      'maxTargets',
      'maxAncestorsPerTarget',
      'maxPropertiesPerTarget',
      'maxRebuildEntries',
      'maxAccessibilityEntries',
      'maxNetworkEntries',
      'maxRuntimeEntries',
    ]) {
      final rawValue = queryParameters[key];
      if (rawValue == null || rawValue.isEmpty) {
        continue;
      }
      json[key] = _parseNonNegativeQueryInt(key, rawValue);
    }

    final networkStatusCodeAtLeast =
        queryParameters['networkStatusCodeAtLeast'];
    if (networkStatusCodeAtLeast != null &&
        networkStatusCodeAtLeast.isNotEmpty) {
      json['networkStatusCodeAtLeast'] = _parseHttpStatusQueryInt(
        'networkStatusCodeAtLeast',
        networkStatusCodeAtLeast,
      );
    }

    for (final key in <String>[
      'includeStyleDetails',
      'includeDiagnosticProperties',
      'includeRebuildActivity',
      'includeAccessibilitySummary',
      'includeNetworkActivity',
      'networkOnlyFailures',
      'includeRuntimeActivity',
      'runtimeOnlyErrors',
    ]) {
      final rawValue = queryParameters[key];
      if (rawValue == null || rawValue.isEmpty) {
        continue;
      }
      json[key] = _parseQueryBool(key, rawValue);
    }

    final artifact = queryParameters['artifact'];
    if (artifact != null && artifact.isNotEmpty) {
      json['artifact'] = artifact;
    }

    final networkQuery = <String, Object?>{};
    final networkId = queryParameters['networkId'];
    if (networkId != null && networkId.isNotEmpty) {
      networkQuery['id'] = networkId;
    }
    final networkBefore = queryParameters['networkBefore'];
    if (networkBefore != null && networkBefore.isNotEmpty) {
      networkQuery['before'] = networkBefore;
    }
    final networkMethod = queryParameters['networkMethod'];
    if (networkMethod != null && networkMethod.isNotEmpty) {
      networkQuery['method'] = networkMethod;
    }
    final networkUriContains = queryParameters['networkUriContains'];
    if (networkUriContains != null && networkUriContains.isNotEmpty) {
      networkQuery['uriContains'] = networkUriContains;
    }
    if (json.containsKey('networkOnlyFailures')) {
      networkQuery['onlyFailures'] = json.remove('networkOnlyFailures');
    }
    if (json.containsKey('networkStatusCodeAtLeast')) {
      networkQuery['statusCodeAtLeast'] = json.remove(
        'networkStatusCodeAtLeast',
      );
    }
    if (networkQuery.isNotEmpty) {
      json['networkQuery'] = networkQuery;
    }

    final runtimeQuery = <String, Object?>{};
    final runtimeMessageContains = queryParameters['runtimeMessageContains'];
    if (runtimeMessageContains != null && runtimeMessageContains.isNotEmpty) {
      runtimeQuery['messageContains'] = runtimeMessageContains;
    }
    if (json.containsKey('runtimeOnlyErrors')) {
      runtimeQuery['onlyErrors'] = json.remove('runtimeOnlyErrors');
    }
    if (runtimeQuery.isNotEmpty) {
      json['runtimeQuery'] = runtimeQuery;
    }

    return CockpitSnapshotOptions.fromJson(json);
  }

  void _validateSnapshotProfileQueryValue(String value) {
    final supported = CockpitSnapshotProfile.values
        .map((profile) => profile.jsonValue)
        .toSet();
    if (supported.contains(value)) {
      return;
    }
    throw FormatException(
      'Query parameter "profile" must be one of: ${supported.join(', ')}.',
    );
  }

  int _parseNonNegativeQueryInt(String key, String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0) {
      throw FormatException(
        'Query parameter "$key" must be a non-negative integer.',
      );
    }
    return parsed;
  }

  int _parsePositiveQueryInt(String key, String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      throw FormatException(
        'Query parameter "$key" must be a positive integer.',
      );
    }
    return parsed;
  }

  int _parseHttpStatusQueryInt(String key, String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 100 || parsed > 599) {
      throw FormatException(
        'Query parameter "$key" must be an HTTP status code from 100 to 599.',
      );
    }
    return parsed;
  }

  bool _parseQueryBool(String key, String value) {
    final normalized = value.toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
    throw FormatException(
      'Query parameter "$key" must be either "true" or "false".',
    );
  }

  String? _routePathFor(String path) {
    final prefix = _configuration.normalizedRoutePrefix;
    if (prefix.isEmpty) {
      return path;
    }
    if (path == prefix) {
      return '/';
    }
    if (path.startsWith('$prefix/')) {
      return path.substring(prefix.length);
    }
    return null;
  }

  Future<_CommandArtifactRegistration> _registerCommandArtifacts(
    CockpitCommandExecution execution,
  ) async {
    final downloads = <CockpitRemoteArtifactDownload>[];
    final inlinePayloads = <String, List<int>>{};
    for (final artifact in execution.result.artifacts) {
      final sourceFilePath =
          execution.artifactSourcePaths[artifact.relativePath];
      if (sourceFilePath != null && sourceFilePath.isNotEmpty) {
        final sourceFile = File(sourceFilePath);
        if (sourceFile.existsSync() && sourceFile.lengthSync() > 0) {
          _downloadableArtifacts[artifact.relativePath] = _RemoteArtifactEntry(
            sourceFilePath: sourceFile.path,
          );
          downloads.add(
            CockpitRemoteArtifactDownload(
              artifact: artifact,
              downloadPath: _downloadPathFor(artifact.relativePath),
            ),
          );
          continue;
        }
      }

      final bytes = execution.artifactPayloads[artifact.relativePath];
      if (bytes == null || bytes.isEmpty) {
        if (artifact.role == 'screenshot' ||
            artifact.role == 'step_screenshot') {
          throw StateError(
            'Command ${execution.result.commandId} produced an empty artifact '
            '${artifact.relativePath}.',
          );
        }
        continue;
      }
      try {
        _downloadableArtifacts[artifact.relativePath] =
            await _persistArtifactBytes(
              cockpitSanitizeRemoteArtifactBasename(artifact.relativePath),
              bytes,
            );
      } on Object {
        // Constrained runtimes, especially web, may not support temp-file
        // persistence. Preserve evidence inline so the caller can externalize
        // it instead of returning a dangling artifact reference.
        inlinePayloads[artifact.relativePath] = bytes;
        continue;
      }
      downloads.add(
        CockpitRemoteArtifactDownload(
          artifact: artifact,
          downloadPath: _downloadPathFor(artifact.relativePath),
        ),
      );
    }
    return _CommandArtifactRegistration(
      downloads: downloads,
      inlinePayloads: inlinePayloads,
    );
  }

  Future<CockpitRemoteRecordingResponse> _recordingResponseFor(
    CockpitRecordingResult result,
  ) async {
    final artifact = result.artifact;
    if (artifact == null) {
      return CockpitRemoteRecordingResponse(
        result: _recordingResultForTransport(result),
      );
    }

    final artifactEntry = await _artifactEntryFor(result);
    if (artifactEntry == null) {
      return CockpitRemoteRecordingResponse(
        result: _recordingResultForTransport(result, includeArtifact: false),
      );
    }

    _downloadableArtifacts[artifact.relativePath] = artifactEntry;
    return CockpitRemoteRecordingResponse(
      result: _recordingResultForTransport(result),
      artifactDownloads: <CockpitRemoteArtifactDownload>[
        CockpitRemoteArtifactDownload(
          artifact: artifact,
          downloadPath: _downloadPathFor(artifact.relativePath),
        ),
      ],
    );
  }

  Future<CockpitRecordingSession> _handleStartRecording(
    CockpitRecordingRequest request,
  ) async {
    if (_recordingStarting ||
        _performanceStarting ||
        _performanceStopping ||
        _activeRecordingSession != null ||
        _activePerformanceSession != null) {
      throw StateError(
        'Screen recording cannot overlap a performance capture.',
      );
    }
    _recordingStarting = true;
    try {
      final session = await _startRecording(request);
      _activeRecordingSession = session;
      return session;
    } finally {
      _recordingStarting = false;
    }
  }

  Future<CockpitRecordingResult> _handleStopRecording() async {
    try {
      final result = await _stopRecording();
      _activeRecordingSession = null;
      return result;
    } on StateError {
      _activeRecordingSession = null;
      rethrow;
    }
  }

  Future<CockpitPerformanceCaptureSession> _handleStartPerformance(
    CockpitPerformanceCaptureRequest request,
  ) async {
    if (_activePerformanceSession != null || _performanceStopping) {
      throw StateError('A performance capture is already active.');
    }
    if (_activeRecordingSession != null) {
      throw StateError(
        'Performance capture cannot overlap a screen recording.',
      );
    }
    if (_recordingStarting || _performanceStarting) {
      throw StateError('A capture operation is already starting.');
    }
    final starter = _startPerformance;
    if (starter == null) {
      throw StateError('Performance capture is unavailable in this session.');
    }
    _performanceStarting = true;
    try {
      final session = await starter(request);
      _activePerformanceSession = session;
      return session;
    } finally {
      _performanceStarting = false;
    }
  }

  Future<CockpitPerformanceReport> _handleStopPerformance() async {
    final stopper = _stopPerformance;
    if (stopper == null || _activePerformanceSession == null) {
      throw StateError('No performance capture is active.');
    }
    if (_performanceStopping) {
      throw StateError('Performance capture stop is already in progress.');
    }
    _performanceStopping = true;
    try {
      final result = await stopper();
      _activePerformanceSession = null;
      return result;
    } on StateError {
      // A target-side inactive error proves that the capture is no longer
      // owned by this endpoint. Other failures retain ownership for retry or
      // shutdown cleanup.
      _activePerformanceSession = null;
      rethrow;
    } finally {
      _performanceStopping = false;
    }
  }

  Future<CockpitRemoteSnapshotResponse> _snapshotResponseFor(
    CockpitSnapshot snapshot, {
    required CockpitSnapshotOptions options,
  }) async {
    final treeArtifact = options.tree != null && snapshot.tree != null;
    final forceTreeArtifact =
        treeArtifact && options.tree?.profile == CockpitWidgetTreeProfile.full;
    if (options.artifact == CockpitSnapshotArtifactMode.inline &&
        !forceTreeArtifact) {
      return CockpitRemoteSnapshotResponse(snapshot: snapshot);
    }
    final artifactBytes = utf8.encode(
      jsonEncode(
        _compactJsonValue(
          treeArtifact ? snapshot.tree!.toJson() : snapshot.toJson(),
        ),
      ),
    );
    if (options.artifact != CockpitSnapshotArtifactMode.always &&
        !forceTreeArtifact &&
        artifactBytes.length <= 16384) {
      return CockpitRemoteSnapshotResponse(snapshot: snapshot);
    }

    final artifactRef = treeArtifact
        ? snapshot.treeArtifactRef ??
              CockpitArtifactRef(
                role: 'widget-tree',
                relativePath:
                    'trees/${cockpitSortableTimestampToken(DateTime.now())}_widget_tree.json',
              )
        : snapshot.diagnosticsArtifactRef ??
              CockpitArtifactRef(
                role: 'diagnostics',
                relativePath:
                    'diagnostics/${cockpitSortableTimestampToken(DateTime.now())}_remote_snapshot.json',
              );
    _downloadableArtifacts[artifactRef.relativePath] =
        await _persistArtifactBytes(
          cockpitSanitizeRemoteArtifactBasename(artifactRef.relativePath),
          artifactBytes,
        );

    return CockpitRemoteSnapshotResponse(
      snapshot: _summarizedSnapshot(snapshot).copyWith(
        diagnosticsArtifactRef: treeArtifact ? null : artifactRef,
        treeArtifactRef: treeArtifact ? artifactRef : null,
      ),
      artifactDownloads: <CockpitRemoteArtifactDownload>[
        CockpitRemoteArtifactDownload(
          artifact: artifactRef,
          downloadPath: _downloadPathFor(artifactRef.relativePath),
        ),
      ],
    );
  }

  CockpitSnapshot _summarizedSnapshot(CockpitSnapshot snapshot) {
    final visibleTargets = snapshot.visibleTargets
        .take(_snapshotTransportTargetLimit)
        .map(
          (target) => CockpitSnapshotTarget(
            registrationId: target.registrationId,
            cockpitId: target.cockpitId,
            semanticId: target.semanticId,
            keyValue: target.keyValue,
            text: _boundedTransportText(target.text),
            tooltip: _boundedTransportText(target.tooltip),
            typeName: target.typeName,
            routeName: target.routeName,
            supportedCommands: target.supportedCommands,
            control: target.control,
          ),
        )
        .toList(growable: false);
    return CockpitSnapshot(
      routeName: snapshot.routeName,
      visibleTargets: visibleTargets,
      diagnosticLevel: snapshot.diagnosticLevel,
      truncated:
          snapshot.truncated ||
          visibleTargets.length < snapshot.visibleTargets.length,
      diagnosticsArtifactRef: snapshot.diagnosticsArtifactRef,
      treeArtifactRef: snapshot.treeArtifactRef,
      summary: snapshot.summary,
      network: snapshot.network,
      tree: snapshot.tree == null
          ? null
          : CockpitWidgetTree(
              profile: snapshot.tree!.profile,
              total: snapshot.tree!.total,
              visible: snapshot.tree!.visible,
              truncated: snapshot.tree!.truncated,
              emitted: snapshot.tree!.emitted,
            ),
      // Focus state is tiny and answers "is the keyboard up / which field is
      // active" without forcing a diagnostics artifact download.
      focus: snapshot.focus,
    );
  }

  String? _boundedTransportText(String? value) {
    if (value == null || value.length <= _snapshotTransportTextLimit) {
      return value;
    }
    return '${value.substring(0, _snapshotTransportTextLimit)}…';
  }

  Future<_RemoteArtifactEntry?> _artifactEntryFor(
    CockpitRecordingResult result,
  ) async {
    final bytes = result.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return _persistArtifactBytes(
        cockpitSanitizeRemoteArtifactBasename(
          result.artifact?.relativePath ?? 'recording.mp4',
        ),
        bytes,
      );
    }

    final sourceFilePath = result.sourceFilePath;
    if (sourceFilePath == null || sourceFilePath.trim().isEmpty) {
      return null;
    }
    final sourceFile = File(sourceFilePath);
    if (!sourceFile.existsSync() || sourceFile.lengthSync() <= 0) {
      return null;
    }
    return _RemoteArtifactEntry(sourceFilePath: sourceFile.path);
  }

  CockpitRecordingResult _recordingResultForTransport(
    CockpitRecordingResult result, {
    bool includeArtifact = true,
  }) {
    return result.copyWith(
      artifact: includeArtifact ? result.artifact : null,
      bytes: null,
      sourceFilePath: null,
    );
  }

  Future<_RemoteArtifactEntry> _persistArtifactBytes(
    String basename,
    List<int> bytes,
  ) async {
    if (bytes.isEmpty) {
      throw StateError('Cannot persist an empty artifact payload.');
    }
    try {
      final file = await _artifactTempFileFactory(basename);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return _RemoteArtifactEntry(
        sourceFilePath: file.path,
        deleteOnClose: true,
      );
    } on Object {
      return _RemoteArtifactEntry(bytes: List<int>.unmodifiable(bytes));
    }
  }

  Future<CockpitRemoteSessionEndpointResponse> _artifactResponseFor(
    CockpitRemoteSessionEndpointRequest request,
  ) async {
    final relativePath = request.uri.queryParameters['path'];
    if (relativePath == null || relativePath.isEmpty) {
      return const CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'invalidArtifactPath',
        'message': 'Artifact path is required.',
      }, statusCode: HttpStatus.badRequest);
    }

    final entry = _downloadableArtifacts[relativePath];
    if (entry == null) {
      return const CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'artifactNotFound',
        'message': 'Unknown artifact path.',
      }, statusCode: HttpStatus.notFound);
    }

    final bytes = entry.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return CockpitRemoteSessionEndpointResponse.binary(bytes);
    }

    final sourceFilePath = entry.sourceFilePath;
    if (sourceFilePath == null || sourceFilePath.isEmpty) {
      _downloadableArtifacts.remove(relativePath);
      return const CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'artifactNotFound',
        'message': 'Artifact content is unavailable.',
      }, statusCode: HttpStatus.notFound);
    }

    final sourceFile = File(sourceFilePath);
    if (!await sourceFile.exists()) {
      _downloadableArtifacts.remove(relativePath);
      return const CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'artifactNotFound',
        'message': 'Artifact file is no longer available.',
      }, statusCode: HttpStatus.notFound);
    }

    return CockpitRemoteSessionEndpointResponse.binaryFile(sourceFile.path);
  }

  Future<void> _bestEffortStopActiveRecording() async {
    if (_activeRecordingSession == null) {
      return;
    }
    _activeRecordingSession = null;
    try {
      await _stopRecording();
    } on Object {
      // Cleanup is best-effort during server shutdown.
    }
  }

  Future<void> _bestEffortStopActivePerformance() async {
    if (_activePerformanceSession == null || _stopPerformance == null) {
      return;
    }
    _activePerformanceSession = null;
    try {
      await _stopPerformance();
    } on Object {
      // Cleanup is best-effort during server shutdown.
    }
  }

  String _downloadPathFor(String relativePath) {
    final routePrefix = _configuration.normalizedRoutePrefix;
    final endpoint = '$routePrefix/artifacts/download';
    return '$endpoint?path=${Uri.encodeQueryComponent(relativePath)}';
  }
}

Future<File> _defaultArtifactTempFileFactory(String basename) async {
  final safeBasename = basename.isEmpty ? 'artifact.bin' : basename;
  final path = [
    Directory.systemTemp.path,
    '${cockpitSortableTimestampToken(DateTime.now())}_flutter_cockpit_remote_$safeBasename',
  ].join(Platform.pathSeparator);
  return File(path);
}

String cockpitSanitizeRemoteArtifactBasename(String relativePath) {
  final basename = relativePath.split('/').last;
  final sanitized = basename.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return sanitized.isEmpty ? 'artifact.bin' : sanitized;
}

Object? _compactJsonValue(Object? value) {
  if (value is Map<Object?, Object?>) {
    final compacted = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        continue;
      }
      final compactedValue = _compactJsonValue(entry.value);
      if (compactedValue != null) {
        compacted[key] = compactedValue;
      }
    }
    return compacted;
  }
  if (value is List<Object?>) {
    return value.map(_compactJsonValue).toList(growable: false);
  }
  return value;
}
