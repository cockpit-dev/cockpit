import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../system_control/cockpit_system_control_profile.dart';
import 'cockpit_worker_document_index.dart';
import 'cockpit_worker_runtime_registry.dart';
import 'cockpit_worker_value_reader.dart';

CockpitSystemControlProfile cockpitWorkerSystemControlProfile(
  CockpitSystemControlProfile profile,
) => CockpitSystemControlProfile(
  platform: profile.platform,
  deviceId: profile.deviceId,
  appId: profile.appId,
  processId: profile.processId,
  adapter: profile.adapter,
  preferredPlane: profile.preferredPlane,
  fallbackOrder: profile.fallbackOrder,
  capabilities: <CockpitSystemControlCapability>[
    for (final capability in profile.capabilities)
      CockpitSystemControlCapability(
        action: capability.action,
        plane: capability.plane,
        availability: capability.availability,
        strategy: capability.strategy,
        groups: capability.groups,
        requires: capability.requires,
        limitations: capability.limitations,
        parameters: _workerSystemActionParameters(
          capability.action,
          profile.platform,
          capability.parameters,
        ),
        fallbackActions: capability.fallbackActions,
      ),
  ],
  recommendedNextStep: profile.recommendedNextStep,
);

List<CockpitSystemControlParameter> _workerSystemActionParameters(
  CockpitSystemControlAction action,
  String platform,
  List<CockpitSystemControlParameter> fallback,
) => switch (action) {
  CockpitSystemControlAction.installApp =>
    const <CockpitSystemControlParameter>[
      ..._workerInputCapabilityParameters,
      CockpitSystemControlParameter(
        name: 'grantPermissions',
        valueType: CockpitSystemControlParameterType.boolean,
      ),
    ],
  CockpitSystemControlAction.pushFile => <CockpitSystemControlParameter>[
    ..._workerInputCapabilityParameters,
    if (_isDesktopPlatform(platform))
      _workerOutputNameParameter
    else
      CockpitSystemControlParameter(
        name: platform == 'ios'
            ? 'containerDestinationPath'
            : 'deviceDestinationPath',
        valueType: CockpitSystemControlParameterType.string,
        required: true,
      ),
  ],
  CockpitSystemControlAction.pullFile =>
    _isDesktopPlatform(platform)
        ? const <CockpitSystemControlParameter>[
            ..._workerInputCapabilityParameters,
            _workerOutputNameParameter,
          ]
        : <CockpitSystemControlParameter>[
            CockpitSystemControlParameter(
              name: platform == 'ios'
                  ? 'containerSourcePath'
                  : 'deviceSourcePath',
              valueType: CockpitSystemControlParameterType.string,
              required: true,
            ),
            _workerOutputNameParameter,
          ],
  CockpitSystemControlAction.addMedia => <CockpitSystemControlParameter>[
    ..._workerInputCapabilityParameters,
    if (_isDesktopPlatform(platform))
      _workerOutputNameParameter
    else if (platform != 'ios')
      const CockpitSystemControlParameter(
        name: 'deviceDestinationPath',
        valueType: CockpitSystemControlParameterType.string,
      ),
  ],
  CockpitSystemControlAction.captureScreenshot =>
    const <CockpitSystemControlParameter>[
      CockpitSystemControlParameter(
        name: 'name',
        valueType: CockpitSystemControlParameterType.string,
      ),
      _workerOutputNameParameter,
    ],
  CockpitSystemControlAction.stopRecording =>
    const <CockpitSystemControlParameter>[_workerOutputNameParameter],
  _ => fallback,
};

const List<CockpitSystemControlParameter>
_workerInputCapabilityParameters = <CockpitSystemControlParameter>[
  CockpitSystemControlParameter(
    name: 'documentId',
    valueType: CockpitSystemControlParameterType.string,
    description:
        'Workspace document capability; mutually exclusive with artifactId.',
  ),
  CockpitSystemControlParameter(
    name: 'artifactId',
    valueType: CockpitSystemControlParameterType.string,
    description:
        'Managed artifact capability; mutually exclusive with documentId.',
  ),
];

const CockpitSystemControlParameter _workerOutputNameParameter =
    CockpitSystemControlParameter(
      name: 'outputName',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Optional managed artifact file name.',
    );

bool _isDesktopPlatform(String platform) =>
    const <String>{'linux', 'macos', 'windows'}.contains(platform);

final class CockpitWorkerSystemActionParameters {
  CockpitWorkerSystemActionParameters({
    required String producerRoot,
    required CockpitWorkerDocumentIndex documents,
    required CockpitWorkerRuntimeRegistry artifacts,
  }) : _producerRoot = p.normalize(producerRoot),
       _documents = documents,
       _artifacts = artifacts {
    if (!p.isAbsolute(_producerRoot)) {
      throw const FormatException(
        'System action producer root must be absolute.',
      );
    }
  }

  final String _producerRoot;
  final CockpitWorkerDocumentIndex _documents;
  final CockpitWorkerRuntimeRegistry _artifacts;

  Future<CockpitPreparedSystemActionParameters> prepare({
    required CockpitSystemControlAction action,
    required String platform,
    required String idempotencyKey,
    required Map<String, Object?> parameters,
  }) async {
    return switch (action) {
      CockpitSystemControlAction.installApp => _installApp(parameters),
      CockpitSystemControlAction.pushFile => _pushFile(
        platform,
        idempotencyKey,
        parameters,
      ),
      CockpitSystemControlAction.pullFile => _pullFile(
        platform,
        idempotencyKey,
        parameters,
      ),
      CockpitSystemControlAction.addMedia => _addMedia(
        platform,
        idempotencyKey,
        parameters,
      ),
      CockpitSystemControlAction.captureScreenshot => _captureScreenshot(
        idempotencyKey,
        parameters,
      ),
      CockpitSystemControlAction.stopRecording => _stopRecording(
        idempotencyKey,
        parameters,
      ),
      CockpitSystemControlAction.readUiTree ||
      CockpitSystemControlAction.readProcessList ||
      CockpitSystemControlAction.readWindows ||
      CockpitSystemControlAction.readSystemState ||
      CockpitSystemControlAction.readNotificationState ||
      CockpitSystemControlAction.readSystemLogs => _captureTextOutput(
        action,
        idempotencyKey,
        parameters,
      ),
      _ => CockpitPreparedSystemActionParameters(
        parameters: Map<String, Object?>.unmodifiable(parameters),
      ),
    };
  }

  Future<CockpitPreparedSystemActionParameters> _installApp(
    Map<String, Object?> parameters,
  ) async {
    workerKeys(parameters, const <String>{
      'documentId',
      'artifactId',
      'grantPermissions',
    }, r'$.input.parameters');
    final path = await _resolveCapability(parameters, allowDirectory: true);
    return CockpitPreparedSystemActionParameters(
      parameters: <String, Object?>{
        'appPath': path,
        if (parameters.containsKey('grantPermissions'))
          'grantPermissions': parameters['grantPermissions'],
      },
    );
  }

  Future<CockpitPreparedSystemActionParameters> _pushFile(
    String platform,
    String idempotencyKey,
    Map<String, Object?> parameters,
  ) async {
    if (_isDesktop(platform)) {
      return _hostCopy(idempotencyKey, parameters, actionName: 'pushFile');
    }
    final destinationKey = platform == 'ios'
        ? 'containerDestinationPath'
        : 'deviceDestinationPath';
    workerKeys(
      parameters,
      <String>{'documentId', 'artifactId', destinationKey},
      r'$.input.parameters',
      required: <String>{destinationKey},
    );
    final source = await _resolveCapability(parameters);
    return CockpitPreparedSystemActionParameters(
      parameters: <String, Object?>{
        'sourcePath': source,
        'destinationPath': workerString(
          parameters[destinationKey],
          '\$.input.parameters.$destinationKey',
          maximum: 32768,
        ),
      },
    );
  }

  Future<CockpitPreparedSystemActionParameters> _pullFile(
    String platform,
    String idempotencyKey,
    Map<String, Object?> parameters,
  ) async {
    if (_isDesktop(platform)) {
      return _hostCopy(idempotencyKey, parameters, actionName: 'pullFile');
    }
    final sourceKey = platform == 'ios'
        ? 'containerSourcePath'
        : 'deviceSourcePath';
    workerKeys(
      parameters,
      <String>{sourceKey, 'outputName'},
      r'$.input.parameters',
      required: <String>{sourceKey},
    );
    final outputPath = _allocateOutput(
      idempotencyKey: idempotencyKey,
      actionName: 'pullFile',
      requestedName: parameters['outputName'],
      defaultName: 'pulled-file.bin',
    );
    return CockpitPreparedSystemActionParameters(
      parameters: <String, Object?>{
        'sourcePath': workerString(
          parameters[sourceKey],
          '\$.input.parameters.$sourceKey',
          maximum: 32768,
        ),
        'destinationPath': outputPath,
      },
      producedPath: outputPath,
    );
  }

  Future<CockpitPreparedSystemActionParameters> _addMedia(
    String platform,
    String idempotencyKey,
    Map<String, Object?> parameters,
  ) async {
    if (_isDesktop(platform)) {
      return _hostCopy(idempotencyKey, parameters, actionName: 'addMedia');
    }
    workerKeys(parameters, const <String>{
      'documentId',
      'artifactId',
      'deviceDestinationPath',
    }, r'$.input.parameters');
    if (platform == 'ios' && parameters.containsKey('deviceDestinationPath')) {
      throw const FormatException(
        'iOS addMedia does not accept a device destination path.',
      );
    }
    final source = await _resolveCapability(parameters);
    return CockpitPreparedSystemActionParameters(
      parameters: <String, Object?>{
        'sourcePath': source,
        if (parameters.containsKey('deviceDestinationPath'))
          'destinationPath': workerString(
            parameters['deviceDestinationPath'],
            r'$.input.parameters.deviceDestinationPath',
            maximum: 32768,
          ),
      },
    );
  }

  Future<CockpitPreparedSystemActionParameters> _hostCopy(
    String idempotencyKey,
    Map<String, Object?> parameters, {
    required String actionName,
  }) async {
    workerKeys(parameters, const <String>{
      'documentId',
      'artifactId',
      'outputName',
    }, r'$.input.parameters');
    final source = await _resolveCapability(parameters);
    final outputPath = _allocateOutput(
      idempotencyKey: idempotencyKey,
      actionName: actionName,
      requestedName: parameters['outputName'],
      defaultName: actionName == 'addMedia'
          ? 'media-copy.bin'
          : 'file-copy.bin',
    );
    return CockpitPreparedSystemActionParameters(
      parameters: <String, Object?>{
        'sourcePath': source,
        'destinationPath': outputPath,
      },
      producedPath: outputPath,
    );
  }

  CockpitPreparedSystemActionParameters _captureScreenshot(
    String idempotencyKey,
    Map<String, Object?> parameters,
  ) {
    workerKeys(parameters, const <String>{
      'name',
      'outputName',
    }, r'$.input.parameters');
    final name = parameters.containsKey('name')
        ? _safeLeaf(parameters['name'], r'$.input.parameters.name')
        : 'system-screenshot';
    final outputPath = _allocateOutput(
      idempotencyKey: idempotencyKey,
      actionName: 'captureScreenshot',
      requestedName: parameters['outputName'],
      defaultName: '$name.png',
    );
    return CockpitPreparedSystemActionParameters(
      parameters: <String, Object?>{'name': name, 'outputPath': outputPath},
      producedPath: outputPath,
    );
  }

  CockpitPreparedSystemActionParameters _stopRecording(
    String idempotencyKey,
    Map<String, Object?> parameters,
  ) {
    workerKeys(parameters, const <String>{'outputName'}, r'$.input.parameters');
    final outputPath = _allocateOutput(
      idempotencyKey: idempotencyKey,
      actionName: 'stopRecording',
      requestedName: parameters['outputName'],
      defaultName: 'system-recording.mp4',
    );
    return CockpitPreparedSystemActionParameters(
      parameters: <String, Object?>{'outputPath': outputPath},
      producedPath: outputPath,
    );
  }

  CockpitPreparedSystemActionParameters _captureTextOutput(
    CockpitSystemControlAction action,
    String idempotencyKey,
    Map<String, Object?> parameters,
  ) {
    final outputPath = _allocateOutput(
      idempotencyKey: idempotencyKey,
      actionName: action.name,
      requestedName: null,
      defaultName: switch (action) {
        CockpitSystemControlAction.readUiTree => 'ui-tree.txt',
        CockpitSystemControlAction.readProcessList => 'processes.txt',
        CockpitSystemControlAction.readWindows => 'windows.txt',
        CockpitSystemControlAction.readSystemState => 'system-state.txt',
        CockpitSystemControlAction.readNotificationState => 'notifications.txt',
        CockpitSystemControlAction.readSystemLogs => 'system.log',
        _ => throw StateError('Unsupported text output action ${action.name}.'),
      },
    );
    return CockpitPreparedSystemActionParameters(
      parameters: Map<String, Object?>.unmodifiable(parameters),
      producedPath: outputPath,
      capturedStdoutRole: 'system.${action.name}',
    );
  }

  Future<String> writeCapturedStdout(
    CockpitPreparedSystemActionParameters prepared,
    String stdout,
  ) async {
    final destinationPath = prepared.producedPath;
    if (destinationPath == null || prepared.capturedStdoutRole == null) {
      throw StateError('System action stdout capture was not prepared.');
    }
    final destination = File(destinationPath);
    final bytes = utf8.encode(stdout);
    final temporary = File(
      '$destinationPath.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp',
    );
    RandomAccessFile? handle;
    try {
      await temporary.create(exclusive: true);
      handle = await temporary.open(mode: FileMode.write);
      await handle.writeFrom(bytes);
      await handle.flush();
      await handle.close();
      handle = null;
      if (await destination.exists()) {
        final current = await destination.readAsBytes();
        if (!_sameBytes(current, bytes)) {
          throw FileSystemException(
            'System action output changed for the same idempotency key.',
            destinationPath,
          );
        }
      } else {
        await temporary.rename(destinationPath);
      }
      final canonical = p.normalize(await destination.resolveSymbolicLinks());
      if (!p.isWithin(_producerRoot, canonical) ||
          await destination.length() != bytes.length) {
        throw FileSystemException(
          'System action output failed producer confinement verification.',
          destinationPath,
        );
      }
      return canonical;
    } finally {
      await handle?.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<String> _resolveCapability(
    Map<String, Object?> parameters, {
    bool allowDirectory = false,
  }) async {
    final documentId = parameters['documentId'];
    final artifactId = parameters['artifactId'];
    if ((documentId == null) == (artifactId == null)) {
      throw const FormatException(
        'Exactly one documentId or artifactId capability is required.',
      );
    }
    if (documentId != null) {
      final id = workerId(documentId, r'$.input.parameters.documentId');
      return (await _documents.resolveDocuments(<String>[
        id,
      ])).single.absolutePath;
    }
    final id = workerId(artifactId, r'$.input.parameters.artifactId');
    final binding = await _artifacts.requireArtifact(id);
    final type = await FileSystemEntity.type(
      binding.retainedPath,
      followLinks: false,
    );
    if (type != FileSystemEntityType.file &&
        !(allowDirectory && type == FileSystemEntityType.directory)) {
      throw const FormatException(
        'The selected artifact type is not valid for this action.',
      );
    }
    return binding.retainedPath;
  }

  String _allocateOutput({
    required String idempotencyKey,
    required String actionName,
    required Object? requestedName,
    required String defaultName,
  }) {
    final leaf = requestedName == null
        ? defaultName
        : _safeLeaf(requestedName, r'$.input.parameters.outputName');
    final keyHash = sha256.convert(utf8.encode(idempotencyKey)).toString();
    final candidate = p.normalize(
      p.join(_producerRoot, 'system_action_${keyHash.substring(0, 32)}_$leaf'),
    );
    if (!p.isWithin(_producerRoot, candidate)) {
      throw const FormatException('System action output escapes worker state.');
    }
    return candidate;
  }

  String _safeLeaf(Object? value, String path) {
    final leaf = workerString(value, path, maximum: 255);
    if (leaf == '.' ||
        leaf == '..' ||
        p.basename(leaf) != leaf ||
        leaf.contains('/') ||
        leaf.contains(r'\')) {
      throw FormatException('$path must be a safe file name.');
    }
    return leaf;
  }

  bool _isDesktop(String platform) =>
      const <String>{'macos', 'linux', 'windows'}.contains(platform);
}

final class CockpitPreparedSystemActionParameters {
  CockpitPreparedSystemActionParameters({
    required Map<String, Object?> parameters,
    this.producedPath,
    this.capturedStdoutRole,
  }) : parameters = Map<String, Object?>.unmodifiable(parameters);

  final Map<String, Object?> parameters;
  final String? producedPath;
  final String? capturedStdoutRole;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
