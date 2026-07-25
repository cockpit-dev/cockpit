import 'dart:io';

import 'package:test/test.dart';

void main() {
  final root = Directory.current.absolute.path;
  final activeRoots = <String>[
    'packages',
    'examples',
    'skills/cockpit',
    'docs/contracts',
    'README.md',
    'test',
  ];
  final allowedPathFragments = <String>{
    'third/',
    '.worktrees/',
    '.dart_tool/',
    '/build/',
    '.git/',
  };
  final allowedPaths = <String>{'test/active_cockpit_naming_test.dart'};
  final allowedExtensions = <String>{
    '.dart',
    '.md',
    '.yaml',
    '.yml',
    '.kt',
    '.swift',
    '.podspec',
    '.plist',
    '.json',
    '.txt',
  };
  final allowedTextPatterns = <Pattern>[
    RegExp(r'copilot', caseSensitive: false),
  ];
  final forbiddenPattern = RegExp(r'\bPilot\b|Pilot[A-Z]|\bpilotId\b');

  test('active source tree no longer exposes legacy Pilot naming', () {
    final offenders = <String>[];

    for (final entry in activeRoots) {
      final target =
          FileSystemEntity.typeSync(entry) == FileSystemEntityType.file
          ? <FileSystemEntity>[File(entry)]
          : Directory(entry).listSync(recursive: true, followLinks: false);

      for (final entity in target) {
        if (entity is! File) {
          continue;
        }
        final relativePath = _relativePath(entity.absolute.path, root);
        if (allowedPathFragments.any(relativePath.contains)) {
          continue;
        }
        if (allowedPaths.contains(relativePath)) {
          continue;
        }
        if (!allowedExtensions.contains(_extension(relativePath)) &&
            _basename(relativePath) != 'README.md') {
          continue;
        }
        final contents = entity.readAsStringSync();
        if (!forbiddenPattern.hasMatch(contents)) {
          continue;
        }
        if (allowedTextPatterns.any(
              (pattern) => pattern.allMatches(contents).isNotEmpty,
            ) &&
            !forbiddenPattern
                .allMatches(contents)
                .any(
                  (match) => !_isAllowedOccurrence(
                    contents,
                    match.start,
                    allowedTextPatterns,
                  ),
                )) {
          continue;
        }

        final line = _firstMatchingLine(contents, forbiddenPattern);
        offenders.add('$relativePath:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Active source still exposes legacy Pilot naming:\n${offenders.join('\n')}',
    );
  });
}

bool _isAllowedOccurrence(
  String contents,
  int start,
  List<Pattern> allowedPatterns,
) {
  for (final pattern in allowedPatterns) {
    for (final match in pattern.allMatches(contents)) {
      if (start >= match.start && start < match.end) {
        return true;
      }
    }
  }
  return false;
}

int _firstMatchingLine(String input, RegExp pattern) {
  final match = pattern.firstMatch(input);
  if (match == null) {
    return 1;
  }
  return '\n'.allMatches(input.substring(0, match.start)).length + 1;
}

String _relativePath(String absolutePath, String root) {
  final normalizedRoot = root.replaceAll('\\', '/');
  final normalizedPath = absolutePath.replaceAll('\\', '/');
  if (normalizedPath.startsWith('$normalizedRoot/')) {
    return normalizedPath.substring(normalizedRoot.length + 1);
  }
  return normalizedPath;
}

String _extension(String path) {
  final basename = _basename(path);
  final dotIndex = basename.lastIndexOf('.');
  if (dotIndex <= 0) {
    return '';
  }
  return basename.substring(dotIndex);
}

String _basename(String path) {
  final separatorIndex = path.lastIndexOf('/');
  return separatorIndex == -1 ? path : path.substring(separatorIndex + 1);
}
