import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_internal_process.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_version.dart';
import 'cockpit_daemon_client.dart';
import 'cockpit_daemon_discovery.dart';

const cockpitSupervisorMaximumResponseBytes = 1024 * 1024;
const cockpitSupervisorMaximumPageItems = 1000;

typedef CockpitHttpClientFactory = HttpClient Function();

final class CockpitSupervisorClientException implements Exception {
  const CockpitSupervisorClientException({
    required this.code,
    required this.message,
    this.apiError,
  });

  final String code;
  final String message;
  final CockpitApiError? apiError;

  @override
  String toString() => '$code: $message';
}

final class CockpitRetirementResponse {
  const CockpitRetirementResponse({
    required this.id,
    required this.tombstoneRetained,
    required this.referenceCounts,
  });

  final String id;
  final bool tombstoneRetained;
  final Map<String, int> referenceCounts;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'tombstoneRetained': tombstoneRetained,
    'referenceCounts': referenceCounts,
  };
}

sealed class CockpitRunStreamItem {
  const CockpitRunStreamItem();
}

final class CockpitRunStreamEvent extends CockpitRunStreamItem {
  const CockpitRunStreamEvent(this.event);

  final CockpitRunEvent event;
}

final class CockpitRunStreamGap extends CockpitRunStreamItem {
  const CockpitRunStreamGap(this.boundary);

  final CockpitEventReplayBoundary boundary;
}

final class CockpitRunStreamTerminal extends CockpitRunStreamItem {
  const CockpitRunStreamTerminal({required this.afterSequence});

  final int afterSequence;
}

final class CockpitRunStreamDisconnected extends CockpitRunStreamItem {
  const CockpitRunStreamDisconnected({required this.afterSequence});

  final int afterSequence;
}

final class CockpitArtifactDownloadReceipt {
  const CockpitArtifactDownloadReceipt({
    required this.file,
    required this.mediaType,
    required this.sizeBytes,
    required this.sha256,
  });

  final File file;
  final String mediaType;
  final int sizeBytes;
  final String sha256;
}

final class CockpitSupervisorApiClient {
  CockpitSupervisorApiClient({
    required this.lifecycle,
    CockpitHttpClientFactory? httpClientFactory,
    CockpitApiVersion? apiVersion,
    Iterable<String> requiredFeatures = const <String>[],
    this.maximumResponseBytes = cockpitSupervisorMaximumResponseBytes,
    this.maximumPageItems = cockpitSupervisorMaximumPageItems,
    Duration requestTimeout = const Duration(seconds: 30),
  }) : apiVersion = apiVersion ?? CockpitApiVersion(major: 2, minor: 0),
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _requestTimeout = requestTimeout,
       requiredFeatures = List<String>.unmodifiable(requiredFeatures) {
    if (maximumResponseBytes < 1 || maximumResponseBytes > 16 * 1024 * 1024) {
      throw ArgumentError.value(maximumResponseBytes, 'maximumResponseBytes');
    }
    if (maximumPageItems < 1 || maximumPageItems > 10000) {
      throw ArgumentError.value(maximumPageItems, 'maximumPageItems');
    }
    _validateRequestTimeout(requestTimeout);
    CockpitNegotiationRequest(
      apiVersion: this.apiVersion,
      requiredFeatures: this.requiredFeatures,
    );
  }

  final CockpitDaemonLifecycleClient lifecycle;
  final CockpitApiVersion apiVersion;
  final List<String> requiredFeatures;
  final int maximumResponseBytes;
  final int maximumPageItems;
  final CockpitHttpClientFactory _httpClientFactory;
  Duration _requestTimeout;

  _CockpitSupervisorSession? _session;

  Duration get requestTimeout => _requestTimeout;

  set requestTimeout(Duration value) {
    _validateRequestTimeout(value);
    _requestTimeout = value;
  }

  Future<CockpitServerInfo> server() async => (await _ensureSession()).server;

  Future<CockpitCapabilityDocument> capabilities() async {
    final session = await _ensureSession();
    final json = await _jsonRequest(session, 'GET', '/api/v2/capabilities');
    return CockpitCapabilityDocument.fromJson(
      json,
      decodePolicy: session.decodePolicy,
    );
  }

  Future<List<CockpitRootResource>> roots() => _allPages(
    '/api/v2/roots',
    (value, path, policy) =>
        CockpitRootResource.fromJson(value, path: path, decodePolicy: policy),
  );

  Future<CockpitRootResource> registerRoot(
    CockpitRootRegistration registration,
  ) async {
    final session = await _ensureSession();
    return CockpitRootResource.fromJson(
      await _jsonRequest(
        session,
        'POST',
        '/api/v2/roots',
        body: registration.toJson(),
      ),
      decodePolicy: session.decodePolicy,
    );
  }

  Future<CockpitRetirementResponse> removeRoot(
    String rootId,
    CockpitRootRemoval removal,
  ) async {
    final session = await _ensureSession();
    return _decodeRetirement(
      await _jsonRequest(
        session,
        'DELETE',
        '/api/v2/roots/${_segment(rootId)}',
        body: removal.toJson(),
      ),
    );
  }

  Future<List<CockpitWorkspaceResource>> workspaces() => _allPages(
    '/api/v2/workspaces',
    (value, path, policy) => CockpitWorkspaceResource.fromJson(
      value,
      path: path,
      decodePolicy: policy,
    ),
  );

  Future<CockpitWorkspaceResource> registerWorkspace(
    CockpitWorkspaceRegistration registration,
  ) async {
    final session = await _ensureSession();
    return CockpitWorkspaceResource.fromJson(
      await _jsonRequest(
        session,
        'POST',
        '/api/v2/workspaces/register',
        body: registration.toJson(),
      ),
      decodePolicy: session.decodePolicy,
    );
  }

  Future<CockpitWorkspaceResource> rebindWorkspace(
    String workspaceId,
    CockpitWorkspaceRebind rebind,
  ) async {
    final session = await _ensureSession();
    return CockpitWorkspaceResource.fromJson(
      await _jsonRequest(
        session,
        'POST',
        '/api/v2/workspaces/${_segment(workspaceId)}/rebind',
        body: rebind.toJson(),
      ),
      decodePolicy: session.decodePolicy,
    );
  }

  Future<CockpitRetirementResponse> removeWorkspace(
    String workspaceId,
    CockpitWorkspaceRemoval removal,
  ) async {
    final session = await _ensureSession();
    return _decodeRetirement(
      await _jsonRequest(
        session,
        'DELETE',
        '/api/v2/workspaces/${_segment(workspaceId)}',
        body: removal.toJson(),
      ),
    );
  }

  Future<List<CockpitAutomationTargetResource>> targets(String workspaceId) =>
      _allPages(
        '/api/v2/workspaces/${_segment(workspaceId)}/targets',
        (value, path, policy) => CockpitAutomationTargetResource.fromJson(
          value,
          path: path,
          decodePolicy: policy,
        ),
      );

  Future<CockpitAutomationTargetResource> target(
    String workspaceId,
    String targetId,
  ) async {
    final session = await _ensureSession();
    return CockpitAutomationTargetResource.fromJson(
      await _jsonRequest(
        session,
        'GET',
        '/api/v2/workspaces/${_segment(workspaceId)}/targets/${_segment(targetId)}',
      ),
      decodePolicy: session.decodePolicy,
    );
  }

  Future<List<CockpitOperationDescriptor>> operations({String? workspaceId}) =>
      _allPages(
        workspaceId == null
            ? '/api/v2/operations'
            : '/api/v2/workspaces/${_segment(workspaceId)}/operations',
        (value, path, policy) => CockpitOperationDescriptor.fromJson(
          value,
          path: path,
          decodePolicy: policy,
        ),
      );

  Future<Map<String, Object?>> operationSchema() async {
    final session = await _ensureSession();
    final value = await _jsonRequest(
      session,
      'GET',
      '/api/v2/operations/schema',
    );
    if (value is! Map<Object?, Object?> ||
        value.keys.any((key) => key is! String)) {
      throw const CockpitSupervisorClientException(
        code: 'invalidOperationSchema',
        message: 'Supervisor returned an invalid operation schema resource.',
      );
    }
    return Map<String, Object?>.from(value);
  }

  Future<CockpitOperationResult> executeOperation(
    CockpitOperationInvocation invocation,
  ) async {
    final workspaceId = invocation.workspaceId;
    final descriptors = await operations(workspaceId: workspaceId);
    final matches = descriptors.where((item) => item.kind == invocation.kind);
    if (matches.length != 1) {
      throw CockpitSupervisorClientException(
        code: CockpitErrorCode.unsupportedOperation,
        message: 'Operation ${invocation.kind} is not advertised.',
      );
    }
    return executeAdvertisedOperation(invocation, descriptor: matches.single);
  }

  Future<CockpitOperationResult> executeAdvertisedOperation(
    CockpitOperationInvocation invocation, {
    required CockpitOperationDescriptor descriptor,
  }) async {
    if (descriptor.kind != invocation.kind) {
      throw CockpitSupervisorClientException(
        code: CockpitErrorCode.unsupportedOperation,
        message:
            'Advertised operation ${descriptor.kind} does not match '
            '${invocation.kind}.',
      );
    }
    _validateInvocation(descriptor, invocation);
    final workspaceId = invocation.workspaceId;
    final session = await _ensureSession();
    final path = workspaceId == null
        ? '/api/v2/operations'
        : '/api/v2/workspaces/${_segment(workspaceId)}/operations';
    final deadline = invocation.deadline;
    final requestTimeout = deadline == null
        ? null
        : _remainingRequestTime(deadline, 'POST', path);
    return CockpitOperationResult.fromJson(
      await _jsonRequest(
        session,
        'POST',
        path,
        body: invocation.toJson(),
        requestTimeout: requestTimeout,
      ),
      decodePolicy: session.decodePolicy,
    );
  }

  Future<List<CockpitDocumentResource>> documents(
    String workspaceId, {
    CockpitIndexedDocumentKind? kind,
    String? relativePath,
    bool authoredOnly = false,
  }) {
    if (authoredOnly && kind != null) {
      throw ArgumentError('authoredOnly and kind are mutually exclusive.');
    }
    return _allPages(
      Uri.parse('/api/v2/workspaces/${_segment(workspaceId)}/documents')
          .replace(
            queryParameters: <String, String>{
              if (authoredOnly)
                'kind': 'authored'
              else if (kind != null)
                'kind': kind == CockpitIndexedDocumentKind.testCase
                    ? 'case'
                    : kind.name,
              'relativePath': ?relativePath,
            },
          )
          .toString(),
      (value, path, policy) => CockpitDocumentResource.fromJson(
        value,
        path: path,
        decodePolicy: policy,
      ),
    );
  }

  Future<List<CockpitCaseIndexEntry>> cases(String workspaceId) => _allPages(
    '/api/v2/workspaces/${_segment(workspaceId)}/cases',
    (value, path, policy) =>
        CockpitCaseIndexEntry.fromJson(value, path: path, decodePolicy: policy),
  );

  Future<CockpitDocumentValidationResult> validateCaseDocument(
    String workspaceId,
    CockpitDocumentValidationRequest request,
  ) async {
    final session = await _ensureSession();
    return CockpitDocumentValidationResult.fromJson(
      await _jsonRequest(
        session,
        'POST',
        '/api/v2/workspaces/${_segment(workspaceId)}/documents/validate',
        body: request.toJson(),
      ),
      decodePolicy: session.decodePolicy,
    );
  }

  Future<CockpitRunAccepted> submitRun(CockpitRunSubmission submission) async {
    final session = await _ensureSession();
    return CockpitRunAccepted.fromJson(
      await _jsonRequest(
        session,
        'POST',
        '/api/v2/workspaces/${_segment(submission.workspaceId)}/runs',
        body: submission.toJson(),
      ),
      decodePolicy: session.decodePolicy,
    );
  }

  Future<CockpitRunResource> run(String runId) async {
    final session = await _ensureSession();
    return CockpitRunResource.fromJson(
      await _jsonRequest(session, 'GET', '/api/v2/runs/${_segment(runId)}'),
      decodePolicy: session.decodePolicy,
    );
  }

  Future<CockpitTestSuiteReport> report(String runId) async {
    final session = await _ensureSession();
    return CockpitTestSuiteReport.fromJson(
      await _jsonRequest(
        session,
        'GET',
        '/api/v2/runs/${_segment(runId)}/report',
      ),
    );
  }

  Future<CockpitRunCancellation> cancelRun(
    String runId,
    CockpitRunCancellationRequest request,
  ) async {
    final session = await _ensureSession();
    return CockpitRunCancellation.fromJson(
      await _jsonRequest(
        session,
        'POST',
        '/api/v2/runs/${_segment(runId)}/cancel',
        body: request.toJson(),
      ),
      decodePolicy: session.decodePolicy,
    );
  }

  Future<List<CockpitRunCaseResource>> runCases(String runId) => _allPages(
    '/api/v2/runs/${_segment(runId)}/cases',
    (value, path, policy) => CockpitRunCaseResource.fromJson(
      value,
      path: path,
      decodePolicy: policy,
    ),
  );

  Future<List<CockpitArtifactResource>> artifacts(String runId) => _allPages(
    '/api/v2/runs/${_segment(runId)}/artifacts',
    (value, path, policy) => CockpitArtifactResource.fromJson(
      value,
      path: path,
      decodePolicy: policy,
    ),
  );

  Future<List<T>> _allPages<T>(
    String path,
    T Function(Object? value, String path, CockpitDecodePolicy policy) decode,
  ) async {
    final session = await _ensureSession();
    final items = <T>[];
    String? cursor;
    final cursors = <String>{};
    do {
      final baseUri = Uri.parse(path);
      final uri = baseUri.replace(
        queryParameters: <String, String>{
          ...baseUri.queryParameters,
          'limit': '100',
          'cursor': ?cursor,
        },
      );
      final page = CockpitPage.fromJson<T>(
        await _jsonRequest(session, 'GET', uri.toString()),
        decode,
        decodePolicy: session.decodePolicy,
      );
      if (items.length + page.items.length > maximumPageItems) {
        throw const CockpitSupervisorClientException(
          code: 'paginationLimitExceeded',
          message: 'Paginated response exceeds the client item bound.',
        );
      }
      items.addAll(page.items);
      cursor = page.nextCursor;
      if (cursor != null && !cursors.add(cursor)) {
        throw const CockpitSupervisorClientException(
          code: 'paginationCursorLoop',
          message: 'Supervisor repeated a pagination cursor.',
        );
      }
    } while (cursor != null);
    return List<T>.unmodifiable(items);
  }

  Stream<CockpitRunStreamItem> events(
    String runId, {
    int afterSequence = 0,
    String? lastEventId,
  }) async* {
    final cursor = CockpitEventCursor(
      afterSequence: afterSequence,
      lastEventId: lastEventId,
    );
    final session = await _ensureSession();
    final client = _httpClientFactory()..connectionTimeout = _requestTimeout;
    var terminal = false;
    var gap = false;
    var sequence = cursor.afterSequence;
    try {
      final uri = session.discovery.endpoint.resolve(
        '/api/v2/runs/${_segment(runId)}/events?afterSequence=$afterSequence',
      );
      final request = await client
          .getUrl(uri)
          .timeout(
            _requestTimeout,
            onTimeout: () => throw _requestTimedOut('GET', uri.path),
          );
      _authorize(request, session);
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      if (lastEventId != null) {
        request.headers.set('Last-Event-ID', lastEventId);
      }
      final response = await request.close().timeout(
        _requestTimeout,
        onTimeout: () => throw _requestTimedOut('GET', uri.path),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final value = _decodeJson(
          await _boundedBytes(response, maximumResponseBytes),
        );
        throw _decodeApiError(response.statusCode, value);
      }
      if (response.headers.contentType?.mimeType != 'text/event-stream') {
        await response.drain<void>();
        throw const CockpitSupervisorClientException(
          code: 'invalidEventStream',
          message: 'Supervisor returned an invalid event stream media type.',
        );
      }
      var frame = _SseFrame();
      await for (final line
          in response
              .transform(const Utf8Decoder(allowMalformed: false))
              .transform(const LineSplitter())) {
        frame.add(line, maximumResponseBytes);
        if (line.isNotEmpty) continue;
        final item = frame.decode(session.decodePolicy);
        frame = _SseFrame();
        if (item == null) continue;
        if (item is CockpitRunStreamEvent) {
          if (item.event.runId != runId ||
              item.event.sequence != sequence + 1) {
            throw const CockpitSupervisorClientException(
              code: 'invalidEventSequence',
              message: 'Supervisor event stream is not contiguous.',
            );
          }
          sequence = item.event.sequence;
          yield item;
          if (item.event.entityKind == CockpitRunEventEntityKind.run &&
              item.event.lifecycle == CockpitRunLifecycle.completed) {
            terminal = true;
            yield CockpitRunStreamTerminal(afterSequence: sequence);
            return;
          }
        } else if (item is CockpitRunStreamGap) {
          gap = true;
          yield item;
          return;
        }
      }
      final trailing = frame.decode(session.decodePolicy);
      if (trailing != null) {
        throw const CockpitSupervisorClientException(
          code: 'invalidEventStream',
          message: 'Supervisor closed an unterminated event frame.',
        );
      }
      if (!terminal && !gap) {
        final current = await run(runId);
        if (current.lifecycle == CockpitRunLifecycle.completed) {
          yield CockpitRunStreamTerminal(afterSequence: sequence);
        } else {
          yield CockpitRunStreamDisconnected(afterSequence: sequence);
        }
      }
    } on CockpitSupervisorClientException {
      rethrow;
    } on Object catch (error) {
      throw CockpitSupervisorClientException(
        code: CockpitErrorCode.transportFailed,
        message: 'Supervisor event stream failed: $error',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<CockpitArtifactDownloadReceipt> downloadArtifactToFile({
    required CockpitArtifactResource artifact,
    required File destination,
  }) => _downloadArtifactToFile(
    path:
        '/api/v2/runs/${_segment(artifact.runId)}/artifacts/'
        '${_segment(artifact.artifactId)}',
    destination: destination,
    expectedMediaType: artifact.mediaType,
    expectedSizeBytes: artifact.sizeBytes,
    expectedSha256: artifact.sha256,
    allowOverwrite: false,
  );

  Future<CockpitArtifactDownloadReceipt> downloadDevelopmentArtifactToFile({
    required String workspaceId,
    required String sessionId,
    required String artifactId,
    required String mediaType,
    required File destination,
  }) => _downloadArtifactToFile(
    path:
        '/api/v2/workspaces/${_segment(workspaceId)}/sessions/'
        '${_segment(sessionId)}/artifacts/${_segment(artifactId)}',
    destination: destination,
    expectedMediaType: mediaType,
    allowOverwrite: true,
  );

  Future<CockpitArtifactDownloadReceipt> _downloadArtifactToFile({
    required String path,
    required File destination,
    required String expectedMediaType,
    required bool allowOverwrite,
    int? expectedSizeBytes,
    String? expectedSha256,
  }) async {
    if (!allowOverwrite && await destination.exists()) {
      throw FileSystemException(
        'Artifact destination already exists.',
        destination.path,
      );
    }
    await destination.parent.create(recursive: true);
    final temporary = File(
      '${destination.path}.part-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.create(exclusive: true);
    IOSink? sink;
    final session = await _ensureSession();
    final client = _httpClientFactory()..connectionTimeout = _requestTimeout;
    final deadline = DateTime.now().toUtc().add(_requestTimeout);
    try {
      final request = await client
          .getUrl(session.discovery.endpoint.resolve(path))
          .timeout(
            _remainingRequestTime(deadline, 'GET', path),
            onTimeout: () => throw _requestTimedOut('GET', path),
          );
      _authorize(request, session);
      final response = await request.close().timeout(
        _remainingRequestTime(deadline, 'GET', path),
        onTimeout: () => throw _requestTimedOut('GET', path),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final value = _decodeJson(
          await _boundedBytes(
            response,
            cockpitSupervisorMaximumResponseBytes,
          ).timeout(
            _remainingRequestTime(deadline, 'GET', path),
            onTimeout: () => throw _requestTimedOut('GET', path),
          ),
        );
        throw _decodeApiError(response.statusCode, value);
      }
      final mediaType =
          response.headers.contentType?.mimeType ?? ContentType.binary.mimeType;
      final declaredSize = response.contentLength;
      final digestHeader = response.headers.value('Digest');
      final declaredDigest = digestHeader?.startsWith('sha-256=') == true
          ? digestHeader!.substring('sha-256='.length)
          : null;
      if (declaredSize < 0 ||
          declaredSize > 16 * 1024 * 1024 * 1024 ||
          declaredDigest == null ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(declaredDigest) ||
          mediaType != expectedMediaType ||
          expectedSizeBytes != null && declaredSize != expectedSizeBytes ||
          expectedSha256 != null && declaredDigest != expectedSha256) {
        await response.drain<void>();
        throw const CockpitSupervisorClientException(
          code: 'artifactMetadataMismatch',
          message: 'Artifact response metadata does not match its resource.',
        );
      }
      sink = temporary.openWrite(mode: FileMode.writeOnly);
      var received = 0;
      final chunks = StreamIterator<List<int>>(response);
      try {
        while (await chunks.moveNext().timeout(
          _remainingRequestTime(deadline, 'GET', path),
          onTimeout: () => throw _requestTimedOut('GET', path),
        )) {
          final chunk = chunks.current;
          received += chunk.length;
          if (received > declaredSize) {
            throw const CockpitSupervisorClientException(
              code: 'artifactIntegrityMismatch',
              message: 'Artifact response exceeds its declared size.',
            );
          }
          sink.add(chunk);
        }
      } finally {
        await chunks.cancel();
      }
      await sink.flush();
      await sink.close();
      sink = null;
      final digest =
          (await sha256
                  .bind(temporary.openRead())
                  .first
                  .timeout(
                    _remainingRequestTime(deadline, 'GET', path),
                    onTimeout: () => throw _requestTimedOut('GET', path),
                  ))
              .toString();
      if (received != declaredSize || digest != declaredDigest) {
        throw const CockpitSupervisorClientException(
          code: 'artifactIntegrityMismatch',
          message: 'Artifact bytes failed size or digest verification.',
        );
      }
      final committed = await _commitArtifactDownload(
        temporary,
        destination,
        allowOverwrite: allowOverwrite,
      );
      return CockpitArtifactDownloadReceipt(
        file: committed,
        mediaType: mediaType,
        sizeBytes: received,
        sha256: digest,
      );
    } on CockpitSupervisorClientException {
      rethrow;
    } on Object catch (error) {
      throw CockpitSupervisorClientException(
        code: CockpitErrorCode.transportFailed,
        message: 'Artifact download failed: $error',
      );
    } finally {
      try {
        await sink?.close();
      } finally {
        client.close(force: true);
        if (await temporary.exists()) await temporary.delete();
      }
    }
  }

  Future<File> _commitArtifactDownload(
    File temporary,
    File destination, {
    required bool allowOverwrite,
  }) async {
    try {
      return await temporary.rename(destination.path);
    } on FileSystemException {
      if (!allowOverwrite || !await destination.exists()) rethrow;
    }
    final backup = File(
      '${destination.path}.previous-$pid-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    await destination.rename(backup.path);
    try {
      final committed = await temporary.rename(destination.path);
      await backup.delete();
      return committed;
    } on Object {
      if (!await destination.exists() && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
  }

  Future<_CockpitSupervisorSession> _ensureSession() async {
    final discovery = await lifecycle.ensure(timeout: _requestTimeout);
    final cached = _session;
    if (cached != null && cached.discovery.instanceId == discovery.instanceId) {
      return cached;
    }
    final provisional = _CockpitSupervisorSession(
      discovery: discovery,
      server: _serverFromDiscovery(discovery),
      negotiation: CockpitNegotiationResult(
        apiVersion: apiVersion,
        featureIds: const <String>[],
      ),
    );
    final raw = await _jsonRequest(provisional, 'GET', '/api/v2/server');
    final server = CockpitServerInfo.fromJson(
      raw,
      decodePolicy: CockpitDecodePolicy.strictResponses,
    );
    if (server.instanceId != discovery.instanceId) {
      throw const CockpitSupervisorClientException(
        code: 'serverIdentityMismatch',
        message: 'Supervisor discovery and API instance identities differ.',
      );
    }
    final negotiation = CockpitProtocolNegotiator.negotiate(
      request: CockpitNegotiationRequest(
        apiVersion: apiVersion,
        requiredFeatures: requiredFeatures,
      ),
      server: server,
    );
    final session = _CockpitSupervisorSession(
      discovery: discovery,
      server: server,
      negotiation: negotiation,
    );
    _session = session;
    return session;
  }

  CockpitServerInfo _serverFromDiscovery(CockpitDaemonDiscovery discovery) =>
      CockpitServerInfo(
        instanceId: discovery.instanceId,
        apiVersion: CockpitApiVersion(
          major: discovery.apiMajor,
          minor: discovery.apiMinor,
        ),
        engineVersion: discovery.engineVersion,
        startedAt: discovery.startedAt,
      );

  Future<Object?> _jsonRequest(
    _CockpitSupervisorSession session,
    String method,
    String path, {
    Object? body,
    Duration? requestTimeout,
  }) async {
    final effectiveTimeout = requestTimeout ?? _requestTimeout;
    _validateRequestTimeout(effectiveTimeout);
    final client = _httpClientFactory();
    client.connectionTimeout = effectiveTimeout;
    try {
      return await (() async {
        final request = await client.openUrl(
          method,
          session.discovery.endpoint.resolve(path),
        );
        _authorize(request, session);
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final response = await request.close();
        final bytes = await _boundedBytes(response, maximumResponseBytes);
        final value = _decodeJson(bytes);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw _decodeApiError(response.statusCode, value);
        }
        return value;
      })().timeout(
        effectiveTimeout,
        onTimeout: () => throw CockpitSupervisorClientException(
          code: 'requestTimeout',
          message:
              'Supervisor $method $path exceeded '
              '${effectiveTimeout.inMilliseconds}ms.',
        ),
      );
    } on CockpitSupervisorClientException {
      rethrow;
    } on CockpitApiException catch (error) {
      throw CockpitSupervisorClientException(
        code: error.error.code,
        message: error.error.message,
        apiError: error.error,
      );
    } on Object catch (error) {
      throw CockpitSupervisorClientException(
        code: CockpitErrorCode.transportFailed,
        message: 'Supervisor request failed: $error',
      );
    } finally {
      client.close(force: true);
    }
  }

  void _authorize(
    HttpClientRequest request,
    _CockpitSupervisorSession session,
  ) {
    request.headers
      ..set(
        HttpHeaders.authorizationHeader,
        'Bearer ${session.discovery.bearerToken}',
      )
      ..set('Cockpit-API-Version', session.versionHeader)
      ..set(cockpitWorkerBuildHeader, cockpitBuildId);
    if (requiredFeatures.isNotEmpty) {
      request.headers.set(
        'Cockpit-Required-Features',
        requiredFeatures.join(','),
      );
    }
  }

  Duration _remainingRequestTime(
    DateTime deadline,
    String method,
    String path,
  ) {
    final remaining = deadline.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) throw _requestTimedOut(method, path);
    return remaining;
  }

  CockpitSupervisorClientException _requestTimedOut(
    String method,
    String path,
  ) => CockpitSupervisorClientException(
    code: 'requestTimeout',
    message:
        'Supervisor $method $path exceeded '
        '${_requestTimeout.inMilliseconds}ms.',
  );
}

void _validateRequestTimeout(Duration value) {
  if (value <= Duration.zero || value > const Duration(hours: 24)) {
    throw ArgumentError.value(value, 'requestTimeout');
  }
}

final class _CockpitSupervisorSession {
  const _CockpitSupervisorSession({
    required this.discovery,
    required this.server,
    required this.negotiation,
  });

  final CockpitDaemonDiscovery discovery;
  final CockpitServerInfo server;
  final CockpitNegotiationResult negotiation;

  String get versionHeader =>
      '${negotiation.apiVersion.major}.${negotiation.apiVersion.minor}';
  CockpitDecodePolicy get decodePolicy => negotiation.responseDecodePolicy;
}

final class _SseFrame {
  String? id;
  String? event;
  final List<String> data = <String>[];
  var size = 0;

  void add(String line, int maximumBytes) {
    size += utf8.encode(line).length + 1;
    if (size > maximumBytes) {
      throw const CockpitSupervisorClientException(
        code: 'eventFrameTooLarge',
        message: 'Supervisor event frame exceeds the response bound.',
      );
    }
    if (line.isEmpty || line.startsWith(':')) return;
    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'id':
        if (id != null || value.isEmpty || value.contains('\u0000')) {
          throw const CockpitSupervisorClientException(
            code: 'invalidEventStream',
            message: 'Supervisor returned an invalid event id.',
          );
        }
        id = value;
      case 'event':
        if (event != null || value.isEmpty) {
          throw const CockpitSupervisorClientException(
            code: 'invalidEventStream',
            message: 'Supervisor returned an invalid event type.',
          );
        }
        event = value;
      case 'data':
        data.add(value);
      default:
        throw CockpitSupervisorClientException(
          code: 'invalidEventStream',
          message: 'Supervisor returned unsupported SSE field $field.',
        );
    }
  }

  CockpitRunStreamItem? decode(CockpitDecodePolicy policy) {
    if (id == null && event == null && data.isEmpty) return null;
    if (event == null || data.isEmpty) {
      throw const CockpitSupervisorClientException(
        code: 'invalidEventStream',
        message: 'Supervisor returned an incomplete event frame.',
      );
    }
    final value = _decodeJson(utf8.encode(data.join('\n')));
    if (event == 'gap') {
      if (id != null) {
        throw const CockpitSupervisorClientException(
          code: 'invalidEventStream',
          message: 'A gap event must not carry an event id.',
        );
      }
      return CockpitRunStreamGap(
        CockpitEventReplayBoundary.fromJson(value, decodePolicy: policy),
      );
    }
    final decoded = CockpitRunEvent.fromJson(value, decodePolicy: policy);
    if (id != decoded.eventId || event != decoded.kind) {
      throw const CockpitSupervisorClientException(
        code: 'invalidEventStream',
        message: 'SSE metadata does not match the run event.',
      );
    }
    return CockpitRunStreamEvent(decoded);
  }
}

Future<CockpitSupervisorApiClient> createCockpitSupervisorApiClient({
  Iterable<String> requiredFeatures = const <String>[],
  bool selfContained = false,
}) async {
  final resolver = CockpitHomeResolver.system();
  final home = CockpitHome.system();
  final paths = await home.initialize();
  _CockpitDaemonLaunchConfiguration launchConfiguration;
  CockpitDaemonException? launchFailure;
  try {
    launchConfiguration = await _resolveDaemonLaunchConfiguration(
      selfContained: selfContained,
    );
  } on CockpitDaemonException catch (error) {
    launchConfiguration = const _CockpitDaemonLaunchConfiguration(
      executable: '',
      daemonArguments: <String>[],
      restartArguments: <String>[],
    );
    launchFailure = error;
  }
  return CockpitSupervisorApiClient(
    lifecycle: CockpitDaemonLifecycleClient(
      paths: paths,
      executable: launchConfiguration.executable,
      daemonArguments: launchConfiguration.daemonArguments,
      restartArguments: launchConfiguration.restartArguments,
      permissionHardener: home.permissionHardener,
      directorySyncer: CockpitSystemDirectorySyncer(resolver.platform),
      requiredEngineVersion: cockpitVersion,
      launchFailure: launchFailure,
    ),
    requiredFeatures: requiredFeatures,
  );
}

Future<_CockpitDaemonLaunchConfiguration> _resolveDaemonLaunchConfiguration({
  bool selfContained = false,
}) async {
  if (selfContained && !_isDartRuntime(Platform.resolvedExecutable)) {
    return _CockpitDaemonLaunchConfiguration(
      executable: Platform.resolvedExecutable,
      daemonArguments: const <String>[cockpitInternalDaemonCommand],
      restartArguments: const <String>[],
    );
  }
  try {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:cockpit/cockpit.dart'),
    );
    if (library != null && library.scheme == 'file') {
      final packageConfig = await Isolate.packageConfig;
      final packageArguments = packageConfig?.scheme == 'file'
          ? <String>['--packages=${packageConfig!.toFilePath()}']
          : const <String>[];
      final packageRoot = p.dirname(p.dirname(library.toFilePath()));
      return _CockpitDaemonLaunchConfiguration(
        executable: Platform.resolvedExecutable,
        daemonArguments: <String>[
          ...packageArguments,
          p.join(packageRoot, 'bin', 'cockpitd.dart'),
        ],
        restartArguments: <String>[
          ...packageArguments,
          p.join(packageRoot, 'bin', 'cockpit.dart'),
        ],
      );
    }
  } on UnsupportedError {
    // AOT runtimes cannot resolve package: URIs.
  }
  return _resolveGloballyActivatedDaemon();
}

Future<_CockpitDaemonLaunchConfiguration>
_resolveGloballyActivatedDaemon() async {
  final environment = Platform.environment;
  final configuredCache = environment['PUB_CACHE']?.trim();
  final home = environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']?.trim();
  final localAppData = environment['LOCALAPPDATA']?.trim();
  final pubCache = configuredCache != null && configuredCache.isNotEmpty
      ? configuredCache
      : Platform.isWindows
      ? localAppData == null || localAppData.isEmpty
            ? null
            : p.join(localAppData, 'Pub', 'Cache')
      : home == null || home.isEmpty
      ? null
      : p.join(home, '.pub-cache');
  if (pubCache == null) {
    throw const CockpitDaemonException(
      'daemonLaunchUnavailable',
      'Unable to locate the Pub cache. Set PUB_CACHE and activate Cockpit '
          'with `dart pub global activate cockpit`.',
    );
  }

  final activationLock = File(
    p.join(pubCache, 'global_packages', 'cockpit', 'pubspec.lock'),
  );
  final snapshotDirectory = Directory(
    p.join(pubCache, 'global_packages', 'cockpit', 'bin'),
  );
  if (!await activationLock.exists() && !await snapshotDirectory.exists()) {
    throw const CockpitDaemonException(
      'daemonLaunchUnavailable',
      'Cockpit is not globally activated. Run '
          '`dart pub global activate cockpit`.',
    );
  }
  final flutterRoot = environment['FLUTTER_ROOT']?.trim();
  final bundledDart = flutterRoot == null || flutterRoot.isEmpty
      ? null
      : p.join(
          flutterRoot,
          'bin',
          'cache',
          'dart-sdk',
          'bin',
          Platform.isWindows ? 'dart.exe' : 'dart',
        );
  final executable = bundledDart != null && await File(bundledDart).exists()
      ? bundledDart
      : Platform.isWindows
      ? 'dart.exe'
      : 'dart';
  return _CockpitDaemonLaunchConfiguration(
    executable: executable,
    daemonArguments: const <String>['pub', 'global', 'run', 'cockpit:cockpitd'],
    restartArguments: const <String>['pub', 'global', 'run', 'cockpit:cockpit'],
  );
}

final class _CockpitDaemonLaunchConfiguration {
  const _CockpitDaemonLaunchConfiguration({
    required this.executable,
    required this.daemonArguments,
    required this.restartArguments,
  });

  final String executable;
  final List<String> daemonArguments;
  final List<String> restartArguments;
}

bool _isDartRuntime(String executable) {
  final name = p.basenameWithoutExtension(executable).toLowerCase();
  return name == 'dart' || name == 'dartaotruntime';
}

Future<List<int>> _boundedBytes(
  HttpClientResponse response,
  int maximum,
) async {
  if (response.contentLength > maximum) {
    await response.drain<void>();
    throw const CockpitSupervisorClientException(
      code: 'responseTooLarge',
      message: 'Supervisor response exceeds the configured byte bound.',
    );
  }
  final bytes = <int>[];
  await for (final chunk in response) {
    if (bytes.length + chunk.length > maximum) {
      throw const CockpitSupervisorClientException(
        code: 'responseTooLarge',
        message: 'Supervisor response exceeds the configured byte bound.',
      );
    }
    bytes.addAll(chunk);
  }
  return bytes;
}

Object? _decodeJson(List<int> bytes) {
  try {
    return jsonDecode(utf8.decode(bytes, allowMalformed: false));
  } on Object catch (error) {
    throw CockpitSupervisorClientException(
      code: 'invalidResponse',
      message: 'Supervisor returned invalid UTF-8 JSON: $error',
    );
  }
}

CockpitSupervisorClientException _decodeApiError(
  int statusCode,
  Object? value,
) {
  try {
    if (value is! Map<Object?, Object?> ||
        value.length != 1 ||
        !value.containsKey('error')) {
      throw const FormatException('Invalid error envelope.');
    }
    final error = CockpitApiError.fromJson(
      value['error'],
      decodePolicy: CockpitDecodePolicy.strictResponses,
    );
    return CockpitSupervisorClientException(
      code: error.code,
      message: error.message,
      apiError: error,
    );
  } on CockpitSupervisorClientException {
    rethrow;
  } on Object {
    return CockpitSupervisorClientException(
      code: 'invalidErrorResponse',
      message: 'Supervisor returned malformed error JSON (HTTP $statusCode).',
    );
  }
}

CockpitRetirementResponse _decodeRetirement(Object? value) {
  if (value is! Map<Object?, Object?> ||
      value.keys.any((key) => key is! String)) {
    throw const FormatException('Retirement response must be an object.');
  }
  final json = value.cast<String, Object?>();
  const keys = <String>{'id', 'tombstoneRetained', 'referenceCounts'};
  if (json.length != keys.length ||
      !json.keys.every(keys.contains) ||
      json['id'] is! String ||
      json['tombstoneRetained'] is! bool ||
      json['referenceCounts'] is! Map<Object?, Object?>) {
    throw const FormatException('Retirement response fields are invalid.');
  }
  final rawCounts = json['referenceCounts']! as Map<Object?, Object?>;
  if (rawCounts.keys.any((key) => key is! String) ||
      rawCounts.values.any((count) => count is! int || count < 0)) {
    throw const FormatException('Retirement reference counts are invalid.');
  }
  return CockpitRetirementResponse(
    id: _segment(json['id']! as String),
    tombstoneRetained: json['tombstoneRetained']! as bool,
    referenceCounts: Map<String, int>.unmodifiable(
      rawCounts.map((key, value) => MapEntry(key! as String, value! as int)),
    ),
  );
}

void _validateInvocation(
  CockpitOperationDescriptor descriptor,
  CockpitOperationInvocation invocation,
) {
  final scopeMatches = switch (descriptor.scope) {
    CockpitOperationScope.supervisor =>
      invocation.rootId == null && invocation.workspaceId == null,
    CockpitOperationScope.root =>
      invocation.rootId != null && invocation.workspaceId == null,
    CockpitOperationScope.workspace =>
      invocation.rootId == null && invocation.workspaceId != null,
  };
  if (!scopeMatches) {
    throw const CockpitSupervisorClientException(
      code: 'operationScopeMismatch',
      message: 'Operation invocation does not match its advertised scope.',
    );
  }
  final hasKey = invocation.idempotencyKey != null;
  if (descriptor.idempotency == CockpitIdempotencyBehavior.required &&
          !hasKey ||
      descriptor.idempotency == CockpitIdempotencyBehavior.prohibited &&
          hasKey) {
    throw const CockpitSupervisorClientException(
      code: 'operationIdempotencyMismatch',
      message: 'Operation invocation violates advertised idempotency.',
    );
  }
}

String _segment(String value) {
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,127}$').hasMatch(value)) {
    throw FormatException('Invalid resource identifier $value.');
  }
  return value;
}
