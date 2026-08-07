import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../registry/cockpit_registry_models.dart';
import 'cockpit_supervisor_http_support.dart';
import 'cockpit_supervisor_runtime.dart';
import 'cockpit_supervisor_sse.dart';

final class CockpitSupervisorHttpApi {
  CockpitSupervisorHttpApi({
    required this.runtime,
    required CockpitServerInfo serverInfo,
    CockpitSupervisorInternalErrorObserver? onInternalError,
  }) : support = CockpitSupervisorHttpSupport(
         serverInfo,
         onInternalError: onInternalError,
       ),
       sse = CockpitSupervisorSse(runtime);

  final CockpitSupervisorRuntime runtime;
  final CockpitSupervisorHttpSupport support;
  final CockpitSupervisorSse sse;

  Future<void> handle(HttpRequest request) async {
    try {
      final path = request.uri.pathSegments;
      if (request.uri.path == '/api/v2/server') {
        await _server(request);
        return;
      }
      if (path.length < 3 || path[0] != 'api' || path[1] != 'v2') {
        await _notFound(request);
        return;
      }
      support.negotiate(request);
      if (path.length == 3) {
        await _collection(request, path[2]);
        return;
      }
      if (path[2] == 'roots' && path.length == 4) {
        await _root(request, path[3]);
        return;
      }
      if (path[2] == 'operations' && path.length == 4 && path[3] == 'schema') {
        if (request.method != 'GET') {
          await _methodNotAllowed(request, const <String>['GET']);
          return;
        }
        await support.json(request, HttpStatus.ok, runtime.operationSchema());
        return;
      }
      if (path[2] == 'workspaces') {
        await _workspaceRoute(request, path);
        return;
      }
      if (path[2] == 'runs') {
        await _runRoute(request, path);
        return;
      }
      await _notFound(request);
    } on Object catch (error, stackTrace) {
      await support.error(request, error, stackTrace: stackTrace);
    }
  }

  Future<void> _server(HttpRequest request) {
    if (request.method != 'GET') {
      return _methodNotAllowed(request, const <String>['GET']);
    }
    if (request.uri.query.isNotEmpty) return _notFound(request);
    return support.json(request, HttpStatus.ok, support.serverInfo.toJson());
  }

  Future<void> _collection(HttpRequest request, String resource) async {
    switch (resource) {
      case 'capabilities':
        if (request.method != 'GET') {
          return _methodNotAllowed(request, const <String>['GET']);
        }
        await support.json(
          request,
          HttpStatus.ok,
          (await runtime.capabilities()).toJson(),
        );
      case 'roots':
        if (request.method == 'GET') {
          final page = support.pageRequest(request, 'roots');
          final roots = await runtime.roots();
          roots.sort((left, right) => left.rootId.compareTo(right.rootId));
          await support.json(
            request,
            HttpStatus.ok,
            support.page(roots, page, 'roots', (root) => root.toJson()),
          );
          return;
        }
        if (request.method == 'POST') {
          final registered = await runtime.registerRoot(
            CockpitRootRegistration.fromJson(await support.readJson(request)),
          );
          await support.json(request, HttpStatus.created, registered.toJson());
          return;
        }
        await _methodNotAllowed(request, const <String>['GET', 'POST']);
      case 'operations':
        if (request.method == 'GET') {
          final page = support.pageRequest(request, 'supervisor-operations');
          final operations = runtime.supervisorOperations();
          await support.json(
            request,
            HttpStatus.ok,
            support.page<CockpitOperationDescriptor>(
              operations,
              page,
              'supervisor-operations',
              (operation) => operation.toJson(),
            ),
          );
          return;
        }
        if (request.method == 'POST') {
          final result = await runtime.executeSupervisorOperation(
            CockpitOperationInvocation.fromJson(
              await support.readJson(request),
            ),
          );
          await support.json(request, HttpStatus.ok, result.toJson());
          return;
        }
        await _methodNotAllowed(request, const <String>['GET', 'POST']);
      case 'workspaces':
        if (request.method != 'GET') {
          return _methodNotAllowed(request, const <String>['GET']);
        }
        final page = support.pageRequest(request, 'workspaces');
        final workspaces = await runtime.workspaces();
        workspaces.sort(
          (left, right) => left.workspaceId.compareTo(right.workspaceId),
        );
        await support.json(
          request,
          HttpStatus.ok,
          support.page(
            workspaces,
            page,
            'workspaces',
            (workspace) => workspace.toJson(),
          ),
        );
      default:
        await _notFound(request);
    }
  }

  Future<void> _root(HttpRequest request, String rootId) async {
    if (request.method != 'DELETE') {
      return _methodNotAllowed(request, const <String>['DELETE']);
    }
    final result = await runtime.removeRoot(
      rootId,
      CockpitRootRemoval.fromJson(await support.readJson(request)),
    );
    await support.json(request, HttpStatus.ok, _retirement(result));
  }

  Future<void> _workspaceRoute(HttpRequest request, List<String> path) async {
    if (path.length == 4 && path[3] == 'register') {
      if (request.method != 'POST') {
        return _methodNotAllowed(request, const <String>['POST']);
      }
      final workspace = await runtime.registerWorkspace(
        CockpitWorkspaceRegistration.fromJson(await support.readJson(request)),
      );
      await support.json(request, HttpStatus.created, workspace.toJson());
      return;
    }
    if (path.length < 4) return _notFound(request);
    final workspaceId = path[3];
    if (path.length == 8 && path[4] == 'sessions' && path[6] == 'artifacts') {
      if (request.method != 'GET') {
        return _methodNotAllowed(request, const <String>['GET']);
      }
      final artifact = await runtime.developmentArtifactFile(
        workspaceId,
        path[5],
        path[7],
      );
      request.response.statusCode = HttpStatus.ok;
      request.response.headers
        ..contentType = ContentType.parse(artifact.mediaType)
        ..contentLength = artifact.sizeBytes
        ..set('Digest', 'sha-256=${artifact.sha256}')
        ..set(
          'Content-Disposition',
          'attachment; filename="${artifact.artifactId}"',
        );
      await request.response.addStream(artifact.file.openRead());
      await request.response.close();
      return;
    }
    if (path.length == 4) {
      if (request.method != 'DELETE') {
        return _methodNotAllowed(request, const <String>['DELETE']);
      }
      final result = await runtime.removeWorkspace(
        workspaceId,
        CockpitWorkspaceRemoval.fromJson(await support.readJson(request)),
      );
      await support.json(request, HttpStatus.ok, _retirement(result));
      return;
    }
    if (path.length == 5 && path[4] == 'rebind') {
      if (request.method != 'POST') {
        return _methodNotAllowed(request, const <String>['POST']);
      }
      final workspace = await runtime.rebindWorkspace(
        workspaceId,
        CockpitWorkspaceRebind.fromJson(await support.readJson(request)),
      );
      await support.json(request, HttpStatus.ok, workspace.toJson());
      return;
    }
    if (path.length == 5 && path[4] == 'targets') {
      if (request.method != 'GET') {
        return _methodNotAllowed(request, const <String>['GET']);
      }
      final page = support.pageRequest(request, 'targets:$workspaceId');
      final targets = await runtime.targets(workspaceId);
      targets.sort((left, right) => left.targetId.compareTo(right.targetId));
      await support.json(
        request,
        HttpStatus.ok,
        support.page(
          targets,
          page,
          'targets:$workspaceId',
          (target) => target.toJson(),
        ),
      );
      return;
    }
    if (path.length == 6 && path[4] == 'targets') {
      if (request.method != 'GET') {
        return _methodNotAllowed(request, const <String>['GET']);
      }
      await support.json(
        request,
        HttpStatus.ok,
        (await runtime.target(workspaceId, path[5])).toJson(),
      );
      return;
    }
    if (path.length == 5 && path[4] == 'documents') {
      if (request.method != 'GET') {
        return _methodNotAllowed(request, const <String>['GET']);
      }
      final query = request.uri.queryParameters;
      final kind = switch (query['kind']) {
        null => null,
        'source' ||
        'case' ||
        'suite' ||
        'project' ||
        'authored' => query['kind'],
        _ => throw const FormatException(
          'Indexed document kind query is invalid.',
        ),
      };
      final relativePath = query['relativePath'];
      final pageScope =
          'documents:$workspaceId:${kind ?? ''}:${relativePath ?? ''}';
      final page = support.pageRequest(
        request,
        pageScope,
        additionalQueryParameters: const <String>{'kind', 'relativePath'},
      );
      final offset = page.cursor == null
          ? 0
          : support.decodeCursor(page.cursor!, pageScope);
      final documentPage = await runtime.documentPage(
        workspaceId,
        kind: kind,
        relativePath: relativePath,
        offset: offset,
        limit: page.limit,
        refreshIndex: page.cursor == null,
      );
      if (offset > documentPage.totalCount) {
        throw const FormatException('Pagination cursor is stale.');
      }
      final nextOffset = offset + documentPage.items.length;
      if (nextOffset < documentPage.totalCount && documentPage.items.isEmpty) {
        throw const FormatException('Document page made no progress.');
      }
      await support.json(request, HttpStatus.ok, <String, Object?>{
        'items': documentPage.items
            .map((document) => document.toJson())
            .toList(growable: false),
        if (nextOffset < documentPage.totalCount)
          'nextCursor': support.encodeCursor(pageScope, nextOffset),
        'totalCount': documentPage.totalCount,
      });
      return;
    }
    if (path.length == 6 && path[4] == 'documents' && path[5] == 'validate') {
      if (request.method != 'POST') {
        return _methodNotAllowed(request, const <String>['POST']);
      }
      final result = await runtime.validateDocument(
        workspaceId,
        CockpitDocumentValidationRequest.fromJson(
          await support.readJson(request),
        ),
      );
      await support.json(request, HttpStatus.ok, result.toJson());
      return;
    }
    if (path.length == 5 && path[4] == 'cases') {
      if (request.method != 'GET') {
        return _methodNotAllowed(request, const <String>['GET']);
      }
      final page = support.pageRequest(request, 'cases:$workspaceId');
      final cases =
          <CockpitCaseIndexEntry>[
            for (final document in await runtime.documents(workspaceId))
              if (document.kind == CockpitIndexedDocumentKind.testCase)
                for (final testCase in document.cases)
                  CockpitCaseIndexEntry(
                    caseId: testCase.caseId,
                    documentId: document.documentId,
                    relativePath: document.relativePath,
                    title: testCase.title,
                    location: testCase.location,
                  ),
          ]..sort((left, right) {
            final byCase = left.caseId.compareTo(right.caseId);
            if (byCase != 0) return byCase;
            final byPath = left.relativePath!.compareTo(right.relativePath!);
            if (byPath != 0) return byPath;
            return left.documentId!.compareTo(right.documentId!);
          });
      await support.json(
        request,
        HttpStatus.ok,
        support.page(
          cases,
          page,
          'cases:$workspaceId',
          (testCase) => testCase.toJson(),
        ),
      );
      return;
    }
    if (path.length == 5 && path[4] == 'operations') {
      if (request.method == 'GET') {
        final page = support.pageRequest(
          request,
          'workspace-operations:$workspaceId',
        );
        final operations = await runtime.workspaceOperations(workspaceId);
        operations.sort((left, right) => left.kind.compareTo(right.kind));
        await support.json(
          request,
          HttpStatus.ok,
          support.page(
            operations,
            page,
            'workspace-operations:$workspaceId',
            (operation) => operation.toJson(),
          ),
        );
        return;
      }
      if (request.method == 'POST') {
        final invocation = CockpitOperationInvocation.fromJson(
          await support.readJson(request),
        );
        final result = await runtime.executeWorkspaceOperation(
          workspaceId,
          invocation,
        );
        await support.json(request, HttpStatus.ok, result.toJson());
        return;
      }
      return _methodNotAllowed(request, const <String>['GET', 'POST']);
    }
    if (path.length == 5 && path[4] == 'runs') {
      if (request.method != 'POST') {
        return _methodNotAllowed(request, const <String>['POST']);
      }
      final submission = CockpitRunSubmission.fromJson(
        await support.readJson(request),
      );
      if (submission.workspaceId != workspaceId) {
        throw const FormatException('Run submission workspace mismatch.');
      }
      final accepted = await runtime.submitRun(submission);
      await support.json(request, HttpStatus.accepted, accepted.toJson());
      return;
    }
    await _notFound(request);
  }

  Future<void> _runRoute(HttpRequest request, List<String> path) async {
    if (path.length < 4) return _notFound(request);
    final runId = path[3];
    if (path.length == 4) {
      if (request.method != 'GET') {
        return _methodNotAllowed(request, const <String>['GET']);
      }
      await support.json(
        request,
        HttpStatus.ok,
        (await runtime.run(runId)).toJson(),
      );
      return;
    }
    if (path.length == 5 && path[4] == 'cancel') {
      if (request.method != 'POST') {
        return _methodNotAllowed(request, const <String>['POST']);
      }
      final cancellation = await runtime.cancelRun(
        runId,
        CockpitRunCancellationRequest.fromJson(await support.readJson(request)),
      );
      await support.json(request, HttpStatus.accepted, cancellation.toJson());
      return;
    }
    if (path.length == 5 && path[4] == 'events') {
      if (request.method != 'GET') {
        return _methodNotAllowed(request, const <String>['GET']);
      }
      await sse.stream(request, runId);
      return;
    }
    if (path.length == 5 && path[4] == 'report') {
      if (request.method != 'GET') {
        return _methodNotAllowed(request, const <String>['GET']);
      }
      await support.json(
        request,
        HttpStatus.ok,
        (await runtime.report(runId)).toJson(),
      );
      return;
    }
    if (path.length == 5 && path[4] == 'cases') {
      if (request.method != 'GET') {
        return _methodNotAllowed(request, const <String>['GET']);
      }
      final page = support.pageRequest(request, 'run-cases:$runId');
      final run = await runtime.run(runId);
      final replay = await runtime.events(runId, 0);
      final byCase = <String, List<CockpitRunEvent>>{};
      for (final event in replay.events) {
        final caseId = event.caseId;
        if (caseId == null) continue;
        byCase.putIfAbsent(caseId, () => <CockpitRunEvent>[]).add(event);
      }
      final cases = <CockpitRunCaseResource>[
        for (final entry in byCase.entries)
          CockpitRunCaseResource(
            runId: run.runId,
            caseId: entry.key,
            sourceSha256: run.sourceSha256,
            attemptIds: entry.value
                .map((event) => event.attemptId)
                .whereType<String>()
                .toSet(),
            outcome: entry.value
                .where(
                  (event) =>
                      event.entityKind == CockpitRunEventEntityKind.testCase,
                )
                .map((event) => event.outcome)
                .whereType<CockpitRunOutcome>()
                .lastOrNull,
            stability: entry.value
                .where(
                  (event) =>
                      event.entityKind == CockpitRunEventEntityKind.testCase,
                )
                .map((event) => event.stability)
                .whereType<CockpitRunStability>()
                .lastOrNull,
          ),
      ]..sort((left, right) => left.caseId.compareTo(right.caseId));
      await support.json(
        request,
        HttpStatus.ok,
        support.page(cases, page, 'run-cases:$runId', (item) => item.toJson()),
      );
      return;
    }
    if (path.length == 5 && path[4] == 'artifacts') {
      if (request.method != 'GET') {
        return _methodNotAllowed(request, const <String>['GET']);
      }
      final page = support.pageRequest(request, 'run-artifacts:$runId');
      final artifacts = await runtime.artifacts(runId);
      await support.json(
        request,
        HttpStatus.ok,
        support.page(
          artifacts,
          page,
          'run-artifacts:$runId',
          (item) => item.toJson(),
        ),
      );
      return;
    }
    if (path.length == 6 && path[4] == 'artifacts') {
      if (request.method != 'GET') {
        return _methodNotAllowed(request, const <String>['GET']);
      }
      final artifact = await runtime.artifactFile(runId, path[5]);
      request.response.statusCode = HttpStatus.ok;
      request.response.headers
        ..contentType = ContentType.parse(artifact.resource.mediaType)
        ..contentLength = artifact.resource.sizeBytes
        ..set('Digest', 'sha-256=${artifact.resource.sha256}')
        ..set(
          'Content-Disposition',
          'attachment; filename="${artifact.resource.artifactId}"',
        );
      await request.response.addStream(artifact.file.openRead());
      await request.response.close();
      return;
    }
    await _notFound(request);
  }

  Future<void> _notFound(HttpRequest request) => support.error(
    request,
    CockpitApiException(
      CockpitApiError(
        code: CockpitErrorCode.notFound,
        category: CockpitErrorCategory.invalidInput,
        message: 'API route was not found.',
        retryable: false,
        responsibleLayer: CockpitResponsibleLayer.supervisor,
      ),
    ),
  );

  Future<void> _methodNotAllowed(HttpRequest request, Iterable<String> allow) {
    request.response.headers.set(HttpHeaders.allowHeader, allow.join(', '));
    return support.json(request, HttpStatus.methodNotAllowed, <String, Object?>{
      'error': CockpitApiError(
        code: CockpitErrorCode.invalidRequest,
        category: CockpitErrorCategory.invalidInput,
        message: 'HTTP method is not allowed for this route.',
        retryable: false,
        responsibleLayer: CockpitResponsibleLayer.supervisor,
      ).toJson(),
    });
  }

  Map<String, Object?> _retirement(CockpitRetirementResult result) =>
      <String, Object?>{
        'id': result.id,
        'tombstoneRetained': result.tombstoneRetained,
        'referenceCounts': result.referenceCounts.bounded,
      };
}
