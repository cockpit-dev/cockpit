import 'dart:async';
import 'dart:typed_data';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

typedef CockpitVmServiceConnector = Future<VmService> Function(Uri uri);

abstract interface class CockpitNetworkProfiler {
  Future<void> enable({required String sessionId, required Uri vmServiceUri});

  Future<CockpitVmNetworkBodies> readBodies({
    required String sessionId,
    required Uri vmServiceUri,
    required CockpitNetworkEntry entry,
  });
}

final class CockpitVmNetworkBodyUnavailableException implements Exception {
  const CockpitVmNetworkBodyUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class CockpitVmNetworkRequestMatcher {
  const CockpitVmNetworkRequestMatcher({
    this.tolerance = const Duration(seconds: 5),
  });

  final Duration tolerance;
  static const CockpitNetworkRedactor _redactor = CockpitNetworkRedactor();

  HttpProfileRequest match(
    CockpitNetworkEntry entry,
    Iterable<HttpProfileRequest> requests,
  ) {
    final candidates =
        requests
            .where((request) => _matchesReference(entry, request))
            .toList(growable: false)
          ..sort(
            (left, right) =>
                _distance(left, entry).compareTo(_distance(right, entry)),
          );
    if (candidates.isEmpty) {
      throw CockpitVmNetworkBodyUnavailableException(
        'The VM profiler did not retain network request ${entry.requestId}. '
        'Run the request again after the development session is ready.',
      );
    }
    if (candidates.length > 1 &&
        _distance(candidates[0], entry) == _distance(candidates[1], entry)) {
      throw CockpitVmNetworkBodyUnavailableException(
        'The VM profiler cannot uniquely match network request '
        '${entry.requestId}. Run the request again and retry with its new ID.',
      );
    }
    return candidates.first;
  }

  bool _matchesReference(
    CockpitNetworkEntry entry,
    HttpProfileRequest request,
  ) {
    if (request.method.toUpperCase() != entry.method.toUpperCase()) {
      return false;
    }
    if (_redactor.uri(request.uri).toString() != entry.uri) return false;
    return _distance(request, entry) <= tolerance;
  }

  Duration _distance(HttpProfileRequest request, CockpitNetworkEntry entry) =>
      request.startTime.difference(entry.startedAt).abs();
}

final class CockpitVmNetworkBody {
  const CockpitVmNetworkBody({
    required this.bytes,
    required this.complete,
    required this.present,
    this.mediaType,
  });

  final Uint8List bytes;
  final bool complete;
  final bool present;
  final String? mediaType;
}

final class CockpitVmNetworkBodies {
  const CockpitVmNetworkBodies({required this.request, required this.response});

  final CockpitVmNetworkBody request;
  final CockpitVmNetworkBody response;
}

final class CockpitVmNetworkProfiler implements CockpitNetworkProfiler {
  CockpitVmNetworkProfiler({
    CockpitVmServiceConnector? connect,
    this.connectionTimeout = const Duration(seconds: 3),
    CockpitVmNetworkRequestMatcher requestMatcher =
        const CockpitVmNetworkRequestMatcher(),
  }) : _connect = connect ?? _defaultConnect,
       _requestMatcher = requestMatcher;

  final CockpitVmServiceConnector _connect;
  final CockpitVmNetworkRequestMatcher _requestMatcher;
  final Duration connectionTimeout;
  final Map<String, Future<void>> _enablements = <String, Future<void>>{};

  @override
  Future<void> enable({required String sessionId, required Uri vmServiceUri}) {
    final previous = _enablements[sessionId] ?? Future<void>.value();
    final next = previous
        .catchError((Object _) {})
        .then((_) => _enable(vmServiceUri));
    _enablements[sessionId] = next;
    return next.whenComplete(() {
      if (identical(_enablements[sessionId], next)) {
        _enablements.remove(sessionId);
      }
    });
  }

  @override
  Future<CockpitVmNetworkBodies> readBodies({
    required String sessionId,
    required Uri vmServiceUri,
    required CockpitNetworkEntry entry,
  }) async {
    await enable(sessionId: sessionId, vmServiceUri: vmServiceUri);
    final service = await _connectWithinBudget(vmServiceUri);
    try {
      final requests = <HttpProfileRequest>[];
      for (final isolateId in await _httpIsolates(service)) {
        final profile = await service.getHttpProfile(isolateId);
        requests.addAll(profile.requests);
      }
      final matched = _requestMatcher.match(entry, requests);
      final request = await service.getHttpProfileRequest(
        matched.isolateId,
        matched.id,
      );
      final requestHeaders = _headers(request.request?.headers);
      final responseHeaders = _headers(request.response?.headers);
      final requestBody = request.requestBody;
      final responseBody = request.responseBody;
      return CockpitVmNetworkBodies(
        request: CockpitVmNetworkBody(
          bytes: requestBody ?? Uint8List(0),
          complete: request.endTime != null,
          present: requestBody?.isNotEmpty ?? false,
          mediaType: _mediaType(requestHeaders),
        ),
        response: CockpitVmNetworkBody(
          bytes: responseBody ?? Uint8List(0),
          complete: request.response?.isComplete ?? false,
          present: responseBody?.isNotEmpty ?? false,
          mediaType: _mediaType(responseHeaders),
        ),
      );
    } finally {
      await service.dispose();
    }
  }

  Future<void> _enable(Uri vmServiceUri) async {
    final service = await _connectWithinBudget(vmServiceUri);
    try {
      for (final isolateId in await _httpIsolates(service)) {
        final state = await service.httpEnableTimelineLogging(isolateId);
        if (!state.enabled) {
          await service.httpEnableTimelineLogging(isolateId, true);
        }
      }
    } finally {
      await service.dispose();
    }
  }

  Future<VmService> _connectWithinBudget(Uri uri) {
    return _connect(uri).timeout(connectionTimeout);
  }

  Future<List<String>> _httpIsolates(VmService service) async {
    final vm = await service.getVM();
    final result = <String>[];
    for (final isolate in vm.isolates ?? const <IsolateRef>[]) {
      final isolateId = isolate.id;
      if (isolateId == null) continue;
      if (await service.isHttpProfilingAvailable(isolateId) &&
          await service.isHttpTimelineLoggingAvailable(isolateId)) {
        result.add(isolateId);
      }
    }
    if (result.isEmpty) {
      throw StateError('Dart HTTP profiling is unavailable in this session.');
    }
    return result;
  }

  static Future<VmService> _defaultConnect(Uri uri) {
    return vmServiceConnectUri(uri.toString());
  }

  Map<String, String> _headers(Map<String, dynamic>? values) => values == null
      ? const <String, String>{}
      : <String, String>{
          for (final entry in values.entries)
            entry.key: switch (entry.value) {
              Iterable<Object?> items => items.join(', '),
              _ => '${entry.value}',
            },
        };

  String? _mediaType(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-type') return entry.value;
    }
    return null;
  }
}
