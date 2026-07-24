import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_application_service_exception.dart';
import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_app_reference_resolver.dart';
import 'cockpit_session_registry.dart';

final class CockpitRuntimeErrorEntry {
  const CockpitRuntimeErrorEntry({
    required this.source,
    required this.message,
    this.recordedAt,
    this.sessionId,
    this.kind,
    this.routeName,
  });

  final String source;
  final String message;
  final DateTime? recordedAt;
  final String? sessionId;
  final String? kind;
  final String? routeName;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'message': message,
    if (recordedAt != null) 'recordedAt': recordedAt!.toUtc().toIso8601String(),
    if (sessionId != null) 'sessionId': sessionId,
    if (kind != null) 'kind': kind,
    if (routeName != null) 'routeName': routeName,
  };
}

final class CockpitReadRuntimeErrorsRequest {
  const CockpitReadRuntimeErrorsRequest({
    this.appId,
    this.appHandlePath,
    this.baseUri,
    this.androidDeviceId,
    this.maxErrors = 20,
    this.includeSessions,
  });

  final String? appId;
  final String? appHandlePath;
  final Uri? baseUri;
  final String? androidDeviceId;
  final int maxErrors;
  final bool? includeSessions;

  bool get hasAppReference =>
      (appId != null && appId!.isNotEmpty) ||
      (appHandlePath != null && appHandlePath!.isNotEmpty) ||
      baseUri != null;

  bool get effectiveIncludeSessions => includeSessions ?? !hasAppReference;
}

final class CockpitReadRuntimeErrorsResult {
  const CockpitReadRuntimeErrorsResult({
    required this.errors,
    this.appId,
    this.routeName,
    this.source,
  });

  final List<CockpitRuntimeErrorEntry> errors;
  final String? appId;
  final String? routeName;
  final String? source;

  bool get hasErrors => errors.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    if (appId != null) 'appId': appId,
    if (routeName != null) 'routeName': routeName,
    if (source != null) 'source': source,
    'hasErrors': hasErrors,
    'errors': errors.map((error) => error.toJson()).toList(growable: false),
  };
}

final class CockpitReadRuntimeErrorsService {
  CockpitReadRuntimeErrorsService({
    required CockpitSessionRegistry registry,
    CockpitAppReferenceResolver? appReferenceResolver,
    CockpitReadRuntimeErrorsSnapshotReader? readSnapshot,
    int maxSnapshotReadAttempts = 5,
    Duration retryDelay = const Duration(milliseconds: 400),
  }) : _registry = registry,
       _appReferenceResolver =
           appReferenceResolver ??
           CockpitAppReferenceResolver(registry: registry),
       _readSnapshot =
           readSnapshot ??
           ((baseUri, options) => CockpitRemoteSessionClient(
             baseUri: baseUri,
           ).readSnapshotDetailed(options: options)),
       _maxSnapshotReadAttempts = maxSnapshotReadAttempts < 1
           ? 1
           : maxSnapshotReadAttempts,
       _retryDelay = retryDelay;

  final CockpitSessionRegistry _registry;
  final CockpitAppReferenceResolver _appReferenceResolver;
  final CockpitReadRuntimeErrorsSnapshotReader _readSnapshot;
  final int _maxSnapshotReadAttempts;
  final Duration _retryDelay;

  Future<CockpitReadRuntimeErrorsResult> read(
    CockpitReadRuntimeErrorsRequest request,
  ) async {
    final errors = <CockpitRuntimeErrorEntry>[];
    String? appId;
    String? routeName;
    String? source;
    if (request.hasAppReference) {
      final resolved = await _appReferenceResolver.resolve(
        appId: request.appId,
        appHandlePath: request.appHandlePath,
        baseUri: request.baseUri,
        androidDeviceId: request.androidDeviceId,
      );
      appId = resolved.app?.appId ?? request.appId;
      source = 'app_snapshot';
      final snapshot = (await _readSnapshotWithRetry(
        resolved.baseUri,
        CockpitSnapshotOptions(
          profile: CockpitSnapshotProfile.investigate,
          includeRuntimeActivity: true,
          maxRuntimeEntries: request.maxErrors <= 0 ? 20 : request.maxErrors,
          runtimeQuery: const CockpitRuntimeQuery(onlyErrors: true),
        ),
      )).snapshot;
      routeName = snapshot.routeName;
      final runtime = snapshot.runtime;
      if (runtime != null) {
        for (final event in runtime.entries) {
          errors.add(
            CockpitRuntimeErrorEntry(
              source: 'app_snapshot',
              message: event.message,
              recordedAt: event.recordedAt,
              kind: event.kind.jsonValue,
              routeName: event.routeName ?? snapshot.routeName,
            ),
          );
        }
      }
    }
    if (request.effectiveIncludeSessions) {
      final snapshot = _registry.snapshot();
      for (final record in snapshot.developmentSessions) {
        final lastError = record.status.lastError;
        if (lastError == null || lastError.isEmpty) {
          continue;
        }
        errors.add(
          CockpitRuntimeErrorEntry(
            source: 'development_session',
            message: lastError,
            recordedAt: record.updatedAt,
            sessionId: record.handle.developmentSessionId,
          ),
        );
      }
    }
    errors.sort((left, right) {
      final leftAt = left.recordedAt;
      final rightAt = right.recordedAt;
      if (leftAt == null && rightAt == null) {
        return 0;
      }
      if (leftAt == null) {
        return 1;
      }
      if (rightAt == null) {
        return -1;
      }
      return rightAt.compareTo(leftAt);
    });
    return CockpitReadRuntimeErrorsResult(
      appId: appId,
      routeName: routeName,
      source: request.hasAppReference
          ? (request.effectiveIncludeSessions ? 'mixed' : source)
          : (request.effectiveIncludeSessions ? 'aggregate' : null),
      errors: List<CockpitRuntimeErrorEntry>.unmodifiable(errors),
    );
  }

  Future<CockpitRemoteSnapshotResponse> _readSnapshotWithRetry(
    Uri baseUri,
    CockpitSnapshotOptions options,
  ) async {
    for (var attempt = 0; attempt < _maxSnapshotReadAttempts; attempt += 1) {
      try {
        return await _readSnapshot(baseUri, options);
      } on CockpitApplicationServiceException catch (error) {
        final shouldRetry =
            attempt + 1 < _maxSnapshotReadAttempts &&
            _isTransientSnapshotReadFailure(error);
        if (!shouldRetry) {
          rethrow;
        }
        if (_retryDelay > Duration.zero) {
          await Future<void>.delayed(_retryDelay * (attempt + 1));
        }
      }
    }
    throw StateError('Unreachable runtime error snapshot retry state.');
  }

  bool _isTransientSnapshotReadFailure(
    CockpitApplicationServiceException error,
  ) {
    return error.code == 'remoteUnavailable' ||
        (error.code == 'serverError' &&
            error.message.contains('FlutterCockpitRoot is not mounted'));
  }
}

typedef CockpitReadRuntimeErrorsSnapshotReader =
    Future<CockpitRemoteSnapshotResponse> Function(
      Uri baseUri,
      CockpitSnapshotOptions options,
    );
