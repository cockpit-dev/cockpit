import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../development/cockpit_vm_network_profiler.dart';
import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_application_service_exception.dart';

enum CockpitNetworkBodyPart { request, response }

typedef CockpitNetworkBodyFileFactory = Future<File> Function(String basename);
typedef CockpitNetworkBodySnapshotReader =
    Future<CockpitRemoteSnapshotResponse> Function(
      Uri baseUri,
      CockpitSnapshotOptions options,
    );
typedef CockpitVmNetworkBodyReader =
    Future<CockpitVmNetworkBodies> Function({
      required String sessionId,
      required Uri vmServiceUri,
      required CockpitNetworkEntry entry,
    });

final class CockpitReadNetworkBodyRequest {
  const CockpitReadNetworkBodyRequest({
    required this.sessionId,
    required this.baseUri,
    required this.vmServiceUri,
    required this.requestId,
    required this.parts,
    this.raw = false,
  });

  final String sessionId;
  final Uri baseUri;
  final Uri vmServiceUri;
  final String requestId;
  final Set<CockpitNetworkBodyPart> parts;
  final bool raw;
}

final class CockpitNetworkBodyArtifact {
  const CockpitNetworkBodyArtifact({
    required this.part,
    required this.complete,
    required this.redacted,
    required this.sourceFilePath,
    required this.relativePath,
  });

  final CockpitNetworkBodyPart part;
  final bool complete;
  final bool redacted;
  final String sourceFilePath;
  final String relativePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'complete': complete,
    'redacted': redacted,
    'sourceFilePath': sourceFilePath,
    'artifact': <String, Object?>{
      'role': 'network.${part.name}.body',
      'relativePath': relativePath,
    },
  };
}

final class CockpitReadNetworkBodyResult {
  const CockpitReadNetworkBodyResult({
    required this.requestId,
    required this.artifacts,
    required this.absent,
    required this.continuing,
  });

  final String requestId;
  final Map<CockpitNetworkBodyPart, CockpitNetworkBodyArtifact> artifacts;
  final Set<CockpitNetworkBodyPart> absent;
  final bool continuing;

  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'continuing': continuing,
    if (absent.isNotEmpty)
      'absent': absent.map((part) => part.name).toList(growable: false),
    for (final entry in artifacts.entries) entry.key.name: entry.value.toJson(),
  };
}

final class CockpitReadNetworkBodyService {
  CockpitReadNetworkBodyService({
    required CockpitVmNetworkBodyReader readBodies,
    required CockpitNetworkBodyFileFactory fileFactory,
    CockpitNetworkBodySnapshotReader? readSnapshot,
  }) : _readBodies = readBodies,
       _fileFactory = fileFactory,
       _readSnapshot =
           readSnapshot ??
           ((baseUri, options) => CockpitRemoteSessionClient(
             baseUri: baseUri,
           ).readSnapshotDetailed(options: options));

  final CockpitVmNetworkBodyReader _readBodies;
  final CockpitNetworkBodyFileFactory _fileFactory;
  final CockpitNetworkBodySnapshotReader _readSnapshot;
  static const CockpitNetworkRedactor _redactor = CockpitNetworkRedactor();

  Future<CockpitReadNetworkBodyResult> read(
    CockpitReadNetworkBodyRequest request,
  ) async {
    if (request.parts.isEmpty) {
      throw const FormatException(
        'At least one network body part is required.',
      );
    }
    final snapshot = (await _readSnapshot(
      request.baseUri,
      const CockpitSnapshotOptions(
        profile: CockpitSnapshotProfile.live,
        includeNetworkActivity: true,
        maxNetworkEntries: 1000,
      ),
    )).snapshot;
    final matches =
        snapshot.network?.entries
            .where((entry) => entry.requestId == request.requestId)
            .toList(growable: false) ??
        const <CockpitNetworkEntry>[];
    if (matches.length != 1) {
      throw CockpitApplicationServiceException(
        code: 'networkRequestNotFound',
        message: 'Network request ${request.requestId} is not retained.',
      );
    }
    if (matches.single.protocol != CockpitNetworkProtocol.http) {
      throw const CockpitApplicationServiceException(
        code: 'networkBodyUnsupported',
        message:
            'Complete body retrieval is available for HTTP requests only. '
            'WebSocket frame metadata and text previews are included in the network entry.',
      );
    }
    final CockpitVmNetworkBodies bodies;
    try {
      bodies = await _readBodies(
        sessionId: request.sessionId,
        vmServiceUri: request.vmServiceUri,
        entry: matches.single,
      );
    } on CockpitVmNetworkBodyUnavailableException catch (error) {
      throw CockpitApplicationServiceException(
        code: 'networkBodyUnavailable',
        message: error.message,
      );
    }
    final artifacts = <CockpitNetworkBodyPart, CockpitNetworkBodyArtifact>{};
    final absent = <CockpitNetworkBodyPart>{};
    var continuing = false;
    for (final part in request.parts) {
      final body = part == CockpitNetworkBodyPart.request
          ? bodies.request
          : bodies.response;
      continuing = continuing || !body.complete;
      if (!body.present) {
        absent.add(part);
        continue;
      }
      final bytes = _outputBytes(body, raw: request.raw);
      final extension = _extension(body.mediaType, raw: request.raw);
      final basename = _basename(request.requestId, part, extension);
      final file = await _fileFactory(basename);
      await file.writeAsBytes(bytes, flush: true);
      artifacts[part] = CockpitNetworkBodyArtifact(
        part: part,
        complete: body.complete,
        redacted: !request.raw,
        sourceFilePath: p.normalize(await file.resolveSymbolicLinks()),
        relativePath: basename,
      );
    }
    return CockpitReadNetworkBodyResult(
      requestId: request.requestId,
      artifacts:
          Map<CockpitNetworkBodyPart, CockpitNetworkBodyArtifact>.unmodifiable(
            artifacts,
          ),
      absent: Set<CockpitNetworkBodyPart>.unmodifiable(absent),
      continuing: continuing,
    );
  }

  Uint8List _outputBytes(CockpitVmNetworkBody body, {required bool raw}) {
    if (raw || body.bytes.isEmpty) return body.bytes;
    if (!_isText(body.mediaType)) {
      throw const CockpitApplicationServiceException(
        code: 'networkBodyRawRequired',
        message: 'Binary network bodies require explicit raw retrieval.',
      );
    }
    try {
      final decoded = utf8.decode(body.bytes, allowMalformed: false);
      return Uint8List.fromList(
        utf8.encode(_redactor.body(decoded, contentType: body.mediaType)),
      );
    } on FormatException {
      throw const CockpitApplicationServiceException(
        code: 'networkBodyRawRequired',
        message: 'Non-UTF-8 network bodies require explicit raw retrieval.',
      );
    }
  }

  bool _isText(String? contentType) {
    final mediaType = contentType?.split(';').first.trim().toLowerCase();
    if (mediaType == null || mediaType.isEmpty) return true;
    return mediaType.startsWith('text/') ||
        mediaType.contains('json') ||
        mediaType.contains('xml') ||
        mediaType.contains('yaml') ||
        mediaType.contains('javascript') ||
        mediaType == 'application/x-www-form-urlencoded';
  }

  String _extension(String? contentType, {required bool raw}) {
    if (raw && !_isText(contentType)) return 'bin';
    final mediaType = contentType?.split(';').first.trim().toLowerCase();
    if (mediaType?.contains('json') == true) return 'json';
    if (mediaType?.contains('xml') == true) return 'xml';
    if (mediaType?.contains('yaml') == true) return 'yaml';
    return 'txt';
  }

  String _basename(
    String requestId,
    CockpitNetworkBodyPart part,
    String extension,
  ) {
    final id = requestId.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return 'network-$id-${part.name}.$extension';
  }
}
