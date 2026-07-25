import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../application/cockpit_application_service_exception.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../registry/cockpit_registry_models.dart';
import '../worker/cockpit_json_rpc_peer.dart';
import 'cockpit_lease_support.dart';
import 'cockpit_worker_pool.dart';

const cockpitMaximumRequestBytes = 1024 * 1024;

typedef CockpitSupervisorInternalErrorObserver =
    void Function(HttpRequest request, Object error, StackTrace? stackTrace);

final class CockpitSupervisorHttpSupport {
  const CockpitSupervisorHttpSupport(this.serverInfo, {this.onInternalError});

  final CockpitServerInfo serverInfo;
  final CockpitSupervisorInternalErrorObserver? onInternalError;

  void negotiate(HttpRequest request) {
    final rawVersion = request.headers.value('Cockpit-API-Version');
    final match = rawVersion == null
        ? null
        : RegExp(r'^(\d+)\.(\d+)$').firstMatch(rawVersion);
    if (match == null) {
      throw _apiError(
        CockpitErrorCode.invalidRequest,
        CockpitErrorCategory.invalidInput,
        'Cockpit-API-Version is required and must use major.minor form.',
      );
    }
    final required = _requiredFeatures(
      request.headers.value('Cockpit-Required-Features'),
    );
    CockpitProtocolNegotiator.negotiate(
      request: CockpitNegotiationRequest(
        apiVersion: CockpitApiVersion(
          major: int.parse(match[1]!),
          minor: int.parse(match[2]!),
        ),
        requiredFeatures: required,
      ),
      server: serverInfo,
    );
  }

  Future<Object?> readJson(HttpRequest request) async {
    if (request.headers.contentType?.mimeType != ContentType.json.mimeType) {
      throw _apiError(
        CockpitErrorCode.invalidRequest,
        CockpitErrorCategory.invalidInput,
        'Content-Type must be application/json.',
      );
    }
    final expected = request.contentLength;
    if (expected > cockpitMaximumRequestBytes) {
      throw _apiError(
        CockpitErrorCode.invalidRequest,
        CockpitErrorCategory.invalidInput,
        'Request body exceeds 1 MiB.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > cockpitMaximumRequestBytes) {
        throw _apiError(
          CockpitErrorCode.invalidRequest,
          CockpitErrorCategory.invalidInput,
          'Request body exceeds 1 MiB.',
        );
      }
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) {
      throw _apiError(
        CockpitErrorCode.invalidRequest,
        CockpitErrorCategory.invalidInput,
        'A JSON request body is required.',
      );
    }
    try {
      return jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      throw _apiError(
        CockpitErrorCode.invalidRequest,
        CockpitErrorCategory.invalidInput,
        'Request body is not valid UTF-8 JSON.',
      );
    }
  }

  CockpitPageRequest pageRequest(HttpRequest request, String scope) {
    final unknown = request.uri.queryParameters.keys.toSet().difference(
      const <String>{'limit', 'cursor'},
    );
    if (unknown.isNotEmpty) {
      throw _apiError(
        CockpitErrorCode.invalidRequest,
        CockpitErrorCategory.invalidInput,
        'Unknown pagination query parameter.',
      );
    }
    final limitText = request.uri.queryParameters['limit'];
    final limit = limitText == null ? 50 : int.tryParse(limitText);
    if (limit == null) {
      throw _apiError(
        CockpitErrorCode.invalidRequest,
        CockpitErrorCategory.invalidInput,
        'Page limit is invalid.',
      );
    }
    final cursor = request.uri.queryParameters['cursor'];
    if (cursor != null) decodeCursor(cursor, scope);
    return CockpitPageRequest(limit: limit, cursor: cursor);
  }

  Map<String, Object?> page<T>(
    Iterable<T> source,
    CockpitPageRequest request,
    String scope,
    Object? Function(T item) encode,
  ) {
    final values = source.toList(growable: false);
    final offset = request.cursor == null
        ? 0
        : decodeCursor(request.cursor!, scope);
    if (offset > values.length) {
      throw _apiError(
        CockpitErrorCode.staleReference,
        CockpitErrorCategory.invalidInput,
        'Pagination cursor is stale.',
      );
    }
    final end = (offset + request.limit).clamp(0, values.length);
    return CockpitPage<T>(
      items: values.sublist(offset, end),
      nextCursor: end < values.length ? encodeCursor(scope, end) : null,
      totalCount: values.length,
    ).toJson(encode);
  }

  String encodeCursor(String scope, int offset) => base64Url
      .encode(
        utf8.encode(
          jsonEncode(<String, Object?>{'scope': scope, 'offset': offset}),
        ),
      )
      .replaceAll('=', '');

  int decodeCursor(String cursor, String scope) {
    if (cursor.length > 512 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(cursor)) {
      throw _invalidCursor();
    }
    try {
      final normalized = cursor.padRight((cursor.length + 3) ~/ 4 * 4, '=');
      final value = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (value is! Map<Object?, Object?> ||
          value.length != 2 ||
          value['scope'] != scope ||
          value['offset'] is! int ||
          (value['offset']! as int) < 0) {
        throw const FormatException('invalid cursor');
      }
      return value['offset']! as int;
    } on Object {
      throw _invalidCursor();
    }
  }

  Future<void> json(HttpRequest request, int status, Object? value) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(value));
    await request.response.close();
  }

  Future<void> error(
    HttpRequest request,
    Object error, {
    StackTrace? stackTrace,
  }) {
    final api = switch (error) {
      CockpitApiException() => error.error,
      CockpitRegistryException() => CockpitApiError(
        code: error.code,
        category: CockpitErrorCategory.resource,
        message: _boundedMessage(error.message),
        retryable: _isLockedCode(error.code),
        responsibleLayer: CockpitResponsibleLayer.supervisor,
        redactedDetails: <String, Object?>{
          'referenceCounts': error.referenceCounts.bounded,
        },
      ),
      CockpitLeaseException() => CockpitApiError(
        code: error.code,
        category: CockpitErrorCategory.resource,
        message: _boundedMessage(error.message),
        retryable: _isLockedCode(error.code) || error.code.endsWith('Timeout'),
        responsibleLayer: CockpitResponsibleLayer.supervisor,
        redactedDetails: _boundedDetails(<String, Object?>{
          if (error.lease != null) 'lease': error.lease!.toJson(),
        }),
      ),
      CockpitWorkerPoolException() => CockpitApiError(
        code: error.code,
        category: error.code.contains('IdentityMismatch')
            ? CockpitErrorCategory.resource
            : CockpitErrorCategory.environment,
        message: _boundedMessage(error.message),
        retryable: !error.code.contains('IdentityMismatch'),
        responsibleLayer: CockpitResponsibleLayer.supervisor,
      ),
      CockpitJsonRpcRemoteException() => CockpitApiError(
        code: error.error.workerCode,
        category: CockpitErrorCategory.application,
        message: _boundedMessage(error.error.message),
        retryable: false,
        responsibleLayer: CockpitResponsibleLayer.worker,
        redactedDetails: _boundedDetails(error.error.details),
      ),
      CockpitJsonRpcPeerClosedException() ||
      CockpitJsonRpcPeerCleanupPendingException() => CockpitApiError(
        code: 'workerUnavailable',
        category: CockpitErrorCategory.environment,
        message: 'Workspace worker is unavailable.',
        retryable: true,
        responsibleLayer: CockpitResponsibleLayer.worker,
      ),
      CockpitApplicationServiceException() => CockpitApiError(
        code: error.code,
        category: CockpitErrorCategory.application,
        message: _boundedMessage(error.message),
        retryable: false,
        responsibleLayer: CockpitResponsibleLayer.application,
        redactedDetails: _boundedDetails(error.details),
      ),
      CockpitStorageException() => CockpitApiError(
        code: error.code,
        category: CockpitErrorCategory.internal,
        message: 'Supervisor durable storage failed.',
        retryable: true,
        responsibleLayer: CockpitResponsibleLayer.supervisor,
      ),
      FormatException() => CockpitApiError(
        code: CockpitErrorCode.invalidRequest,
        category: CockpitErrorCategory.invalidInput,
        message: error.message,
        retryable: false,
        responsibleLayer: CockpitResponsibleLayer.supervisor,
      ),
      _ => CockpitApiError(
        code: CockpitErrorCode.internalError,
        category: CockpitErrorCategory.internal,
        message: 'Supervisor request failed.',
        retryable: true,
        responsibleLayer: CockpitResponsibleLayer.supervisor,
      ),
    };
    if (api.code == CockpitErrorCode.internalError &&
        error is! CockpitApiException) {
      onInternalError?.call(request, error, stackTrace);
    }
    return json(request, _status(api), <String, Object?>{
      'error': api.toJson(),
    });
  }

  List<String> _requiredFeatures(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    if (raw.length > 4096) {
      throw _apiError(
        CockpitErrorCode.invalidRequest,
        CockpitErrorCategory.invalidInput,
        'Required feature header exceeds its bound.',
      );
    }
    final values = raw.split(',').map((value) => value.trim()).toList();
    if (values.any(
      (value) =>
          value.isEmpty ||
          !RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,127}$').hasMatch(value) ||
          values.where((item) => item == value).length != 1,
    )) {
      throw _apiError(
        CockpitErrorCode.invalidRequest,
        CockpitErrorCategory.invalidInput,
        'Required feature header is invalid.',
      );
    }
    return values;
  }

  CockpitApiException _invalidCursor() => _apiError(
    CockpitErrorCode.invalidRequest,
    CockpitErrorCategory.invalidInput,
    'Pagination cursor is invalid for this resource.',
  );
}

CockpitApiException _apiError(
  String code,
  CockpitErrorCategory category,
  String message,
) => CockpitApiException(
  CockpitApiError(
    code: code,
    category: category,
    message: message,
    retryable: false,
    responsibleLayer: CockpitResponsibleLayer.supervisor,
  ),
);

int _status(CockpitApiError error) => switch (error.code) {
  CockpitErrorCode.authenticationRequired => HttpStatus.unauthorized,
  CockpitErrorCode.authorizationDenied => HttpStatus.forbidden,
  CockpitErrorCode.notFound => HttpStatus.notFound,
  CockpitErrorCode.conflict ||
  'idempotencyConflict' ||
  CockpitErrorCode.staleReference => HttpStatus.conflict,
  CockpitErrorCode.upgradeRequired => HttpStatus.upgradeRequired,
  CockpitErrorCode.unsupportedOperation => HttpStatus.notFound,
  CockpitErrorCode.resourceBusy => HttpStatus.locked,
  'workerUnavailable' ||
  'workerPoolClosed' ||
  'workerUnhealthy' ||
  CockpitErrorCode.transportFailed => HttpStatus.serviceUnavailable,
  CockpitErrorCode.internalError => HttpStatus.internalServerError,
  _ =>
    error.code.endsWith('NotFound')
        ? HttpStatus.notFound
        : _isLockedCode(error.code)
        ? HttpStatus.locked
        : error.code.endsWith('Conflict') ||
              error.code.endsWith('Changed') ||
              error.code.endsWith('NotActive') ||
              error.code.endsWith('Retired') ||
              error.code.contains('IdentityMismatch')
        ? HttpStatus.conflict
        : error.category == CockpitErrorCategory.internal ||
              error.category == CockpitErrorCategory.application
        ? HttpStatus.internalServerError
        : HttpStatus.badRequest,
};

bool _isLockedCode(String code) =>
    code == CockpitErrorCode.resourceBusy ||
    code.endsWith('InUse') ||
    code.endsWith('Busy') ||
    code.endsWith('Quarantined');

String _boundedMessage(String message) =>
    message.length <= 4096 ? message : '${message.substring(0, 4093)}...';

Map<String, Object?> _boundedDetails(Map<String, Object?> details) {
  final result = <String, Object?>{};
  for (final entry in details.entries.take(16)) {
    final value = entry.value;
    result[entry.key] = switch (value) {
      String() when value.length > 1024 => '${value.substring(0, 1021)}...',
      num() || bool() || null => value,
      List<Object?>() when value.length <= 32 => value,
      Map<String, Object?>() when value.length <= 32 => value,
      _ =>
        '$value'.length <= 1024
            ? '$value'
            : '${'$value'.substring(0, 1021)}...',
    };
  }
  return result;
}
