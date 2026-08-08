import 'dart:io';

import 'package:path/path.dart' as p;

import '../application/cockpit_application_service_exception.dart';

const String _reservedDartDefinePrefix = 'FLUTTER_COCKPIT_';

const Set<String> _reservedFlutterArgs = <String>{
  '--dart-define',
  '--dart-define-from-file',
  '--target',
  '-t',
  '-d',
  '--device-id',
  '--flavor',
  '--machine',
  '--no-resident',
  '--app-id',
  '--debug',
  '--profile',
  '--release',
  '--simulator',
  '--no-codesign',
  '--dds',
  '--no-dds',
  '--disable-dds',
  '--no-disable-dds',
};

final class CockpitFlutterLaunchConfiguration {
  factory CockpitFlutterLaunchConfiguration({
    Iterable<String> dartDefines = const <String>[],
    Iterable<String> dartDefineFromFiles = const <String>[],
    Iterable<String> flutterArgs = const <String>[],
    Map<String, String> environment = const <String, String>{},
  }) {
    final normalizedDartDefines = _normalizeDartDefines(dartDefines);
    final normalizedDartDefineFromFiles = _normalizeNonEmptyList(
      dartDefineFromFiles,
      fieldName: 'dartDefineFromFiles',
    );
    final normalizedFlutterArgs = _normalizeFlutterArgs(flutterArgs);
    final normalizedEnvironment = _normalizeEnvironment(environment);
    return CockpitFlutterLaunchConfiguration._(
      dartDefines: normalizedDartDefines,
      dartDefineFromFiles: normalizedDartDefineFromFiles,
      flutterArgs: normalizedFlutterArgs,
      environment: normalizedEnvironment,
    );
  }

  const CockpitFlutterLaunchConfiguration._({
    required this.dartDefines,
    required this.dartDefineFromFiles,
    required this.flutterArgs,
    required this.environment,
  });

  static const CockpitFlutterLaunchConfiguration empty =
      CockpitFlutterLaunchConfiguration._(
        dartDefines: <String>[],
        dartDefineFromFiles: <String>[],
        flutterArgs: <String>[],
        environment: <String, String>{},
      );

  factory CockpitFlutterLaunchConfiguration.fromJson(
    Map<String, Object?> json,
  ) {
    try {
      const allowed = <String>{
        'dartDefines',
        'dartDefineFromFiles',
        'flutterArgs',
        'environment',
      };
      final unknown = json.keys.toSet().difference(allowed);
      if (unknown.isNotEmpty) {
        throw CockpitApplicationServiceException(
          code: 'invalidLaunchConfiguration',
          message: 'Launch configuration contains unknown fields.',
          details: <String, Object?>{'fields': unknown.toList()..sort()},
        );
      }
      return CockpitFlutterLaunchConfiguration(
        dartDefines: _readStringList(json, 'dartDefines'),
        dartDefineFromFiles: _readStringList(json, 'dartDefineFromFiles'),
        flutterArgs: _readStringList(json, 'flutterArgs'),
        environment: _readStringMap(json, 'environment'),
      );
    } on CockpitApplicationServiceException {
      rethrow;
    } on ArgumentError catch (error) {
      throw CockpitApplicationServiceException(
        code: 'invalidLaunchConfiguration',
        message: error.message,
        details: <String, Object?>{
          if (error.name != null) 'field': error.name,
          if (error.invalidValue != null) 'value': error.invalidValue,
        },
      );
    }
  }

  final List<String> dartDefines;
  final List<String> dartDefineFromFiles;
  final List<String> flutterArgs;
  final Map<String, String> environment;

  bool get isEmpty =>
      dartDefines.isEmpty &&
      dartDefineFromFiles.isEmpty &&
      flutterArgs.isEmpty &&
      environment.isEmpty;

  Map<String, String>? get processEnvironment => environment.isEmpty
      ? null
      : Map<String, String>.unmodifiable(environment);

  Future<void> validateProjectFiles(String projectDir) async {
    if (dartDefineFromFiles.isEmpty) return;
    final requestedRoot = p.normalize(p.absolute(projectDir));
    late final String canonicalRoot;
    try {
      canonicalRoot = p.normalize(
        await Directory(requestedRoot).resolveSymbolicLinks(),
      );
    } on FileSystemException {
      throw const CockpitApplicationServiceException(
        code: 'invalidLaunchConfiguration',
        message: 'The Flutter project directory is unavailable.',
      );
    }
    for (final value in dartDefineFromFiles) {
      final relative = p.normalize(value);
      if (p.isAbsolute(value) ||
          relative == '.' ||
          relative == '..' ||
          relative.startsWith('../') ||
          relative.startsWith('..${p.separator}')) {
        throw CockpitApplicationServiceException(
          code: 'invalidLaunchConfiguration',
          message: 'Dart define files must be project-relative files.',
          details: <String, Object?>{'field': 'dartDefineFromFiles'},
        );
      }
      final requestedPath = p.normalize(p.join(requestedRoot, relative));
      final expectedCanonicalPath = p.normalize(
        p.join(canonicalRoot, relative),
      );
      if (!p.isWithin(requestedRoot, requestedPath) ||
          !p.isWithin(canonicalRoot, expectedCanonicalPath) ||
          await FileSystemEntity.type(requestedPath, followLinks: false) !=
              FileSystemEntityType.file) {
        throw CockpitApplicationServiceException(
          code: 'invalidLaunchConfiguration',
          message: 'A Dart define file is missing or outside the project.',
          details: <String, Object?>{'field': 'dartDefineFromFiles'},
        );
      }
      late final String canonicalPath;
      try {
        canonicalPath = p.normalize(
          await File(requestedPath).resolveSymbolicLinks(),
        );
      } on FileSystemException {
        throw CockpitApplicationServiceException(
          code: 'invalidLaunchConfiguration',
          message: 'A Dart define file is unavailable.',
          details: <String, Object?>{'field': 'dartDefineFromFiles'},
        );
      }
      if (!p.equals(canonicalPath, expectedCanonicalPath)) {
        throw CockpitApplicationServiceException(
          code: 'invalidLaunchConfiguration',
          message: 'Dart define files must not traverse symbolic links.',
          details: <String, Object?>{'field': 'dartDefineFromFiles'},
        );
      }
    }
  }

  List<String> toFlutterArguments() => <String>[
    for (final define in dartDefines) '--dart-define=$define',
    for (final path in dartDefineFromFiles) '--dart-define-from-file=$path',
    ...flutterArgs,
  ];

  Map<String, Object?> toJson({bool includeEnvironmentValues = false}) =>
      <String, Object?>{
        if (dartDefines.isNotEmpty) 'dartDefines': dartDefines,
        if (dartDefineFromFiles.isNotEmpty)
          'dartDefineFromFiles': dartDefineFromFiles,
        if (flutterArgs.isNotEmpty) 'flutterArgs': flutterArgs,
        if (environment.isNotEmpty)
          if (includeEnvironmentValues)
            'environment': environment
          else
            'environmentKeys': environment.keys.toList(growable: false),
      };

  static List<String> _normalizeDartDefines(Iterable<String> values) {
    return _normalizeNonEmptyList(values, fieldName: 'dartDefines')
        .map((value) {
          final separatorIndex = value.indexOf('=');
          if (separatorIndex <= 0) {
            throw ArgumentError.value(
              value,
              'dartDefines',
              'Entries must use KEY=VALUE syntax.',
            );
          }
          final key = value.substring(0, separatorIndex);
          if (key.startsWith(_reservedDartDefinePrefix)) {
            throw ArgumentError.value(
              key,
              'dartDefines',
              'FLUTTER_COCKPIT_* remote-control defines are reserved.',
            );
          }
          return value;
        })
        .toList(growable: false);
  }

  static List<String> _normalizeFlutterArgs(Iterable<String> values) {
    return _normalizeNonEmptyList(values, fieldName: 'flutterArgs')
        .map((value) {
          final optionName = _flutterArgOptionName(value);
          if (_reservedFlutterArgs.contains(optionName)) {
            throw ArgumentError.value(
              value,
              'flutterArgs',
              'This Flutter argument is managed by cockpit. Use the structured launch options instead.',
            );
          }
          return value;
        })
        .toList(growable: false);
  }

  static String _flutterArgOptionName(String value) {
    final equalsIndex = value.indexOf('=');
    final whitespaceIndex = value.indexOf(RegExp(r'\s'));
    final separatorIndex = switch ((equalsIndex, whitespaceIndex)) {
      (final equals, final whitespace) when equals < 0 => whitespace,
      (final equals, final whitespace) when whitespace < 0 => equals,
      (final equals, final whitespace) =>
        equals < whitespace ? equals : whitespace,
    };
    return separatorIndex < 0 ? value : value.substring(0, separatorIndex);
  }

  static List<String> _normalizeNonEmptyList(
    Iterable<String> values, {
    required String fieldName,
  }) {
    return values
        .map((value) {
          final trimmed = value.trim();
          if (trimmed.isEmpty) {
            throw ArgumentError.value(
              value,
              fieldName,
              'Entries cannot be empty.',
            );
          }
          return trimmed;
        })
        .toList(growable: false);
  }

  static Map<String, String> _normalizeEnvironment(Map<String, String> values) {
    final normalized = <String, String>{};
    for (final entry in values.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || key.contains('=')) {
        throw ArgumentError.value(
          entry.key,
          'environment',
          'Environment variable names cannot be empty or contain "=".',
        );
      }
      normalized[key] = entry.value;
    }
    return Map<String, String>.unmodifiable(normalized);
  }

  static List<String> _readStringList(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) {
      return const <String>[];
    }
    if (value is! List<Object?>) {
      throw const CockpitApplicationServiceException(
        code: 'invalidLaunchConfiguration',
        message: 'Launch configuration list fields must be arrays.',
      );
    }
    if (value.length > 1024) {
      throw const CockpitApplicationServiceException(
        code: 'invalidLaunchConfiguration',
        message: 'Launch configuration arrays are limited to 1024 entries.',
      );
    }
    return value
        .map((entry) {
          if (entry is! String) {
            throw const CockpitApplicationServiceException(
              code: 'invalidLaunchConfiguration',
              message: 'Launch configuration arrays must contain only strings.',
            );
          }
          return entry;
        })
        .toList(growable: false);
  }

  static Map<String, String> _readStringMap(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return const <String, String>{};
    }
    if (value is! Map<Object?, Object?>) {
      throw const CockpitApplicationServiceException(
        code: 'invalidLaunchConfiguration',
        message: 'Launch configuration environment must be an object.',
      );
    }
    if (value.length > 1024) {
      throw const CockpitApplicationServiceException(
        code: 'invalidLaunchConfiguration',
        message: 'Launch configuration environment is limited to 1024 entries.',
      );
    }
    final result = <String, String>{};
    for (final entry in value.entries) {
      final entryKey = entry.key;
      final entryValue = entry.value;
      if (entryKey is! String || entryValue is! String) {
        throw const CockpitApplicationServiceException(
          code: 'invalidLaunchConfiguration',
          message: 'Launch configuration environment values must be strings.',
        );
      }
      result[entryKey] = entryValue;
    }
    return result;
  }
}

List<String> cockpitBuildFlutterLaunchArguments({
  required CockpitFlutterLaunchConfiguration userConfiguration,
  required Iterable<String> internalArguments,
}) {
  return <String>[
    ...userConfiguration.toFlutterArguments(),
    ...internalArguments,
  ];
}

List<String> cockpitBuildRemoteControlDartDefineArguments({
  required String host,
  required int port,
  required String flutterVersion,
  String? launchId,
  bool disableHttpNetworkObserver = false,
  bool disableRuntimeObserver = false,
}) {
  return <String>[
    '--dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true',
    '--dart-define=FLUTTER_COCKPIT_REMOTE_HOST=$host',
    '--dart-define=FLUTTER_COCKPIT_REMOTE_PORT=$port',
    if (launchId case final value? when value.isNotEmpty)
      '--dart-define=FLUTTER_COCKPIT_REMOTE_LAUNCH_ID=$value',
    if (disableHttpNetworkObserver)
      '--dart-define=FLUTTER_COCKPIT_ENABLE_HTTP_NETWORK_OBSERVER=false',
    if (disableRuntimeObserver)
      '--dart-define=FLUTTER_COCKPIT_ENABLE_RUNTIME_OBSERVER=false',
    '--dart-define=FLUTTER_COCKPIT_FLUTTER_VERSION=$flutterVersion',
  ];
}

List<String> cockpitParseFlutterArgumentString(String value) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  String? quote;

  void flushToken() {
    if (buffer.isEmpty) {
      return;
    }
    tokens.add(buffer.toString());
    buffer.clear();
  }

  for (var index = 0; index < value.length; index += 1) {
    final char = value[index];
    if (quote != null) {
      if (char == quote) {
        quote = null;
        continue;
      }
      if (quote == '"' &&
          char == r'\' &&
          index + 1 < value.length &&
          (value[index + 1] == '"' || value[index + 1] == r'\')) {
        index += 1;
        buffer.write(value[index]);
        continue;
      }
      buffer.write(char);
      continue;
    }

    if (char.trim().isEmpty) {
      flushToken();
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    buffer.write(char);
  }

  if (quote != null) {
    throw ArgumentError.value(
      value,
      'flutterArgs',
      'Quoted Flutter arguments must be closed.',
    );
  }
  flushToken();
  if (tokens.isEmpty) {
    throw ArgumentError.value(value, 'flutterArgs', 'Entries cannot be empty.');
  }
  return tokens;
}
