import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../application/cockpit_application_service_exception.dart';
import '../foundation/cockpit_ids.dart';
import 'cockpit_remote_command_timeout_budget.dart';

typedef CockpitRemoteArtifactTempFileFactory =
    Future<File> Function(String basename);

final class CockpitRemoteCommandCancelledException implements Exception {
  const CockpitRemoteCommandCancelledException();

  @override
  String toString() => 'CockpitRemoteCommandCancelledException';
}

final class CockpitRemoteSessionClient {
  CockpitRemoteSessionClient({
    required Uri baseUri,
    HttpClient Function()? httpClientFactory,
    Duration? requestTimeout,
    Duration? artifactDownloadTimeout,
    CockpitRemoteArtifactTempFileFactory? artifactTempFileFactory,
    bool downloadDiagnosticsArtifacts = false,
  }) : _baseUri = _normalizedBaseUri(baseUri),
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _requestTimeout = requestTimeout ?? const Duration(seconds: 30),
       _artifactDownloadTimeout =
           artifactDownloadTimeout ?? const Duration(seconds: 30),
       _artifactTempFileFactory =
           artifactTempFileFactory ?? _defaultArtifactTempFileFactory,
       _downloadDiagnosticsArtifacts = downloadDiagnosticsArtifacts;

  final Uri _baseUri;
  final HttpClient Function() _httpClientFactory;
  final Duration _requestTimeout;
  final Duration _artifactDownloadTimeout;
  final CockpitRemoteArtifactTempFileFactory _artifactTempFileFactory;
  final bool _downloadDiagnosticsArtifacts;

  Uri get baseUri => _baseUri;

  Future<CockpitRemoteSessionStatus> readStatus() async {
    final payload = await _send(method: 'GET', path: '/health');
    return CockpitRemoteSessionStatus.fromJson(payload);
  }

  Future<bool> ping() async {
    final payload = await _send(method: 'GET', path: '/ping');
    return payload['ok'] == true;
  }

  Future<bool> ready() async {
    final payload = await _send(method: 'GET', path: '/ready');
    return payload['ok'] == true &&
        payload['ready'] != false &&
        payload['supportsInAppControl'] != false;
  }

  Future<CockpitViewportResizeResult> resizeViewport(
    CockpitViewportResizeRequest request, {
    Duration? requestTimeout,
  }) async {
    final payload = await _send(
      method: 'POST',
      path: '/viewport',
      body: request.toJson(),
      requestTimeout: requestTimeout,
    );
    return CockpitViewportResizeResult.fromJson(payload);
  }

  Future<CockpitSnapshot> readSnapshot({
    CockpitSnapshotOptions options = const CockpitSnapshotOptions.live(),
    bool? downloadDiagnosticsArtifacts,
  }) async {
    return (await readSnapshotDetailed(
      options: options,
      downloadDiagnosticsArtifacts: downloadDiagnosticsArtifacts,
    )).snapshot;
  }

  Future<CockpitRemoteSnapshotResponse> readSnapshotDetailed({
    CockpitSnapshotOptions options = const CockpitSnapshotOptions.live(),
    bool? downloadDiagnosticsArtifacts,
  }) async {
    final queryParameters = <String, String>{
      'profile': options.profile.jsonValue,
      'maxTargets': options.maxTargets.toString(),
      'maxAncestorsPerTarget': options.maxAncestorsPerTarget.toString(),
      'maxPropertiesPerTarget': options.maxPropertiesPerTarget.toString(),
      'maxRebuildEntries': options.maxRebuildEntries.toString(),
      'maxAccessibilityEntries': options.maxAccessibilityEntries.toString(),
      'includeStyleDetails': options.includeStyleDetails.toString(),
      'includeDiagnosticProperties': options.includeDiagnosticProperties
          .toString(),
      'emitArtifactWhenLarge': options.emitArtifactWhenLarge.toString(),
      'includeRebuildActivity': options.includeRebuildActivity.toString(),
      'includeAccessibilitySummary': options.includeAccessibilitySummary
          .toString(),
      'includeNetworkActivity': options.includeNetworkActivity.toString(),
      'maxNetworkEntries': options.maxNetworkEntries.toString(),
      'includeRuntimeActivity': options.includeRuntimeActivity.toString(),
      'maxRuntimeEntries': options.maxRuntimeEntries.toString(),
      if (options.tree != null) ...<String, String>{
        'treeProfile': options.tree!.profile.jsonValue,
        'treeMaxNodes': options.tree!.maxNodes.toString(),
        'treeMaxProps': options.tree!.maxProps.toString(),
      },
      if (options.networkQuery.id != null)
        'networkId': options.networkQuery.id!,
      if (options.networkQuery.before != null)
        'networkBefore': options.networkQuery.before!,
      if (options.networkQuery.method != null)
        'networkMethod': options.networkQuery.method!,
      if (options.networkQuery.uriContains != null)
        'networkUriContains': options.networkQuery.uriContains!,
      'networkOnlyFailures': options.networkQuery.onlyFailures.toString(),
      'runtimeOnlyErrors': options.runtimeQuery.onlyErrors.toString(),
      if (options.runtimeQuery.messageContains != null)
        'runtimeMessageContains': options.runtimeQuery.messageContains!,
      if (options.networkQuery.statusCodeAtLeast != null)
        'networkStatusCodeAtLeast': options.networkQuery.statusCodeAtLeast!
            .toString(),
    };
    final payload = await _send(
      method: 'GET',
      path: Uri(path: '/snapshot', queryParameters: queryParameters).toString(),
    );
    if (!payload.containsKey('snapshot')) {
      return CockpitRemoteSnapshotResponse(
        snapshot: CockpitSnapshot.fromJson(payload),
      );
    }

    final response = CockpitRemoteSnapshotResponse.fromJson(payload);
    final diagnosticsArtifactRef = response.snapshot.diagnosticsArtifactRef;
    final treeArtifactRef = response.snapshot.treeArtifactRef;
    final artifactRef = diagnosticsArtifactRef ?? treeArtifactRef;
    if (artifactRef == null) {
      return response;
    }
    if (!(downloadDiagnosticsArtifacts ?? _downloadDiagnosticsArtifacts)) {
      return response;
    }
    final download = response.artifactDownloads.firstWhere(
      (candidate) =>
          candidate.artifact.relativePath == artifactRef.relativePath,
      orElse: () => const CockpitRemoteArtifactDownload(
        artifact: CockpitArtifactRef(role: '', relativePath: ''),
        downloadPath: '',
      ),
    );
    if (download.downloadPath.isEmpty) {
      return response;
    }

    final bytes = await _download(download.downloadPath);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<Object?, Object?>) {
      throw StateError(
        'Remote snapshot artifact must decode to a JSON object.',
      );
    }
    final fullSnapshot = diagnosticsArtifactRef != null
        ? CockpitSnapshot.fromJson(
            Map<String, Object?>.from(decoded),
          ).copyWith(diagnosticsArtifactRef: diagnosticsArtifactRef)
        : response.snapshot.copyWith(
            tree: CockpitWidgetTree.fromJson(
              Map<String, Object?>.from(decoded),
            ),
            treeArtifactRef: treeArtifactRef,
          );
    return response.copyWith(snapshot: fullSnapshot);
  }

  Future<CockpitCommandResult> execute(
    CockpitCommand command, {
    Duration? requestTimeout,
  }) async {
    return (await executeDetailed(
      command,
      requestTimeout: requestTimeout,
    )).result;
  }

  Future<bool> waitForUiIdle({
    Duration quietWindow = const Duration(milliseconds: 96),
    Duration timeout = const Duration(milliseconds: 1600),
    bool includeNetworkIdle = true,
  }) async {
    try {
      final result = await execute(
        CockpitCommand(
          commandId: CockpitSecureTokenGenerator().nextResourceId('w'),
          commandType: CockpitCommandType.waitForUiIdle,
          parameters: <String, Object?>{
            'quietWindowMs': quietWindow.inMilliseconds,
            'timeoutMs': timeout.inMilliseconds,
            'includeNetworkIdle': includeNetworkIdle,
          },
          timeoutMs: timeout.inMilliseconds,
        ),
        requestTimeout: timeout + const Duration(milliseconds: 250),
      );
      return result.success;
    } on Object {
      return false;
    }
  }

  Future<CockpitCommandExecution> executeDetailed(
    CockpitCommand command, {
    Duration? requestTimeout,
    Future<void>? cancellation,
  }) async {
    final payload = await _send(
      method: 'POST',
      path: '/commands/execute',
      body: command.toJson(),
      cancellation: cancellation,
      requestTimeout:
          requestTimeout ??
          cockpitRemoteCommandTransportTimeoutForCommand(
            command,
            minimumTimeout: _requestTimeout,
          ),
    );
    if (payload.containsKey('result')) {
      final response = CockpitRemoteCommandResponse.fromJson(payload);
      final artifactSourcePaths = await _downloadCommandArtifacts(
        response,
        cancellation: cancellation,
      );
      final result = _withDownloadedArtifactRefs(response);
      return CockpitCommandExecution(
        result: result,
        artifactPayloads: <String, List<int>>{
          for (final payload in response.artifactPayloads)
            payload.artifact.relativePath: payload.bytes,
        },
        artifactSourcePaths: artifactSourcePaths,
        runtimeSteps: response.runtimeSteps,
      );
    }
    return CockpitCommandExecution(
      result: CockpitCommandResult.fromJson(payload),
    );
  }

  CockpitCommandResult _withDownloadedArtifactRefs(
    CockpitRemoteCommandResponse response,
  ) {
    if (response.artifactDownloads.isEmpty) {
      return response.result;
    }
    final existingPaths = response.result.artifacts
        .map((artifact) => artifact.relativePath)
        .toSet();
    final downloadedArtifacts = <CockpitArtifactRef>[];
    for (final download in response.artifactDownloads) {
      final artifact = download.artifact;
      if (artifact.relativePath.isEmpty ||
          !existingPaths.add(artifact.relativePath)) {
        continue;
      }
      downloadedArtifacts.add(artifact);
    }
    if (downloadedArtifacts.isEmpty) {
      return response.result;
    }
    final result = response.result;
    return CockpitCommandResult(
      success: result.success,
      commandId: result.commandId,
      commandType: result.commandType,
      locatorResolution: result.locatorResolution,
      durationMs: result.durationMs,
      artifacts: <CockpitArtifactRef>[
        ...result.artifacts,
        ...downloadedArtifacts,
      ],
      snapshot: result.snapshot,
      requestedCaptureProfile: result.requestedCaptureProfile,
      resolvedCaptureKind: result.resolvedCaptureKind,
      usedCaptureFallback: result.usedCaptureFallback,
      degradationReason: result.degradationReason,
      surface: result.surface,
      changed: result.changed,
      error: result.error,
    );
  }

  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    final payload = await _send(
      method: 'POST',
      path: '/recording/start',
      body: request.toJson(),
    );
    return CockpitRecordingSession.fromJson(payload);
  }

  Future<CockpitRecordingResult> stopRecording() async {
    return (await stopRecordingDetailed()).result;
  }

  Future<CockpitRemoteRecordingResponse> stopRecordingDetailed() async {
    final payload = await _send(
      method: 'POST',
      path: '/recording/stop',
      body: const <String, Object?>{},
    );
    final response = CockpitRemoteRecordingResponse.fromJson(payload);
    final artifact = response.result.artifact;
    if (artifact == null) {
      return response;
    }
    final download = response.artifactDownloads.firstWhere(
      (candidate) => candidate.artifact.relativePath == artifact.relativePath,
      orElse: () => const CockpitRemoteArtifactDownload(
        artifact: CockpitArtifactRef(role: '', relativePath: ''),
        downloadPath: '',
      ),
    );
    if (download.downloadPath.isEmpty) {
      return response;
    }

    final sourceFile = await _downloadToFile(
      download.downloadPath,
      artifactRelativePath: artifact.relativePath,
    );
    return CockpitRemoteRecordingResponse(
      result: CockpitRecordingResult(
        state: response.result.state,
        purpose: response.result.purpose,
        recordingKind: response.result.recordingKind,
        requestedMode: response.result.requestedMode,
        requestedLayer: response.result.requestedLayer,
        effectiveLayer: response.result.effectiveLayer,
        fallbackUsed: response.result.fallbackUsed,
        fallbackReason: response.result.fallbackReason,
        artifact: response.result.artifact,
        durationMs: response.result.durationMs,
        sourceFilePath: sourceFile.path,
        failureReason: response.result.failureReason,
      ),
      artifactDownloads: response.artifactDownloads,
    );
  }

  Future<Map<String, String>> downloadArtifactsToFiles(
    Iterable<CockpitRemoteArtifactDownload> downloads, {
    Future<void>? cancellation,
  }) async {
    final sourcePaths = <String, String>{};
    for (final download in downloads) {
      final relativePath = download.artifact.relativePath;
      if (relativePath.isEmpty || download.downloadPath.isEmpty) {
        continue;
      }
      final sourceFile = await _downloadToFile(
        download.downloadPath,
        artifactRelativePath: relativePath,
        cancellation: cancellation,
      );
      sourcePaths[relativePath] = sourceFile.path;
    }
    return sourcePaths;
  }

  Future<Map<String, String>> _downloadCommandArtifacts(
    CockpitRemoteCommandResponse response, {
    Future<void>? cancellation,
  }) => downloadArtifactsToFiles(
    response.artifactDownloads,
    cancellation: cancellation,
  );

  Future<Map<String, Object?>> _send({
    required String method,
    required String path,
    Map<String, Object?>? body,
    Duration? requestTimeout,
    Future<void>? cancellation,
  }) async {
    final client = _httpClientFactory();
    try {
      final requestFuture =
          (() async {
            final request = await client.openUrl(
              method,
              _resolveRemotePath(path),
            );
            if (body != null) {
              request.headers.contentType = ContentType.json;
              request.write(jsonEncode(body));
            }

            final response = await request.close();
            final payload = await utf8.decoder.bind(response).join();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              final remoteError = _structuredRemoteError(payload);
              if (_isTransientRemoteHttpError(remoteError.code)) {
                throw _remoteUnavailable(
                  method: method,
                  path: path,
                  error: StateError(remoteError.message),
                  remoteCode: remoteError.code,
                  remoteMessage: remoteError.message,
                  remoteDetails: remoteError.remoteDetails,
                  statusCode: response.statusCode,
                );
              }
              throw _remoteHttpError(
                statusCode: response.statusCode,
                method: method,
                path: path,
                payload: payload,
              );
            }
            if (payload.isEmpty) {
              throw StateError('Remote session returned an empty response.');
            }

            final decoded = jsonDecode(payload);
            if (decoded is! Map<Object?, Object?>) {
              throw StateError(
                'Remote session response must be a JSON object.',
              );
            }
            return Map<String, Object?>.from(decoded);
          })().timeout(
            requestTimeout ?? _requestTimeout,
            onTimeout: () {
              client.close(force: true);
              throw TimeoutException(
                'Remote session request timed out for $method $path.',
              );
            },
          );
      return await _awaitRemoteCancellation(
        requestFuture,
        client: client,
        cancellation: cancellation,
      );
    } on CockpitRemoteCommandCancelledException {
      rethrow;
    } on SocketException catch (error) {
      throw _remoteUnavailable(method: method, path: path, error: error);
    } on HttpException catch (error) {
      throw _remoteUnavailable(method: method, path: path, error: error);
    } on TimeoutException catch (error) {
      throw _remoteUnavailable(method: method, path: path, error: error);
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> _download(
    String relativePath, {
    Future<void>? cancellation,
  }) async {
    for (
      var attempt = 0;
      attempt < _artifactDownloadMaxAttempts;
      attempt += 1
    ) {
      try {
        return await _downloadOnce(relativePath, cancellation: cancellation);
      } on CockpitApplicationServiceException catch (error) {
        if (error.code != 'remoteUnavailable' ||
            attempt + 1 >= _artifactDownloadMaxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(_artifactDownloadRetryDelay(attempt));
      }
    }
    throw StateError('Unreachable artifact download retry state.');
  }

  Future<List<int>> _downloadOnce(
    String relativePath, {
    Future<void>? cancellation,
  }) async {
    final client = _httpClientFactory();
    try {
      final requestFuture =
          (() async {
            final request = await client.getUrl(
              _resolveRemotePath(relativePath),
            );
            final response = await request.close();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              final payload = await utf8.decoder.bind(response).join();
              throw _remoteHttpError(
                statusCode: response.statusCode,
                method: 'GET',
                path: relativePath,
                payload: payload,
              );
            }

            final bytes = BytesBuilder(copy: false);
            await for (final chunk in response) {
              bytes.add(chunk);
            }
            return bytes.takeBytes();
          })().timeout(
            _artifactDownloadTimeout,
            onTimeout: () {
              client.close(force: true);
              throw TimeoutException(
                'Remote session artifact download timed out for $relativePath.',
              );
            },
          );
      return await _awaitRemoteCancellation(
        requestFuture,
        client: client,
        cancellation: cancellation,
      );
    } on CockpitRemoteCommandCancelledException {
      rethrow;
    } on SocketException catch (error) {
      throw _remoteUnavailable(method: 'GET', path: relativePath, error: error);
    } on HttpException catch (error) {
      throw _remoteUnavailable(method: 'GET', path: relativePath, error: error);
    } on TimeoutException catch (error) {
      throw _remoteUnavailable(method: 'GET', path: relativePath, error: error);
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _downloadToFile(
    String relativePath, {
    required String artifactRelativePath,
    Future<void>? cancellation,
  }) async {
    for (
      var attempt = 0;
      attempt < _artifactDownloadMaxAttempts;
      attempt += 1
    ) {
      try {
        return await _downloadToFileOnce(
          relativePath,
          artifactRelativePath: artifactRelativePath,
          cancellation: cancellation,
        );
      } on CockpitApplicationServiceException catch (error) {
        if (error.code != 'remoteUnavailable' ||
            attempt + 1 >= _artifactDownloadMaxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(_artifactDownloadRetryDelay(attempt));
      }
    }
    throw StateError('Unreachable artifact download retry state.');
  }

  Future<File> _downloadToFileOnce(
    String relativePath, {
    required String artifactRelativePath,
    Future<void>? cancellation,
  }) async {
    final client = _httpClientFactory();
    File? outputFile;
    try {
      final requestFuture =
          (() async {
            final request = await client.getUrl(
              _resolveRemotePath(relativePath),
            );
            final response = await request.close();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              final payload = await utf8.decoder.bind(response).join();
              throw _remoteHttpError(
                statusCode: response.statusCode,
                method: 'GET',
                path: relativePath,
                payload: payload,
              );
            }

            outputFile = await _artifactTempFileFactory(
              _sanitizeArtifactBasename(artifactRelativePath),
            );
            await outputFile!.parent.create(recursive: true);
            if (await outputFile!.exists()) {
              await outputFile!.delete();
            }

            final sink = outputFile!.openWrite();
            try {
              await response.pipe(sink);
            } catch (_) {
              await sink.close();
              rethrow;
            }
            if (await outputFile!.length() <= 0) {
              throw CockpitApplicationServiceException(
                code: 'artifactDownloadEmpty',
                message:
                    'Remote session artifact download produced an empty file.',
                details: <String, Object?>{
                  'baseUrl': _baseUri.toString(),
                  'path': relativePath,
                  'artifactPath': artifactRelativePath,
                },
              );
            }
            return outputFile!;
          })().timeout(
            _artifactDownloadTimeout,
            onTimeout: () {
              client.close(force: true);
              throw TimeoutException(
                'Remote session artifact download timed out for $relativePath.',
              );
            },
          );
      return await _awaitRemoteCancellation(
        requestFuture,
        client: client,
        cancellation: cancellation,
      );
    } on CockpitRemoteCommandCancelledException {
      await _deletePartialDownload(outputFile);
      rethrow;
    } on SocketException catch (error) {
      await _deletePartialDownload(outputFile);
      throw _remoteUnavailable(method: 'GET', path: relativePath, error: error);
    } on HttpException catch (error) {
      await _deletePartialDownload(outputFile);
      throw _remoteUnavailable(method: 'GET', path: relativePath, error: error);
    } on TimeoutException catch (error) {
      await _deletePartialDownload(outputFile);
      throw _remoteUnavailable(method: 'GET', path: relativePath, error: error);
    } catch (_) {
      await _deletePartialDownload(outputFile);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _deletePartialDownload(File? file) async {
    if (file == null) {
      return;
    }
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // The caller already has the actionable transport or parse failure.
    }
  }

  Future<T> _awaitRemoteCancellation<T>(
    Future<T> operation, {
    required HttpClient client,
    required Future<void>? cancellation,
  }) {
    if (cancellation == null) return operation;
    return Future.any<T>(<Future<T>>[
      operation,
      cancellation.then<T>((_) {
        client.close(force: true);
        throw const CockpitRemoteCommandCancelledException();
      }),
    ]);
  }

  CockpitApplicationServiceException _remoteUnavailable({
    required String method,
    required String path,
    required Object error,
    String? remoteCode,
    String? remoteMessage,
    Map<String, Object?>? remoteDetails,
    int? statusCode,
  }) {
    return CockpitApplicationServiceException(
      code: 'remoteUnavailable',
      message:
          'Remote session is temporarily unavailable. The app may still be launching, restarting, or reconnecting; wait and retry.',
      details: <String, Object?>{
        'baseUrl': _baseUri.toString(),
        'method': method,
        'path': path,
        'errorType': error.runtimeType.toString(),
        'cause': error.toString(),
        'remoteCode': ?remoteCode,
        'remoteMessage': ?remoteMessage,
        'remoteDetails': ?remoteDetails,
        'statusCode': ?statusCode,
      },
    );
  }

  bool _isTransientRemoteHttpError(String code) {
    return code == 'bridgeUnavailable' || code == 'bridgeTimeout';
  }

  CockpitApplicationServiceException _remoteHttpError({
    required int statusCode,
    required String method,
    required String path,
    required String payload,
  }) {
    final parsed = _structuredRemoteError(payload);
    return CockpitApplicationServiceException(
      code: parsed.code,
      message: parsed.message,
      details: <String, Object?>{
        'baseUrl': _baseUri.toString(),
        'method': method,
        'path': path,
        'statusCode': statusCode,
        if (parsed.remoteDetails.isNotEmpty)
          'remoteDetails': parsed.remoteDetails,
        if (parsed.code == 'remoteHttpError' && payload.isNotEmpty)
          'body': payload,
      },
    );
  }

  _StructuredRemoteError _structuredRemoteError(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<Object?, Object?>) {
        return _StructuredRemoteError(
          code: 'remoteHttpError',
          message: 'Remote session request failed.',
        );
      }
      final error = decoded['error'];
      final message = decoded['message'];
      final details = decoded['details'];
      return _StructuredRemoteError(
        code: error is String && error.isNotEmpty ? error : 'remoteHttpError',
        message: message is String && message.isNotEmpty
            ? message
            : 'Remote session request failed.',
        remoteDetails: details is Map<Object?, Object?>
            ? Map<String, Object?>.from(details)
            : const <String, Object?>{},
      );
    } on FormatException {
      return _StructuredRemoteError(
        code: 'remoteHttpError',
        message: 'Remote session request failed.',
      );
    }
  }

  static Uri _normalizedBaseUri(Uri uri) {
    return uri.path.isEmpty
        ? uri.replace(path: '/')
        : uri.path.endsWith('/')
        ? uri
        : uri.replace(path: '${uri.path}/');
  }

  Uri _resolveRemotePath(String path) {
    final uri = Uri.parse(path);
    if (uri.hasScheme) {
      _validateRemoteUri(uri, originalPath: path);
      return uri;
    }
    if (!path.startsWith('/')) {
      return _baseUri.resolve(path);
    }

    final basePath = _baseUri.path.endsWith('/') && _baseUri.path.length > 1
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    final alreadyScoped =
        basePath.isNotEmpty &&
        basePath != '/' &&
        (uri.path == basePath || uri.path.startsWith('$basePath/'));
    if (alreadyScoped || basePath.isEmpty || basePath == '/') {
      return _baseUri.replace(
        path: uri.path,
        query: uri.hasQuery ? uri.query : null,
        fragment: uri.hasFragment ? uri.fragment : null,
      );
    }

    return _baseUri.resolve(path.substring(1));
  }

  void _validateRemoteUri(Uri uri, {required String originalPath}) {
    final basePort = _effectivePort(_baseUri);
    final uriPort = _effectivePort(uri);
    if (uri.scheme == _baseUri.scheme &&
        uri.host == _baseUri.host &&
        uriPort == basePort) {
      return;
    }
    throw CockpitApplicationServiceException(
      code: 'invalidArtifactUrl',
      message:
          'Remote artifact downloads must stay on the same remote session origin.',
      details: <String, Object?>{
        'baseUrl': _baseUri.toString(),
        'path': originalPath,
      },
    );
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    return switch (uri.scheme) {
      'http' => 80,
      'https' => 443,
      _ => 0,
    };
  }
}

const int _artifactDownloadMaxAttempts = 3;

Duration _artifactDownloadRetryDelay(int attempt) {
  return Duration(milliseconds: 100 * (attempt + 1));
}

final class _StructuredRemoteError {
  const _StructuredRemoteError({
    required this.code,
    required this.message,
    this.remoteDetails = const <String, Object?>{},
  });

  final String code;
  final String message;
  final Map<String, Object?> remoteDetails;
}

Future<File> _defaultArtifactTempFileFactory(String basename) async {
  final directory = await Directory.systemTemp.createTemp(
    'flutter_cockpit_remote_artifact_',
  );
  return File(p.join(directory.path, basename));
}

String _sanitizeArtifactBasename(String relativePath) {
  final basename = p.basename(relativePath);
  final sanitized = basename.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return sanitized.isEmpty ? 'artifact.bin' : sanitized;
}
