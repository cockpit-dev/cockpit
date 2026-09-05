import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_performance_archive_backend.dart';
import 'cockpit_performance_archive_backend_stub.dart'
    if (dart.library.io) 'cockpit_performance_archive_backend_io.dart'
    as platform;
import 'cockpit_performance_archive_options.dart';

export 'cockpit_performance_archive_options.dart';

/// An append-only performance archive for captures that should not stay in
/// the test process memory.
///
/// JSONL is intentionally the first format: each line is independently
/// parseable, files rotate at a configurable size, and an index is updated as
/// chunks complete. The writer accepts records synchronously and swaps to a
/// fresh chunk before awaiting a slow flush/rename, so instrumentation does
/// not accumulate an in-memory queue on the measured path. The default
/// [CockpitPerformanceArchiveMode.lossless] mode keeps every accepted record.
/// Use [CockpitPerformanceArchiveOptions.maxPendingBytes] to tune the
/// in-memory back-pressure window. In `low` mode records beyond it are
/// dropped and counted; in `lossless` mode they spill to a recoverable JSONL
/// sidecar instead of growing the Dart heap.
final class CockpitPerformanceArchive {
  CockpitPerformanceArchive._(this._backend, this.options);

  final CockpitPerformanceArchiveBackend _backend;
  final CockpitPerformanceArchiveOptions options;
  var _captureSequence = 0;

  /// Opens a new archive directory. If [directory] is omitted, a unique
  /// directory under `build/cockpit/performance/` is created.
  static Future<CockpitPerformanceArchive> open({
    String? directory,
    String name = 'performance',
    CockpitPerformanceArchiveOptions options =
        const CockpitPerformanceArchiveOptions(),
  }) async {
    final normalizedName = _slug(name);
    final root = directory == null || directory.trim().isEmpty
        ? 'build/cockpit/performance/$normalizedName-${DateTime.now().toUtc().microsecondsSinceEpoch}'
        : directory.trim();
    final backend = platform.createCockpitPerformanceArchiveBackend(
      directory: root,
      name: normalizedName,
      options: options,
    );
    await backend.open();
    return CockpitPerformanceArchive._(backend, options);
  }

  /// Exports already completed reports as a compact JSONL artifact set and
  /// returns the manifest path. Each frame/event/sample is a separate record;
  /// no giant JSON array is constructed during the write.
  static Future<String> exportReports(
    Iterable<CockpitPerformanceReport> reports, {
    String? directory,
    String name = 'performance',
    CockpitPerformanceArchiveOptions options =
        const CockpitPerformanceArchiveOptions(),
  }) async {
    final source = reports.toList(growable: false);
    if (source.isEmpty) throw StateError('No performance reports to export.');
    final archive = await open(
      directory: directory,
      name: name,
      options: options,
    );
    try {
      for (final report in source) {
        final id = archive.beginCapture(
          id: report.stepId,
          startedAt: report.startedAt,
        );
        for (final frame in report.frames) {
          archive.addFrame(frame);
        }
        for (final event in report.events) {
          archive.addEvent(event);
        }
        for (final sample
            in report.memory?.samples ??
                const <CockpitPerformanceMemorySample>[]) {
          archive.addMemory(sample);
        }
        final devtools = report.devTools;
        if (devtools != null) {
          for (final sample
              in devtools.heap?.samples ?? const <CockpitHeapSample>[]) {
            archive.addHeap(sample);
          }
          for (final event
              in devtools.isolate?.events ?? const <CockpitIsolateEvent>[]) {
            archive.addIsolate(event);
          }
          for (final event in devtools.logs) {
            archive.addLog(event);
          }
          for (final event in devtools.debug) {
            archive.addDebug(event);
          }
        }
        archive.endCapture(id, report);
      }
      return (await archive.close()).manifest;
    } catch (_) {
      try {
        await archive.close();
      } on Object {
        // Preserve the original export failure.
      }
      rethrow;
    }
  }

  /// Merges one or more JSONL archives (or individual JSONL chunks) into a
  /// new chunked archive and returns its manifest path.
  ///
  /// Sources are consumed incrementally in the order supplied. A source may
  /// be an archive manifest, a completed `.jsonl` chunk, or a recoverable
  /// `.jsonl.part` chunk. Records are validated before they enter the output;
  /// no complete source is loaded into memory. Capture ids are namespaced by
  /// source so combining parallel platform runs cannot create duplicate
  /// start/end identities. The event/frame/sample order inside each source is
  /// preserved; timestamps from different devices are not globally sorted.
  static Future<String> merge(
    Iterable<String> sources, {
    String? directory,
    String name = 'performance-merged',
    CockpitPerformanceArchiveOptions options =
        const CockpitPerformanceArchiveOptions(),
  }) => platform.mergeCockpitPerformanceArchives(
    sources,
    directory: directory,
    name: _slug(name),
    options: options,
  );

  CockpitPerformanceArchiveInfo get info => _backend.snapshot();

  /// Marks the start of one capture in the shared stream.
  String beginCapture({String? id, DateTime? startedAt}) {
    final captureId = id == null || id.trim().isEmpty
        ? (++_captureSequence).toRadixString(36)
        : id.trim();
    _backend.add('s', <String, Object?>{
      'id': captureId,
      'at': (startedAt ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
    });
    return captureId;
  }

  void addEvent(CockpitPerformanceEvent event) {
    _backend.add('e', event.toJson());
  }

  void addFrame(CockpitPerformanceFrame frame) {
    _backend.add('f', frame.toJson());
  }

  void addMemory(CockpitPerformanceMemorySample sample) {
    _backend.add('m', sample.toJson());
  }

  void addHeap(CockpitHeapSample sample) {
    _backend.add('h', sample.toJson());
  }

  void addIsolate(CockpitIsolateEvent event) {
    _backend.add('i', event.toJson());
  }

  void addLog(CockpitVmLogEvent event) {
    _backend.add('l', event.toJson());
  }

  void addDebug(CockpitVmDebugEvent event) {
    _backend.add('d', event.toJson());
  }

  /// Appends a compact capture summary without embedding the retained arrays.
  void endCapture(String id, CockpitPerformanceReport report) {
    _backend.add('x', <String, Object?>{
      'id': id,
      'step': ?report.stepId,
      'started': report.startedAt.toIso8601String(),
      'finished': report.finishedAt.toIso8601String(),
      'durationUs': report.durationUs,
      'platform': report.platform,
      'build': report.buildMode,
      'mode': report.mode.jsonValue,
      'summary': report.summary.toJson(),
      'retained': <String, Object?>{
        'frames': report.frames.length,
        'events': report.events.length,
      },
      if (report.droppedFrames > 0 || report.droppedEvents > 0)
        'dropped': <String, Object?>{
          if (report.droppedFrames > 0) 'frames': report.droppedFrames,
          if (report.droppedEvents > 0) 'events': report.droppedEvents,
        },
    });
  }

  Future<void> flush() => _backend.flush();

  Future<CockpitPerformanceArchiveInfo> close() => _backend.close();
}

String _slug(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'performance' : slug;
}
