import 'dart:convert';
import 'dart:io';

/// Writes an HTML report atomically and returns its absolute path.
Future<String> writeCockpitPerformanceHtml(
  String html, {
  required String? path,
  required String title,
}) async {
  final target = _resolvePath(path, title);
  final file = File(target);
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.part-${pid.toRadixString(36)}');
  try {
    await temporary.writeAsString(html, encoding: utf8, flush: true);
    await temporary.rename(file.path);
  } finally {
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }
  return file.path;
}

String _resolvePath(String? path, String title) {
  if (path != null && path.trim().isNotEmpty) {
    return File(path.trim()).absolute.path;
  }
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final stem = slug.isEmpty ? 'cockpit-performance' : slug;
  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  return File('build/cockpit/performance/$stem-$stamp.html').absolute.path;
}
