import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_performance_archive_backend.dart';
import 'cockpit_performance_archive_options.dart';

final class _UnsupportedPerformanceArchive
    implements CockpitPerformanceArchiveBackend {
  _UnsupportedPerformanceArchive(this.directory);

  final String directory;

  Never _unsupported() {
    throw UnsupportedError(
      'Performance JSONL archives require a dart:io host. '
      'Use CockpitPerformanceHtml.fullJson(...) on web.',
    );
  }

  @override
  Future<void> open() async => _unsupported();

  @override
  void add(String kind, Map<String, Object?> value) => _unsupported();

  @override
  Future<void> flush() async => _unsupported();

  @override
  Future<CockpitPerformanceArchiveInfo> close() async => _unsupported();

  @override
  CockpitPerformanceArchiveInfo snapshot() => _unsupported();
}

CockpitPerformanceArchiveBackend createCockpitPerformanceArchiveBackend({
  required String directory,
  required String name,
  required CockpitPerformanceArchiveOptions options,
}) => _UnsupportedPerformanceArchive(directory);

Future<String> mergeCockpitPerformanceArchives(
  Iterable<String> sources, {
  required String? directory,
  required String name,
  required CockpitPerformanceArchiveOptions options,
}) => throw UnsupportedError(
  'Performance JSONL archives require a dart:io host. '
  'Use CockpitPerformanceHtml.fullJson(...) on web.',
);
