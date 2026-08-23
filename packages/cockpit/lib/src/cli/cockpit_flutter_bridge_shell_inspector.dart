import 'package:path/path.dart' as p;

import '../application/cockpit_application_service_exception.dart';
import '../application/cockpit_package_config_support.dart';
import '../infrastructure/cockpit_file_system.dart';
import '../supervisor/cockpit_supervisor_api_client.dart';

final class CockpitFlutterBridgeShellInspector {
  const CockpitFlutterBridgeShellInspector({
    this.fileSystem = const LocalCockpitFileSystem(),
    this.maximumFiles = 8192,
    this.maximumDepth = 256,
    this.maximumSourceBytes = 2 * 1024 * 1024,
  }) : assert(maximumFiles > 0),
       assert(maximumDepth >= 0),
       assert(maximumSourceBytes > 0);

  final CockpitFileSystem fileSystem;
  final int maximumFiles;
  final int maximumDepth;
  final int maximumSourceBytes;

  void validate({
    required String checkoutRoot,
    required String projectPath,
    required String entrypoint,
  }) {
    final packages = _packages(projectPath);
    if (!packages.containsKey('flutter_cockpit')) {
      throw const CockpitSupervisorClientException(
        code: 'flutterCockpitDependencyMissing',
        message:
            'flutter_cockpit is not resolved for this Flutter project. Add it '
            'under dev_dependencies and run flutter pub get.',
      );
    }

    final pathContext = fileSystem.pathContext;
    final absoluteEntrypoint = pathContext.normalize(
      pathContext.joinAll(<String>[projectPath, ...entrypoint.split('/')]),
    );
    final pending = <({String path, int depth})>[
      (path: absoluteEntrypoint, depth: 0),
    ];
    final visited = <String>{};
    var importsBridge = false;
    var wrapsApplication = false;

    for (var cursor = 0; cursor < pending.length; cursor += 1) {
      final current = pending[cursor];
      if (current.depth > maximumDepth) {
        throw _scanLimit(entrypoint, 'depth', maximumDepth);
      }
      final sourcePath = pathContext.normalize(current.path);
      if (!visited.add(sourcePath)) continue;
      if (visited.length > maximumFiles) {
        throw _scanLimit(entrypoint, 'files', maximumFiles);
      }

      final sourceFile = fileSystem.file(sourcePath);
      if (!sourceFile.existsSync()) {
        if (sourcePath == absoluteEntrypoint) {
          throw CockpitSupervisorClientException(
            code: 'flutterBridgeEntrypointMissing',
            message: 'Flutter entrypoint $entrypoint does not exist.',
          );
        }
        continue;
      }
      if (sourceFile.lengthSync() > maximumSourceBytes) {
        throw _scanLimit(entrypoint, 'sourceBytes', maximumSourceBytes);
      }

      final scan = _scanDartSource(sourceFile.readAsStringSync());
      wrapsApplication = wrapsApplication || scan.wrapsApplication;
      for (final uriText in scan.directiveUris) {
        final uri = Uri.tryParse(uriText);
        if (uri == null) continue;
        if (uri.scheme == 'package') {
          final segments = uri.pathSegments;
          if (segments.isEmpty) continue;
          final packageName = segments.first;
          if (packageName == 'flutter_cockpit') {
            importsBridge = true;
            continue;
          }
          final package = packages[packageName];
          if (package == null ||
              !_inside(checkoutRoot, package.rootPath, pathContext)) {
            continue;
          }
          pending.add((
            path: pathContext.joinAll(<String>[
              package.packagePath,
              ...segments.skip(1),
            ]),
            depth: current.depth + 1,
          ));
          continue;
        }
        if (uri.scheme == 'dart') continue;
        final resolved = _resolveFileUri(uri, sourcePath, pathContext);
        if (resolved != null && _inside(checkoutRoot, resolved, pathContext)) {
          pending.add((path: resolved, depth: current.depth + 1));
        }
      }
    }

    if (importsBridge && wrapsApplication) return;
    final reason = importsBridge
        ? 'imports flutter_cockpit but does not wrap the app with FlutterCockpitApp'
        : 'does not load package:flutter_cockpit';
    throw CockpitSupervisorClientException(
      code: 'flutterBridgeShellMissing',
      message:
          'Flutter entrypoint $entrypoint $reason. Use a development-only '
          'cockpit/main.dart bridge shell before cockpit dev start.',
    );
  }

  Map<String, CockpitResolvedPackageConfigEntry> _packages(String projectPath) {
    try {
      return cockpitReadPackageConfig(
        fileSystem: fileSystem,
        workspaceRoot: projectPath,
      );
    } on CockpitApplicationServiceException catch (error) {
      if (error.code == 'packageConfigNotFound') {
        throw const CockpitSupervisorClientException(
          code: 'flutterPubGetRequired',
          message:
              'Flutter package resolution is missing. Run flutter pub get '
              'before cockpit dev start.',
        );
      }
      throw CockpitSupervisorClientException(
        code: 'flutterPackageConfigInvalid',
        message: error.message,
      );
    } on FormatException catch (error) {
      throw CockpitSupervisorClientException(
        code: 'flutterPackageConfigInvalid',
        message: 'Flutter package resolution is invalid: ${error.message}',
      );
    } catch (_) {
      throw const CockpitSupervisorClientException(
        code: 'flutterPackageConfigInvalid',
        message:
            'Flutter package resolution is unreadable or invalid. Run '
            'flutter pub get before cockpit dev start.',
      );
    }
  }

  CockpitSupervisorClientException _scanLimit(
    String entrypoint,
    String bound,
    int limit,
  ) {
    return CockpitSupervisorClientException(
      code: 'flutterBridgeShellScanLimit',
      message:
          'Flutter bridge preflight stopped while scanning $entrypoint '
          'because the $bound limit ($limit) was exceeded.',
    );
  }
}

String? _resolveFileUri(Uri uri, String sourcePath, p.Context pathContext) {
  if (uri.scheme.isEmpty) {
    return pathContext.normalize(
      pathContext.joinAll(<String>[
        pathContext.dirname(sourcePath),
        ...uri.pathSegments,
      ]),
    );
  }
  if (uri.scheme != 'file') return null;
  try {
    return pathContext.normalize(
      uri.toFilePath(windows: pathContext.style == p.Style.windows),
    );
  } on ArgumentError {
    return null;
  }
}

bool _inside(String root, String candidate, p.Context pathContext) {
  final normalizedRoot = pathContext.normalize(root);
  final normalizedCandidate = pathContext.normalize(candidate);
  return pathContext.equals(normalizedRoot, normalizedCandidate) ||
      pathContext.isWithin(normalizedRoot, normalizedCandidate);
}

({List<String> directiveUris, bool wrapsApplication}) _scanDartSource(
  String source,
) {
  final uris = <String>[];
  String? directive;
  var partOf = false;
  var wrapsApplication = false;
  var offset = 0;
  while (offset < source.length) {
    final skipped = _skipTrivia(source, offset);
    if (skipped != offset) {
      offset = skipped;
      continue;
    }
    final unit = source.codeUnitAt(offset);
    if (unit == 0x3b) {
      directive = null;
      partOf = false;
      offset += 1;
      continue;
    }
    final string = _readDartString(source, offset);
    if (string != null) {
      if (directive != null && !(directive == 'part' && partOf)) {
        uris.add(string.value);
      }
      offset = string.end;
      continue;
    }
    if (_isIdentifierStart(unit)) {
      final start = offset;
      offset += 1;
      while (offset < source.length &&
          _isIdentifierPart(source.codeUnitAt(offset))) {
        offset += 1;
      }
      final word = source.substring(start, offset);
      if (word == 'FlutterCockpitApp') wrapsApplication = true;
      if (directive == null &&
          (word == 'import' || word == 'export' || word == 'part')) {
        directive = word;
      } else if (directive == 'part' && word == 'of') {
        partOf = true;
      }
      continue;
    }
    offset += 1;
  }
  return (directiveUris: uris, wrapsApplication: wrapsApplication);
}

int _skipTrivia(String source, int offset) {
  var cursor = offset;
  while (cursor < source.length) {
    final unit = source.codeUnitAt(cursor);
    if (_isWhitespace(unit)) {
      cursor += 1;
      continue;
    }
    if (unit != 0x2f || cursor + 1 >= source.length) break;
    final next = source.codeUnitAt(cursor + 1);
    if (next == 0x2f) {
      cursor += 2;
      while (cursor < source.length) {
        final current = source.codeUnitAt(cursor);
        cursor += 1;
        if (current == 0x0a || current == 0x0d) break;
      }
      continue;
    }
    if (next != 0x2a) break;
    cursor += 2;
    var nesting = 1;
    while (cursor < source.length && nesting > 0) {
      if (cursor + 1 < source.length &&
          source.codeUnitAt(cursor) == 0x2f &&
          source.codeUnitAt(cursor + 1) == 0x2a) {
        nesting += 1;
        cursor += 2;
      } else if (cursor + 1 < source.length &&
          source.codeUnitAt(cursor) == 0x2a &&
          source.codeUnitAt(cursor + 1) == 0x2f) {
        nesting -= 1;
        cursor += 2;
      } else {
        cursor += 1;
      }
    }
  }
  return cursor;
}

({String value, int end})? _readDartString(String source, int offset) {
  var cursor = offset;
  var raw = false;
  if (cursor + 1 < source.length &&
      (source.codeUnitAt(cursor) == 0x72 ||
          source.codeUnitAt(cursor) == 0x52) &&
      _isQuote(source.codeUnitAt(cursor + 1))) {
    raw = true;
    cursor += 1;
  }
  if (!_isQuote(source.codeUnitAt(cursor))) return null;
  final quote = source.codeUnitAt(cursor);
  final triple =
      cursor + 2 < source.length &&
      source.codeUnitAt(cursor + 1) == quote &&
      source.codeUnitAt(cursor + 2) == quote;
  cursor += triple ? 3 : 1;
  final content = StringBuffer();
  while (cursor < source.length) {
    if (triple) {
      if (cursor + 2 < source.length &&
          source.codeUnitAt(cursor) == quote &&
          source.codeUnitAt(cursor + 1) == quote &&
          source.codeUnitAt(cursor + 2) == quote) {
        return (value: content.toString(), end: cursor + 3);
      }
    } else if (source.codeUnitAt(cursor) == quote) {
      return (value: content.toString(), end: cursor + 1);
    }
    final unit = source.codeUnitAt(cursor);
    if (!raw && unit == 0x5c && cursor + 1 < source.length) {
      content.writeCharCode(source.codeUnitAt(cursor + 1));
      cursor += 2;
      continue;
    }
    content.writeCharCode(unit);
    cursor += 1;
  }
  return (value: content.toString(), end: source.length);
}

bool _isWhitespace(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0a ||
    unit == 0x0d ||
    unit == 0x0c;

bool _isQuote(int unit) => unit == 0x22 || unit == 0x27;

bool _isIdentifierStart(int unit) =>
    (unit >= 0x41 && unit <= 0x5a) ||
    (unit >= 0x61 && unit <= 0x7a) ||
    unit == 0x5f ||
    unit == 0x24;

bool _isIdentifierPart(int unit) =>
    _isIdentifierStart(unit) || (unit >= 0x30 && unit <= 0x39);
