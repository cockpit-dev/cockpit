import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

/// Writes an HTML report atomically and returns its absolute path.
Future<String> writeCockpitPerformanceHtml(
  String html, {
  required String? path,
  required String title,
}) async {
  final target = _resolvePath(path, title, extension: 'html');
  return _writeCockpitPerformanceFile(html, target);
}

/// Writes a canonical JSON performance export atomically and returns its
/// absolute path.
Future<String> writeCockpitPerformanceJson(
  String json, {
  required String? path,
  required String title,
}) async {
  final target = _resolvePath(path, title, extension: 'json');
  return _writeCockpitPerformanceFile(json, target);
}

/// Writes raw VM Perfetto traces as standalone binary artifacts.
///
/// Compact report transport deliberately omits the payload. Exporting it as
/// files keeps large traces out of stdout and the integration-test envelope.
Future<List<String>> writeCockpitPerformancePerfetto(
  Iterable<CockpitPerformanceReport> source, {
  required String? directory,
  required String title,
}) async {
  final reports = source.toList(growable: false);
  if (reports.isEmpty) {
    throw StateError('No performance reports were captured.');
  }
  final root = directory == null || directory.trim().isEmpty
      ? Directory('build/cockpit/performance/${_slug(title)}-perfetto')
      : Directory(directory.trim());
  await root.create(recursive: true);
  final paths = <String>[];
  for (var index = 0; index < reports.length; index += 1) {
    final traces = reports[index].devTools?.perfetto;
    if (traces == null || traces.isEmpty) continue;
    final label = reports[index].stepId?.trim().isNotEmpty == true
        ? reports[index].stepId!
        : 'capture-${index + 1}';
    for (final entry in <(String, CockpitPerfettoTrace?)>[
      ('cpu', traces.cpu),
      ('timeline', traces.timeline),
    ]) {
      final data = entry.$2?.data;
      if (data == null) continue;
      final file = File(
        '${root.absolute.path}/${_slug(label)}-${index + 1}.${entry.$1}.pftrace',
      );
      await _writeBinary(file, base64Decode(data));
      paths.add(file.path);
    }
  }
  if (paths.isEmpty) {
    throw StateError('This performance report has no raw Perfetto payload.');
  }
  return paths;
}

Future<String> _writeCockpitPerformanceFile(
  String content,
  String target,
) async {
  final file = File(target);
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.part-${pid.toRadixString(36)}');
  try {
    await temporary.writeAsString(content, encoding: utf8, flush: true);
    await temporary.rename(file.path);
  } finally {
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }
  return file.path;
}

Future<void> _writeBinary(File file, List<int> bytes) async {
  final temporary = File('${file.path}.part-${pid.toRadixString(36)}');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

String _resolvePath(String? path, String title, {required String extension}) {
  if (path != null && path.trim().isNotEmpty) {
    return File(path.trim()).absolute.path;
  }
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final stem = slug.isEmpty ? 'cockpit-performance' : slug;
  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  return File(
    'build/cockpit/performance/$stem-$stamp.$extension',
  ).absolute.path;
}

String _slug(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'cockpit-performance' : slug;
}
