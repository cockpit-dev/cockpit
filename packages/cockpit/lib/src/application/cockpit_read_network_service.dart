import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_app_reference_resolver.dart';
import 'cockpit_session_registry.dart';

typedef CockpitReadNetworkSnapshotReader =
    Future<CockpitRemoteSnapshotResponse> Function(
      Uri baseUri,
      CockpitSnapshotOptions options,
    );

final class CockpitReadNetworkRequest {
  const CockpitReadNetworkRequest({
    this.appId,
    this.appHandlePath,
    this.baseUri,
    this.androidDeviceId,
    this.maxEntries = 8,
    this.maxEndpointSummaries = 8,
    this.includeEntries = false,
    this.id,
    this.before,
    this.method,
    this.uriContains,
    this.onlyFailures = false,
    this.statusCodeAtLeast,
  });

  final String? appId;
  final String? appHandlePath;
  final Uri? baseUri;
  final String? androidDeviceId;
  final int maxEntries;
  final int maxEndpointSummaries;
  final bool includeEntries;
  final String? id;
  final String? before;
  final String? method;
  final String? uriContains;
  final bool onlyFailures;
  final int? statusCodeAtLeast;

  CockpitNetworkQuery get networkQuery => CockpitNetworkQuery(
    id: id,
    before: before,
    method: method,
    uriContains: uriContains,
    onlyFailures: onlyFailures,
    statusCodeAtLeast: statusCodeAtLeast,
  );
}

final class CockpitReadNetworkSummary {
  const CockpitReadNetworkSummary({
    required this.totalEntryCount,
    required this.failureCount,
    required this.capturedEntryCount,
    required this.inFlightCount,
    required this.truncated,
    required this.query,
  });

  final int totalEntryCount;
  final int failureCount;
  final int capturedEntryCount;
  final int inFlightCount;
  final bool truncated;
  final CockpitNetworkQuery query;

  Map<String, Object?> toJson() => <String, Object?>{
    'totalEntryCount': totalEntryCount,
    'failureCount': failureCount,
    'capturedEntryCount': capturedEntryCount,
    'inFlightCount': inFlightCount,
    'truncated': truncated,
    'query': (query.toJson()),
  };
}

final class CockpitReadNetworkResult {
  const CockpitReadNetworkResult({
    required this.appId,
    required this.source,
    required this.available,
    required this.summary,
    required this.endpointSummaries,
    required this.endpointSummariesTruncated,
    required this.recentFailures,
    this.routeName,
    this.entries,
  });

  final String appId;
  final String source;
  final bool available;
  final String? routeName;
  final CockpitReadNetworkSummary summary;
  final List<CockpitNetworkEndpointSummary> endpointSummaries;
  final bool endpointSummariesTruncated;
  final List<CockpitNetworkEntry> recentFailures;
  final List<CockpitNetworkEntry>? entries;

  Map<String, Object?> toJson() => <String, Object?>{
    'appId': appId,
    'source': source,
    'available': available,
    'routeName': routeName,
    'summary': summary.toJson(),
    'endpointSummaries': endpointSummaries
        .map((summary) => (summary.toJson()))
        .toList(growable: false),
    'endpointSummariesTruncated': endpointSummariesTruncated,
    'recentFailures': recentFailures
        .map((entry) => (entry.toJson()))
        .toList(growable: false),
    'entries': entries
        ?.map((entry) => (entry.toJson()))
        .toList(growable: false),
  };
}

final class CockpitReadNetworkService {
  CockpitReadNetworkService({
    required CockpitSessionRegistry registry,
    CockpitAppReferenceResolver? appReferenceResolver,
    CockpitReadNetworkSnapshotReader? readSnapshot,
  }) : _appReferenceResolver =
           appReferenceResolver ??
           CockpitAppReferenceResolver(registry: registry),
       _readSnapshot =
           readSnapshot ??
           ((baseUri, options) => CockpitRemoteSessionClient(
             baseUri: baseUri,
           ).readSnapshotDetailed(options: options));

  final CockpitAppReferenceResolver _appReferenceResolver;
  final CockpitReadNetworkSnapshotReader _readSnapshot;

  Future<CockpitReadNetworkResult> read(
    CockpitReadNetworkRequest request,
  ) async {
    final resolved = await _appReferenceResolver.resolve(
      appId: request.appId,
      appHandlePath: request.appHandlePath,
      baseUri: request.baseUri,
      androidDeviceId: request.androidDeviceId,
    );
    final effectiveAppId = resolved.app?.appId ?? request.appId ?? 'unknown';
    final snapshot = (await _readSnapshot(
      resolved.baseUri,
      CockpitSnapshotOptions(
        includeNetworkActivity: true,
        maxNetworkEntries: _sanitizeMax(request.maxEntries, fallback: 8),
        networkQuery: request.networkQuery,
      ),
    )).snapshot;
    final network = snapshot.network;
    if (network == null) {
      return CockpitReadNetworkResult(
        appId: effectiveAppId,
        source: 'app_snapshot',
        available: true,
        routeName: snapshot.routeName,
        summary: CockpitReadNetworkSummary(
          totalEntryCount: 0,
          failureCount: 0,
          capturedEntryCount: 0,
          inFlightCount: 0,
          truncated: false,
          query: request.networkQuery,
        ),
        endpointSummaries: const <CockpitNetworkEndpointSummary>[],
        endpointSummariesTruncated: false,
        recentFailures: const <CockpitNetworkEntry>[],
        entries: request.includeEntries ? const <CockpitNetworkEntry>[] : null,
      );
    }

    final maxEndpointSummaries = _sanitizeMax(
      request.maxEndpointSummaries,
      fallback: 8,
    );
    final endpointSummaries =
        network.endpointSummaries.length > maxEndpointSummaries
        ? network.endpointSummaries.sublist(0, maxEndpointSummaries)
        : network.endpointSummaries;
    final recentFailures = await _loadRecentFailures(
      baseUri: resolved.baseUri,
      request: request,
      snapshot: snapshot,
    );

    return CockpitReadNetworkResult(
      appId: effectiveAppId,
      source: 'app_snapshot',
      available: true,
      routeName: snapshot.routeName,
      summary: CockpitReadNetworkSummary(
        totalEntryCount: network.totalEntryCount,
        failureCount: network.failureCount,
        capturedEntryCount: network.capturedEntryCount,
        inFlightCount: network.inFlightCount,
        truncated: network.truncated,
        query: network.query,
      ),
      endpointSummaries: List<CockpitNetworkEndpointSummary>.unmodifiable(
        endpointSummaries,
      ),
      endpointSummariesTruncated:
          network.endpointSummaries.length > endpointSummaries.length,
      recentFailures: recentFailures,
      entries: request.includeEntries
          ? List<CockpitNetworkEntry>.unmodifiable(network.entries)
          : null,
    );
  }

  Future<List<CockpitNetworkEntry>> _loadRecentFailures({
    required Uri baseUri,
    required CockpitReadNetworkRequest request,
    required CockpitSnapshot snapshot,
  }) async {
    final network = snapshot.network;
    if (network == null) {
      return const <CockpitNetworkEntry>[];
    }

    final visibleFailures = network.entries
        .where((entry) => entry.isFailure)
        .toList(growable: false);
    if (visibleFailures.isNotEmpty ||
        network.failureCount == 0 ||
        request.onlyFailures) {
      return List<CockpitNetworkEntry>.unmodifiable(visibleFailures);
    }

    final failureSnapshot = (await _readSnapshot(
      baseUri,
      CockpitSnapshotOptions(
        includeNetworkActivity: true,
        maxNetworkEntries: _sanitizeMax(request.maxEntries, fallback: 8),
        networkQuery: CockpitNetworkQuery(
          method: request.method,
          uriContains: request.uriContains,
          onlyFailures: true,
          statusCodeAtLeast: request.statusCodeAtLeast,
        ),
      ),
    )).snapshot;
    final failureEntries =
        failureSnapshot.network?.entries
            .where((entry) => entry.isFailure)
            .toList(growable: false) ??
        const <CockpitNetworkEntry>[];
    return List<CockpitNetworkEntry>.unmodifiable(failureEntries);
  }

  int _sanitizeMax(int value, {required int fallback}) {
    if (value <= 0) {
      return fallback;
    }
    return value;
  }
}
