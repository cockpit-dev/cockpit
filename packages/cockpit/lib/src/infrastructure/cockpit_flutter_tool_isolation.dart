import 'dart:io';

import 'package:path/path.dart' as p;

const String cockpitResidentCompilerInfoPath =
    '.dart_tool/cockpit_flutter_compiler.json';

Map<String, String>? cockpitIsolateFlutterTool({
  required String executable,
  required String? workingDirectory,
  required Map<String, String>? environment,
  Map<String, String>? parentEnvironment,
  bool? windows,
}) {
  final directory = workingDirectory?.trim();
  if (directory == null ||
      directory.isEmpty ||
      !_usesResidentCompiler(
        executable,
        environment: environment,
        parentEnvironment: parentEnvironment,
        windows: windows,
      )) {
    return environment;
  }

  if (!Directory(directory).existsSync()) return environment;
  Directory(p.join(directory, '.dart_tool')).createSync(recursive: true);
  final useWindowsSemantics = windows ?? Platform.isWindows;
  final result = <String, String>{...?environment};
  final inherited = _environmentValue(
    result,
    'FLUTTER_TOOL_ARGS',
    windows: useWindowsSemantics,
  );
  final existing =
      inherited ??
      _environmentValue(
        parentEnvironment ?? Platform.environment,
        'FLUTTER_TOOL_ARGS',
        windows: useWindowsSemantics,
      );
  _removeEnvironmentKey(
    result,
    'FLUTTER_TOOL_ARGS',
    windows: useWindowsSemantics,
  );
  result['FLUTTER_TOOL_ARGS'] = <String>[
    ..._withoutResidentCompilerInfo(existing),
    '--resident-compiler-info-file=$cockpitResidentCompilerInfoPath',
  ].join(' ');
  return result;
}

bool _usesResidentCompiler(
  String executable, {
  required Map<String, String>? environment,
  required Map<String, String>? parentEnvironment,
  required bool? windows,
}) {
  final useWindowsSemantics = windows ?? Platform.isWindows;
  final pathContext = p.Context(
    style: useWindowsSemantics ? p.Style.windows : p.Style.posix,
  );
  final resolved = _resolveExecutable(
    executable,
    environment: environment,
    parentEnvironment: parentEnvironment,
    windows: useWindowsSemantics,
    pathContext: pathContext,
  );
  if (resolved == null) return false;
  final name = pathContext.basename(resolved).toLowerCase();
  return name == 'flutter-dev' || name == 'flutter-dev.bat';
}

String? _resolveExecutable(
  String executable, {
  required Map<String, String>? environment,
  required Map<String, String>? parentEnvironment,
  required bool windows,
  required p.Context pathContext,
}) {
  final value = executable.trim();
  if (value.isEmpty) return null;
  final candidates = <String>[];
  if (pathContext.isAbsolute(value) || pathContext.dirname(value) != '.') {
    candidates.add(value);
  } else {
    final pathValue =
        _environmentValue(environment, 'PATH', windows: windows) ??
        _environmentValue(
          parentEnvironment ?? Platform.environment,
          'PATH',
          windows: windows,
        );
    if (pathValue != null) {
      for (final directory in pathValue.split(windows ? ';' : ':')) {
        if (directory.isEmpty) continue;
        candidates.add(pathContext.join(directory, value));
      }
    }
  }

  for (final candidate in candidates) {
    try {
      if (FileSystemEntity.typeSync(candidate, followLinks: true) ==
          FileSystemEntityType.notFound) {
        continue;
      }
      return File(candidate).resolveSymbolicLinksSync();
    } on FileSystemException {
      continue;
    }
  }
  return null;
}

List<String> _withoutResidentCompilerInfo(String? value) {
  final tokens =
      value
          ?.trim()
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty)
          .toList(growable: false) ??
      const <String>[];
  final result = <String>[];
  for (var index = 0; index < tokens.length; index += 1) {
    final token = tokens[index];
    if (token == '--resident-compiler-info-file') {
      if (index + 1 < tokens.length) index += 1;
      continue;
    }
    if (token.startsWith('--resident-compiler-info-file=')) continue;
    result.add(token);
  }
  return result;
}

String? _environmentValue(
  Map<String, String>? environment,
  String name, {
  required bool windows,
}) {
  if (environment == null) return null;
  if (!windows) return environment[name];
  final lowerName = name.toLowerCase();
  for (final entry in environment.entries) {
    if (entry.key.toLowerCase() == lowerName) return entry.value;
  }
  return null;
}

void _removeEnvironmentKey(
  Map<String, String> environment,
  String name, {
  required bool windows,
}) {
  if (!windows) {
    environment.remove(name);
    return;
  }
  final lowerName = name.toLowerCase();
  environment.removeWhere((key, _) => key.toLowerCase() == lowerName);
}
