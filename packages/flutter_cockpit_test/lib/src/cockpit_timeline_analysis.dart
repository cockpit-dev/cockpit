import 'package:cockpit_protocol/cockpit_protocol.dart';

/// Visits retained timeline events as measured operations.
///
/// VM timeline recorders commonly represent one operation as a `B`/`E` pair.
/// This helper emits that pair once, with the duration derived from the real
/// timestamps, while preserving explicit-duration and instant events. An
/// unmatched marker is never converted into a fabricated duration.
void visitCockpitTimelineMeasurements(
  Iterable<CockpitPerformanceEvent> events,
  void Function(
    CockpitPerformanceEvent event,
    int durationUs,
    CockpitPerformanceEvent? end,
  )
  visit, {
  void Function(CockpitPerformanceEvent event)? unmatchedBegin,
  void Function(CockpitPerformanceEvent event)? unmatchedEnd,
}) {
  final open = <String, List<CockpitPerformanceEvent>>{};
  for (final event in events) {
    final phase = event.phase;
    if (phase == 'B' && event.durationUs == 0) {
      (open[_timelineSpanKey(event)] ??= <CockpitPerformanceEvent>[]).add(
        event,
      );
      continue;
    }
    if (phase == 'E' && event.durationUs == 0) {
      final key = _timelineSpanKey(event);
      final stack = open[key];
      if (stack != null && stack.isNotEmpty) {
        final begin = stack.removeLast();
        if (stack.isEmpty) open.remove(key);
        final duration = event.timestampUs - begin.timestampUs;
        if (duration >= 0) {
          visit(begin, duration, event);
          continue;
        }
      }
      unmatchedEnd?.call(event);
      continue;
    }
    visit(event, event.durationUs, null);
  }

  if (unmatchedBegin == null) return;
  for (final stack in open.values) {
    for (final event in stack) {
      unmatchedBegin(event);
    }
  }
}

/// Returns the normalized generation for a GC timeline event, or null when
/// the event is unrelated to garbage collection.
String? cockpitGcEventKind(CockpitPerformanceEvent event) {
  final category = event.category.toLowerCase();
  final name = event.name.toLowerCase();
  final isNew =
      name.contains('collectnewgeneration') ||
      name.contains('scavenge') ||
      name.contains('new generation');
  final isOld =
      name.contains('collectoldgeneration') ||
      name.contains('mark-sweep') ||
      name.contains('marksweep') ||
      name.contains('old generation');
  final isGc =
      category == 'gc' ||
      category.contains('garbage') ||
      name.contains('garbage collection') ||
      isNew ||
      isOld;
  if (!isGc) return null;
  if (isNew) return 'new';
  if (isOld) return 'old';
  return 'gc';
}

String _timelineSpanKey(CockpitPerformanceEvent event) =>
    '${event.category}\u0000${event.name}\u0000'
    '${event.processId ?? ''}\u0000${event.threadId ?? ''}\u0000'
    '${event.eventId ?? ''}';
