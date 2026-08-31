/// Web integration tests do not expose a local file system.
Future<String> writeCockpitPerformanceHtml(
  String html, {
  required String? path,
  required String title,
}) {
  throw UnsupportedError(
    'HTML report files require a native Dart test target. '
    'Use CockpitPerformanceHtml.render(...) and save the returned string '
    'through the browser host when running on web.',
  );
}

/// Web integration tests do not expose a local file system.
Future<String> writeCockpitPerformanceJson(
  String json, {
  required String? path,
  required String title,
}) {
  throw UnsupportedError(
    'JSON report files require a native Dart test target. '
    'Use CockpitPerformanceHtml.fullJson(...) and save the returned string '
    'through the browser host when running on web.',
  );
}
