import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/application/cockpit_read_network_body_service.dart';
import 'package:cockpit/src/development/cockpit_vm_network_profiler.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  group('CockpitVmNetworkRequestMatcher', () {
    test('matches redacted identity and selects the closest request', () {
      final startedAt = DateTime.utc(2026, 8, 6, 10);
      final uri = Uri.parse(
        'https://user:password@example.test/api?token=secret&visible=yes',
      );
      final entry = CockpitNetworkEntry(
        requestId: '37',
        method: 'POST',
        uri: const CockpitNetworkRedactor().uri(uri).toString(),
        startedAt: startedAt,
        durationMs: 0,
      );
      final selected = _profileRequest(
        id: 'selected',
        method: 'post',
        uri: uri,
        startedAt: startedAt.add(const Duration(milliseconds: 20)),
      );

      final result = const CockpitVmNetworkRequestMatcher()
          .match(entry, <HttpProfileRequest>[
            _profileRequest(
              id: 'wrong-method',
              method: 'GET',
              uri: uri,
              startedAt: startedAt,
            ),
            _profileRequest(
              id: 'farther',
              method: 'POST',
              uri: uri,
              startedAt: startedAt.add(const Duration(milliseconds: 80)),
            ),
            selected,
          ]);

      expect(result.id, 'selected');
    });

    test('rejects equally close matches instead of guessing', () {
      final startedAt = DateTime.utc(2026, 8, 6, 10);
      final uri = Uri.parse('https://example.test/events');
      final entry = CockpitNetworkEntry(
        requestId: '38',
        method: 'GET',
        uri: uri.toString(),
        startedAt: startedAt,
        durationMs: 0,
      );

      expect(
        () => const CockpitVmNetworkRequestMatcher()
            .match(entry, <HttpProfileRequest>[
              _profileRequest(
                id: 'before',
                method: 'GET',
                uri: uri,
                startedAt: startedAt.subtract(const Duration(milliseconds: 10)),
              ),
              _profileRequest(
                id: 'after',
                method: 'GET',
                uri: uri,
                startedAt: startedAt.add(const Duration(milliseconds: 10)),
              ),
            ]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('ambiguous'),
          ),
        ),
      );
    });
  });

  group('CockpitReadNetworkBodyService', () {
    test(
      'writes separately redacted request and continuing response files',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'cockpit_network_body_test_',
        );
        addTearDown(() => directory.delete(recursive: true));
        final entry = _networkEntry('37');
        final service = CockpitReadNetworkBodyService(
          readBodies:
              ({
                required sessionId,
                required vmServiceUri,
                required entry,
              }) async {
                expect(sessionId, 'session-1');
                expect(vmServiceUri.toString(), 'ws://127.0.0.1:8181/ws');
                expect(entry.requestId, '37');
                return CockpitVmNetworkBodies(
                  request: CockpitVmNetworkBody(
                    bytes: Uint8List.fromList(
                      utf8.encode('{"token":"secret","visible":"yes"}'),
                    ),
                    complete: true,
                    present: true,
                    mediaType: 'application/json; charset=utf-8',
                  ),
                  response: CockpitVmNetworkBody(
                    bytes: Uint8List.fromList(
                      utf8.encode('data: {"password":"secret"}\n\n'),
                    ),
                    complete: false,
                    present: true,
                    mediaType: 'text/event-stream',
                  ),
                );
              },
          fileFactory: (basename) async => File('${directory.path}/$basename'),
          readSnapshot: (baseUri, options) async {
            expect(baseUri.toString(), 'http://127.0.0.1:57331');
            expect(options.profile, CockpitSnapshotProfile.live);
            expect(options.includeNetworkActivity, isTrue);
            expect(options.maxNetworkEntries, 1000);
            return _snapshot(entry);
          },
        );

        final result = await service.read(
          CockpitReadNetworkBodyRequest(
            sessionId: 'session-1',
            baseUri: Uri.parse('http://127.0.0.1:57331'),
            vmServiceUri: Uri.parse('ws://127.0.0.1:8181/ws'),
            requestId: '37',
            parts: const <CockpitNetworkBodyPart>{
              CockpitNetworkBodyPart.request,
              CockpitNetworkBodyPart.response,
            },
          ),
        );

        final request = result.artifacts[CockpitNetworkBodyPart.request]!;
        final response = result.artifacts[CockpitNetworkBodyPart.response]!;
        expect(result.continuing, isTrue);
        expect(request.relativePath, 'network-37-request.json');
        expect(response.relativePath, 'network-37-response.txt');
        expect(request.redacted, isTrue);
        expect(response.complete, isFalse);
        final requestText = await File(request.sourceFilePath).readAsString();
        final responseText = await File(response.sourceFilePath).readAsString();
        expect(requestText, contains('********'));
        expect(requestText, contains('visible'));
        expect(requestText, isNot(contains('secret')));
        expect(responseText, contains('********'));
        expect(responseText, isNot(contains('secret')));
      },
    );

    test('requires raw mode for binary data and preserves raw bytes', () async {
      final directory = await Directory.systemTemp.createTemp(
        'cockpit_network_binary_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final entry = _networkEntry('41');
      final bytes = Uint8List.fromList(<int>[0, 255, 1, 2]);
      final service = CockpitReadNetworkBodyService(
        readBodies:
            ({
              required sessionId,
              required vmServiceUri,
              required entry,
            }) async => CockpitVmNetworkBodies(
              request: CockpitVmNetworkBody(
                bytes: bytes,
                complete: true,
                present: true,
                mediaType: 'application/octet-stream',
              ),
              response: CockpitVmNetworkBody(
                bytes: bytes,
                complete: true,
                present: true,
                mediaType: 'application/octet-stream',
              ),
            ),
        fileFactory: (basename) async => File('${directory.path}/$basename'),
        readSnapshot: (_, _) async => _snapshot(entry),
      );
      final request = CockpitReadNetworkBodyRequest(
        sessionId: 'session-1',
        baseUri: Uri.parse('http://127.0.0.1:57331'),
        vmServiceUri: Uri.parse('ws://127.0.0.1:8181/ws'),
        requestId: '41',
        parts: const <CockpitNetworkBodyPart>{CockpitNetworkBodyPart.response},
      );

      await expectLater(
        service.read(request),
        throwsA(
          isA<CockpitApplicationServiceException>().having(
            (error) => error.code,
            'code',
            'networkBodyRawRequired',
          ),
        ),
      );
      final result = await service.read(
        CockpitReadNetworkBodyRequest(
          sessionId: request.sessionId,
          baseUri: request.baseUri,
          vmServiceUri: request.vmServiceUri,
          requestId: request.requestId,
          parts: request.parts,
          raw: true,
        ),
      );
      final artifact = result.artifacts[CockpitNetworkBodyPart.response]!;
      expect(artifact.relativePath, 'network-41-response.bin');
      expect(artifact.redacted, isFalse);
      expect(await File(artifact.sourceFilePath).readAsBytes(), bytes);
    });

    test('reports absent parts without creating empty artifacts', () async {
      final directory = await Directory.systemTemp.createTemp(
        'cockpit_network_absent_body_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final entry = _networkEntry('42');
      final service = CockpitReadNetworkBodyService(
        readBodies:
            ({
              required sessionId,
              required vmServiceUri,
              required entry,
            }) async => CockpitVmNetworkBodies(
              request: CockpitVmNetworkBody(
                bytes: Uint8List(0),
                complete: true,
                present: false,
              ),
              response: CockpitVmNetworkBody(
                bytes: Uint8List.fromList(utf8.encode('{"ok":true}')),
                complete: true,
                present: true,
                mediaType: 'application/json',
              ),
            ),
        fileFactory: (basename) async => File('${directory.path}/$basename'),
        readSnapshot: (_, _) async => _snapshot(entry),
      );

      final result = await service.read(
        CockpitReadNetworkBodyRequest(
          sessionId: 'session-1',
          baseUri: Uri.parse('http://127.0.0.1:57331'),
          vmServiceUri: Uri.parse('ws://127.0.0.1:8181/ws'),
          requestId: '42',
          parts: const <CockpitNetworkBodyPart>{
            CockpitNetworkBodyPart.request,
            CockpitNetworkBodyPart.response,
          },
        ),
      );

      expect(result.absent, <CockpitNetworkBodyPart>{
        CockpitNetworkBodyPart.request,
      });
      expect(result.continuing, isFalse);
      expect(result.artifacts, contains(CockpitNetworkBodyPart.response));
      expect(result.artifacts, isNot(contains(CockpitNetworkBodyPart.request)));
      expect(await directory.list().length, 1);
    });

    test('keeps an empty unfinished response marked as continuing', () async {
      final directory = await Directory.systemTemp.createTemp(
        'cockpit_network_continuing_body_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final entry = _networkEntry('43');
      final service = CockpitReadNetworkBodyService(
        readBodies:
            ({
              required sessionId,
              required vmServiceUri,
              required entry,
            }) async => CockpitVmNetworkBodies(
              request: CockpitVmNetworkBody(
                bytes: Uint8List(0),
                complete: true,
                present: false,
              ),
              response: CockpitVmNetworkBody(
                bytes: Uint8List(0),
                complete: false,
                present: false,
                mediaType: 'text/event-stream',
              ),
            ),
        fileFactory: (basename) async => File('${directory.path}/$basename'),
        readSnapshot: (_, _) async => _snapshot(entry),
      );

      final result = await service.read(
        CockpitReadNetworkBodyRequest(
          sessionId: 'session-1',
          baseUri: Uri.parse('http://127.0.0.1:57331'),
          vmServiceUri: Uri.parse('ws://127.0.0.1:8181/ws'),
          requestId: '43',
          parts: const <CockpitNetworkBodyPart>{
            CockpitNetworkBodyPart.response,
          },
        ),
      );

      expect(result.continuing, isTrue);
      expect(result.absent, <CockpitNetworkBodyPart>{
        CockpitNetworkBodyPart.response,
      });
      expect(await directory.list().isEmpty, isTrue);
    });

    test('rejects WebSocket body retrieval before VM profiling', () async {
      final directory = await Directory.systemTemp.createTemp(
        'cockpit_network_socket_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      var profilerCalled = false;
      final entry = CockpitNetworkEntry(
        requestId: '44',
        method: 'GET',
        uri: 'wss://example.test/events',
        startedAt: DateTime.utc(2026, 8, 6, 10),
        durationMs: 10,
        protocol: CockpitNetworkProtocol.webSocket,
        state: CockpitNetworkState.open,
      );
      final service = CockpitReadNetworkBodyService(
        readBodies:
            ({
              required sessionId,
              required vmServiceUri,
              required entry,
            }) async {
              profilerCalled = true;
              throw StateError('unreachable');
            },
        fileFactory: (basename) async => File('${directory.path}/$basename'),
        readSnapshot: (_, _) async => _snapshot(entry),
      );

      await expectLater(
        service.read(
          CockpitReadNetworkBodyRequest(
            sessionId: 'session-1',
            baseUri: Uri.parse('http://127.0.0.1:57331'),
            vmServiceUri: Uri.parse('ws://127.0.0.1:8181/ws'),
            requestId: '44',
            parts: const <CockpitNetworkBodyPart>{
              CockpitNetworkBodyPart.response,
            },
          ),
        ),
        throwsA(
          isA<CockpitApplicationServiceException>().having(
            (error) => error.code,
            'code',
            'networkBodyUnsupported',
          ),
        ),
      );
      expect(profilerCalled, isFalse);
    });
  });
}

HttpProfileRequest _profileRequest({
  required String id,
  required String method,
  required Uri uri,
  required DateTime startedAt,
}) => HttpProfileRequest(
  isolateId: 'isolate-1',
  id: id,
  method: method,
  uri: uri,
  events: const <HttpProfileRequestEvent>[],
  startTime: startedAt,
);

CockpitNetworkEntry _networkEntry(String requestId) => CockpitNetworkEntry(
  requestId: requestId,
  method: 'GET',
  uri: 'https://example.test/data',
  startedAt: DateTime.utc(2026, 8, 6, 10),
  durationMs: 10,
);

CockpitRemoteSnapshotResponse _snapshot(CockpitNetworkEntry entry) =>
    CockpitRemoteSnapshotResponse(
      snapshot: CockpitSnapshot(
        routeName: '/network',
        network: CockpitNetworkSnapshot(
          totalEntryCount: 1,
          failureCount: 0,
          capturedEntryCount: 1,
          entries: <CockpitNetworkEntry>[entry],
        ),
      ),
    );
