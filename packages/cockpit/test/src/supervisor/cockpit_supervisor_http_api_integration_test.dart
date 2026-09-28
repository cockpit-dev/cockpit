import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_home.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_client.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_discovery.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_api_client.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_http_api.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_runtime.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Wire-level integration coverage for the daemon-side supervisor HTTP API.
///
/// A real [CockpitSupervisorHttpApi] backed by a real
/// [CockpitSupervisorRuntime] (registry, leases, and run admissions over a
/// temporary home) serves an in-process HTTP server. Raw HTTP requests
/// exercise the routing, negotiation, pagination, and error-envelope
/// contracts, and the final test drives the same server with the production
/// [CockpitSupervisorApiClient] to prove both wire ends interoperate.
void main() {
  late final _HttpApiHarness harness;

  setUpAll(() async {
    harness = await _HttpApiHarness.create();
  });

  tearDownAll(() async {
    await harness.dispose();
  });

  test(
    'server info is served before negotiation and rejects query strings',
    () async {
      final response = await harness.request(
        'GET',
        '/api/v2/server',
        versionHeader: false,
      );
      expect(response.status, HttpStatus.ok);
      final body = response.body as Map<Object?, Object?>;
      expect(body['instanceId'], harness.serverInfo.instanceId);
      expect((body['apiVersion'] as Map<Object?, Object?>)['major'], 2);
      expect(body['engineVersion'], harness.serverInfo.engineVersion);

      final queried = await harness.request(
        'GET',
        '/api/v2/server?extra=1',
        versionHeader: false,
      );
      expect(queried.status, HttpStatus.notFound);
      expect((queried.body as Map<Object?, Object?>)['error'], isNotNull);
    },
  );

  test('every negotiated route demands a compatible api version', () async {
    final missing = await harness.request(
      'GET',
      '/api/v2/roots',
      versionHeader: false,
    );
    expect(missing.status, HttpStatus.badRequest);
    expect(_errorCode(missing), 'invalidRequest');
    expect(_errorMessage(missing), contains('Cockpit-API-Version is required'));

    for (final malformed in const <String>['2', 'two.0', '2.0.1']) {
      final response = await harness.request(
        'GET',
        '/api/v2/roots',
        headers: <String, String>{'Cockpit-API-Version': malformed},
      );
      expect(response.status, HttpStatus.badRequest, reason: malformed);
      expect(_errorCode(response), 'invalidRequest');
    }

    for (final incompatible in const <String>['1.0', '3.0']) {
      final response = await harness.request(
        'GET',
        '/api/v2/roots',
        headers: <String, String>{'Cockpit-API-Version': incompatible},
      );
      expect(response.status, HttpStatus.upgradeRequired, reason: incompatible);
      expect(_errorCode(response), 'upgradeRequired');
    }

    final featureless = await harness.request(
      'GET',
      '/api/v2/roots',
      headers: <String, String>{
        'Cockpit-API-Version': '2.0',
        'Cockpit-Required-Features': 'feature-that-does-not-exist',
      },
    );
    expect(featureless.status, HttpStatus.upgradeRequired);
    expect(_errorCode(featureless), 'upgradeRequired');
    expect(_errorMessage(featureless), contains('missing required'));
  });

  test('capabilities document is served', () async {
    final response = await harness.request('GET', '/api/v2/capabilities');
    expect(response.status, HttpStatus.ok);
    final body = response.body as Map<Object?, Object?>;
    expect((body['apiVersion'] as Map<Object?, Object?>)['major'], 2);
    expect(body['operations'], isA<List<Object?>>());
    expect(body['resources'], isA<List<Object?>>());
  });

  test(
    'roots register, list deterministically, and retire end to end',
    () async {
      final baseline = await harness.rootCount();

      final directories = <Directory>[];
      for (var index = 0; index < 3; index += 1) {
        directories.add(await harness.createDirectory('root-$index'));
      }
      final rootIds = <String>[];
      for (final directory in directories) {
        final response = await harness.request(
          'POST',
          '/api/v2/roots',
          body: <String, Object?>{'path': directory.path},
        );
        expect(response.status, HttpStatus.created);
        final root = response.body as Map<Object?, Object?>;
        expect(root['canonicalPath'], directory.path);
        rootIds.add(root['rootId'] as String);
      }
      expect(await harness.rootCount(), baseline + 3);

      final listed = await harness.listRoots();
      final listedIds = listed.map((root) => root['rootId'] as String).toList();
      expect(listedIds, equals(listedIds.toList()..sort()));
      expect(listedIds, containsAll(rootIds));

      final removal = await harness.request(
        'DELETE',
        '/api/v2/roots/${rootIds.last}',
        body: <String, Object?>{'force': true, 'drainTimeoutMs': 30},
      );
      expect(removal.status, HttpStatus.ok);
      final retirement = removal.body as Map<Object?, Object?>;
      expect(retirement['id'], rootIds.last);
      expect(retirement['tombstoneRetained'], isA<bool>());
      expect(retirement['referenceCounts'], isA<Map<Object?, Object?>>());

      expect(await harness.rootCount(), baseline + 2);
    },
  );

  test('pagination honors limits and cursors and rejects abuse', () async {
    final baseline = await harness.rootCount();
    final directories = <Directory>[
      for (var index = 0; index < 3; index += 1)
        await harness.createDirectory('paged-$index'),
    ];
    addTearDown(() async {
      for (final directory in directories) {
        await harness.removeRootAtPath(directory.path);
      }
    });
    for (final directory in directories) {
      await harness.registerRoot(directory.path);
    }
    expect(await harness.rootCount(), baseline + 3);

    final first = await harness.request('GET', '/api/v2/roots?limit=1');
    expect(first.status, HttpStatus.ok);
    final firstPage = first.body as Map<Object?, Object?>;
    expect((firstPage['items'] as List<Object?>), hasLength(1));
    expect(firstPage['totalCount'], baseline + 3);
    final cursor = firstPage['nextCursor'] as String;
    expect(cursor, isNotNull);

    final second = await harness.request(
      'GET',
      '/api/v2/roots?limit=2&cursor=${Uri.encodeQueryComponent(cursor)}',
    );
    expect(second.status, HttpStatus.ok);
    final secondPage = second.body as Map<Object?, Object?>;
    expect(secondPage['items'], hasLength(2));
    expect(secondPage['totalCount'], baseline + 3);

    final foreign = await harness.request(
      'GET',
      '/api/v2/workspaces?cursor=${Uri.encodeQueryComponent(cursor)}',
    );
    expect(foreign.status, HttpStatus.badRequest);
    expect(_errorCode(foreign), 'invalidRequest');
    expect(_errorMessage(foreign), contains('cursor is invalid'));

    final forged = await harness.request(
      'GET',
      '/api/v2/roots?cursor=${Uri.encodeQueryComponent('bm90LWEtY3Vyc29y')}'
          '&limit=1',
    );
    expect(forged.status, HttpStatus.badRequest);
    expect(_errorCode(forged), 'invalidRequest');

    final deepCursor = harness.forgedRootCursor(100000);
    for (final directory in directories.take(2)) {
      await harness.removeRootAtPath(directory.path);
    }
    expect(await harness.rootCount(), baseline + 1);
    final stale = await harness.request(
      'GET',
      '/api/v2/roots?limit=1&cursor=${Uri.encodeQueryComponent(deepCursor)}',
    );
    expect(stale.status, HttpStatus.conflict);
    expect(_errorCode(stale), 'staleReference');
  });

  test('pagination query parameters are validated', () async {
    for (final query in const <String>[
      'limit=abc',
      'limit=0',
      'limit=-1',
      'limit=101',
      'unknown=yes',
    ]) {
      final response = await harness.request('GET', '/api/v2/roots?$query');
      expect(response.status, HttpStatus.badRequest, reason: query);
      expect(_errorCode(response), 'invalidRequest');
    }

    final allowed = await harness.request('GET', '/api/v2/roots?limit=100');
    expect(allowed.status, HttpStatus.ok);
  });

  test('write requests demand json bodies', () async {
    final untyped = await harness.request('POST', '/api/v2/roots');
    expect(untyped.status, HttpStatus.badRequest);
    expect(_errorMessage(untyped), contains('Content-Type'));

    final empty = await harness.request('POST', '/api/v2/roots', rawBody: '');
    expect(empty.status, HttpStatus.badRequest);
    expect(_errorMessage(empty), contains('JSON request body'));

    final malformed = await harness.request(
      'POST',
      '/api/v2/roots',
      rawBody: 'not json at all',
    );
    expect(malformed.status, HttpStatus.badRequest);
    expect(_errorMessage(malformed), contains('not valid UTF-8 JSON'));
  });

  test('method mismatches advertise Allow', () async {
    final deleted = await harness.request('DELETE', '/api/v2/roots');
    expect(deleted.status, HttpStatus.methodNotAllowed);
    expect(
      deleted.headers.value(HttpHeaders.allowHeader),
      anyOf(equals('GET, POST'), equals('POST, GET')),
    );

    final put = await harness.request('PUT', '/api/v2/server');
    expect(put.status, HttpStatus.methodNotAllowed);
    expect(put.headers.value(HttpHeaders.allowHeader), 'GET');

    final patched = await harness.request('PATCH', '/api/v2/operations/schema');
    expect(patched.status, HttpStatus.methodNotAllowed);
    expect(patched.headers.value(HttpHeaders.allowHeader), 'GET');
  });

  test('unknown routes produce the not found envelope', () async {
    for (final path in const <String>[
      '/api/v1/roots',
      '/api/v2/bogus',
      '/api/v2/workspaces/workspace-x/nonsense',
      '/',
    ]) {
      final response = await harness.request('GET', path);
      expect(response.status, HttpStatus.notFound, reason: path);
      expect(_errorCode(response), CockpitErrorCode.notFound);
    }
  });

  test(
    'workspace registration is idempotent, rebindable, and removable',
    () async {
      final rootDirectory = await harness.createDirectory('workspace-root');
      final rootId = await harness.registerRoot(rootDirectory.path);
      addTearDown(() async {
        await harness.removeRootAtPath(rootDirectory.path);
      });

      final workspaceDirectory = Directory(
        p.join(rootDirectory.path, 'workspace'),
      )..createSync();
      final registered = await harness.request(
        'POST',
        '/api/v2/workspaces/register',
        body: <String, Object?>{
          'rootId': rootId,
          'path': workspaceDirectory.path,
        },
      );
      expect(registered.status, HttpStatus.created);
      final workspace = registered.body as Map<Object?, Object?>;
      final workspaceId = workspace['workspaceId'] as String;
      expect(workspace['rootId'], rootId);
      expect(workspace['canonicalPath'], workspaceDirectory.path);
      expect(workspace['state'], 'active');
      final checkoutId = workspace['checkoutId'] as String;

      final again = await harness.request(
        'POST',
        '/api/v2/workspaces/register',
        body: <String, Object?>{
          'rootId': rootId,
          'path': workspaceDirectory.path,
        },
      );
      expect(again.status, HttpStatus.created);
      expect((again.body as Map<Object?, Object?>)['workspaceId'], workspaceId);

      final conflict = await harness.request(
        'POST',
        '/api/v2/workspaces/$workspaceId/rebind',
        body: <String, Object?>{
          'path': workspaceDirectory.path,
          'expectedCheckoutId': 'checkout-mismatch',
        },
      );
      expect(conflict.status, HttpStatus.conflict);
      expect(_errorCode(conflict), 'workspaceRebindConflict');

      final rebound = await harness.request(
        'POST',
        '/api/v2/workspaces/$workspaceId/rebind',
        body: <String, Object?>{
          'path': workspaceDirectory.path,
          'expectedCheckoutId': checkoutId,
        },
      );
      expect(rebound.status, HttpStatus.ok);
      expect(
        (rebound.body as Map<Object?, Object?>)['canonicalPath'],
        workspaceDirectory.path,
      );

      final removed = await harness.request(
        'DELETE',
        '/api/v2/workspaces/$workspaceId',
        body: <String, Object?>{'force': true, 'drainTimeoutMs': 30},
      );
      expect(removed.status, HttpStatus.ok);
      expect((removed.body as Map<Object?, Object?>)['id'], workspaceId);
    },
  );

  test('root retirement drains and retires its active workspaces', () async {
    final rootDirectory = await harness.createDirectory('fenced-root');
    final rootId = await harness.registerRoot(rootDirectory.path);
    final workspaceDirectory = Directory(
      p.join(rootDirectory.path, 'workspace'),
    )..createSync();
    final workspaceId = await harness.registerWorkspace(
      rootId,
      workspaceDirectory.path,
    );

    final removal = await harness.request(
      'DELETE',
      '/api/v2/roots/$rootId',
      body: <String, Object?>{'force': false, 'drainTimeoutMs': 5000},
    );
    expect(removal.status, HttpStatus.ok);
    final retirement = removal.body as Map<Object?, Object?>;
    expect(retirement['id'], rootId);
    expect(retirement['referenceCounts'], isA<Map<Object?, Object?>>());

    final rebound = await harness.request(
      'POST',
      '/api/v2/workspaces/$workspaceId/rebind',
      body: <String, Object?>{
        'path': workspaceDirectory.path,
        'expectedCheckoutId': 'checkout-any',
      },
    );
    expect(
      rebound.status,
      greaterThanOrEqualTo(400),
      reason: 'A drained workspace must never accept mutation authority again.',
    );
    expect(rebound.status, lessThan(500));

    final reRooted = await harness.request(
      'POST',
      '/api/v2/roots',
      body: <String, Object?>{'path': rootDirectory.path},
    );
    expect(reRooted.status, HttpStatus.created);
    final freshRootId =
        (reRooted.body as Map<Object?, Object?>)['rootId'] as String;

    final reRegistered = await harness.request(
      'POST',
      '/api/v2/workspaces/register',
      body: <String, Object?>{
        'rootId': freshRootId,
        'path': workspaceDirectory.path,
      },
    );
    expect(reRegistered.status, HttpStatus.created);
    final freshWorkspace = reRegistered.body as Map<Object?, Object?>;
    expect(freshWorkspace['workspaceId'], isNot(workspaceId));
    expect(freshWorkspace['state'], 'active');
  });

  test('operations expose catalog, schema, and execution', () async {
    final catalog = await harness.request('GET', '/api/v2/operations');
    expect(catalog.status, HttpStatus.ok);
    final catalogPage = catalog.body as Map<Object?, Object?>;
    final descriptors = catalogPage['items'] as List<Object?>;
    expect(descriptors, isNotEmpty);
    expect(catalogPage['totalCount'], greaterThanOrEqualTo(descriptors.length));

    final schema = await harness.request('GET', '/api/v2/operations/schema');
    expect(schema.status, HttpStatus.ok);
    expect(schema.body, isA<Map<Object?, Object?>>());

    final executed = await harness.request(
      'POST',
      '/api/v2/operations',
      body: <String, Object?>{
        'kind': 'lease.list',
        'input': <String, Object?>{},
        'requiredFeatures': <String>[],
      },
    );
    expect(executed.status, HttpStatus.ok);
    final result = executed.body as Map<Object?, Object?>;
    expect(result['kind'], 'lease.list');
    expect(result['lifecycle'], 'completed');
    expect(result['outcome'], 'succeeded');
    expect(result['operationId'], isNotNull);
    expect(result['finishedAt'], isNotNull);

    // Kinds are rejected at the decode boundary when their syntax is invalid,
    // before the catalog is ever consulted.
    final malformed = await harness.request(
      'POST',
      '/api/v2/operations',
      body: <String, Object?>{
        'kind': 'operation.that-does-not-exist',
        'input': <String, Object?>{},
        'requiredFeatures': <String>[],
      },
    );
    expect(malformed.status, HttpStatus.badRequest);
    expect(_errorCode(malformed), 'invalidRequest');

    // A syntactically valid but unsupported kind is a catalog miss, not a
    // decode failure.
    final unknown = await harness.request(
      'POST',
      '/api/v2/operations',
      body: <String, Object?>{
        'kind': 'operation.missing',
        'input': <String, Object?>{},
        'requiredFeatures': <String>[],
      },
    );
    expect(unknown.status, HttpStatus.notFound);
    expect(_errorCode(unknown), 'unsupportedOperation');

    final scoped = await harness.request(
      'POST',
      '/api/v2/operations',
      body: <String, Object?>{
        'kind': 'document.list',
        'workspaceId': 'workspace-x',
        'input': <String, Object?>{},
        'requiredFeatures': <String>[],
      },
    );
    expect(scoped.status, HttpStatus.notFound);
    expect(_errorMessage(scoped), contains('workspace operation route'));
  });

  test('indexed document queries validate the kind filter', () async {
    final response = await harness.request(
      'GET',
      '/api/v2/workspaces/workspace-x/documents?kind=bogus',
    );
    expect(response.status, HttpStatus.badRequest);
    expect(_errorMessage(response), contains('kind query is invalid'));

    final unknownParameter = await harness.request(
      'GET',
      '/api/v2/workspaces/workspace-x/documents?kind=source&extra=1',
    );
    expect(unknownParameter.status, HttpStatus.badRequest);
    expect(_errorCode(unknownParameter), 'invalidRequest');
  });

  test('run lookups surface structured not found envelopes', () async {
    final response = await harness.request('GET', '/api/v2/runs/run-missing');
    expect(response.status, HttpStatus.notFound);
    final error = _errorBody(response);
    expect(error['code'], isNotNull);
    expect(error['message'], isA<String>());
    expect(error['category'], isA<String>());
    expect(error['retryable'], isA<bool>());
    expect(error['responsibleLayer'], isA<String>());
  });

  test('error envelopes never leak stack traces or raw exceptions', () async {
    final failures = <_ApiResponse>[
      await harness.request('GET', '/api/v2/runs/run-missing'),
      await harness.request('GET', '/api/v2/unknown'),
      await harness.request('GET', '/api/v2/roots?limit=abc'),
      await harness.request(
        'GET',
        '/api/v2/roots',
        headers: <String, String>{'Cockpit-API-Version': '1.0'},
      ),
      await harness.request('DELETE', '/api/v2/roots'),
    ];
    for (final failure in failures) {
      expect(failure.status, greaterThanOrEqualTo(400));
      expect(failure.body, isA<Map<Object?, Object?>>());
      final encoded = jsonEncode(failure.body);
      expect(encoded, isNot(contains('stackTrace')));
      expect(encoded, isNot(contains('FileSystemException')));
      expect(encoded, isNot(contains('#0')));
    }
    expect(harness.internalErrors, isEmpty);
  });

  test('concurrent root registrations serialize without corruption', () async {
    final baseline = await harness.rootCount();
    final directories = <Directory>[
      for (var index = 0; index < 5; index += 1)
        await harness.createDirectory('concurrent-$index'),
    ];
    addTearDown(() async {
      for (final directory in directories) {
        await harness.removeRootAtPath(directory.path);
      }
    });

    final responses = await Future.wait(<Future<_ApiResponse>>[
      for (final directory in directories)
        harness.request(
          'POST',
          '/api/v2/roots',
          body: <String, Object?>{'path': directory.path},
        ),
    ]);
    expect(
      responses.every((response) => response.status == HttpStatus.created),
      isTrue,
    );

    final listed = await harness.listRoots();
    final ids = listed.map((root) => root['rootId'] as String).toSet();
    expect(ids, hasLength(baseline + 5));
  });

  test('registration failures name the offending paths and roots', () async {
    // A root registration against a missing directory reports pathNotFound
    // with the requested path instead of a generic internal error.
    final missingPath = p.join(
      harness.scratchDirectory.path,
      'registration-missing',
    );
    final missing = await harness.request(
      'POST',
      '/api/v2/roots',
      body: <String, Object?>{'path': missingPath},
    );
    expect(missing.status, HttpStatus.notFound);
    expect(_errorCode(missing), 'pathNotFound');
    expect(_errorMessage(missing), contains('registration-missing'));
    final missingDetails =
        _errorBody(missing)['redactedDetails'] as Map<Object?, Object?>?;
    expect(missingDetails?['path'], contains('registration-missing'));

    // Overlapping roots report both the requested and the existing paths.
    final rootDirectory = await harness.createDirectory(
      'failure-explained-root',
    );
    final rootId = await harness.registerRoot(rootDirectory.path);
    addTearDown(() async {
      await harness.removeRootAtPath(rootDirectory.path);
    });
    final nested = Directory(p.join(rootDirectory.path, 'nested'))
      ..createSync(recursive: true);
    final overlap = await harness.request(
      'POST',
      '/api/v2/roots',
      body: <String, Object?>{'path': nested.path},
    );
    expect(overlap.status, HttpStatus.badRequest);
    expect(_errorCode(overlap), 'rootOverlap');
    expect(_errorMessage(overlap), contains(nested.path));
    expect(_errorMessage(overlap), contains(rootDirectory.path));

    // A workspace outside its declared root reports both paths.
    final outside = await harness.createDirectory('failure-outside-workspace');
    final outsideResponse = await harness.request(
      'POST',
      '/api/v2/workspaces/register',
      body: <String, Object?>{'rootId': rootId, 'path': outside.path},
    );
    expect(outsideResponse.status, HttpStatus.badRequest);
    expect(_errorCode(outsideResponse), 'workspaceOutsideRoot');
    expect(_errorMessage(outsideResponse), contains(outside.path));
    expect(_errorMessage(outsideResponse), contains(rootDirectory.path));

    // An unknown root id is named in the failure.
    final inside = Directory(p.join(rootDirectory.path, 'workspace'))
      ..createSync(recursive: true);
    final unknownRoot = await harness.request(
      'POST',
      '/api/v2/workspaces/register',
      body: <String, Object?>{
        'rootId': 'root-does-not-exist',
        'path': inside.path,
      },
    );
    expect(unknownRoot.status, HttpStatus.notFound);
    expect(_errorCode(unknownRoot), 'rootNotFound');
    expect(_errorMessage(unknownRoot), contains('root-does-not-exist'));
  });

  test(
    'the production supervisor client interoperates with the served api',
    () async {
      final client = await harness.productionClient();
      try {
        final server = await client.server();
        expect(server.instanceId, harness.serverInfo.instanceId);
        expect(server.engineVersion, harness.serverInfo.engineVersion);

        final directory = await harness.createDirectory('client-interop');
        addTearDown(() async {
          await harness.removeRootAtPath(directory.path);
        });
        final root = await client.registerRoot(
          CockpitRootRegistration(path: directory.path),
        );
        expect(root.canonicalPath, directory.path);

        final workspaceDirectory = Directory(
          p.join(directory.path, 'workspace'),
        )..createSync();
        final workspace = await client.registerWorkspace(
          CockpitWorkspaceRegistration(
            rootId: root.rootId,
            path: workspaceDirectory.path,
          ),
        );
        expect(workspace.rootId, root.rootId);

        final roots = await client.roots();
        expect(roots.map((value) => value.rootId), contains(root.rootId));
        final workspaces = await client.workspaces();
        expect(
          workspaces.map((value) => value.workspaceId),
          contains(workspace.workspaceId),
        );

        final workspaceRetirement = await client.removeWorkspace(
          workspace.workspaceId,
          CockpitWorkspaceRemoval(force: true, drainTimeoutMs: 30),
        );
        expect(workspaceRetirement.id, workspace.workspaceId);
        final rootRetirement = await client.removeRoot(
          root.rootId,
          CockpitRootRemoval(force: true, drainTimeoutMs: 30),
        );
        expect(rootRetirement.id, root.rootId);
        final remaining = await client.roots();
        expect(
          remaining.map((value) => value.rootId),
          isNot(contains(root.rootId)),
        );
      } finally {
        // The client creates one HttpClient per request, so there is nothing
        // to dispose here; the block only guards assertion failures.
      }
    },
  );
}

String _errorCode(_ApiResponse response) =>
    (_errorBody(response)['code'] as String?) ?? '';

String _errorMessage(_ApiResponse response) =>
    (_errorBody(response)['message'] as String?) ?? '';

Map<Object?, Object?> _errorBody(_ApiResponse response) =>
    (response.body as Map<Object?, Object?>)['error'] as Map<Object?, Object?>;

final class _ApiResponse {
  const _ApiResponse(this.status, this.body, this.headers);

  final int status;
  final Object? body;
  final HttpHeaders headers;
}

final class _HttpApiHarness {
  _HttpApiHarness._({
    required this.homeDirectory,
    required this.scratchDirectory,
    required this.runtime,
    required this.serverInfo,
    required this.internalErrors,
    required HttpServer server,
  }) : _server = server;

  static const String instanceId = 'supervisor-http-api-itest';

  final Directory homeDirectory;
  final Directory scratchDirectory;
  final CockpitSupervisorRuntime runtime;
  final CockpitServerInfo serverInfo;
  final List<Object> internalErrors;
  final HttpServer _server;

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<Directory> _canonicalTempDirectory(String prefix) async {
    final created = await Directory.systemTemp.createTemp(prefix);
    return Directory(p.normalize(await created.resolveSymbolicLinks()));
  }

  static Future<_HttpApiHarness> create() async {
    final homeDirectory = await _canonicalTempDirectory(
      'cockpit_http_api_home',
    );
    final scratchDirectory = await _canonicalTempDirectory(
      'cockpit_http_api_scratch',
    );
    final workerStub = File(p.join(homeDirectory.path, 'worker_stub.dart'));
    await workerStub.writeAsString('void main() {}\n');

    final platform = Platform.isWindows
        ? CockpitHostPlatform.windows
        : Platform.isMacOS
        ? CockpitHostPlatform.macos
        : CockpitHostPlatform.linux;
    final runtime = await CockpitSupervisorRuntime.initialize(
      homeResolver: CockpitHomeResolver(
        platform: platform,
        environment: <String, String>{'COCKPIT_HOME': homeDirectory.path},
        userHome: homeDirectory.parent.path,
      ),
      dartExecutable: Platform.resolvedExecutable,
      workerEntrypoint: workerStub.path,
    );
    final serverInfo = runtime.serverInfo(instanceId: instanceId);
    final internalErrors = <Object>[];
    final api = CockpitSupervisorHttpApi(
      runtime: runtime,
      serverInfo: serverInfo,
      onInternalError: (request, error, stackTrace) =>
          internalErrors.add(error),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final harness = _HttpApiHarness._(
      homeDirectory: homeDirectory,
      scratchDirectory: scratchDirectory,
      runtime: runtime,
      serverInfo: serverInfo,
      internalErrors: internalErrors,
      server: server,
    );
    server.listen((request) => harness._handle(request, api));
    return harness;
  }

  Future<void> _handle(
    HttpRequest request,
    CockpitSupervisorHttpApi api,
  ) async {
    if (request.method == 'GET' && request.uri.path == '/_cockpit/health') {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(serverInfo.toJson()));
      await request.response.close();
      return;
    }
    await api.handle(request);
  }

  Future<void> dispose() async {
    await _server.close(force: true);
    await runtime.shutdown(cancel: true, emergency: false);
    if (await scratchDirectory.exists()) {
      await scratchDirectory.delete(recursive: true);
    }
    if (await homeDirectory.exists()) {
      await homeDirectory.delete(recursive: true);
    }
  }

  Future<_ApiResponse> request(
    String method,
    String path, {
    Object? body,
    String? rawBody,
    Map<String, String>? headers,
    bool versionHeader = true,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, endpoint.resolve(path));
      if (versionHeader) {
        request.headers.set('Cockpit-API-Version', '2.0');
      }
      headers?.forEach((name, value) => request.headers.set(name, value));
      final payload = rawBody ?? (body == null ? null : jsonEncode(body));
      if (payload != null) {
        request.headers.contentType = ContentType.json;
        request.write(payload);
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      final Object? decoded = text.isEmpty ? null : jsonDecode(text) as Object?;
      return _ApiResponse(response.statusCode, decoded, response.headers);
    } finally {
      client.close(force: true);
    }
  }

  Future<Directory> createDirectory(String name) async {
    final directory = Directory(p.join(scratchDirectory.path, name));
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> registerRoot(String path) async {
    final response = await request(
      'POST',
      '/api/v2/roots',
      body: <String, Object?>{'path': path},
    );
    expect(response.status, HttpStatus.created, reason: path);
    return (response.body as Map<Object?, Object?>)['rootId'] as String;
  }

  Future<String> registerWorkspace(String rootId, String path) async {
    final response = await request(
      'POST',
      '/api/v2/workspaces/register',
      body: <String, Object?>{'rootId': rootId, 'path': path},
    );
    expect(response.status, HttpStatus.created, reason: path);
    return (response.body as Map<Object?, Object?>)['workspaceId'] as String;
  }

  Future<void> removeRootAtPath(String path) async {
    final listed = await listRoots();
    final match = listed
        .where((root) => root['canonicalPath'] == path)
        .toList(growable: false);
    if (match.isEmpty) return;
    for (final root in match) {
      await request(
        'DELETE',
        '/api/v2/roots/${root['rootId']}',
        body: <String, Object?>{'force': true, 'drainTimeoutMs': 30},
      );
    }
  }

  Future<List<Map<Object?, Object?>>> listRoots() async {
    final response = await request('GET', '/api/v2/roots?limit=100');
    expect(response.status, HttpStatus.ok);
    final page = response.body as Map<Object?, Object?>;
    return (page['items'] as List<Object?>)
        .cast<Map<Object?, Object?>>()
        .toList(growable: false);
  }

  Future<int> rootCount() async {
    final response = await request('GET', '/api/v2/roots?limit=1');
    expect(response.status, HttpStatus.ok);
    return (response.body as Map<Object?, Object?>)['totalCount'] as int;
  }

  /// Builds a cursor the way the server does, pointing at [offset] within
  /// the roots scope, so stale-cursor behavior is deterministic regardless
  /// of how many roots earlier tests left registered.
  String forgedRootCursor(int offset) => base64Url
      .encode(
        utf8.encode(
          jsonEncode(<String, Object?>{'scope': 'roots', 'offset': offset}),
        ),
      )
      .replaceAll('=', '');

  Future<CockpitSupervisorApiClient> productionClient() async {
    final paths = CockpitHomePaths(homeDirectory.path);
    final identity = await const CockpitSystemProcessIdentityProbe()
        .readStartIdentity(pid);
    if (identity == null) {
      throw StateError('Unable to probe the test process start identity.');
    }
    await CockpitDaemonDiscoveryStore(
      paths: paths,
      permissionHardener: const CockpitPosixPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
    ).write(
      CockpitDaemonDiscovery(
        instanceId: serverInfo.instanceId,
        processId: pid,
        processStartIdentity: identity,
        endpoint: endpoint,
        bearerToken: 'http-api-itest-token-0123456789abcdef',
        apiMajor: 2,
        apiMinor: 0,
        engineVersion: serverInfo.engineVersion,
        startedAt: serverInfo.startedAt,
        authorizationMode: CockpitAuthorizationMode.yolo,
      ),
    );
    return CockpitSupervisorApiClient(
      lifecycle: CockpitDaemonLifecycleClient(
        paths: paths,
        executable: 'dart',
        daemonArguments: const <String>[],
        restartArguments: const <String>[],
        permissionHardener: const CockpitPosixPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
        requiredEngineVersion: serverInfo.engineVersion,
      ),
    );
  }
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
