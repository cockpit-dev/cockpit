import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

typedef CockpitCheckoutProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

final class CockpitCheckoutIdentity {
  const CockpitCheckoutIdentity({
    required this.value,
    required this.canonicalRoot,
    this.gitCommonDirectory,
    this.gitDirectory,
  });

  final String value;
  final String canonicalRoot;
  final String? gitCommonDirectory;
  final String? gitDirectory;

  bool get isGit => gitDirectory != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'canonicalRoot': canonicalRoot,
    if (gitCommonDirectory != null) 'gitCommonDirectory': gitCommonDirectory,
    if (gitDirectory != null) 'gitDirectory': gitDirectory,
  };
}

final class CockpitCheckoutIdentityResolver {
  CockpitCheckoutIdentityResolver({CockpitCheckoutProcessRunner? processRunner})
    : _processRunner = processRunner ?? _runProcess;

  final CockpitCheckoutProcessRunner _processRunner;

  Future<CockpitCheckoutIdentity> resolve(String path) async {
    final directory = Directory(p.normalize(p.absolute(path)));
    if (!await directory.exists()) {
      throw FileSystemException('Checkout directory does not exist.', path);
    }
    final canonical = p.normalize(await directory.resolveSymbolicLinks());
    final result = await _processRunner(
      'git',
      const <String>[
        'rev-parse',
        '--path-format=absolute',
        '--show-toplevel',
        '--git-common-dir',
        '--git-dir',
      ],
      workingDirectory: canonical,
      environment: const <String, String>{'LANG': 'C', 'LC_ALL': 'C'},
    );
    if (result.exitCode != 0) {
      return CockpitCheckoutIdentity(
        value: _digest(<String>['filesystem', canonical]),
        canonicalRoot: canonical,
      );
    }
    final lines = const LineSplitter()
        .convert('${result.stdout}')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length != 3) {
      throw const FormatException(
        'Git checkout identity returned an unexpected response.',
      );
    }
    final root = await _canonicalDirectory(lines[0]);
    final common = await _canonicalDirectory(lines[1]);
    final gitDirectory = await _canonicalDirectory(lines[2]);
    if (!p.isWithin(root, canonical) && p.normalize(root) != canonical) {
      throw const FormatException(
        'Git checkout root does not contain the requested directory.',
      );
    }
    return CockpitCheckoutIdentity(
      value: _digest(<String>['git', root, common, gitDirectory]),
      canonicalRoot: root,
      gitCommonDirectory: common,
      gitDirectory: gitDirectory,
    );
  }

  Future<String> _canonicalDirectory(String path) async {
    final directory = Directory(p.normalize(p.absolute(path)));
    if (!await directory.exists()) {
      throw FileSystemException(
        'Git checkout identity directory does not exist.',
        path,
      );
    }
    return p.normalize(await directory.resolveSymbolicLinks());
  }
}

String _digest(List<String> parts) => sha256
    .convert(utf8.encode(parts.map((part) => '${part.length}:$part').join()))
    .toString();

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
);
