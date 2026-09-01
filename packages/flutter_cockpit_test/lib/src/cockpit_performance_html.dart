import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_startup_report.dart';
import 'cockpit_timeline_analysis.dart';

/// Renders one or more [CockpitPerformanceReport] values as a self-contained
/// offline HTML report.
///
/// The report keeps the canonical JSON payload in the document for exact
/// inspection and uses a small, dependency-free viewer for the human-facing
/// timeline. No network request, font, image, or external JavaScript bundle is
/// required. Large frame and event collections are paged in the browser so a
/// bounded capture remains useful without creating a giant DOM.
final class CockpitPerformanceHtml {
  const CockpitPerformanceHtml._();

  /// Renders a single performance capture.
  static String render(
    CockpitPerformanceReport report, {
    String title = 'Cockpit performance',
    CockpitStartupReport? startup,
  }) => renderMany(
    <CockpitPerformanceReport>[report],
    title: title,
    startup: startup,
  );

  /// Encodes the retained VM timeline as a Chrome trace-compatible JSON file.
  ///
  /// The trace contains only events actually retained by the collector. Frame
  /// timing aggregates remain in [CockpitPerformanceReport.toJson] and the
  /// HTML charts; they are not represented as synthetic VM samples here.
  /// Compact events do not retain async/flow IDs, so those phases are lowered
  /// to self-contained instant or duration events for safe importing.
  static String timelineJson(CockpitPerformanceReport report) =>
      jsonEncode(_timelinePayload(report));

  /// Encodes the complete canonical report bundle as JSON.
  ///
  /// Unlike the compact integration-test result, this payload keeps every
  /// retained frame, VM event and argument, memory sample, startup milestone,
  /// and explicit retention/drop count for every capture. It is the
  /// machine-readable export that pairs with [renderMany].
  static String fullJson(
    Iterable<CockpitPerformanceReport> source, {
    String title = 'Cockpit performance',
    CockpitStartupReport? startup,
  }) {
    final reports = source.toList(growable: false);
    if (reports.isEmpty) {
      throw ArgumentError.value(source, 'source', 'Must not be empty.');
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Must not be blank.');
    }
    return jsonEncode(_reportPayload(reports, normalizedTitle, startup));
  }

  /// Renders several captures into one report with a capture switcher.
  ///
  /// Keeping related captures in one file makes before/after and multi-step
  /// comparisons practical while preserving each report exactly as emitted by
  /// the collector.
  static String renderMany(
    Iterable<CockpitPerformanceReport> source, {
    String title = 'Cockpit performance',
    CockpitStartupReport? startup,
  }) {
    final reports = source.toList(growable: false);
    if (reports.isEmpty) {
      throw ArgumentError.value(source, 'source', 'Must not be empty.');
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Must not be blank.');
    }

    final payload = _reportPayload(reports, normalizedTitle, startup);
    return _document(normalizedTitle, _scriptJson(payload));
  }
}

Map<String, Object?> _reportPayload(
  List<CockpitPerformanceReport> reports,
  String title,
  CockpitStartupReport? startup,
) => <String, Object?>{
  'title': title,
  if (startup != null) 'startup': startup.toJson(),
  'reports': <Object?>[
    for (var index = 0; index < reports.length; index += 1)
      <String, Object?>{
        'id': 'p$index',
        'label': reports[index].stepId?.trim().isNotEmpty == true
            ? reports[index].stepId
            : 'Capture ${index + 1}',
        // HTML is the explicit complete export surface. Normal integration
        // test output still uses report.toJson() without raw Perfetto bytes.
        'report': reports[index].toJson(includeRaw: true),
        'analysis': _performanceAnalysisPayload(reports[index]),
      },
  ],
};

Map<String, Object?> _performanceAnalysisPayload(
  CockpitPerformanceReport report,
) {
  final grouped = <String, _PerformanceHotspotAccumulator>{};
  visitCockpitTimelineMeasurements(report.events, (event, durationUs, _) {
    final key = '${event.category}\u0000${event.name}';
    final hotspot = grouped.putIfAbsent(
      key,
      () => _PerformanceHotspotAccumulator(
        category: event.category,
        name: event.name,
      ),
    );
    hotspot.count += 1;
    if (durationUs > 0) {
      hotspot.totalUs += durationUs;
      hotspot.durationsUs.add(durationUs);
      if (durationUs > hotspot.maxUs) {
        hotspot.maxUs = durationUs;
      }
    }
  });
  final hotspots = grouped.values.toList(growable: false)
    ..sort((left, right) {
      final total = right.totalUs.compareTo(left.totalUs);
      if (total != 0) return total;
      final longest = right.maxUs.compareTo(left.maxUs);
      if (longest != 0) return longest;
      return right.count.compareTo(left.count);
    });
  return <String, Object?>{
    'hotspots': <Object?>[
      for (final hotspot in hotspots.take(100)) hotspot.toJson(),
    ],
    'gc': _gcAnalysisPayload(report),
  };
}

Map<String, Object?> _gcAnalysisPayload(CockpitPerformanceReport report) {
  final durations = <int>[];
  var count = 0;
  var newCount = 0;
  var oldCount = 0;
  visitCockpitTimelineMeasurements(report.events, (event, durationUs, _) {
    final kind = cockpitGcEventKind(event);
    if (kind == null) return;
    count += 1;
    if (kind == 'new') newCount += 1;
    if (kind == 'old') oldCount += 1;
    if (durationUs > 0) durations.add(durationUs);
  });
  if (count == 0) return <String, Object?>{'count': 0};
  durations.sort();
  int percentile(double ratio) {
    if (durations.isEmpty) return 0;
    final index = ((durations.length * ratio).ceil() - 1).clamp(
      0,
      durations.length - 1,
    );
    return durations[index];
  }

  return <String, Object?>{
    'count': count,
    'timed': durations.length,
    if (newCount > 0) 'new': newCount,
    if (oldCount > 0) 'old': oldCount,
    if (durations.isNotEmpty) 'total': durations.fold<int>(0, (a, b) => a + b),
    if (durations.isNotEmpty) 'p50': percentile(.5),
    if (durations.isNotEmpty) 'p90': percentile(.9),
    if (durations.isNotEmpty) 'max': durations.last,
  };
}

final class _PerformanceHotspotAccumulator {
  _PerformanceHotspotAccumulator({required this.category, required this.name});

  final String category;
  final String name;
  var count = 0;
  var totalUs = 0;
  var maxUs = 0;
  final durationsUs = <int>[];

  int get p90Us {
    if (durationsUs.isEmpty) return 0;
    final sorted = List<int>.of(durationsUs)..sort();
    final index = ((sorted.length * 0.9).ceil() - 1).clamp(
      0,
      sorted.length - 1,
    );
    return sorted[index];
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'c': category,
    'n': name,
    'count': count,
    'timed': durationsUs.length,
    if (totalUs > 0) 'total': totalUs,
    if (p90Us > 0) 'p90': p90Us,
    if (maxUs > 0) 'max': maxUs,
  };
}

Map<String, Object?> _timelinePayload(CockpitPerformanceReport report) {
  final traceEvents = <Map<String, Object?>>[];
  visitCockpitTimelineMeasurements(
    report.events,
    (event, durationUs, end) {
      if (end == null) {
        traceEvents.add(_traceEvent(event, phase: _tracePhase(event)));
      } else {
        traceEvents.add(
          _traceEvent(
            event,
            phase: 'X',
            durationUs: durationUs,
            args: event.args.isNotEmpty ? event.args : end.args,
          ),
        );
      }
    },
    unmatchedBegin: (event) {
      traceEvents.add(_traceEvent(event, phase: 'i'));
    },
    unmatchedEnd: (event) {
      traceEvents.add(_traceEvent(event, phase: 'i'));
    },
  );
  traceEvents.sort((left, right) {
    final leftTime = (left['ts'] as num).toInt();
    final rightTime = (right['ts'] as num).toInt();
    return leftTime.compareTo(rightTime);
  });
  return <String, Object?>{'traceEvents': traceEvents};
}

Map<String, Object?> _traceEvent(
  CockpitPerformanceEvent event, {
  required String phase,
  int? durationUs,
  Map<String, Object?>? args,
}) {
  final effectiveDuration = durationUs ?? event.durationUs;
  return <String, Object?>{
    'name': event.name,
    'cat': event.category,
    'ph': phase,
    'ts': event.timestampUs,
    'pid': event.processId ?? 1,
    'tid': event.threadId ?? 1,
    if (event.eventId != null) 'id': event.eventId,
    if (event.scope != null) 's': event.scope,
    if (event.bindId != null) 'bind_id': event.bindId,
    if ((args ?? event.args).isNotEmpty) 'args': args ?? event.args,
    if (phase == 'X' && effectiveDuration > 0) 'dur': effectiveDuration,
  };
}

String _tracePhase(CockpitPerformanceEvent event) {
  final phase = event.phase;
  if ((phase == 'B' || phase == 'E') && event.durationUs > 0) return 'X';
  if (phase == 'X' && event.durationUs <= 0) return 'i';
  // Async and flow phases need an event id that the compact report does not
  // retain. Downgrade those phases to a self-contained instant/span instead
  // of emitting a trace that a DevTools importer cannot correlate.
  const supported = <String>{
    'B', 'E', 'X', 'I', 'i', 'C',
    // Chrome trace async/flow and metadata phases. The VM trace already
    // carries the required ids; preserving them is more useful than lowering
    // a valid event to an instant.
    'S', 'F', 'T', 'b', 'e', 'n', 'N', 'O', 'D', 'P',
  };
  if (phase != null && supported.contains(phase)) return phase;
  return event.durationUs > 0 ? 'X' : 'i';
}

String _document(String title, String payload) {
  final safeTitle = _html(title);
  return
  // language=html
  '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark light">
<title>$safeTitle</title>
<style>
:root {
  color-scheme: dark;
  --bg: #0b1014;
  --surface: #11191f;
  --surface-2: #172129;
  --surface-3: #1d2a33;
  --line: #2c3b45;
  --line-strong: #40535e;
  --text: #edf5f2;
  --text-soft: #c1cfcb;
  --muted: #8ea19c;
  --accent: #74e3bd;
  --accent-soft: #1d4a3e;
  --blue: #9eb4ff;
  --blue-soft: #29385f;
  --danger: #ff9da4;
  --danger-soft: #4d292e;
  --warning: #ffd27f;
  --warning-soft: #4c3b21;
  --shadow: 0 10px 30px rgba(0, 0, 0, .18);
  --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
}
:root[data-theme="light"] {
  color-scheme: light;
  --bg: #f4f7f6;
  --surface: #ffffff;
  --surface-2: #f7faf9;
  --surface-3: #edf3f0;
  --line: #d7e1dd;
  --line-strong: #b6c7c0;
  --text: #15221f;
  --text-soft: #354742;
  --muted: #657a73;
  --accent: #08785d;
  --accent-soft: #dcefe8;
  --blue: #365db8;
  --blue-soft: #e3e9fb;
  --danger: #b3303b;
  --danger-soft: #fde8e9;
  --warning: #8a5a00;
  --warning-soft: #fff0d1;
  --shadow: 0 8px 24px rgba(33, 58, 50, .08);
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font: 14px/1.5 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-variant-numeric: tabular-nums;
}
button, input, select { font: inherit; }
button, select, input { color: inherit; }
button { cursor: pointer; }
button:focus-visible, select:focus-visible, input:focus-visible,
summary:focus-visible { outline: 3px solid color-mix(in srgb, var(--accent) 55%, transparent); outline-offset: 2px; }
a { color: var(--accent); text-underline-offset: 3px; }
.shell { width: min(1500px, 100%); margin: 0 auto; padding: 0 28px; }
.topbar {
  position: sticky;
  top: 0;
  z-index: 5;
  background: color-mix(in srgb, var(--bg) 91%, transparent);
  border-bottom: 1px solid var(--line);
  backdrop-filter: blur(14px);
}
.topbar-inner { display: flex; align-items: center; justify-content: space-between; gap: 20px; min-height: 64px; }
.brand { display: flex; align-items: center; gap: 10px; min-width: 0; }
.brand-mark { display: grid; place-items: center; width: 30px; height: 30px; border-radius: 9px; overflow: hidden; background: var(--surface-3); color: var(--text); }
.brand-mark svg { display: block; width: 100%; height: 100%; }
.brand-copy { min-width: 0; }
.brand-copy strong, .brand-copy span { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.brand-copy strong { font-size: 13px; }
.brand-copy span { color: var(--muted); font-size: 11px; }
.top-actions { display: flex; align-items: center; gap: 8px; }
.icon-button, .quiet-button {
  min-height: 36px;
  border: 1px solid var(--line-strong);
  border-radius: 9px;
  background: var(--surface);
  color: var(--text-soft);
  padding: 7px 11px;
  transition: background 160ms ease, border-color 160ms ease, color 160ms ease;
}
.icon-button { width: 36px; padding: 0; }
.icon-button:hover, .quiet-button:hover { background: var(--surface-3); border-color: var(--accent); color: var(--text); }
.hero { padding: 34px 0 25px; }
.hero-grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(270px, .36fr); gap: 22px; align-items: stretch; }
.eyebrow { color: var(--accent); font-size: 11px; font-weight: 750; letter-spacing: .08em; text-transform: uppercase; }
h1 { margin: 7px 0 0; font-size: clamp(29px, 4vw, 48px); line-height: 1.05; letter-spacing: -.035em; text-wrap: balance; }
.hero-copy { max-width: 72ch; margin: 13px 0 0; color: var(--text-soft); }
.meta-row { display: flex; flex-wrap: wrap; gap: 7px 15px; margin-top: 17px; color: var(--muted); font-size: 12px; }
.meta-row code, code { font-family: var(--mono); font-size: 11px; }
.health { display: flex; flex-direction: column; justify-content: space-between; padding: 20px; border: 1px solid var(--line); border-radius: 14px; background: var(--surface); box-shadow: var(--shadow); }
.health-head { display: flex; align-items: start; justify-content: space-between; gap: 14px; }
.health h2 { margin: 0; font-size: 14px; }
.health-score { margin-top: 13px; font-size: 38px; font-weight: 800; letter-spacing: -.04em; }
.health-score.good { color: var(--accent); }
.health-score.warn { color: var(--warning); }
.health-score.bad { color: var(--danger); }
.health-note { margin: 4px 0 0; color: var(--muted); font-size: 12px; }
.meter { height: 8px; margin-top: 19px; overflow: hidden; border-radius: 5px; background: var(--surface-3); }
.meter > span { display: block; height: 100%; border-radius: inherit; background: var(--accent); transition: width 220ms ease; }
.health-foot { display: flex; justify-content: space-between; gap: 10px; margin-top: 18px; color: var(--muted); font-size: 11px; }
.metric-grid { display: grid; grid-template-columns: repeat(8, minmax(0, 1fr)); gap: 9px; margin-top: 23px; }
.metric { min-width: 0; padding: 14px 15px; border: 1px solid var(--line); border-radius: 11px; background: var(--surface); }
.metric span, .metric strong { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.metric span { color: var(--muted); font-size: 11px; }
.metric strong { margin-top: 3px; font-size: 18px; }
.metric strong.good { color: var(--accent); }
.metric strong.warn { color: var(--warning); }
.metric strong.bad { color: var(--danger); }
.startup-strip { display: grid; grid-template-columns: minmax(130px, .8fr) repeat(3, minmax(130px, 1fr)); gap: 9px; margin-top: 10px; padding: 11px 13px; border: 1px solid var(--line); border-radius: 11px; background: var(--surface-2); }
.startup-strip > div { min-width: 0; }
.startup-strip span, .startup-strip strong { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.startup-strip span { color: var(--muted); font-size: 10px; }
.startup-strip strong { margin-top: 2px; font-size: 14px; }
.startup-strip .startup-title { color: var(--text-soft); font-size: 11px; font-weight: 750; }
.workspace { padding-bottom: 54px; }
.toolbar { display: flex; align-items: end; justify-content: space-between; gap: 14px; margin: 4px 0 17px; }
.control { display: grid; gap: 5px; min-width: 230px; }
.control label { color: var(--muted); font-size: 11px; font-weight: 700; }
select, input[type="search"], input[type="number"] { min-height: 38px; border: 1px solid var(--line-strong); border-radius: 9px; background: var(--surface); padding: 7px 10px; }
input[type="search"] { width: 100%; }
.toolbar-actions { display: flex; align-items: center; gap: 8px; }
.panel { min-width: 0; margin-top: 15px; padding: 16px; border: 1px solid var(--line); border-radius: 14px; background: var(--surface); box-shadow: var(--shadow); }
.panel-head { display: flex; align-items: end; justify-content: space-between; gap: 18px; margin-bottom: 12px; }
.panel-head h2 { margin: 0; font-size: 17px; letter-spacing: -.01em; }
.panel-head p { margin: 4px 0 0; color: var(--muted); font-size: 12px; }
.panel-tools { display: flex; align-items: center; gap: 8px; }
.chart-grid, .insight-grid { display: grid; grid-template-columns: minmax(0, 1.65fr) minmax(280px, .9fr); gap: 15px; align-items: start; }
.chart-grid { margin-top: 15px; }
.chart-grid .panel { margin-top: 0; }
.insight-grid { margin-top: 15px; }
.insight-grid .panel { margin-top: 0; }
.chart-wrap { position: relative; display: flex; min-width: 0; min-height: 0; height: 310px; padding: 6px 8px; border: 1px solid var(--line); border-radius: 10px; background: var(--surface-2); overflow: hidden; }
.chart-wrap canvas { display: block; flex: 1 1 auto; min-width: 0; min-height: 0; width: 100%; height: 100%; }
.chart-wrap canvas:hover { cursor: crosshair; }
.chart-tooltip { position: fixed; z-index: 20; max-width: min(360px, calc(100vw - 24px)); padding: 9px 11px; border: 1px solid var(--line-strong); border-radius: 9px; background: color-mix(in srgb, var(--surface) 96%, transparent); color: var(--text-soft); box-shadow: var(--shadow); font-size: 11px; line-height: 1.45; pointer-events: none; opacity: 0; transform: translate(12px, 12px); transition: opacity 100ms ease; }
.chart-tooltip.visible { opacity: 1; }
.chart-tooltip strong { color: var(--text); font-size: 12px; }
.chart-tooltip .tooltip-row { display: flex; justify-content: space-between; gap: 16px; }
.chart-tooltip .tooltip-row span:last-child { color: var(--text); font-family: var(--mono); text-align: right; }
.chart-legend { display: flex; flex-wrap: wrap; gap: 8px 14px; margin-top: 11px; color: var(--muted); font-size: 11px; }
.legend-item { display: inline-flex; align-items: center; gap: 6px; }
.legend-swatch { width: 9px; height: 9px; border-radius: 3px; }
.legend-swatch.total { background: var(--accent); }
.legend-swatch.build { background: var(--blue); }
.legend-swatch.raster { background: var(--warning); }
.legend-swatch.budget { background: var(--danger); }
.event-summary { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 9px; }
.event-stat { padding: 13px; border-radius: 10px; background: var(--surface-2); }
.event-stat span, .event-stat strong { display: block; }
.event-stat span { color: var(--muted); font-size: 11px; }
.event-stat strong { margin-top: 3px; font-size: 18px; }
.resource-summary { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; margin-top: 11px; }
.resource-summary > div { min-width: 0; padding: 9px 10px; border-radius: 9px; background: var(--surface-2); }
.resource-summary span, .resource-summary strong { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.resource-summary span { color: var(--muted); font-size: 10px; }
.resource-summary strong { margin-top: 2px; font-size: 12px; }
.category-list { display: grid; gap: 7px; margin-top: 15px; }
.category-row { display: grid; grid-template-columns: minmax(90px, 1fr) minmax(90px, 1.3fr) auto; align-items: center; gap: 9px; font-size: 11px; }
.category-row > span:first-child { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.category-track { height: 7px; overflow: hidden; border-radius: 4px; background: var(--surface-3); }
.category-track span { display: block; height: 100%; border-radius: inherit; background: var(--blue); }
.category-row > span:last-child { color: var(--muted); text-align: right; }
.table-wrap { overflow: auto; border: 1px solid var(--line); border-radius: 10px; }
table { width: 100%; min-width: 760px; border-collapse: collapse; }
th, td { padding: 10px 12px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: middle; }
th { position: sticky; top: 0; z-index: 1; background: var(--surface-3); color: var(--text-soft); font-size: 10px; font-weight: 750; letter-spacing: .04em; text-transform: uppercase; }
tbody tr:last-child td { border-bottom: 0; }
tbody tr:hover td { background: color-mix(in srgb, var(--accent-soft) 35%, var(--surface)); }
td { color: var(--text-soft); font-size: 12px; }
.comparison-table { min-width: 900px; }
.comparison-table th:not(:first-child), .comparison-table td:not(:first-child) { text-align: right; }
.comparison-table th:first-child, .comparison-table td:first-child { text-align: left; }
.comparison-table td { white-space: nowrap; font-variant-numeric: tabular-nums; }
.comparison-table td:first-child { white-space: normal; }
.comparison-table .quiet-button { min-height: 34px; padding: 6px 12px; white-space: nowrap; }
.comparison-table tbody tr.current td { background: var(--accent-soft); }
td code { color: var(--text); }
.subtle { color: var(--muted); }
.status { display: inline-flex; align-items: center; gap: 5px; padding: 3px 7px; border-radius: 999px; font-size: 10px; font-weight: 750; }
.status::before { content: ""; width: 6px; height: 6px; border-radius: 50%; background: currentColor; }
.status-good { color: var(--accent); background: var(--accent-soft); }
.status-warn { color: var(--warning); background: var(--warning-soft); }
.status-bad { color: var(--danger); background: var(--danger-soft); }
.pager { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-top: 12px; color: var(--muted); font-size: 11px; }
.pager-actions { display: flex; gap: 7px; }
.pager button { min-height: 32px; padding: 5px 10px; }
.empty { padding: 26px; color: var(--muted); text-align: center; }
details { border-top: 1px solid var(--line); }
details:first-child { border-top: 0; }
summary { display: flex; align-items: center; justify-content: space-between; gap: 14px; padding: 12px 0; cursor: pointer; list-style: none; }
summary::-webkit-details-marker { display: none; }
summary::after { content: "+"; color: var(--muted); font-size: 17px; }
details[open] summary::after { content: "−"; }
.detail-body { padding: 0 0 14px; color: var(--text-soft); }
.detail-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 9px; }
.detail-cell { padding: 11px; border-radius: 9px; background: var(--surface-2); }
.detail-cell span, .detail-cell strong { display: block; }
.detail-cell span { color: var(--muted); font-size: 10px; }
.detail-cell strong { margin-top: 3px; font-size: 13px; overflow-wrap: anywhere; }
.json-view { max-height: 330px; overflow: auto; margin: 0; padding: 14px; border-radius: 10px; background: #091015; color: #d4e4de; font: 11px/1.55 var(--mono); white-space: pre-wrap; overflow-wrap: anywhere; }
:root[data-theme="light"] .json-view { background: #15221f; color: #e4f1ec; }
.resource-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
.resource-grid .panel { margin-top: 0; }
.analysis-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); margin-top: 15px; }
.analysis-grid .panel { margin-top: 0; }
.analysis-grid .wide { grid-column: 1 / -1; }
.startup-panel { margin-top: 15px; }
.coverage-panel { margin-top: 15px; }
.coverage-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 9px; }
.coverage-card { min-width: 0; padding: 12px 13px; border: 1px solid var(--line); border-radius: 10px; background: var(--surface-2); }
.coverage-card-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 8px; }
.coverage-card strong { min-width: 0; color: var(--text); font-size: 12px; line-height: 1.3; overflow-wrap: anywhere; }
.coverage-card p { margin: 7px 0 0; color: var(--muted); font-size: 11px; line-height: 1.4; }
.coverage-state { flex: none; padding: 3px 6px; border-radius: 999px; font-size: 9px; font-weight: 750; letter-spacing: .02em; text-transform: uppercase; }
.coverage-state.available { color: var(--accent); background: var(--accent-soft); }
.coverage-state.unavailable { color: var(--warning); background: var(--warning-soft); }
.coverage-state.not-collected { color: var(--muted); background: var(--surface-3); }
.devtools-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 15px; margin-top: 15px; }
.devtools-grid .panel { margin-top: 0; }
.vm-runtime-panel { margin-top: 15px; }
.vm-runtime-grid { display: grid; grid-template-columns: minmax(0, 1.55fr) minmax(250px, .85fr); gap: 15px; align-items: start; }
.vm-runtime-grid .chart-wrap { height: 210px; }
.vm-memory-panel { margin-top: 15px; }
.vm-memory-grid { display: grid; grid-template-columns: minmax(0, 1.55fr) minmax(250px, .85fr); gap: 15px; align-items: start; }
.vm-memory-grid .chart-wrap { height: 190px; }
.devtools-list { display: grid; gap: 7px; max-height: 260px; overflow: auto; }
.devtools-row { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 10px; align-items: center; padding: 8px 9px; border-radius: 8px; background: var(--surface-2); font-size: 11px; }
.devtools-row strong { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.devtools-row span { color: var(--muted); font-family: var(--mono); white-space: nowrap; }
.devtools-note { margin: 0 0 10px; color: var(--muted); font-size: 11px; }
.detail-button { min-height: 30px; padding: 5px 9px; font-size: 11px; }
.details-dialog { width: min(860px, calc(100vw - 28px)); max-height: min(760px, calc(100vh - 28px)); padding: 0; border: 1px solid var(--line-strong); border-radius: 14px; background: var(--surface); color: var(--text); box-shadow: var(--shadow); }
.details-dialog::backdrop { background: rgba(3, 8, 10, .62); backdrop-filter: blur(3px); }
.details-dialog-shell { display: grid; grid-template-rows: auto auto minmax(0, 1fr) auto; min-height: 0; max-height: min(760px, calc(100vh - 28px)); }
.details-dialog-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 15px 17px; border-bottom: 1px solid var(--line); }
.details-dialog-head h2 { margin: 0; font-size: 16px; }
.details-dialog-note { margin: 0; padding: 11px 17px 0; color: var(--muted); font-size: 11px; }
.details-dialog .json-view { max-height: none; margin: 11px 17px; min-height: 120px; }
.details-dialog-foot { display: flex; justify-content: flex-end; gap: 8px; padding: 0 17px 15px; }
.details-dialog-foot form { margin: 0; }
.jank-grid { margin-top: 15px; }
.jank-grid .panel { margin-top: 0; }
.stall-panel { margin-top: 15px; }
.stall-summary { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 12px; }
.stall-pill { padding: 8px 10px; border: 1px solid var(--line); border-radius: 9px; background: var(--surface-2); color: var(--text-soft); font-size: 11px; }
.stall-pill strong { color: var(--text); font-size: 14px; }
.stall-table { min-width: 900px; }
.stall-table td:first-child { white-space: nowrap; }
.stall-table td:nth-child(2), .stall-table td:nth-child(3) { white-space: nowrap; }
.stall-evidence { display: grid; gap: 3px; }
.stall-evidence code { color: var(--text); }
.stall-evidence span { color: var(--muted); font-size: 10px; }
.hotspot-table { min-width: 980px; }
.hotspot-table td:first-child, .hotspot-table td:nth-child(2) { white-space: nowrap; }
.hotspot-name { display: grid; gap: 2px; }
.hotspot-name strong { color: var(--text); }
.hotspot-source { max-width: 290px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.footer { margin-top: 23px; padding-top: 14px; border-top: 1px solid var(--line); color: var(--muted); font-size: 11px; }
.hidden { display: none !important; }
@media (max-width: 1120px) {
  .metric-grid { grid-template-columns: repeat(4, minmax(0, 1fr)); }
  .hero-grid, .chart-grid, .insight-grid, .resource-grid, .analysis-grid, .devtools-grid, .vm-runtime-grid, .vm-memory-grid { grid-template-columns: 1fr; }
  .health { min-height: 200px; }
}
@media (max-width: 700px) {
  .shell { padding-left: 16px; padding-right: 16px; }
  .topbar-inner { min-height: 58px; flex-wrap: wrap; padding-top: 8px; padding-bottom: 8px; }
  .brand-copy span { display: none; }
  .top-actions { margin-left: auto; flex-wrap: wrap; justify-content: flex-end; }
  .hero { padding-top: 24px; }
  h1 { font-size: 32px; }
  .metric-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .startup-strip { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .toolbar, .panel-head { display: block; }
  .toolbar-actions, .panel-tools { margin-top: 10px; flex-wrap: wrap; }
  .control { min-width: 0; }
  .panel { padding: 14px; border-radius: 11px; }
  .chart-wrap { height: 250px; }
  .event-summary, .detail-grid, .resource-summary, .coverage-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .event-summary > :last-child:nth-child(odd),
  .detail-grid > :last-child:nth-child(odd),
  .resource-summary > :last-child:nth-child(odd),
  .coverage-grid > :last-child:nth-child(odd) { grid-column: 1 / -1; }
  .chart-tooltip { max-width: calc(100vw - 20px); }
  .analysis-grid .wide { grid-column: auto; }
}
@media (max-width: 420px) {
  .event-summary, .detail-grid, .resource-summary, .coverage-grid { grid-template-columns: 1fr; }
  .event-summary > :last-child:nth-child(odd),
  .detail-grid > :last-child:nth-child(odd),
  .resource-summary > :last-child:nth-child(odd),
  .coverage-grid > :last-child:nth-child(odd) { grid-column: auto; }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { scroll-behavior: auto !important; transition: none !important; }
}
@media print {
  .topbar { position: static; background: var(--surface); backdrop-filter: none; }
  .top-actions, .toolbar-actions, .panel-tools, .pager { display: none !important; }
  .panel, .metric, .health { box-shadow: none; break-inside: avoid; }
  .chart-wrap { height: 260px; }
}
</style>
</head>
<body>
<header class="topbar"><div class="shell topbar-inner">
  <div class="brand"><span class="brand-mark" aria-hidden="true"><svg viewBox="0 0 1024 1024" focusable="false"><rect width="1024" height="1024" rx="192" fill="#111418"/><path d="M704 254A318 318 0 1 0 704 770" fill="none" stroke="#F4F7F9" stroke-linecap="round" stroke-width="104"/><rect x="512" y="480" width="276" height="64" rx="32" fill="#38D49B"/><circle cx="512" cy="512" r="76" fill="#38D49B"/><path d="M473 512L501 540L556 480" fill="none" stroke="#111418" stroke-linecap="round" stroke-linejoin="round" stroke-width="28"/><circle cx="788" cy="512" r="42" fill="#F6B94A"/></svg></span><div class="brand-copy"><strong>Cockpit performance</strong><span>Offline report · exact retained data</span></div></div>
  <div class="top-actions"><button class="icon-button" id="theme-button" type="button" title="Toggle theme" aria-label="Toggle theme">☼</button><button class="quiet-button" id="download-button" type="button">Download full JSON</button><button class="quiet-button" id="timeline-button" type="button">Download timeline</button><button class="quiet-button hidden" id="perfetto-button" type="button">Download Perfetto</button></div>
</div></header>
<div class="shell">
  <section class="hero">
    <div class="hero-grid">
      <div><div class="eyebrow">Flutter runtime evidence</div><h1 id="report-title">$safeTitle</h1><p class="hero-copy">Frame pacing, raster pressure, cache growth, garbage collection, and VM timeline activity in one file you can inspect without a server.</p><div class="meta-row" id="report-meta"></div></div>
      <aside class="health"><div class="health-head"><h2>Capture health</h2><span class="subtle" id="health-label">—</span></div><div><div class="health-score" id="health-score">—</div><p class="health-note" id="health-note">Select a capture to inspect its retained samples.</p><div class="meter" aria-hidden="true"><span id="health-meter" style="width:0%"></span></div></div><div class="health-foot"><span id="health-left">—</span><span id="health-right">—</span></div></aside>
    </div>
    <div class="metric-grid" id="metric-grid"></div>
    <div class="startup-strip" id="startup-strip"></div>
    <section class="panel startup-panel hidden" id="startup-panel"><div class="panel-head"><div><h2>Cold-start milestones</h2><p>Ordered harness measurements from app build to first frame and initial ready state.</p></div></div><div class="chart-wrap" style="height:110px"><canvas id="startup-chart" aria-label="Cold start milestone chart"></canvas></div></section>
  </section>
  <main class="workspace">
    <div class="toolbar"><div class="control"><label for="report-select">Capture</label><select id="report-select"></select></div><div class="toolbar-actions"><button class="quiet-button" id="copy-button" type="button">Copy report JSON</button><button class="quiet-button" id="raw-button" type="button">Show raw JSON</button></div></div>
    <section class="panel coverage-panel"><div class="panel-head"><div><h2>DevTools coverage</h2><p>What this deterministic capture can prove, and which DevTools profilers are intentionally not collected.</p></div><span class="subtle" id="coverage-summary">—</span></div><div class="coverage-grid" id="coverage-grid"></div></section>
    <section class="devtools-grid" id="devtools-grid">
      <div class="panel"><div class="panel-head"><div><h2>CPU sampling</h2><p>Real VM samples and top inclusive stacks from this capture.</p></div><div class="panel-tools"><span class="subtle" id="cpu-note">—</span><button class="quiet-button detail-button" type="button" data-details="cpu">Details</button></div></div><div class="chart-wrap" style="height:170px"><canvas id="cpu-chart" aria-label="CPU sampling chart"></canvas></div><div class="devtools-list" id="cpu-list"></div></div>
      <div class="panel"><div class="panel-head"><div><h2>Heap &amp; allocation</h2><p>Dart heap usage, allocation classes, and explicitly selected allocation call stacks.</p></div><div class="panel-tools"><span class="subtle" id="heap-note">—</span><button class="quiet-button detail-button" type="button" data-details="heap">Details</button></div></div><div class="chart-wrap" style="height:150px"><canvas id="heap-chart" aria-label="Dart heap chart"></canvas></div><div class="devtools-list" id="heap-list"></div></div>
      <div class="panel"><div class="panel-head"><div><h2>GPU / Shader signals</h2><p>Only actual GPU, raster, Skia, and shader timeline events are shown.</p></div><div class="panel-tools"><span class="subtle" id="gpu-note">—</span><button class="quiet-button detail-button" type="button" data-details="gpu">Details</button></div></div><div class="devtools-list" id="gpu-list"></div></div>
    </section>
    <section class="panel rebuild-panel"><div class="panel-head"><div><h2>Widget rebuilds</h2><p>DevTools-compatible <code>Flutter.RebuiltWidgets</code> counts by frame and source location. This is collected only when explicitly enabled.</p></div><div class="panel-tools"><span class="subtle" id="rebuild-note">—</span><button class="quiet-button detail-button" type="button" data-details="rebuilds">Details</button></div></div><div class="vm-runtime-grid"><div class="chart-wrap" style="height:190px"><canvas id="rebuild-chart" aria-label="Widget rebuilds by frame chart"></canvas></div><div class="devtools-list" id="rebuild-list"></div></div></section>
    <section class="panel vm-runtime-panel"><div class="panel-head"><div><h2>VM runtime health</h2><p>Isolate lifecycle, heap capacity, and timeline recorder state captured from VM Service.</p></div><div class="panel-tools"><span class="subtle" id="vm-note">—</span><button class="quiet-button detail-button" type="button" data-details="vm">Details</button></div></div><div class="vm-runtime-grid"><div class="chart-wrap" style="height:210px"><canvas id="heap-trend-chart" aria-label="VM heap trend chart"></canvas></div><div class="devtools-list" id="vm-list"></div></div></section>
    <section class="panel vm-memory-panel"><div class="panel-head"><div><h2>VM process memory</h2><p>Retained VM Service memory buckets before and after the capture. Expand Details for the complete bounded tree.</p></div><div class="panel-tools"><span class="subtle" id="vm-memory-note">—</span><button class="quiet-button detail-button" type="button" data-details="vmMemory">Details</button></div></div><div class="vm-memory-grid"><div class="chart-wrap" style="height:190px"><canvas id="vm-memory-chart" aria-label="VM process memory comparison chart"></canvas></div><div class="devtools-list" id="vm-memory-list"></div></div></section>
    <section class="chart-grid">
      <div class="panel"><div class="panel-head"><div><h2>Frame pacing</h2><p>Total frame span against the display budget. Jank is marked in place.</p></div><span class="subtle" id="frame-range">—</span></div><div class="chart-wrap"><canvas id="frame-chart" aria-label="Frame pacing chart"></canvas></div><div class="chart-legend"><span class="legend-item"><i class="legend-swatch total"></i>Total</span><span class="legend-item"><i class="legend-swatch build"></i>Build</span><span class="legend-item"><i class="legend-swatch raster"></i>Raster</span><span class="legend-item"><i class="legend-swatch budget"></i>Budget</span></div></div>
      <div class="panel"><div class="panel-head"><div><h2>VM timeline</h2><p>Retained event volume and category mix.</p></div></div><div class="event-summary" id="event-summary"></div><div class="chart-wrap" style="height:160px;margin-top:14px"><canvas id="event-chart" aria-label="VM timeline chart"></canvas></div><div class="category-list" id="category-list"></div></div>
    </section>
    <section class="panel stall-panel"><div class="panel-head"><div><h2>Jank &amp; stalls</h2><p>Only retained timeline events that overlap a slow frame are shown; no source or cause is guessed.</p></div><span class="subtle" id="stall-note">—</span></div><div class="stall-summary" id="stall-summary"></div><div class="table-wrap"><table class="stall-table"><thead><tr><th>Frame</th><th>Over budget</th><th>Frame total</th><th>Observed evidence</th><th>Source</th></tr></thead><tbody id="stall-body"></tbody></table></div></section>
    <section class="insight-grid">
      <div class="panel"><div class="panel-head"><div><h2>Phase latency</h2><p>Percentiles make long-tail build and raster pressure visible.</p></div></div><div class="chart-wrap" style="height:170px"><canvas id="phase-chart" aria-label="Frame phase latency chart"></canvas></div><div class="chart-legend"><span class="legend-item"><i class="legend-swatch total"></i>p50</span><span class="legend-item"><i class="legend-swatch build"></i>p90</span><span class="legend-item"><i class="legend-swatch raster"></i>p99</span><span class="legend-item"><i class="legend-swatch budget"></i>max</span></div></div>
      <div class="panel"><div class="panel-head"><div><h2>Jank distribution</h2><p>Frames grouped by how far they exceed the display budget.</p></div></div><div class="chart-wrap" style="height:132px"><canvas id="jank-chart" aria-label="Frame budget distribution chart"></canvas></div><div class="resource-summary" id="jank-summary"></div></div>
    </section>
    <section class="resource-grid insight-grid">
      <div class="panel"><div class="panel-head"><div><h2>Memory trend</h2><p>Resident process memory and the platform-reported process peak over capture time.</p></div></div><div class="chart-wrap" style="height:210px"><canvas id="resource-chart" aria-label="Process memory trend chart"></canvas></div><div class="resource-summary" id="resource-summary"></div></div>
      <div class="panel"><div class="panel-head"><div><h2>Cache &amp; GC pressure</h2><p>Flutter layer and picture cache peaks beside retained garbage collection activity.</p></div></div><div class="chart-wrap" style="height:182px"><canvas id="cache-chart" aria-label="Cache and garbage collection chart"></canvas></div><div class="resource-summary" id="cache-summary"></div></div>
    </section>
    <section class="analysis-grid insight-grid">
      <div class="panel"><div class="panel-head"><div><h2>Frame cadence</h2><p>Actual time between engine frame timestamps. Spikes expose refresh jitter even when frame work is short.</p></div></div><div class="chart-wrap" style="height:210px"><canvas id="cadence-chart" aria-label="Frame cadence chart"></canvas></div></div>
      <div class="panel"><div class="panel-head"><div><h2>Raster cache trend</h2><p>Layer and picture cache counts across retained frames, with byte values available on hover.</p></div></div><div class="chart-wrap" style="height:210px"><canvas id="cache-trend-chart" aria-label="Raster cache trend chart"></canvas></div></div>
      <div class="panel"><div class="panel-head"><div><h2>Frame pipeline</h2><p>Raw engine phase timestamps separate build wait, build work, raster wait, and raster work.</p></div></div><div class="chart-wrap" style="height:210px"><canvas id="pipeline-chart" aria-label="Frame pipeline chart"></canvas></div><div class="resource-summary" id="pipeline-summary"></div></div>
      <div class="panel"><div class="panel-head"><div><h2>GC pauses</h2><p>Real VM garbage-collection pauses, with generation and long-tail details on hover.</p></div><span class="subtle" id="gc-note">—</span></div><div class="chart-wrap" style="height:210px"><canvas id="gc-chart" aria-label="Garbage collection pause chart"></canvas></div><div class="resource-summary" id="gc-summary"></div></div>
      <div class="panel wide"><div class="panel-head"><div><h2>VM category cost</h2><p>Duration and event count grouped by the actual VM timeline category.</p></div></div><div class="chart-wrap" style="height:80px"><canvas id="category-cost-chart" aria-label="VM category duration chart"></canvas></div></div>
    </section>
    <section class="panel"><div class="panel-head"><div><h2>Operation hotspots</h2><p>Concrete VM event names ranked by retained duration. Source is shown only when the event arguments provide it.</p></div><span class="subtle" id="hotspot-note">—</span></div><div class="chart-wrap" style="height:92px"><canvas id="hotspot-chart" aria-label="VM operation hotspots chart"></canvas></div><div class="table-wrap"><table class="hotspot-table"><thead><tr><th>Operation</th><th>Category</th><th>Events</th><th>Timed</th><th>Total</th><th>p90</th><th>Longest</th><th>Source evidence</th></tr></thead><tbody id="hotspot-body"></tbody></table></div></section>
    <section class="panel"><div class="panel-head"><div><h2>Timeline flame view</h2><p>Nested VM spans by real event intervals. This is a timeline view, not an invented CPU call stack.</p></div><span class="subtle" id="flame-range">—</span></div><div class="chart-wrap" style="height:88px"><canvas id="flame-chart" aria-label="Nested VM timeline flame view"></canvas></div></section>
    <section class="panel"><div class="panel-head"><div><h2>Frame explorer</h2><p>Inspect retained engine timings without rendering every sample at once.</p></div><div class="panel-tools"><select id="frame-sort" aria-label="Sort frames"><option value="index">Capture order</option><option value="total">Slowest total</option><option value="build">Slowest build</option><option value="raster">Slowest raster</option></select></div></div><div class="table-wrap"><table><thead><tr><th>#</th><th>Frame</th><th>Total</th><th>Build</th><th>Raster</th><th>Vsync</th><th>Budget</th><th>Cache</th></tr></thead><tbody id="frame-body"></tbody></table></div><div class="pager"><span id="frame-page-label">—</span><div class="pager-actions"><button class="quiet-button" id="frame-prev" type="button">Previous</button><button class="quiet-button" id="frame-next" type="button">Next</button></div></div></section>
    <section class="panel"><div class="panel-head"><div><h2>Capture comparison</h2><p>Compare every capture in this file without switching context.</p></div></div><div class="table-wrap"><table class="comparison-table"><thead><tr><th>Capture</th><th>Frames</th><th>Jank</th><th>FPS</th><th>Total p90</th><th>Total max</th><th>Duration</th><th>RSS peak</th><th>RSS Δ</th></tr></thead><tbody id="comparison-body"></tbody></table></div></section>
    <section class="panel"><div class="panel-head"><div><h2>Timeline events</h2><p>Newest retained VM events first. Search by name, category, or argument key.</p></div><div class="panel-tools"><div class="control"><label for="event-search">Search</label><input id="event-search" type="search" placeholder="Name or category"></div><select id="event-category" aria-label="Filter event category"><option value="">All categories</option></select></div></div><div class="table-wrap"><table><thead><tr><th>When</th><th>Event</th><th>Category</th><th>Duration</th><th>Phase</th><th>Arguments</th></tr></thead><tbody id="event-body"></tbody></table></div><div class="pager"><span id="event-page-label">—</span><div class="pager-actions"><button class="quiet-button" id="event-prev" type="button">Previous</button><button class="quiet-button" id="event-next" type="button">Next</button></div></div></section>
    <section class="panel"><div class="panel-head"><div><h2>Code evidence</h2><p>Source locations are shown only when the VM timeline provides them; no location is guessed from a frame.</p></div></div><div class="table-wrap"><table><thead><tr><th>Source</th><th>Events</th><th>Total time</th><th>Longest</th><th>Categories</th></tr></thead><tbody id="code-body"></tbody></table></div></section>
    <section class="panel"><div class="panel-head"><div><h2>Capture details</h2><p>Retention boundaries and interpretation context are kept beside the measurements.</p></div></div><div class="detail-grid" id="detail-grid"></div><div id="raw-wrap" class="hidden" style="margin-top:14px"><pre class="json-view" id="raw-json"></pre></div></section>
    <div class="footer">Generated by <strong>Cockpit</strong>. JSON remains the canonical machine-readable payload. This viewer is self-contained and works offline.</div>
  </main>
</div>
<div class="chart-tooltip" id="chart-tooltip" role="status" aria-live="polite"></div>
<dialog class="details-dialog" id="details-dialog" aria-labelledby="details-title">
  <div class="details-dialog-shell">
    <div class="details-dialog-head"><h2 id="details-title">Capture details</h2><form method="dialog"><button class="icon-button" type="submit" aria-label="Close details">×</button></form></div>
    <p class="details-dialog-note" id="details-note">—</p>
    <pre class="json-view" id="details-json"></pre>
    <div class="details-dialog-foot"><button class="quiet-button" id="details-copy" type="button">Copy details</button><form method="dialog"><button class="quiet-button" type="submit">Close</button></form></div>
  </div>
</dialog>
<script id="cockpit-performance-data" type="application/json">$payload</script>
<script>
(function () {
  'use strict';
  var data = JSON.parse(document.getElementById('cockpit-performance-data').textContent || '{}');
  var reports = Array.isArray(data.reports) ? data.reports : [];
  var startup = data.startup || null;
  var state = { report: 0, framePage: 0, eventPage: 0, frameSort: 'index', eventQuery: '', eventCategory: '' };
  var framePageSize = 45;
  var eventPageSize = 45;
  var el = function (id) { return document.getElementById(id); };
  var root = document.documentElement;
  var nf = new Intl.NumberFormat();
  var css = function (name) { return getComputedStyle(root).getPropertyValue(name).trim(); };
  var clamp = function (n, min, max) { return Math.max(min, Math.min(max, n)); };
  var esc = function (value) { return String(value == null ? '' : value).replace(/[&<>"']/g, function (c) { return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]; }); };
  var us = function (value) {
    var n = Number(value || 0);
    if (Math.abs(n) < 1000) return n + ' µs';
    if (Math.abs(n) < 1000000) return (n / 1000).toFixed(n < 10000 ? 2 : 1) + ' ms';
    return (n / 1000000).toFixed(2) + ' s';
  };
  var metricUs = function (value) { return value == null ? 'Unavailable' : us(value); };
  var metricCount = function (value) { return value == null ? 'Unavailable' : nf.format(number(value)); };
  var bytes = function (value) {
    var n = Number(value || 0);
    if (n < 1024) return nf.format(n) + ' B';
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + ' KiB';
    if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + ' MiB';
    return (n / (1024 * 1024 * 1024)).toFixed(1) + ' GiB';
  };
  var duration = function (value) {
    var n = Number(value || 0);
    return n < 1000 ? n + ' ms' : (n / 1000).toFixed(n < 10000 ? 2 : 1) + ' s';
  };
  var dateText = function (value) {
    var date = new Date(number(value));
    return isNaN(date.getTime()) ? String(value) : date.toISOString();
  };
  var report = function () { return reports[state.report] && reports[state.report].report || {}; };
  var summary = function () { return report().summary || {}; };
  var frames = function () { return Array.isArray(report().frames) ? report().frames : []; };
  var events = function () { return Array.isArray(report().events) ? report().events : []; };
  var memory = function () { return report().memory || null; };
  var devtools = function () { return report().devtools || null; };
  var gcStats = function () {
    var exact = devtools();
    if (exact && exact.gc) {
      return { count: number(exact.gc.n), timed: number(exact.gc.timed), total: number(exact.gc.total), p50: exact.gc.p50 == null ? null : number(exact.gc.p50), p90: exact.gc.p90 == null ? null : number(exact.gc.p90), max: exact.gc.max == null ? null : number(exact.gc.max), new: number(exact.gc.new), old: number(exact.gc.old), newPause: number(exact.gc.newUs), oldPause: number(exact.gc.oldUs) };
    }
    var rows = events().filter(function (event) {
      var text = String(event.c || '') + ' ' + String(event.n || '');
      text = text.toLowerCase();
      return text.indexOf('gc') >= 0 || text.indexOf('garbage') >= 0 || text.indexOf('scavenge') >= 0 || text.indexOf('mark-sweep') >= 0;
    });
    var durations = rows.map(function (event) { return number(event.d); }).filter(function (value) { return value > 0; }).sort(function (a, b) { return a - b; });
    var percentile = function (ratio) { return durations.length ? durations[Math.max(0, Math.min(durations.length - 1, Math.ceil(durations.length * ratio) - 1))] : null; };
    return { count: rows.length, timed: durations.length, total: durations.reduce(function (sum, value) { return sum + value; }, 0), p50: percentile(.5), p90: percentile(.9), max: durations.length ? durations[durations.length - 1] : null };
  };
  var phase = function (name) { return summary()[name] || {}; };
  var number = function (value, fallback) { return Number.isFinite(Number(value)) ? Number(value) : (fallback || 0); };
  var tracePhase = function (event) {
    var phase = String(event.p || '');
    if ((phase === 'B' || phase === 'E') && number(event.d) > 0) return 'X';
    if (phase === 'X' && number(event.d) <= 0) return 'i';
    if (['B', 'E', 'X', 'I', 'i', 'C', 'S', 'F', 'T', 'b', 'e', 'n', 'N', 'O', 'D', 'P'].indexOf(phase) >= 0) return phase;
    return number(event.d) > 0 ? 'X' : 'i';
  };
  var traceEvent = function (event, phase, durationUs, args) {
    var duration = durationUs == null ? number(event.d) : durationUs;
    var item = { name: String(event.n || 'Unnamed event'), cat: String(event.c || 'uncategorized'), ph: phase, ts: number(event.t), pid: event.pid == null ? 1 : number(event.pid), tid: event.tid == null ? 1 : number(event.tid) };
    if (event.id != null) item.id = String(event.id);
    if (event.scope != null) item.s = String(event.scope);
    if (event.bid != null) item.bind_id = String(event.bid);
    var payload = args || (event.a && typeof event.a === 'object' ? event.a : {});
    if (payload && Object.keys(payload).length) item.args = payload;
    if (phase === 'X' && duration > 0) item.dur = duration;
    return item;
  };
  var fileStem = function (value) { var stem = String(value == null ? '' : value).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+\$/g, ''); return stem || 'cockpit-performance'; };
  var downloadBase64 = function (value, name) {
    var raw = atob(String(value || '')); var bytes = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i += 1) bytes[i] = raw.charCodeAt(i);
    var blob = new Blob([bytes], { type: 'application/octet-stream' }); var link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = name; link.click(); setTimeout(function () { URL.revokeObjectURL(link.href); }, 1000);
  };
  var spanKey = function (event) { return String(event.c || 'uncategorized') + '\\u0000' + String(event.n || 'Unnamed event') + '\\u0000' + String(event.pid == null ? '' : event.pid) + '\\u0000' + String(event.tid == null ? '' : event.tid) + '\\u0000' + String(event.id == null ? '' : event.id); };
  var timelinePayload = function () {
    var traceEvents = []; var openSpans = {};
    events().forEach(function (event) {
      var phase = String(event.p || '');
      if (phase === 'B' && number(event.d) <= 0) { (openSpans[spanKey(event)] = openSpans[spanKey(event)] || []).push(event); return; }
      if (phase === 'E' && number(event.d) <= 0) {
        var stack = openSpans[spanKey(event)];
        if (stack && stack.length) {
          var begin = stack.pop();
          if (!stack.length) delete openSpans[spanKey(event)];
          var duration = number(event.t) - number(begin.t);
          if (duration >= 0) { traceEvents.push(traceEvent(begin, 'X', duration, begin.a && typeof begin.a === 'object' ? begin.a : event.a)); return; }
        }
        traceEvents.push(traceEvent(event, 'i')); return;
      }
      traceEvents.push(traceEvent(event, tracePhase(event)));
    });
    Object.keys(openSpans).forEach(function (key) { openSpans[key].forEach(function (event) { traceEvents.push(traceEvent(event, 'i')); }); });
    traceEvents.sort(function (a, b) { return number(a.ts) - number(b.ts); });
    return { traceEvents: traceEvents };
  };
  var originOf = function (list) { return list.length ? list.reduce(function (min, item) { return Math.min(min, number(item.t)); }, Infinity) : 0; };
  var frameOrigin = function () { return originOf(frames()); };
  var eventOrigin = function () { return originOf(events()); };
  var relativeUs = function (value, origin) { return us(number(value) - number(origin)); };
  var tooltip = el('chart-tooltip');
  var chartHits = {};
  var tooltipRow = function (label, value) { return '<div class="tooltip-row"><span>' + esc(label) + '</span><span>' + esc(value) + '</span></div>'; };
  var hideTooltip = function () { tooltip.classList.remove('visible'); };
  var detailsDialog = el('details-dialog');
  var detailsPayload = '';
  var preview = function (list, limit) {
    if (!Array.isArray(list) || list.length <= limit) return { items: list || [], total: Array.isArray(list) ? list.length : 0 };
    var head = Math.ceil(limit * .7); var tail = Math.max(1, limit - head);
    return { items: list.slice(0, head).concat(list.slice(list.length - tail)), total: list.length, omitted: list.length - head - tail };
  };
  var detailValue = function (kind) {
    var d = devtools();
    if (!d) return null;
    if (kind === 'cpu' && d.cpu) {
      var cpu = d.cpu;
      var functions = Array.isArray(cpu.f) ? cpu.f : [];
      var stackCounts = {};
      (Array.isArray(cpu.s) ? cpu.s : []).forEach(function (sample) {
        var stack = Array.isArray(sample.s) ? sample.s : [];
        var names = stack.map(function (index) { return functions[index] && functions[index].n ? String(functions[index].n) : null; }).filter(function (name) { return name; });
        if (!names.length) return;
        var path = names.join(' › ');
        stackCounts[path] = (stackCounts[path] || 0) + 1;
      });
      var topStacks = Object.keys(stackCounts).map(function (path) { return { path: path, samples: stackCounts[path] }; }).sort(function (a, b) { return b.samples - a.samples; });
      return { summary: { period: cpu.period, depth: cpu.depth, samples: cpu.n, span: cpu.span, dropped: cpu.dropped || 0 }, functions: preview(functions, 200), topStacks: preview(topStacks, 100), samples: preview(cpu.s, 300) };
    }
    if (kind === 'heap' && d.heap) {
      var heap = d.heap;
      return { summary: { before: heap.before, after: heap.after, groupBefore: heap.gb || null, groupAfter: heap.ga || null, interval: heap.interval || 0, samples: Array.isArray(heap.samples) ? heap.samples.length : 0, dropped: heap.drop || 0, classes: Array.isArray(heap.classes) ? heap.classes.length : 0, allocationTraces: Array.isArray(d.alloc) ? d.alloc.length : 0 }, classes: preview(heap.classes, 200), allocationTraces: preview(d.alloc, 20), samples: preview(heap.samples, 300) };
    }
    if (kind === 'gpu' && d.gpu) return d.gpu;
    if (kind === 'rebuilds' && d.rebuild) return d.rebuild;
    if (kind === 'vm') return { vm: d.vm || null, isolate: d.isolate || null, timeline: d.timeline || null, display: d.display || null, rebuild: d.rebuild || null, gc: (reports[state.report].analysis || {}).gc || null };
    if (kind === 'vmMemory' && d.vmem) return d.vmem;
    return d;
  };
  var openDetails = function (kind) {
    var value = detailValue(kind);
    var labels = { cpu: 'CPU sampling details', heap: 'Heap and allocation details', gpu: 'GPU and shader details', rebuilds: 'Widget rebuild details', vm: 'VM runtime details', vmMemory: 'VM process memory details' };
    el('details-title').textContent = labels[kind] || 'Capture details';
    if (value == null) {
      detailsPayload = '';
      el('details-note').textContent = 'This capture did not retain this data.';
      el('details-json').textContent = 'Unavailable';
    } else {
      detailsPayload = JSON.stringify(value);
      var raw = JSON.stringify(value, null, 2);
      el('details-note').textContent = 'Explicit detail view. Long arrays are bounded here for responsiveness; the full retained capture remains available through Download full JSON.';
      el('details-json').textContent = raw;
    }
    if (detailsDialog && typeof detailsDialog.showModal === 'function') {
      if (!detailsDialog.open) detailsDialog.showModal();
    } else if (detailsDialog) {
      detailsDialog.setAttribute('open', '');
    }
  };
  var nearestHit = function (hits, x, y) {
    var best = null; var bestDistance = Infinity;
    hits.forEach(function (hit) {
      var left = hit.x; var right = hit.x + (hit.w || 0); var top = hit.y; var bottom = hit.y + (hit.h || 0);
      var dx = x < left ? left - x : x > right ? x - right : 0;
      var dy = y < top ? top - y : y > bottom ? y - bottom : 0;
      var distance = dx * dx + dy * dy;
      if (distance < bestDistance) { bestDistance = distance; best = hit; }
    });
    return bestDistance <= 256 ? best : null;
  };
  var showTooltip = function (event, hit) {
    if (!hit) { hideTooltip(); return; }
    tooltip.innerHTML = hit.html;
    tooltip.style.left = event.clientX + 'px';
    tooltip.style.top = event.clientY + 'px';
    tooltip.classList.add('visible');
    var rect = tooltip.getBoundingClientRect();
    var x = Math.min(event.clientX, window.innerWidth - rect.width - 16);
    var y = Math.min(event.clientY, window.innerHeight - rect.height - 16);
    tooltip.style.left = Math.max(8, x) + 'px';
    tooltip.style.top = Math.max(8, y) + 'px';
  };
  var bindChart = function (id) {
    var canvas = el(id);
    canvas.addEventListener('pointermove', function (event) {
      var rect = canvas.getBoundingClientRect();
      showTooltip(event, nearestHit(chartHits[id] || [], event.clientX - rect.left, event.clientY - rect.top));
    });
    canvas.addEventListener('pointerleave', hideTooltip);
  };
  var quality = function () {
    var s = summary();
    var count = number(s.frames);
    var jank = number(s.jank);
    if (!count) return { score: null, label: 'No frames', kind: 'warn' };
    var score = clamp(Math.round(100 * (1 - jank / count)), 0, 100);
    return { score: score, label: score >= 98 ? 'Healthy pacing' : score >= 90 ? 'Review pacing' : 'Jank detected', kind: score >= 98 ? 'good' : score >= 90 ? 'warn' : 'bad' };
  };
  var draw = function (canvas, painter) {
    if (!canvas) return;
    var rect = canvas.getBoundingClientRect();
    var dpr = window.devicePixelRatio || 1;
    // The chart wrapper owns the border. Measure the canvas content box rather
    // than the wrapper so the painter never treats the border as plot space.
    var width = Math.max(1, Math.round(rect.width * dpr));
    var height = Math.max(1, Math.round(rect.height * dpr));
    if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
    var ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    painter(ctx, rect.width, rect.height);
  };
  var setChartHeight = function (id, height) {
    var canvas = el(id);
    var wrap = canvas && canvas.parentElement;
    if (!wrap) return;
    var styles = window.getComputedStyle(wrap);
    var border = (parseFloat(styles.borderTopWidth) || 0) + (parseFloat(styles.borderBottomWidth) || 0);
    var inset = (parseFloat(styles.paddingTop) || 0) + (parseFloat(styles.paddingBottom) || 0);
    // Callers specify the drawable canvas height. Add only the wrapper's
    // border and symmetric vertical inset so the canvas keeps that height.
    wrap.style.height = Math.max(1, Math.round(height + border + inset)) + 'px';
  };
  var fitChartRows = function (id, count, min, max, row, top, bottom) {
    var rows = Math.max(1, number(count));
    setChartHeight(id, clamp(top + bottom + rows * row, min, max));
  };
  var grid = function (ctx, width, height, max, budget) {
    var left = 44, right = 14, top = 18, bottom = 28;
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
    ctx.strokeStyle = css('--line'); ctx.lineWidth = 1;
    ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif';
    for (var i = 0; i <= 4; i += 1) {
      var y = top + (height - top - bottom) * i / 4;
      ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(width - right, y); ctx.stroke();
      ctx.fillText(us(Math.round(max * (1 - i / 4))), 7, y + 3);
    }
    if (budget > 0 && budget <= max) {
      var by = top + (height - top - bottom) * (1 - budget / max);
      ctx.strokeStyle = css('--danger'); ctx.setLineDash([5, 4]);
      ctx.beginPath(); ctx.moveTo(left, by); ctx.lineTo(width - right, by); ctx.stroke(); ctx.setLineDash([]);
    }
    return { left: left, right: right, top: top, bottom: bottom, plotW: width - left - right, plotH: height - top - bottom };
  };
  var drawFrameChart = function () {
    var list = frames();
    setChartHeight('frame-chart', 240);
    draw(el('frame-chart'), function (ctx, width, height) {
      chartHits['frame-chart'] = [];
      var budget = number(summary().build && summary().build.bud);
      var max = Math.max(budget, 1, list.reduce(function (m, f) { return Math.max(m, number(f.s)); }, 0));
      max = max * 1.12;
      var area = grid(ctx, width, height, max, budget);
      if (!list.length) { ctx.fillStyle = css('--muted'); ctx.fillText('No retained frame timings', area.left, height / 2); return; }
      var stride = Math.max(1, Math.ceil(list.length / Math.max(1, Math.floor(area.plotW))));
      var sample = list.filter(function (_, i) { return i % stride === 0; });
      var origin = number(list[0].t);
      var path = function (key, color, lineWidth) {
        ctx.strokeStyle = color; ctx.lineWidth = lineWidth; ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.beginPath();
        sample.forEach(function (f, i) { var x = area.left + (sample.length === 1 ? .5 : i / (sample.length - 1)) * area.plotW; var y = area.top + area.plotH * (1 - number(f[key]) / max); if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); });
        ctx.stroke();
      };
      path('s', css('--accent'), 2.2); path('b', css('--blue'), 1.15); path('r', css('--warning'), 1.15);
      ctx.fillStyle = css('--danger');
      sample.forEach(function (f, i) {
        var x = area.left + (sample.length === 1 ? .5 : i / (sample.length - 1)) * area.plotW;
        var y = area.top + area.plotH * (1 - number(f.s) / max);
        if (number(f.s) > budget) { ctx.beginPath(); ctx.arc(x, y, 2.7, 0, Math.PI * 2); ctx.fill(); }
        chartHits['frame-chart'].push({ x: x - 7, y: area.top, w: 14, h: area.plotH, html: '<strong>Frame ' + esc(number(f.i)) + '</strong>' + tooltipRow('Time', relativeUs(f.t, origin)) + tooltipRow('Total', us(f.s)) + tooltipRow('Build', us(f.b)) + tooltipRow('Raster', us(f.r)) + tooltipRow('Vsync', us(f.v)) + tooltipRow('Budget', us(budget)) + tooltipRow('Jank', number(f.s) > budget ? 'yes' : 'no') + tooltipRow('Layers', nf.format(number(f.l))) + tooltipRow('Pictures', nf.format(number(f.p))) + '<div class="subtle">Raw timestamp: ' + esc(us(f.t)) + '</div>' });
      });
      ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('0', area.left, height - 8); ctx.fillText(nf.format(list.length) + ' frames', Math.max(area.left, width - 92), height - 8);
    });
  };
  var hashColor = function (value) { var colors = [css('--accent'), css('--blue'), css('--warning'), '#d79aff', '#8bd4ff', '#ff9da4']; var hash = 0; for (var i = 0; i < value.length; i += 1) hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0; return colors[Math.abs(hash) % colors.length]; };
  var drawEventChart = function () {
    var list = events();
    setChartHeight('event-chart', 160);
    draw(el('event-chart'), function (ctx, width, height) {
      chartHits['event-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      if (!list.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('No retained VM events', 15, height / 2); return; }
      var min = list.reduce(function (m, e) { return Math.min(m, number(e.t)); }, Infinity); var max = list.reduce(function (m, e) { return Math.max(m, number(e.t) + number(e.d)); }, -Infinity); var span = Math.max(1, max - min);
      var lanes = {}; list.forEach(function (e) { var key = String(e.c || 'uncategorized'); if (!lanes[key]) lanes[key] = []; lanes[key].push(e); });
      var laneNames = Object.keys(lanes).sort(function (a, b) { return lanes[b].length - lanes[a].length; }).slice(0, 7); var left = 12; var labelW = Math.min(105, Math.max(58, width * .22)); var plotLeft = left + labelW; var plotW = width - plotLeft - 12; var plotTop = 10; var plotBottom = 22; var rowH = Math.max(14, (height - plotTop - plotBottom) / Math.max(1, laneNames.length));
      ctx.font = '10px system-ui, sans-serif';
      laneNames.forEach(function (lane, laneIndex) { var y = plotTop + laneIndex * rowH; ctx.fillStyle = css('--muted'); ctx.fillText(lane.length > 16 ? lane.slice(0, 15) + '…' : lane, left, y + rowH * .65); var laneEvents = lanes[lane]; var stride = Math.max(1, Math.ceil(laneEvents.length / Math.max(1, Math.floor(plotW / 2)))); laneEvents.forEach(function (e, i) { if (i % stride !== 0) return; var x = plotLeft + ((number(e.t) - min) / span) * plotW; var w = Math.max(2, (number(e.d) / span) * plotW); var visibleW = Math.min(w, plotLeft + plotW - x); ctx.fillStyle = hashColor(lane); ctx.globalAlpha = .88; ctx.fillRect(x, y + 2, visibleW, Math.max(5, rowH - 6)); ctx.globalAlpha = 1; chartHits['event-chart'].push({ x: x, y: y + 2, w: Math.max(8, visibleW), h: Math.max(5, rowH - 6), html: '<strong>' + esc(e.n || 'Unnamed event') + '</strong>' + tooltipRow('Category', lane) + tooltipRow('When', relativeUs(e.t, min)) + tooltipRow('Duration', e.d ? us(e.d) : 'Instant') + tooltipRow('Phase', e.p || '—') + (e.a && Object.keys(e.a).length ? '<div class="subtle">Arguments: ' + esc(Object.keys(e.a).join(', ')) + '</div>' : '') + '<div class="subtle">Raw timestamp: ' + esc(us(e.t)) + '</div>' }); }); });
      ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(plotLeft, height - plotBottom + 3); ctx.lineTo(plotLeft + plotW, height - plotBottom + 3); ctx.stroke();
      ctx.fillStyle = css('--muted'); ctx.fillText(nf.format(list.length) + ' retained · ' + us(span) + ' span', left, height - 8);
    });
  };
  var drawPhaseChart = function () {
    fitChartRows('phase-chart', 4, 156, 220, 32, 10, 24);
    draw(el('phase-chart'), function (ctx, width, height) {
      chartHits['phase-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var names = [['Build', phase('build')], ['Raster', phase('raster')], ['Vsync', phase('vsync')], ['Total', phase('total')]]; var values = names.reduce(function (all, item) { var p = item[1]; return all.concat([p.p50, p.p90, p.p99, p.max].filter(function (value) { return value != null; }).map(number)); }, []); var max = Math.max(1, values.reduce(function (m, value) { return Math.max(m, value); }, 0)) * 1.15; var left = 54, right = 13, top = 10, bottom = 24, plotW = width - left - right, plotH = height - top - bottom, rowH = 32;
      ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif';
      for (var i = 0; i <= 4; i += 1) { var x = left + plotW * i / 4; ctx.beginPath(); ctx.moveTo(x, top); ctx.lineTo(x, top + plotH); ctx.stroke(); var axisLabel = us(Math.round(max * i / 4)); var axisWidth = ctx.measureText(axisLabel).width; ctx.fillText(axisLabel, clamp(x - axisWidth / 2, left, width - right - axisWidth), height - 8); }
      var bars = [['p50', css('--accent')], ['p90', css('--blue')], ['p99', css('--warning')], ['max', css('--danger')]];
      names.forEach(function (item, row) { var label = item[0], p = item[1], rowTop = top + row * rowH; ctx.fillStyle = css('--text-soft'); ctx.fillText(label, 10, rowTop + 19); bars.forEach(function (bar, index) { var raw = p[bar[0]], value = raw == null ? 0 : number(raw); var by = rowTop + 2 + index * 6; var barW = raw == null ? 0 : Math.max(value ? 2 : 0, value / max * plotW); ctx.fillStyle = bar[1]; ctx.globalAlpha = raw == null ? .08 : value ? .92 : .22; ctx.fillRect(left, by, barW, 4); ctx.globalAlpha = 1; }); chartHits['phase-chart'].push({ x: left, y: rowTop, w: plotW, h: rowH, html: '<strong>' + esc(label) + ' latency</strong>' + tooltipRow('Average', metricUs(p.avg)) + tooltipRow('p50', metricUs(p.p50)) + tooltipRow('p90', metricUs(p.p90)) + tooltipRow('p99', metricUs(p.p99)) + tooltipRow('Max', metricUs(p.max)) + tooltipRow('Budget', metricUs(p.bud)) + tooltipRow('Missed', metricCount(p.miss)) }); });
      if (!values.some(function (value) { return value > 0; })) { ctx.fillStyle = css('--muted'); ctx.fillText('No phase aggregates retained', left, height / 2); }
    });
  };
  var drawResourceChart = function () {
    setChartHeight('resource-chart', 210);
    draw(el('resource-chart'), function (ctx, width, height) {
      chartHits['resource-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var mem = memory(); var samples = mem && Array.isArray(mem.samples) ? mem.samples : [];
      if (samples.length) {
        var min = samples.reduce(function (m, item) { return Math.min(m, number(item.rss)); }, Infinity);
        var max = samples.reduce(function (m, item) { return Math.max(m, number(item.peak), number(item.rss)); }, 0);
        if (!Number.isFinite(min)) min = 0;
        max = Math.max(max, min + 1) * 1.08;
        var left = 52, right = 18, top = 18, bottom = 28, plotW = width - left - right, plotH = height - top - bottom;
        ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif';
        for (var i = 0; i <= 4; i += 1) { var y = top + plotH * i / 4; ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(width - right, y); ctx.stroke(); ctx.fillText(bytes(Math.round(max * (1 - i / 4))), 5, y + 3); }
        var first = number(samples[0].t), last = number(samples[samples.length - 1].t), span = Math.max(1, last - first);
        var path = function (key, color, dashed) { ctx.strokeStyle = color; ctx.lineWidth = dashed ? 1.1 : 2.2; ctx.setLineDash(dashed ? [5, 4] : []); ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.beginPath(); samples.forEach(function (item, index) { var x = left + (number(item.t) - first) / span * plotW; var y = top + plotH * (1 - number(item[key]) / max); if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); }); ctx.stroke(); ctx.setLineDash([]); };
        path('rss', css('--accent'), false); path('peak', css('--blue'), true);
        var stride = Math.max(1, Math.ceil(samples.length / Math.max(1, Math.floor(plotW))));
        samples.forEach(function (item, index) { if (index % stride !== 0) return; var x = left + (number(item.t) - first) / span * plotW; chartHits['resource-chart'].push({ x: x - 7, y: top, w: 14, h: plotH, html: '<strong>Memory sample</strong>' + tooltipRow('Elapsed', duration(number(item.t) / 1000)) + tooltipRow('RSS', bytes(item.rss)) + tooltipRow('Process peak', bytes(item.peak)) }); });
        ctx.fillStyle = css('--muted'); ctx.fillText('RSS', left, height - 8); ctx.fillText(nf.format(samples.length) + ' samples · ' + duration(last / 1000), Math.max(left + 30, width - 165), height - 8);
      } else {
        ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('No retained memory samples', 15, height / 2);
      }
    });
  };
  var drawCacheChart = function () {
    fitChartRows('cache-chart', 6, 170, 220, 27, 10, 10);
    draw(el('cache-chart'), function (ctx, width, height) {
      chartHits['cache-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var s = summary(); var hasFrames = frames().length > 0; var layer = hasFrames ? (s.layerCache || {}) : {}; var picture = hasFrames ? (s.pictureCache || {}) : {}; var gc = s.gc || {};
      var rows = [['Layer bytes', layer.bytes == null ? null : number(layer.bytes), css('--accent'), layer.bytes == null ? 'Unavailable' : bytes(layer.bytes), 'bytes'], ['Picture bytes', picture.bytes == null ? null : number(picture.bytes), css('--blue'), picture.bytes == null ? 'Unavailable' : bytes(picture.bytes), 'bytes'], ['Layer count', layer.count == null ? null : number(layer.count), css('--warning'), layer.count == null ? 'Unavailable' : nf.format(number(layer.count)), 'count'], ['Picture count', picture.count == null ? null : number(picture.count), '#d79aff', picture.count == null ? 'Unavailable' : nf.format(number(picture.count)), 'count'], ['New GC', gc.new == null ? null : number(gc.new), css('--danger'), gc.new == null ? 'Unavailable' : nf.format(number(gc.new)), 'count'], ['Old GC', gc.old == null ? null : number(gc.old), '#ff9da4', gc.old == null ? 'Unavailable' : nf.format(number(gc.old)), 'count']];
      var byteMax = Math.max(1, rows.slice(0, 2).reduce(function (m, row) { return Math.max(m, row[1] == null ? 0 : row[1]); }, 0)); var countMax = Math.max(1, rows.slice(2).reduce(function (m, row) { return Math.max(m, row[1] == null ? 0 : row[1]); }, 0)); var left = 92, right = 82, top = 10, rowH = 27; ctx.font = '10px system-ui, sans-serif'; rows.forEach(function (row, index) { var y = top + index * rowH; var rowMax = row[4] === 'bytes' ? byteMax : countMax; var value = row[1] == null ? 0 : row[1]; var barW = row[1] == null ? 0 : Math.max(value ? 3 : 0, value / rowMax * (width - left - right)); ctx.fillStyle = css('--muted'); ctx.fillText(row[0], 8, y + 11); ctx.fillStyle = css('--surface-3'); ctx.fillRect(left, y + 2, width - left - right, 12); if (row[1] != null) { ctx.fillStyle = row[2]; ctx.fillRect(left, y + 2, barW, 12); } ctx.fillStyle = row[1] == null ? css('--muted') : css('--text-soft'); ctx.fillText(row[3], width - right + 6, y + 12); chartHits['cache-chart'].push({ x: left, y: y, w: width - left - right, h: 16, html: '<strong>' + esc(row[0]) + '</strong>' + tooltipRow('Value', row[3]) + tooltipRow('Scale', row[1] == null ? 'Unavailable' : row[4] === 'bytes' ? bytes(rowMax) : nf.format(rowMax)) }); });
      if (!rows.some(function (row) { return row[1] > 0; })) { ctx.fillStyle = css('--muted'); ctx.fillText('No cache or GC data retained', left, height / 2); }
    });
  };
  var drawJankChart = function () {
    var list = frames(); var budget = number(summary().build && summary().build.bud); var bins = [{ label: 'Within budget', max: budget, min: 0, count: 0, color: css('--accent') }, { label: '1–1.5× budget', max: budget * 1.5, min: budget, count: 0, color: css('--warning') }, { label: '1.5–2× budget', max: budget * 2, min: budget * 1.5, count: 0, color: '#e89a63' }, { label: '>2× budget', max: Infinity, min: budget * 2, count: 0, color: css('--danger') }];
    if (!budget) bins = [{ label: 'All frames', max: Infinity, min: 0, count: list.length, color: css('--accent') }]; else list.forEach(function (frame) { var value = number(frame.s); bins.some(function (bin) { if (value <= bin.max) { bin.count += 1; return true; } return false; }); });
    fitChartRows('jank-chart', bins.length, 82, 196, 28, 10, 10);
    draw(el('jank-chart'), function (ctx, width, height) {
      chartHits['jank-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var total = Math.max(1, list.length); var left = 116, right = 84, top = 10, rowH = 28, plotW = width - left - right; ctx.font = '10px system-ui, sans-serif'; bins.forEach(function (bin, index) { var y = top + index * rowH; var barW = bin.count / total * plotW; ctx.fillStyle = css('--muted'); ctx.fillText(bin.label, 8, y + 12); ctx.fillStyle = css('--surface-3'); ctx.fillRect(left, y + 2, plotW, 14); ctx.fillStyle = bin.color; ctx.fillRect(left, y + 2, barW, 14); ctx.fillStyle = css('--text-soft'); ctx.fillText(nf.format(bin.count) + ' · ' + (bin.count / total * 100).toFixed(1) + '%', left + plotW + 6, y + 13); chartHits['jank-chart'].push({ x: left, y: y, w: plotW, h: 18, html: '<strong>' + esc(bin.label) + '</strong>' + tooltipRow('Frames', nf.format(bin.count)) + tooltipRow('Share', (bin.count / total * 100).toFixed(1) + '%') + tooltipRow('Budget', budget ? us(budget) : 'Unavailable') }); });
      if (!list.length) { ctx.fillStyle = css('--muted'); ctx.fillText('No retained frame timings', left, height / 2); }
    });
  };
  var drawCadenceChart = function () {
    setChartHeight('cadence-chart', 210);
    draw(el('cadence-chart'), function (ctx, width, height) {
      chartHits['cadence-chart'] = [];
      var list = frames(); var intervals = []; for (var index = 1; index < list.length; index += 1) { var delta = number(list[index].t) - number(list[index - 1].t); if (delta > 0) intervals.push({ frame: list[index], delta: delta }); }
      if (!intervals.length) { ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height); ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('At least two increasing frame timestamps are required', 15, height / 2); return; }
      var budget = number(summary().build && summary().build.bud); var max = Math.max(budget, intervals.reduce(function (value, item) { return Math.max(value, item.delta); }, 1)) * 1.12; var area = grid(ctx, width, height, max, budget); var stride = Math.max(1, Math.ceil(intervals.length / Math.max(1, Math.floor(area.plotW)))); var sample = intervals.filter(function (_, index) { return index % stride === 0; });
      ctx.strokeStyle = css('--blue'); ctx.lineWidth = 2; ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.beginPath(); sample.forEach(function (item, index) { var x = area.left + (sample.length === 1 ? .5 : index / (sample.length - 1)) * area.plotW; var y = area.top + area.plotH * (1 - item.delta / max); if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); chartHits['cadence-chart'].push({ x: x - 7, y: area.top, w: 14, h: area.plotH, html: '<strong>Frame ' + esc(number(item.frame.i)) + ' cadence</strong>' + tooltipRow('Elapsed', relativeUs(item.frame.t, frameOrigin())) + tooltipRow('Interval', us(item.delta)) + tooltipRow('Budget', us(budget)) + tooltipRow('Jitter', us(item.delta - budget)) }); }); ctx.stroke();
      ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('Frame 1', area.left, height - 8); ctx.fillText(nf.format(intervals.length) + ' intervals', Math.max(area.left + 30, width - 92), height - 8);
    });
  };
  var drawCacheTrendChart = function () {
    setChartHeight('cache-trend-chart', 210);
    draw(el('cache-trend-chart'), function (ctx, width, height) {
      chartHits['cache-trend-chart'] = [];
      var list = frames(); ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      if (!list.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('No retained frame cache samples', 15, height / 2); return; }
      var max = Math.max(1, list.reduce(function (value, frame) { return Math.max(value, number(frame.l), number(frame.p)); }, 0)) * 1.12; var left = 48; var right = 16; var top = 18; var bottom = 28; var plotW = width - left - right; var plotH = height - top - bottom; ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; for (var i = 0; i <= 4; i += 1) { var y = top + plotH * i / 4; ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(width - right, y); ctx.stroke(); ctx.fillText(nf.format(Math.round(max * (1 - i / 4))), 8, y + 3); }
      var stride = Math.max(1, Math.ceil(list.length / Math.max(1, Math.floor(plotW)))); var sample = list.filter(function (_, index) { return index % stride === 0; }); var path = function (key, color) { ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.beginPath(); sample.forEach(function (frame, index) { var x = left + (sample.length === 1 ? .5 : index / (sample.length - 1)) * plotW; var y = top + plotH * (1 - number(frame[key]) / max); if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); }); ctx.stroke(); }; path('l', css('--accent')); path('p', css('--blue'));
      sample.forEach(function (frame, index) { var x = left + (sample.length === 1 ? .5 : index / (sample.length - 1)) * plotW; chartHits['cache-trend-chart'].push({ x: x - 7, y: top, w: 14, h: plotH, html: '<strong>Raster cache · frame ' + esc(number(frame.i)) + '</strong>' + tooltipRow('Elapsed', relativeUs(frame.t, frameOrigin())) + tooltipRow('Layers', nf.format(number(frame.l)) + ' · ' + bytes(frame.lb)) + tooltipRow('Pictures', nf.format(number(frame.p)) + ' · ' + bytes(frame.pb)) }); });
      ctx.fillStyle = css('--muted'); ctx.fillText('Layer count', left, height - 8); ctx.fillText(nf.format(list.length) + ' frames', Math.max(left + 66, width - 82), height - 8);
    });
  };
  var pipelineSamples = function () {
    return frames().map(function (frame) {
      if (frame.bs == null || frame.bf == null || frame.rs == null || frame.rf == null) return null;
      var vsync = number(frame.t); var buildStart = number(frame.bs); var buildFinish = number(frame.bf); var rasterStart = number(frame.rs); var rasterFinish = number(frame.rf);
      if (buildStart < vsync || buildFinish < buildStart || rasterStart < buildFinish || rasterFinish < rasterStart) return null;
      return { frame: frame, buildWait: buildStart - vsync, build: buildFinish - buildStart, rasterWait: rasterStart - buildFinish, raster: rasterFinish - rasterStart, total: rasterFinish - vsync };
    }).filter(function (item) { return item != null; });
  };
  var drawPipelineChart = function () {
    var list = pipelineSamples();
    setChartHeight('pipeline-chart', 210);
    draw(el('pipeline-chart'), function (ctx, width, height) {
      chartHits['pipeline-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      if (!list.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('Raw phase timestamps were not retained', 15, height / 2); el('pipeline-summary').innerHTML = '<div><span>Samples</span><strong>Unavailable</strong></div>'; return; }
      var max = Math.max(1, list.reduce(function (value, item) { return Math.max(value, item.total, item.buildWait, item.build, item.rasterWait, item.raster); }, 0)) * 1.12;
      var budget = number(summary().build && summary().build.bud); var area = grid(ctx, width, height, max, budget); var stride = Math.max(1, Math.ceil(list.length / Math.max(1, Math.floor(area.plotW)))); var sample = list.filter(function (_, index) { return index % stride === 0; });
      var paths = [['buildWait', css('--blue')], ['build', '#8bd4ff'], ['rasterWait', css('--warning')], ['raster', css('--accent')]];
      paths.forEach(function (path) { ctx.strokeStyle = path[1]; ctx.lineWidth = 1.7; ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.beginPath(); sample.forEach(function (item, index) { var x = area.left + (sample.length === 1 ? .5 : index / (sample.length - 1)) * area.plotW; var y = area.top + area.plotH * (1 - item[path[0]] / max); if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); }); ctx.stroke(); });
      sample.forEach(function (item, index) { var x = area.left + (sample.length === 1 ? .5 : index / (sample.length - 1)) * area.plotW; chartHits['pipeline-chart'].push({ x: x - 7, y: area.top, w: 14, h: area.plotH, html: '<strong>Frame ' + esc(number(item.frame.i)) + '</strong>' + tooltipRow('Build wait', us(item.buildWait)) + tooltipRow('Build', us(item.build)) + tooltipRow('Raster wait', us(item.rasterWait)) + tooltipRow('Raster', us(item.raster)) + tooltipRow('Pipeline', us(item.total)) }); });
      ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('Build wait · build · raster wait · raster', area.left, height - 8); ctx.fillText(nf.format(list.length) + ' frames', Math.max(area.left + 70, width - 84), height - 8);
    });
    var values = function (key) { return list.map(function (item) { return item[key]; }); };
    el('pipeline-summary').innerHTML = [['Samples', nf.format(list.length)], ['Build wait p90', us(percentile(values('buildWait'), .9))], ['Raster wait p90', us(percentile(values('rasterWait'), .9))], ['Pipeline p90', us(percentile(values('total'), .9))]].map(function (cell) { return '<div><span>' + esc(cell[0]) + '</span><strong>' + esc(cell[1]) + '</strong></div>'; }).join('');
  };
  var gcEvents = function () {
    return events().map(function (event) {
      var text = (String(event.c || '') + ' ' + String(event.n || '')).toLowerCase();
      if (text.indexOf('gc') < 0 && text.indexOf('garbage') < 0 && text.indexOf('scavenge') < 0 && text.indexOf('mark-sweep') < 0 && text.indexOf('generation') < 0) return null;
      return { event: event, duration: number(event.d), kind: text.indexOf('new') >= 0 || text.indexOf('scavenge') >= 0 ? 'new' : text.indexOf('old') >= 0 || text.indexOf('mark-sweep') >= 0 ? 'old' : 'gc' };
    }).filter(function (item) { return item != null && item.duration > 0; });
  };
  var drawGcChart = function () {
    var list = gcEvents();
    setChartHeight('gc-chart', 210);
    draw(el('gc-chart'), function (ctx, width, height) {
      chartHits['gc-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var stats = gcStats();
      if (!list.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText(stats.count ? 'GC events had no duration samples' : 'No retained GC pause events', 15, height / 2); el('gc-note').textContent = stats.count ? nf.format(stats.count) + ' events · no durations' : 'Not collected'; el('gc-summary').innerHTML = [['Cycles', stats.count ? nf.format(stats.count) : 'Unavailable'], ['Timed', nf.format(stats.timed)], ['p90', stats.p90 == null ? 'Unavailable' : us(stats.p90)], ['Max', stats.max == null ? 'Unavailable' : us(stats.max)]].map(function (cell) { return '<div><span>' + esc(cell[0]) + '</span><strong>' + esc(cell[1]) + '</strong></div>'; }).join(''); return; }
      var max = Math.max(1, list.reduce(function (value, item) { return Math.max(value, item.duration); }, 0)) * 1.12; var left = 48, right = 18, top = 18, bottom = 28, plotW = width - left - right, plotH = height - top - bottom; ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; for (var i = 0; i <= 4; i += 1) { var y = top + plotH * i / 4; ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(width - right, y); ctx.stroke(); ctx.fillText(us(Math.round(max * (1 - i / 4))), 5, y + 3); }
      var stride = Math.max(1, Math.ceil(list.length / Math.max(1, Math.floor(plotW / 3)))); list.forEach(function (item, index) { if (index % stride !== 0) return; var x = left + (list.length === 1 ? .5 : index / (list.length - 1)) * plotW; var h = Math.max(2, item.duration / max * plotH); var y = top + plotH - h; ctx.fillStyle = item.kind === 'new' ? css('--blue') : item.kind === 'old' ? css('--danger') : css('--warning'); ctx.globalAlpha = .88; ctx.fillRect(x - 2, y, 4, h); ctx.globalAlpha = 1; chartHits['gc-chart'].push({ x: x - 6, y: top, w: 12, h: plotH, html: '<strong>' + esc(item.event.n || 'GC') + '</strong>' + tooltipRow('Generation', item.kind) + tooltipRow('When', relativeUs(item.event.t, eventOrigin())) + tooltipRow('Pause', us(item.duration)) }); });
      ctx.fillStyle = css('--muted'); ctx.fillText(nf.format(list.length) + ' timed pauses', left, height - 8); ctx.fillText('max ' + us(max / 1.12), Math.max(left + 50, width - 86), height - 8);
    });
    var stats = gcStats(); el('gc-note').textContent = stats.count ? nf.format(stats.count) + ' events · ' + nf.format(stats.timed) + ' timed' : 'Not collected'; el('gc-summary').innerHTML = [['Cycles', stats.count ? nf.format(stats.count) : 'Unavailable'], ['New / old', nf.format(stats.new || 0) + ' / ' + nf.format(stats.old || 0)], ['p90', stats.p90 == null ? 'Unavailable' : us(stats.p90)], ['Max', stats.max == null ? 'Unavailable' : us(stats.max)]].map(function (cell) { return '<div><span>' + esc(cell[0]) + '</span><strong>' + esc(cell[1]) + '</strong></div>'; }).join('');
  };
  var drawCategoryCostChart = function () {
    var categoryKeys = {};
    events().forEach(function (event) { categoryKeys[String(event.c || 'uncategorized')] = true; });
    fitChartRows('category-cost-chart', Math.min(10, Object.keys(categoryKeys).length), 76, 320, 28, 10, 10);
    draw(el('category-cost-chart'), function (ctx, width, height) {
      chartHits['category-cost-chart'] = [];
      var grouped = {}; events().forEach(function (event) { var key = String(event.c || 'uncategorized'); var value = grouped[key] || { total: 0, count: 0, longest: 0 }; value.total += number(event.d); value.count += 1; value.longest = Math.max(value.longest, number(event.d)); grouped[key] = value; }); var rows = Object.keys(grouped).map(function (key) { return { key: key, value: grouped[key] }; }).sort(function (a, b) { return b.value.total - a.value.total || b.value.count - a.value.count; }).slice(0, 10);
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height); if (!rows.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('No retained VM events', 15, height / 2); return; }
      var max = Math.max(1, rows.reduce(function (value, row) { return Math.max(value, row.value.total); }, 0)); var left = 112; var right = 80; var top = 10; var rowH = 28; var plotW = width - left - right; ctx.font = '10px system-ui, sans-serif'; rows.forEach(function (row, index) { var y = top + index * rowH; var barW = row.value.total / max * plotW; ctx.fillStyle = css('--muted'); ctx.fillText(row.key.length > 17 ? row.key.slice(0, 16) + '…' : row.key, 8, y + 12); ctx.fillStyle = css('--surface-3'); ctx.fillRect(left, y + 2, plotW, 12); ctx.fillStyle = hashColor(row.key); ctx.fillRect(left, y + 2, barW, 12); ctx.fillStyle = css('--text-soft'); ctx.fillText(us(row.value.total) + ' · ' + nf.format(row.value.count), width - right + 6, y + 12); chartHits['category-cost-chart'].push({ x: left, y: y, w: plotW, h: 16, html: '<strong>' + esc(row.key) + '</strong>' + tooltipRow('Total duration', us(row.value.total)) + tooltipRow('Longest event', us(row.value.longest)) + tooltipRow('Events', nf.format(row.value.count)) }); });
    });
  };
  var hotspotCache = {};
  var hotspotSourceCache = {};
  var percentile = function (values, ratio) {
    if (!values.length) return null;
    var sorted = values.slice().sort(function (a, b) { return a - b; });
    var index = Math.max(0, Math.min(sorted.length - 1, Math.ceil(sorted.length * ratio) - 1));
    return sorted[index];
  };
  var hotspotKey = function (category, name) { return String(category || 'uncategorized') + '\\u0000' + String(name || 'Unnamed event'); };
  var hotspotSources = function () {
    if (hotspotSourceCache[state.report]) return hotspotSourceCache[state.report];
    var result = {};
    events().forEach(function (event) {
      var source = sourceLabel(event.a);
      if (!source) return;
      var key = hotspotKey(event.c, event.n);
      var current = result[key];
      if (!current || number(event.d) > current.duration) result[key] = { label: source, duration: number(event.d) };
    });
    hotspotSourceCache[state.report] = result;
    return result;
  };
  var hotspotRows = function () {
    if (hotspotCache[state.report]) return hotspotCache[state.report];
    var item = reports[state.report] || {};
    var stored = item.analysis && Array.isArray(item.analysis.hotspots) ? item.analysis.hotspots : null;
    var rows;
    if (stored) {
      rows = stored.map(function (row) {
        var category = String(row.c || 'uncategorized');
        var name = String(row.n || 'Unnamed event');
        var key = hotspotKey(category, name);
        var source = hotspotSources()[key];
        return { category: category, name: name, count: number(row.count), timed: number(row.timed), total: number(row.total), p90: row.p90 == null ? null : number(row.p90), max: row.max == null ? null : number(row.max), source: source ? source.label : 'Unavailable' };
      });
    } else {
      var grouped = {};
      events().forEach(function (event) {
        var category = String(event.c || 'uncategorized');
        var name = String(event.n || 'Unnamed event');
        var key = hotspotKey(category, name);
        var value = grouped[key] || { category: category, name: name, count: 0, timed: 0, total: 0, max: 0, durations: [] };
        value.count += 1;
        if (number(event.d) > 0) { value.timed += 1; value.total += number(event.d); value.max = Math.max(value.max, number(event.d)); value.durations.push(number(event.d)); }
        grouped[key] = value;
      });
      rows = Object.keys(grouped).map(function (key) {
        var value = grouped[key];
        return { category: value.category, name: value.name, count: value.count, timed: value.timed, total: value.total, p90: percentile(value.durations, .9), max: value.max || null, source: (hotspotSources()[key] || {}).label || 'Unavailable' };
      });
    }
    rows.sort(function (a, b) { return b.total - a.total || (b.max || 0) - (a.max || 0) || b.count - a.count; });
    hotspotCache[state.report] = rows.slice(0, 100);
    return hotspotCache[state.report];
  };
  var drawHotspotChart = function () {
    fitChartRows('hotspot-chart', Math.min(12, hotspotRows().length), 88, 360, 28, 10, 22);
    draw(el('hotspot-chart'), function (ctx, width, height) {
      chartHits['hotspot-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var rows = hotspotRows().slice(0, 12);
      if (!rows.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('No retained VM operations', 15, height / 2); return; }
      var useDuration = rows.some(function (row) { return row.total > 0; });
      var max = Math.max(1, rows.reduce(function (value, row) { return Math.max(value, useDuration ? row.total : row.count); }, 0));
      var left = 150, right = 92, top = 10, bottom = 22, rowH = 28, plotW = width - left - right;
      ctx.font = '10px system-ui, sans-serif';
      rows.forEach(function (row, index) {
        var y = top + index * rowH;
        var value = useDuration ? row.total : row.count;
        var barW = value / max * plotW;
        var label = row.name.length > 22 ? row.name.slice(0, 21) + '…' : row.name;
        ctx.fillStyle = css('--muted'); ctx.fillText(label, 8, y + 12);
        ctx.fillStyle = css('--surface-3'); ctx.fillRect(left, y + 2, plotW, 12);
        ctx.fillStyle = hashColor(row.category); ctx.fillRect(left, y + 2, Math.max(value ? 3 : 0, barW), 12);
        ctx.fillStyle = css('--text-soft'); ctx.fillText(useDuration ? us(row.total) : nf.format(row.count), width - right + 6, y + 12);
        chartHits['hotspot-chart'].push({ x: left, y: y, w: plotW, h: 16, html: '<strong>' + esc(row.name) + '</strong>' + tooltipRow('Category', row.category) + tooltipRow('Events', nf.format(row.count)) + tooltipRow('Timed', nf.format(row.timed)) + tooltipRow('Total', row.total ? us(row.total) : 'Instant only') + tooltipRow('p90', row.p90 == null ? 'Unavailable' : us(row.p90)) + tooltipRow('Longest', row.max == null ? 'Unavailable' : us(row.max)) + '<div class="subtle">Source: ' + esc(row.source) + '</div>' });
      });
      ctx.fillStyle = css('--muted'); ctx.fillText(useDuration ? 'Total retained duration' : 'Event count (no duration samples)', left, height - 8);
      ctx.fillText(nf.format(rows.length) + ' operations', Math.max(left + 80, width - 93), height - 8);
    });
  };
  var renderHotspots = function () {
    var rows = hotspotRows();
    var timed = rows.reduce(function (count, row) { return count + row.timed; }, 0);
    el('hotspot-note').textContent = rows.length ? nf.format(rows.length) + ' operations · ' + nf.format(timed) + ' timed events' : 'No retained operations';
    el('hotspot-body').innerHTML = rows.length ? rows.map(function (row) {
      return '<tr><td><div class="hotspot-name"><strong>' + esc(row.name) + '</strong></div></td><td>' + esc(row.category) + '</td><td>' + nf.format(row.count) + '</td><td>' + nf.format(row.timed) + '</td><td>' + esc(row.total ? us(row.total) : 'Instant only') + '</td><td>' + esc(row.p90 == null ? 'Unavailable' : us(row.p90)) + '</td><td>' + esc(row.max == null ? 'Unavailable' : us(row.max)) + '</td><td class="hotspot-source"><code>' + esc(row.source) + '</code></td></tr>';
    }).join('') : '<tr><td colspan="8"><div class="empty">No retained VM operations.</div></td></tr>';
  };
  var drawStartupChart = function () {
    fitChartRows('startup-chart', startup ? 3 : 1, 100, 180, 30, 10, 10);
    draw(el('startup-chart'), function (ctx, width, height) {
      chartHits['startup-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height); if (!startup) return;
      var rows = [['App build', number(startup.appMs), css('--blue')], ['First frame', number(startup.firstMs), css('--accent')], ['Ready', number(startup.readyMs), css('--warning')]]; var max = Math.max(1, rows.reduce(function (value, row) { return Math.max(value, row[1]); }, 0)) * 1.12; var left = 92; var right = 70; var top = 10; var rowH = 30; var plotW = width - left - right; ctx.font = '10px system-ui, sans-serif'; rows.forEach(function (row, index) { var y = top + index * rowH; var barW = row[1] / max * plotW; ctx.fillStyle = css('--muted'); ctx.fillText(row[0], 8, y + 12); ctx.fillStyle = css('--surface-3'); ctx.fillRect(left, y + 2, plotW, 14); ctx.fillStyle = row[2]; ctx.fillRect(left, y + 2, barW, 14); ctx.fillStyle = css('--text-soft'); ctx.fillText(duration(row[1]), width - right + 6, y + 13); chartHits['startup-chart'].push({ x: left, y: y, w: plotW, h: 18, html: '<strong>' + esc(row[0]) + '</strong>' + tooltipRow('Elapsed', duration(row[1])) + tooltipRow('Clock', startup.source || 'harness') }); });
    });
  };
  var drawFlameChart = function () {
    var spanEvents = events().filter(function (event) { return number(event.d) > 0; });
    var shownEvents = spanEvents.slice().sort(function (a, b) { return number(b.d) - number(a.d); }).slice(0, 5000).sort(function (a, b) { return number(a.t) - number(b.t) || number(b.d) - number(a.d); });
    var depthStack = [];
    var maxDepth = 1;
    shownEvents.forEach(function (event) {
      var start = number(event.t);
      while (depthStack.length && depthStack[depthStack.length - 1] <= start) depthStack.pop();
      maxDepth = Math.max(maxDepth, depthStack.length + 1);
      depthStack.push(start + number(event.d));
    });
    setChartHeight('flame-chart', clamp(48 + maxDepth * 22, 84, 360));
    draw(el('flame-chart'), function (ctx, width, height) {
      chartHits['flame-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var all = events().filter(function (event) { return number(event.d) > 0; });
      var shown = all.slice().sort(function (a, b) { return number(b.d) - number(a.d); }).slice(0, 5000).sort(function (a, b) { return number(a.t) - number(b.t) || number(b.d) - number(a.d); });
      if (!shown.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('No duration-bearing VM spans retained', 15, height / 2); el('flame-range').textContent = 'No spans'; return; }
      var min = shown.reduce(function (value, event) { return Math.min(value, number(event.t)); }, Infinity); var max = shown.reduce(function (value, event) { return Math.max(value, number(event.t) + number(event.d)); }, -Infinity); var span = Math.max(1, max - min); var stack = []; var placed = [];
      shown.forEach(function (event) { var start = number(event.t); var end = start + number(event.d); while (stack.length && stack[stack.length - 1] <= start) stack.pop(); var depth = stack.length; stack.push(end); placed.push({ event: event, depth: depth }); });
      var maxDepth = placed.reduce(function (value, item) { return Math.max(value, item.depth + 1); }, 1); var left = 10; var right = 12; var top = 12; var bottom = 24; var plotW = width - left - right; var plotH = height - top - bottom; var rowH = Math.max(8, Math.min(24, plotH / maxDepth));
      placed.forEach(function (item) { var event = item.event; var x = left + (number(event.t) - min) / span * plotW; var w = Math.max(2, number(event.d) / span * plotW); var y = top + item.depth * rowH; var h = Math.max(5, rowH - 2); ctx.fillStyle = hashColor(String(event.c || 'uncategorized')); ctx.globalAlpha = .88; ctx.fillRect(x, y, Math.min(w, left + plotW - x), h); ctx.globalAlpha = 1; if (w > 44) { ctx.fillStyle = css('--text'); ctx.font = '10px system-ui, sans-serif'; ctx.save(); ctx.beginPath(); ctx.rect(x + 4, y, Math.max(0, w - 8), h); ctx.clip(); ctx.fillText(String(event.n || 'Unnamed event'), x + 4, y + h - 5); ctx.restore(); } chartHits['flame-chart'].push({ x: x, y: y, w: Math.max(8, w), h: h, html: '<strong>' + esc(event.n || 'Unnamed event') + '</strong>' + tooltipRow('Category', event.c || 'uncategorized') + tooltipRow('Depth', nf.format(item.depth)) + tooltipRow('When', relativeUs(event.t, min)) + tooltipRow('Duration', us(event.d)) + tooltipRow('Phase', event.p || '—') + (event.a && Object.keys(event.a).length ? '<div class="subtle">Arguments: ' + esc(Object.keys(event.a).join(', ')) + '</div>' : '') }); });
      ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(left, height - bottom + 3); ctx.lineTo(left + plotW, height - bottom + 3); ctx.stroke(); ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText(nf.format(shown.length) + (all.length > shown.length ? ' of ' + nf.format(all.length) : '') + ' spans · ' + us(span) + ' span', left, height - 8); el('flame-range').textContent = relativeUs(min, min) + ' → ' + relativeUs(max, min);
    });
  };
  var metric = function (label, value, kind) { return '<div class="metric"><span>' + esc(label) + '</span><strong class="' + (kind || '') + '">' + esc(value) + '</strong></div>'; };
  var status = function (isBad, isWarn) { return '<span class="status ' + (isBad ? 'status-bad' : isWarn ? 'status-warn' : 'status-good') + '">' + (isBad ? 'Over budget' : isWarn ? 'Review' : 'Within budget') + '</span>'; };
  var renderMeta = function () {
    var r = report(); var label = reports[state.report] && reports[state.report].label || 'Capture';
    el('report-meta').innerHTML = '<span>' + esc(label) + '</span><span><code>' + esc(r.platform || 'unknown') + '</code></span><span>' + esc(r.build || 'unknown') + ' build</span><span>source: ' + esc(r.source || 'unavailable') + '</span><span>' + esc(r.started || '') + '</span>';
    el('report-title').textContent = data.title || 'Cockpit performance';
  };
  var renderHealth = function () {
    var r = report(); var q = quality(); var s = summary(); var retained = frames().length; var observed = retained + number(r.dropped && r.dropped.frames); var score = q.score == null ? '—' : q.score + '%';
    el('health-score').textContent = score; el('health-score').className = 'health-score ' + q.kind; el('health-label').textContent = q.label; el('health-note').textContent = q.score == null ? 'No valid frames were retained.' : number(s.jank) + ' of ' + number(s.frames) + ' retained frames exceeded the budget.'; el('health-meter').style.width = (q.score == null ? 0 : q.score) + '%'; el('health-left').textContent = nf.format(retained) + ' retained'; el('health-right').textContent = nf.format(observed) + ' observed';
  };
  var renderMetrics = function () {
    var r = report(); var s = summary(); var jank = number(s.jank); var count = number(s.frames); var fps = s.fps == null ? '—' : Number(s.fps).toFixed(1) + ' fps'; var eventCount = events().length; var gc = s.gc ? number(s.gc.new) + number(s.gc.old) : null; var mem = memory(); var memSummary = mem && mem.summary ? mem.summary : null;
    el('metric-grid').innerHTML = metric('Frames', nf.format(count)) + metric('Jank', nf.format(jank), jank ? 'bad' : 'good') + metric('Cadence', fps) + metric('Duration', duration(r.durationMs)) + metric('VM events', nf.format(eventCount)) + metric('GC cycles', gc == null ? '—' : nf.format(gc)) + metric('RSS peak', memSummary ? bytes(memSummary.peak) : '—') + metric('RSS Δ', memSummary ? bytes(memSummary.delta) : '—', memSummary && number(memSummary.delta) > 0 ? 'warn' : '');
    if (count) { var times = frames().map(function (frame) { return number(frame.t); }); var first = times.reduce(function (min, value) { return Math.min(min, value); }, Infinity); var last = times.reduce(function (max, value) { return Math.max(max, value); }, -Infinity); el('frame-range').textContent = relativeUs(first, first) + ' → ' + relativeUs(last, first); } else { el('frame-range').textContent = 'No samples'; }
  };
  var renderStartup = function () {
    var node = el('startup-strip'); var panel = el('startup-panel');
    if (!startup) { node.classList.add('hidden'); panel.classList.add('hidden'); return; }
    node.classList.remove('hidden'); panel.classList.remove('hidden'); node.innerHTML = '<div><span class="startup-title">Cold start milestones</span><span>' + esc(startup.source || 'harness') + ' clock</span></div><div><span>App build</span><strong>' + esc(duration(startup.appMs)) + '</strong></div><div><span>First frame</span><strong class="good">' + esc(duration(startup.firstMs)) + '</strong></div><div><span>Ready</span><strong>' + esc(duration(startup.readyMs)) + '</strong></div>';
  };
  var renderCoverage = function () {
    var r = report(); var s = summary(); var mem = memory(); var d = r.devtools || null; var available = 0;
    var rows = [
      ['Frame timing', frames().length ? 'available' : 'unavailable', frames().length ? nf.format(frames().length) + ' retained frames' : 'No valid FrameTiming samples'],
      ['Frame pipeline', pipelineSamples().length ? 'available' : 'unavailable', pipelineSamples().length ? nf.format(pipelineSamples().length) + ' phase-timestamp samples' : 'Raw phase timestamps unavailable'],
      ['VM timeline', r.source === 'vm' && events().length ? 'available' : 'unavailable', r.source === 'vm' && events().length ? nf.format(events().length) + ' retained events' : (r.source || 'Timeline not collected')],
      ['Raster cache', frames().length ? 'available' : 'unavailable', frames().length ? 'Layer/picture counts and bytes' : 'Requires retained frame samples'],
      ['GC events', s.gc ? 'available' : 'unavailable', s.gc ? nf.format(number(s.gc.new) + number(s.gc.old)) + ' collection events · pause p90 ' + (gcStats().p90 == null ? 'unavailable' : us(gcStats().p90)) : 'No GC stream in this capture'],
      ['Process memory', mem && mem.samples && mem.samples.length ? 'available' : 'unavailable', mem && mem.samples && mem.samples.length ? nf.format(mem.samples.length) + ' RSS samples' : 'Native RSS unavailable'],
      ['Cold start', startup ? 'available' : 'unavailable', startup ? 'Build, first frame, ready' : 'No startup harness supplied'],
      ['Jank attribution', frames().length && events().length ? 'available' : 'unavailable', frames().length && events().length ? 'Slow frames matched to overlapping VM spans' : 'Requires retained frames and VM events'],
      ['Operation hotspots', events().length ? 'available' : 'unavailable', events().length ? nf.format(hotspotRows().length) + ' event operations aggregated' : 'Requires retained VM events'],
      ['CPU sampling', d && d.cpu ? 'available' : 'unavailable', d && d.cpu ? nf.format(number(d.cpu.n)) + ' VM samples' : (d && d.why ? d.why : 'CPU profiler unavailable')],
      ['Heap profile', d && d.heap ? 'available' : 'unavailable', d && d.heap ? nf.format((d.heap.classes || []).length) + ' allocation classes' : (d && d.why ? d.why : 'Dart heap profile unavailable')],
      ['Heap trend', d && d.heap && Array.isArray(d.heap.samples) && d.heap.samples.length ? 'available' : 'unavailable', d && d.heap && Array.isArray(d.heap.samples) && d.heap.samples.length ? nf.format(d.heap.samples.length) + ' VM heap samples' : 'No retained VM heap samples'],
      ['Isolate group memory', d && d.heap && d.heap.gb && d.heap.ga ? 'available' : 'unavailable', d && d.heap && d.heap.gb && d.heap.ga ? 'Group heap before/after points' : 'Group memory usage unavailable'],
      ['Allocation trace', d && Array.isArray(d.alloc) && d.alloc.length ? 'available' : 'unavailable', d && Array.isArray(d.alloc) && d.alloc.length ? nf.format(d.alloc.length) + ' selected class call stacks' : 'Pass allocationClassIds to trace selected classes'],
      ['VM runtime', d && d.vm ? 'available' : 'unavailable', d && d.vm ? 'VM identity, CPU target, and isolate inventory' : 'No VM runtime metadata retained'],
      ['Isolate health', d && d.isolate ? 'available' : 'unavailable', d && d.isolate ? 'Before/after lifecycle and pause state' : 'No isolate snapshot retained'],
      ['VM logs', d && (Array.isArray(d.log) && d.log.length || d.dropLog) ? 'available' : 'unavailable', d && (Array.isArray(d.log) && d.log.length || d.dropLog) ? nf.format((d.log || []).length) + ' logging events' + (d.dropLog ? ' · ' + nf.format(number(d.dropLog)) + ' dropped' : '') : 'VM Logging stream unavailable'],
      ['VM debug events', d && (Array.isArray(d.dbg) && d.dbg.length || d.dropDbg) ? 'available' : 'unavailable', d && (Array.isArray(d.dbg) && d.dbg.length || d.dropDbg) ? nf.format((d.dbg || []).length) + ' pause/debug events' + (d.dropDbg ? ' · ' + nf.format(number(d.dropDbg)) + ' dropped' : '') : 'VM Debug stream unavailable'],
      ['Timeline streams', d && d.timeline ? 'available' : 'unavailable', d && d.timeline ? nf.format((d.timeline.recorded || []).length) + ' recorded / ' + nf.format((d.timeline.available || []).length) + ' available streams' : 'Timeline recorder metadata unavailable'],
      ['Display refresh', d && d.display && d.display.hz != null ? 'available' : 'unavailable', d && d.display && d.display.hz != null ? Number(d.display.hz).toFixed(1) + ' Hz · budget ' + us(number(d.display.bud)) : 'Engine refresh-rate extension unavailable'],
      ['Widget rebuilds', d && d.rebuild ? 'available' : 'unavailable', d && d.rebuild ? nf.format((d.rebuild.frames || []).length) + ' frames · ' + nf.format((d.rebuild.tot || []).length) + ' locations' : 'Set trackRebuilds: true for DevTools rebuild events'],
      ['VM process memory', d && d.vmem && (d.vmem.before || d.vmem.after) ? 'available' : 'unavailable', d && d.vmem && (d.vmem.before || d.vmem.after) ? 'Before/after retained memory tree' : 'VM process memory usage unavailable'],
      ['Network profiler', 'not-collected', 'Use Cockpit network evidence for HTTP/SSE/WebSocket traffic'],
      ['GPU/shader', d && d.gpu ? 'available' : 'unavailable', d && d.gpu ? nf.format(number(d.gpu.events)) + ' timeline signals' : 'No matching GPU or shader timeline events'],
      ['Perfetto export', d && d.perfetto && ((d.perfetto.cpu && d.perfetto.cpu.data) || (d.perfetto.timeline && d.perfetto.timeline.data)) ? 'available' : 'unavailable', d && d.perfetto && ((d.perfetto.cpu && d.perfetto.cpu.data) || (d.perfetto.timeline && d.perfetto.timeline.data)) ? 'Raw CPU/timeline proto traces retained' : 'Set perfetto: true for an exact trace artifact'],
    ];
    rows.forEach(function (row) { if (row[1] === 'available') available += 1; });
    el('coverage-summary').textContent = available + ' of ' + rows.length + ' views backed by this capture';
    el('coverage-grid').innerHTML = rows.map(function (row) { var label = row[1] === 'available' ? 'Available' : row[1] === 'not-collected' ? 'Not collected' : 'Unavailable'; return '<div class="coverage-card"><div class="coverage-card-head"><strong>' + esc(row[0]) + '</strong><span class="coverage-state ' + esc(row[1]) + '">' + esc(label) + '</span></div><p>' + esc(row[2]) + '</p></div>'; }).join('');
  };
  var drawCpuChart = function () {
    setChartHeight('cpu-chart', 170);
    draw(el('cpu-chart'), function (ctx, width, height) {
      chartHits['cpu-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var cpu = report().devtools && report().devtools.cpu; var functions = cpu && Array.isArray(cpu.f) ? cpu.f.slice().sort(function (a, b) { return number(b.in) - number(a.in); }).slice(0, 8) : [];
      if (!functions.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('No CPU samples retained', 14, height / 2); return; }
      var max = Math.max(1, functions.reduce(function (m, item) { return Math.max(m, number(item.in)); }, 0)); var left = 112; var right = 48; var top = 10; var rowH = Math.max(17, (height - top - 18) / functions.length); ctx.font = '10px system-ui, sans-serif';
      functions.forEach(function (fn, index) { var y = top + index * rowH; var label = String(fn.n || '<anonymous>'); ctx.fillStyle = css('--muted'); ctx.fillText(label.length > 17 ? label.slice(0, 16) + '…' : label, 8, y + 12); ctx.fillStyle = css('--surface-3'); ctx.fillRect(left, y + 2, width - left - right, 10); ctx.fillStyle = hashColor(label); var barW = number(fn.in) / max * (width - left - right); ctx.fillRect(left, y + 2, barW, 10); ctx.fillStyle = css('--text-soft'); ctx.fillText(nf.format(number(fn.in)), width - right + 6, y + 12); chartHits['cpu-chart'].push({ x: left, y: y, w: width - left - right, h: 14, html: '<strong>' + esc(label) + '</strong>' + tooltipRow('Inclusive ticks', nf.format(number(fn.in))) + tooltipRow('Exclusive ticks', nf.format(number(fn.ex))) + tooltipRow('URI', fn.u || '—') }); });
      ctx.fillStyle = css('--muted'); ctx.fillText('Top sampled functions · inclusive ticks', 8, height - 6);
    });
  };
  var drawHeapChart = function () {
    setChartHeight('heap-chart', 150);
    draw(el('heap-chart'), function (ctx, width, height) {
      chartHits['heap-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var heap = report().devtools && report().devtools.heap; if (!heap || !heap.before || !heap.after) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('Heap profile unavailable', 14, height / 2); return; }
      var points = [['Before', heap.before], ['After', heap.after]]; var max = Math.max(1, number(heap.before.cap), number(heap.after.cap)) * 1.08; var left = 58; var right = 18; var top = 16; var plotW = width - left - right; var groupW = plotW / points.length; var colors = [css('--accent'), css('--blue'), css('--warning')]; ctx.font = '10px system-ui, sans-serif';
      for (var i = 0; i <= 3; i += 1) { var y = top + (height - top - 24) * i / 3; ctx.strokeStyle = css('--line'); ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(width - right, y); ctx.stroke(); ctx.fillStyle = css('--muted'); ctx.fillText(bytes(Math.round(max * (1 - i / 3))), 5, y + 3); }
      points.forEach(function (point, index) { var x = left + index * groupW + groupW * .24; var barW = groupW * .52; var values = [number(point[1].use), number(point[1].cap), number(point[1].ext)]; values.forEach(function (value, series) { var w = barW / 3 - 3; var bx = x + series * (barW / 3); var bh = value / max * (height - top - 24); ctx.fillStyle = colors[series]; ctx.globalAlpha = .88; ctx.fillRect(bx, height - 24 - bh, w, bh); ctx.globalAlpha = 1; chartHits['heap-chart'].push({ x: bx, y: height - 24 - bh, w: w, h: Math.max(8, bh), html: '<strong>' + esc(point[0]) + '</strong>' + tooltipRow(series === 0 ? 'Used' : series === 1 ? 'Capacity' : 'External', bytes(value)) }); }); ctx.fillStyle = css('--text-soft'); ctx.fillText(point[0], x + barW / 2 - 17, height - 8); });
    });
  };
  var drawHeapTrendChart = function () {
    setChartHeight('heap-trend-chart', 210);
    draw(el('heap-trend-chart'), function (ctx, width, height) {
      chartHits['heap-trend-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var heap = report().devtools && report().devtools.heap;
      var samples = heap && Array.isArray(heap.samples) ? heap.samples : [];
      if (!samples.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('No VM heap samples retained', 14, height / 2); return; }
      var first = number(samples[0].t); var last = number(samples[samples.length - 1].t); var span = Math.max(1, last - first);
      var max = Math.max(1, samples.reduce(function (m, item) { return Math.max(m, number(item.cap), number(item.use), number(item.ext)); }, 0)) * 1.08;
      var left = 54, right = 18, top = 18, bottom = 28, plotW = width - left - right, plotH = height - top - bottom;
      ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif';
      for (var i = 0; i <= 4; i += 1) { var y = top + plotH * i / 4; ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(width - right, y); ctx.stroke(); ctx.fillText(bytes(Math.round(max * (1 - i / 4))), 5, y + 3); }
      var series = [['use', css('--accent'), 'Used'], ['cap', css('--blue'), 'Capacity'], ['ext', css('--warning'), 'External']];
      series.forEach(function (item) { ctx.strokeStyle = item[1]; ctx.lineWidth = item[0] === 'use' ? 2.2 : 1.2; ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.beginPath(); samples.forEach(function (sample, index) { var x = left + (number(sample.t) - first) / span * plotW; var y = top + plotH * (1 - number(sample[item[0]]) / max); if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); }); ctx.stroke(); });
      var stride = Math.max(1, Math.ceil(samples.length / Math.max(1, Math.floor(plotW))));
      samples.forEach(function (sample, index) { if (index % stride !== 0) return; var x = left + (number(sample.t) - first) / span * plotW; chartHits['heap-trend-chart'].push({ x: x - 7, y: top, w: 14, h: plotH, html: '<strong>VM heap sample</strong>' + tooltipRow('Elapsed', duration(number(sample.t) / 1000)) + tooltipRow('Used', bytes(sample.use)) + tooltipRow('Capacity', bytes(sample.cap)) + tooltipRow('External', bytes(sample.ext)) }); });
      ctx.fillStyle = css('--muted'); ctx.fillText('Used', left, height - 8); ctx.fillText(nf.format(samples.length) + ' samples · ' + duration(last / 1000), Math.max(left + 30, width - 178), height - 8);
    });
  };
  var drawVmMemoryChart = function () {
    setChartHeight('vm-memory-chart', 190);
    draw(el('vm-memory-chart'), function (ctx, width, height) {
      chartHits['vm-memory-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var profile = report().devtools && report().devtools.vmem;
      var points = [];
      if (profile && profile.before && profile.before.root) points.push(['Before', profile.before]);
      if (profile && profile.after && profile.after.root) points.push(['After', profile.after]);
      if (!points.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('VM process memory unavailable', 14, height / 2); return; }
      var max = Math.max(1, points.reduce(function (value, point) { return Math.max(value, number(point[1].root.s)); }, 0)) * 1.1;
      var left = 74, right = 84, top = 18, bottom = 28, plotW = width - left - right, plotH = height - top - bottom;
      ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif';
      for (var i = 0; i <= 3; i += 1) { var y = top + plotH * i / 3; ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(width - right, y); ctx.stroke(); ctx.fillText(bytes(Math.round(max * (1 - i / 3))), 5, y + 3); }
      points.forEach(function (point, index) {
        var rootNode = point[1].root; var y = top + index * Math.max(38, plotH / points.length); var barH = Math.min(20, plotH / points.length * .48); var barW = number(rootNode.s) / max * plotW;
        ctx.fillStyle = css('--muted'); ctx.fillText(point[0], 8, y + 14); ctx.fillStyle = css('--surface-3'); ctx.fillRect(left, y + 2, plotW, barH); ctx.fillStyle = index === 0 ? css('--accent') : css('--blue'); ctx.fillRect(left, y + 2, Math.max(rootNode.s ? 3 : 0, barW), barH); ctx.fillStyle = css('--text-soft'); ctx.fillText(bytes(rootNode.s), width - right + 6, y + 15);
        var children = Array.isArray(rootNode.c) ? rootNode.c.slice(0, 5) : [];
        chartHits['vm-memory-chart'].push({ x: left, y: y, w: plotW, h: Math.max(22, barH + 6), html: '<strong>' + esc(point[0]) + ' · ' + esc(rootNode.n || 'process') + '</strong>' + tooltipRow('Retained', bytes(rootNode.s)) + tooltipRow('Top buckets', children.length ? children.map(function (child) { return String(child.n || 'bucket') + ' ' + bytes(child.s); }).join(' · ') : 'Unavailable') + (rootNode.drop ? '<div class="subtle">Dropped children: ' + esc(nf.format(number(rootNode.drop))) + '</div>' : '') + tooltipRow('Timestamp', duration(number(point[1].t) / 1000)) });
      });
      ctx.fillStyle = css('--muted'); ctx.fillText('Retained process memory · before / after', left, height - 8);
    });
  };
  var drawRebuildChart = function () {
    setChartHeight('rebuild-chart', 190);
    draw(el('rebuild-chart'), function (ctx, width, height) {
      chartHits['rebuild-chart'] = [];
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var rebuild = report().devtools && report().devtools.rebuild;
      var list = rebuild && Array.isArray(rebuild.frames) ? rebuild.frames : [];
      if (!list.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('Widget rebuild tracking was not collected', 14, height / 2); return; }
      var points = list.map(function (frame) { var entries = Array.isArray(frame.e) ? frame.e : []; var count = 0; for (var index = 1; index < entries.length; index += 2) count += number(entries[index]); return { frame: frame, count: count }; });
      var max = Math.max(1, points.reduce(function (value, item) { return Math.max(value, item.count); }, 0)); var left = 52, right = 18, top = 18, bottom = 28, plotW = width - left - right, plotH = height - top - bottom;
      ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif';
      for (var i = 0; i <= 4; i += 1) { var y = top + plotH * i / 4; ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(width - right, y); ctx.stroke(); ctx.fillText(nf.format(Math.round(max * (1 - i / 4))), 8, y + 3); }
      var stride = Math.max(1, Math.ceil(points.length / Math.max(1, Math.floor(plotW)))); var sample = points.filter(function (_, index) { return index % stride === 0; });
      ctx.strokeStyle = css('--accent'); ctx.lineWidth = 2.2; ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.beginPath(); sample.forEach(function (item, index) { var x = left + (sample.length === 1 ? .5 : index / (sample.length - 1)) * plotW; var y = top + plotH * (1 - item.count / max); if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); chartHits['rebuild-chart'].push({ x: x - 7, y: top, w: 14, h: plotH, html: '<strong>Frame ' + esc(number(item.frame.n)) + '</strong>' + tooltipRow('Rebuilds', nf.format(item.count)) + tooltipRow('Locations', nf.format((item.frame.e || []).length / 2)) }); }); ctx.stroke();
      ctx.fillStyle = css('--muted'); ctx.fillText('Rebuilds per frame', left, height - 8); ctx.fillText(nf.format(points.length) + ' frames', Math.max(left + 80, width - 92), height - 8);
    });
  };
  var renderDevTools = function () {
    var d = report().devtools || null;
    var cpu = d && d.cpu ? d.cpu : null;
    var heap = d && d.heap ? d.heap : null;
    var gpu = d && d.gpu ? d.gpu : null;
    var isolate = d && d.isolate ? d.isolate : null;
    var timeline = d && d.timeline ? d.timeline : null;
    var display = d && d.display ? d.display : null;
    var rebuild = d && d.rebuild ? d.rebuild : null;
    var vmRuntime = d && d.vm ? d.vm : null;
    var vmMemory = d && d.vmem ? d.vmem : null;
    var logs = d && Array.isArray(d.log) ? d.log : [];
    var debugEvents = d && Array.isArray(d.dbg) ? d.dbg : [];
    var allocations = d && Array.isArray(d.alloc) ? d.alloc : [];
    var perfetto = d && d.perfetto ? d.perfetto : null;
    el('cpu-note').textContent = cpu ? nf.format(number(cpu.n)) + ' samples · ' + us(number(cpu.span)) + (cpu.period ? ' · ' + us(number(cpu.period)) + ' period' : '') : (d && d.why ? 'Unavailable' : 'Not collected');
    var functions = cpu && Array.isArray(cpu.f) ? cpu.f.slice().sort(function (a, b) { return number(b.in) - number(a.in); }).slice(0, 12) : [];
    el('cpu-list').innerHTML = functions.length ? functions.map(function (fn) { return '<div class="devtools-row"><strong title="' + esc(fn.n || '') + '">' + esc(fn.n || '<anonymous>') + '</strong><span>' + nf.format(number(fn.in)) + ' ticks · ' + nf.format(number(fn.ex)) + ' self</span></div>'; }).join('') : '<p class="devtools-note">' + esc(cpu ? 'No samples retained.' : (d && d.why ? d.why : 'CPU sampling was unavailable for this run.')) + '</p>';
    el('heap-note').textContent = heap ? bytes(number(heap.after && heap.after.use)) + ' used · ' + bytes(number(heap.after && heap.after.ext)) + ' external' + (heap.samples && heap.samples.length ? ' · ' + nf.format(heap.samples.length) + ' samples' : '') + (heap.ga ? ' · group tracked' : '') + (allocations.length ? ' · ' + nf.format(allocations.length) + ' traces' : '') : (d && d.why ? 'Unavailable' : 'Not collected');
    var classes = heap && Array.isArray(heap.classes) ? heap.classes.slice(0, 12) : [];
    var classRows = classes.map(function (item) { return '<div class="devtools-row"><strong title="' + esc(item.n || '') + '">' + esc(item.n || '<unknown>') + '</strong><span>' + bytes(number(item.bytes)) + ' · ' + nf.format(number(item.count)) + ' objs</span></div>'; });
    var allocationRows = allocations.map(function (item) { var trace = item.trace || {}; return '<div class="devtools-row"><strong title="' + esc(item.name || item.id || '') + '">' + esc(item.name || item.id || '<unknown>') + '</strong><span>' + nf.format(number(trace.n)) + ' allocation samples</span></div>'; });
    el('heap-list').innerHTML = classRows.concat(allocationRows).join('') || '<p class="devtools-note">' + esc(heap ? 'No allocation classes retained.' : (d && d.why ? d.why : 'Dart heap profiling was unavailable for this run.')) + '</p>';
    el('gpu-note').textContent = gpu ? nf.format(number(gpu.events)) + ' signals · ' + us(number(gpu.time)) : 'No matching timeline signals';
    el('gpu-list').innerHTML = gpu ? '<div class="devtools-row"><strong>GPU / raster / Skia</strong><span>' + nf.format(number(gpu.events)) + ' events</span></div><div class="devtools-row"><strong>Shader signals</strong><span>' + nf.format(number(gpu.shaders)) + ' events</span></div><div class="devtools-row"><strong>Observed duration</strong><span>' + esc(us(gpu.time)) + '</span></div>' : '<p class="devtools-note">GPU counters are platform-specific. Cockpit reports only real matching VM timeline events.</p>';
    var rebuildFrames = rebuild && Array.isArray(rebuild.frames) ? rebuild.frames : [];
    var rebuildTotals = rebuild && Array.isArray(rebuild.tot) ? rebuild.tot : [];
    var rebuildLocations = {};
    if (rebuild && Array.isArray(rebuild.loc)) rebuild.loc.forEach(function (item) { if (item && item.id != null) rebuildLocations[String(item.id)] = item; });
    el('rebuild-note').textContent = rebuild ? nf.format(rebuildFrames.length) + ' frames · ' + nf.format(rebuildTotals.length) + ' widgets' + (rebuild.unknown ? ' · ' + nf.format(number(rebuild.unknown)) + ' unresolved' : '') : 'Not collected';
    el('rebuild-list').innerHTML = rebuildTotals.length ? rebuildTotals.slice(0, 10).map(function (item) { var location = rebuildLocations[String(item.id)] || {}; var label = location.n || location.u || ('location ' + item.id); if (location.u && location.l != null) label += ':' + location.l; return '<div class="devtools-row"><strong title="' + esc(label) + '">' + esc(label) + '</strong><span>' + nf.format(number(item.n)) + ' rebuilds</span></div>'; }).join('') : '<p class="devtools-note">Enable trackRebuilds to collect Flutter.RebuiltWidgets events.</p>';
    var after = isolate && isolate.after ? isolate.after : isolate && isolate.before ? isolate.before : null;
    var beforeAll = isolate && Array.isArray(isolate.allB) ? isolate.allB : [];
    var afterAll = isolate && Array.isArray(isolate.allA) ? isolate.allA : [];
    var beforeIds = {};
    beforeAll.forEach(function (item) { if (item && item.id) beforeIds[String(item.id)] = true; });
    var afterIds = {};
    afterAll.forEach(function (item) { if (item && item.id) afterIds[String(item.id)] = true; });
    var startedIsolates = afterAll.filter(function (item) { return item && item.id && !beforeIds[String(item.id)]; }).length;
    var stoppedIsolates = beforeAll.filter(function (item) { return item && item.id && !afterIds[String(item.id)]; }).length;
    el('vm-note').textContent = after ? (after.run === false ? 'paused' : 'runnable') + (timeline ? ' · ' + (timeline.recorder || 'unknown recorder') : '') + (display && display.hz != null ? ' · ' + Number(display.hz).toFixed(1) + ' Hz' : '') : 'VM metadata unavailable';
    var vmRows = [];
    if (vmRuntime) {
      if (vmRuntime.name || vmRuntime.ver) vmRows.push(['VM', (vmRuntime.name || 'VM') + (vmRuntime.ver ? ' · ' + vmRuntime.ver : '')]);
      if (vmRuntime.os) vmRows.push(['OS', vmRuntime.os]);
      if (vmRuntime.host || vmRuntime.target) vmRows.push(['CPU', (vmRuntime.host || '—') + ' → ' + (vmRuntime.target || '—')]);
      if (vmRuntime.arch != null) vmRows.push(['Word size', nf.format(number(vmRuntime.arch)) + '-bit']);
      if (vmRuntime.pid != null) vmRows.push(['VM pid', nf.format(number(vmRuntime.pid))]);
      if (vmRuntime.isolates != null) vmRows.push(['Isolates', nf.format(number(vmRuntime.isolates))]);
      if (vmRuntime.groups != null) vmRows.push(['Isolate groups', nf.format(number(vmRuntime.groups))]);
      if (vmRuntime.sys != null) vmRows.push(['System isolates', nf.format(number(vmRuntime.sys))]);
      if (vmRuntime.start != null) vmRows.push(['VM started', dateText(vmRuntime.start)]);
    }
    if (beforeAll.length || afterAll.length) vmRows.push(['Isolate snapshots', nf.format(beforeAll.length) + ' before / ' + nf.format(afterAll.length) + ' after']);
    if (startedIsolates || stoppedIsolates) vmRows.push(['Isolate changes', '+' + nf.format(startedIsolates) + ' started / −' + nf.format(stoppedIsolates) + ' stopped']);
    if (isolate && (isolate.dropB || isolate.dropA)) vmRows.push(['Isolate snapshot drops', nf.format(number(isolate.dropB)) + ' before / ' + nf.format(number(isolate.dropA)) + ' after']);
    if (after) { vmRows.push(['Isolate', (after.name || 'isolate') + (after.id ? ' · ' + after.id : '')]); if (after.group) vmRows.push(['Group', after.group]); if (after.run != null) vmRows.push(['Runnable', after.run ? 'yes' : 'no']); if (after.ports != null) vmRows.push(['Live ports', nf.format(number(after.ports))]); if (after.libs != null) vmRows.push(['Libraries', nf.format(number(after.libs))]); if (after.ext != null) vmRows.push(['Extensions', nf.format(number(after.ext))]); if (after.start != null) vmRows.push(['Started', dateText(after.start)]); if (after.pause) vmRows.push(['Pause state', after.pause]); if (after.exit != null) vmRows.push(['Pause on exit', after.exit ? 'yes' : 'no']); if (after.ex) vmRows.push(['Exception pause', after.ex]); if (after.root) vmRows.push(['Root library', after.root]); if (after.error) vmRows.push(['Error', after.error]); }
    if (timeline) { vmRows.push(['Recorder', timeline.recorder || 'unknown']); vmRows.push(['Streams', nf.format((timeline.recorded || []).length) + ' recorded / ' + nf.format((timeline.available || []).length) + ' available']); }
    if (logs.length || (d && d.dropLog)) vmRows.push(['VM logs', nf.format(logs.length) + (d.dropLog ? ' retained · ' + nf.format(number(d.dropLog)) + ' dropped' : ' events')]);
    if (debugEvents.length || (d && d.dropDbg)) vmRows.push(['Debug events', nf.format(debugEvents.length) + (d.dropDbg ? ' retained · ' + nf.format(number(d.dropDbg)) + ' dropped' : ' events')]);
    if (heap && heap.drop) vmRows.push(['Heap sample drops', nf.format(number(heap.drop))]);
    el('vm-list').innerHTML = vmRows.length ? vmRows.map(function (row) { return '<div class="devtools-row"><strong>' + esc(row[0]) + '</strong><span title="' + esc(row[1]) + '">' + esc(row[1]) + '</span></div>'; }).join('') : '<p class="devtools-note">VM runtime metadata was unavailable for this capture.</p>';
    var memoryPoints = [];
    if (vmMemory && vmMemory.before && vmMemory.before.root) memoryPoints.push(['Before', vmMemory.before.root]);
    if (vmMemory && vmMemory.after && vmMemory.after.root) memoryPoints.push(['After', vmMemory.after.root]);
    var memoryRoot = memoryPoints.length ? memoryPoints[memoryPoints.length - 1][1] : null;
    var memoryRows = memoryRoot && Array.isArray(memoryRoot.c) ? memoryRoot.c.slice(0, 8) : [];
    el('vm-memory-note').textContent = memoryPoints.length ? memoryPoints.map(function (point) { return point[0] + ' ' + bytes(point[1].s); }).join(' · ') : 'VM process memory unavailable';
    el('vm-memory-list').innerHTML = memoryRows.length ? '<div class="devtools-row"><strong>' + esc(memoryRoot.n || 'process') + '</strong><span>' + esc(bytes(memoryRoot.s)) + '</span></div>' + memoryRows.map(function (item) { return '<div class="devtools-row"><strong title="' + esc(item.n || '') + '">' + esc(item.n || 'bucket') + '</strong><span>' + esc(bytes(item.s)) + '</span></div>'; }).join('') + (memoryRoot.drop ? '<p class="devtools-note">' + esc(nf.format(number(memoryRoot.drop))) + ' child buckets omitted; Details contains the retained tree.</p>' : '') : '<p class="devtools-note">VM process memory was unavailable for this run.</p>';
    var perfettoButton = el('perfetto-button');
    var hasPerfetto = !!(perfetto && ((perfetto.cpu && perfetto.cpu.data) || (perfetto.timeline && perfetto.timeline.data)));
    perfettoButton.classList.toggle('hidden', !hasPerfetto);
    perfettoButton.title = hasPerfetto ? 'Download exact VM Perfetto traces' : '';
  };
  var renderEventSummary = function () {
    var list = events(); var start = list.reduce(function (m, e) { return Math.min(m, number(e.t)); }, Infinity); var finish = list.reduce(function (m, e) { return Math.max(m, number(e.t) + number(e.d)); }, -Infinity); var traceSpan = list.length ? Math.max(0, finish - start) : 0; var categories = {}; list.forEach(function (e) { var key = String(e.c || 'uncategorized'); categories[key] = (categories[key] || 0) + 1; }); var top = Object.keys(categories).sort(function (a, b) { return categories[b] - categories[a]; })[0];
    el('event-summary').innerHTML = '<div class="event-stat"><span>Retained</span><strong>' + nf.format(list.length) + '</strong></div><div class="event-stat"><span>Categories</span><strong>' + nf.format(Object.keys(categories).length) + '</strong></div><div class="event-stat"><span>Trace span</span><strong>' + (list.length ? (traceSpan ? esc(us(traceSpan)) : 'Instant') : 'Unavailable') + '</strong></div>';
    var max = top ? categories[top] : 1; el('category-list').innerHTML = Object.keys(categories).sort(function (a, b) { return categories[b] - categories[a]; }).slice(0, 6).map(function (key) { return '<div class="category-row"><span title="' + esc(key) + '">' + esc(key) + '</span><div class="category-track"><span style="width:' + Math.max(4, categories[key] / max * 100) + '%;background:' + hashColor(key) + '"></span></div><span>' + nf.format(categories[key]) + '</span></div>'; }).join('') || '<div class="empty">No categories retained.</div>';
  };
  var sourceLabel = function (value) {
    var found = {};
    var visit = function (item) {
      if (!item || typeof item !== 'object') return;
      Object.keys(item).forEach(function (key) {
        var lower = key.toLowerCase(); var child = item[key];
        if (['url', 'uri', 'file', 'filepath', 'script', 'source'].indexOf(lower) >= 0 && (typeof child === 'string' || typeof child === 'number')) found.location = String(child);
        if (['function', 'functionname', 'method', 'symbol', 'library', 'class'].indexOf(lower) >= 0 && (typeof child === 'string' || typeof child === 'number')) found.symbol = String(child);
        if (lower === 'line' && (typeof child === 'string' || typeof child === 'number')) found.line = String(child);
        if (child && typeof child === 'object') visit(child);
      });
    };
    visit(value);
    var label = found.location || (found.symbol ? 'function ' + found.symbol : '');
    if (found.line && found.location) label += ':' + found.line;
    if (found.symbol && found.location) label += ' · ' + found.symbol;
    return label.length > 180 ? label.slice(0, 177) + '…' : label;
  };
  var stallAnalysis = function () {
    var budget = number(summary().total && summary().total.bud);
    if (!budget) budget = number(summary().build && summary().build.bud);
    return frames().filter(function (frame) { return number(frame.s) > budget; }).map(function (frame) {
      var start = number(frame.t); var end = start + number(frame.s);
      var evidence = events().map(function (event) {
        var eventStart = number(event.t); var eventDuration = Math.max(0, number(event.d)); var eventEnd = eventStart + eventDuration;
        var overlap = eventDuration > 0 ? Math.min(end, eventEnd) - Math.max(start, eventStart) : 0;
        if (overlap <= 0 && !(eventDuration === 0 && eventStart >= start && eventStart <= end)) return null;
        return { event: event, overlap: Math.max(0, overlap), source: sourceLabel(event.a) };
      }).filter(function (item) { return item != null; }).sort(function (a, b) { return b.overlap - a.overlap || number(b.event.d) - number(a.event.d); });
      return { frame: frame, over: number(frame.s) - budget, evidence: evidence.slice(0, 3), budget: budget };
    });
  };
  var renderStalls = function () {
    var rows = stallAnalysis(); var attributed = rows.filter(function (row) { return row.evidence.some(function (item) { return item.overlap > 0; }); }).length; var categories = {};
    rows.forEach(function (row) { row.evidence.forEach(function (item) { if (item.overlap > 0) { var category = String(item.event.c || 'uncategorized'); categories[category] = (categories[category] || 0) + item.overlap; } }); });
    var topCategory = Object.keys(categories).sort(function (a, b) { return categories[b] - categories[a]; })[0];
    el('stall-note').textContent = rows.length ? (attributed + ' of ' + rows.length + ' jank frames have overlapping retained spans') : 'No over-budget frames';
    el('stall-summary').innerHTML = '<div class="stall-pill"><strong>' + nf.format(rows.length) + '</strong><br>Jank frames</div><div class="stall-pill"><strong>' + nf.format(attributed) + '</strong><br>With timing evidence</div><div class="stall-pill"><strong>' + esc(topCategory || 'Unavailable') + '</strong><br>Top observed category</div>';
    el('stall-body').innerHTML = rows.length ? rows.map(function (row) {
      var evidence = row.evidence.length ? '<div class="stall-evidence">' + row.evidence.map(function (item) { var event = item.event; return '<div><code>' + esc(event.c || 'uncategorized') + ' · ' + esc(event.n || 'Unnamed event') + '</code><span>' + esc(item.overlap > 0 ? 'overlap ' + us(item.overlap) + ' · span ' + us(event.d) : 'instant marker') + '</span></div>'; }).join('') + '</div>' : '<span class="subtle">No overlapping retained span</span>';
      var source = row.evidence.map(function (item) { return item.source; }).filter(function (value) { return value; })[0] || 'Unavailable';
      return '<tr><td><strong>#' + esc(number(row.frame.i)) + '</strong></td><td class="bad">+' + esc(us(row.over)) + '</td><td>' + esc(us(row.frame.s)) + '</td><td>' + evidence + '</td><td><code>' + esc(source) + '</code></td></tr>';
    }).join('') : '<tr><td colspan="5"><div class="empty">No retained frame exceeded the display budget.</div></td></tr>';
  };
  var renderResources = function () {
    var s = summary(); var mem = memory(); var m = mem && mem.summary ? mem.summary : null; var hasFrames = frames().length > 0; var layer = hasFrames ? (s.layerCache || {}) : {}; var picture = hasFrames ? (s.pictureCache || {}) : {}; var gc = s.gc || {};
    var cells = m ? [['RSS start', bytes(m.start)], ['RSS end', bytes(m.end)], ['RSS min', bytes(m.min)], ['RSS avg', bytes(m.avg)], ['RSS peak', bytes(m.peak)], ['RSS Δ', bytes(m.delta)], ['Samples', nf.format(number(m.n))], ['Source', mem.source || 'unavailable']] : [['RSS', 'Unavailable'], ['Layer cache', layer.bytes == null ? 'Unavailable' : bytes(layer.bytes)], ['Picture cache', picture.bytes == null ? 'Unavailable' : bytes(picture.bytes)], ['Layer count', layer.count == null ? 'Unavailable' : nf.format(number(layer.count))], ['Picture count', picture.count == null ? 'Unavailable' : nf.format(number(picture.count))], ['GC cycles', s.gc ? nf.format(number(gc.new) + number(gc.old)) : 'Unavailable']];
    el('resource-summary').innerHTML = cells.map(function (cell) { return '<div><span>' + esc(cell[0]) + '</span><strong>' + esc(cell[1]) + '</strong></div>'; }).join('');
    var gcProfile = gcStats();
    var cache = [['Layer cache', layer.bytes == null ? 'Unavailable' : bytes(layer.bytes)], ['Picture cache', picture.bytes == null ? 'Unavailable' : bytes(picture.bytes)], ['Layer count', layer.count == null ? 'Unavailable' : nf.format(number(layer.count))], ['Picture count', picture.count == null ? 'Unavailable' : nf.format(number(picture.count))], ['New GC', gc.new == null ? 'Unavailable' : nf.format(number(gc.new))], ['Old GC', gc.old == null ? 'Unavailable' : nf.format(number(gc.old))], ['GC pause total', gcProfile.timed ? us(gcProfile.total) : 'Unavailable'], ['GC pause p90', gcProfile.p90 == null ? 'Unavailable' : us(gcProfile.p90)], ['GC pause max', gcProfile.max == null ? 'Unavailable' : us(gcProfile.max)]];
    el('cache-summary').innerHTML = cache.map(function (cell) { return '<div><span>' + esc(cell[0]) + '</span><strong>' + esc(cell[1]) + '</strong></div>'; }).join('');
    var list = frames(); var budget = number(s.build && s.build.bud); var within = list.filter(function (frame) { return number(frame.s) <= budget; }).length; var jank = list.length - within;
    el('jank-summary').innerHTML = [['Within budget', nf.format(within)], ['Jank frames', nf.format(jank)], ['Jank rate', list.length ? (jank / list.length * 100).toFixed(1) + '%' : '—']].map(function (cell) { return '<div><span>' + esc(cell[0]) + '</span><strong>' + esc(cell[1]) + '</strong></div>'; }).join('');
  };
  var codeEvidence = function () {
    var grouped = {};
    var sourceKeys = ['url', 'uri', 'file', 'filepath', 'script', 'source', 'function', 'functionname', 'method', 'symbol', 'library', 'class'];
    var visit = function (value, result) {
      if (!value || typeof value !== 'object') return;
      Object.keys(value).forEach(function (key) {
        var lower = key.toLowerCase(); var item = value[key];
        if (sourceKeys.indexOf(lower) >= 0 && (typeof item === 'string' || typeof item === 'number')) result[lower] = String(item);
        if (lower === 'line' && (typeof item === 'string' || typeof item === 'number')) result.line = String(item);
        if (item && typeof item === 'object') visit(item, result);
      });
    };
    events().forEach(function (event) {
      var found = {}; visit(event.a, found); var location = found.url || found.uri || found.file || found.filepath || found.script || found.source; var symbol = found.function || found.functionname || found.method || found.symbol || found.library || found.class;
      if (!location && !symbol) return;
      var label = location || ('function ' + symbol); if (found.line && location) label += ':' + found.line; if (symbol && location) label += ' · ' + symbol; if (label.length > 180) label = label.slice(0, 177) + '…';
      var entry = grouped[label] || { count: 0, total: 0, longest: 0, categories: {} }; entry.count += 1; entry.total += number(event.d); entry.longest = Math.max(entry.longest, number(event.d)); entry.categories[String(event.c || 'uncategorized')] = true; grouped[label] = entry;
    });
    return Object.keys(grouped).map(function (label) { return { label: label, value: grouped[label] }; }).sort(function (a, b) { return b.value.total - a.value.total || b.value.count - a.value.count; });
  };
  var renderCodeEvidence = function () {
    var rows = codeEvidence(); var body = el('code-body'); body.innerHTML = rows.length ? rows.slice(0, 100).map(function (item) { var value = item.value; return '<tr><td><code>' + esc(item.label) + '</code></td><td>' + nf.format(value.count) + '</td><td>' + esc(us(value.total)) + '</td><td>' + esc(us(value.longest)) + '</td><td>' + esc(Object.keys(value.categories).join(', ')) + '</td></tr>'; }).join('') : '<tr><td colspan="5"><div class="empty">No source locations were included in the retained VM events.</div></td></tr>';
  };
  var renderComparison = function () {
    var body = el('comparison-body');
    body.innerHTML = reports.map(function (item, index) {
      var r = item.report || {}; var s = r.summary || {}; var total = s.total || {}; var m = r.memory && r.memory.summary ? r.memory.summary : null; var jank = number(s.jank); var count = number(s.frames); var fps = s.fps == null ? '—' : Number(s.fps).toFixed(1); var label = item.label || ('Capture ' + (index + 1));
      return '<tr class="' + (index === state.report ? 'current' : '') + '"><td><button class="quiet-button" type="button" data-report-index="' + index + '">' + esc(label) + '</button></td><td>' + nf.format(count) + '</td><td class="' + (jank ? 'bad' : '') + '">' + nf.format(jank) + '</td><td>' + esc(fps) + '</td><td>' + esc(total.p90 == null ? '—' : us(total.p90)) + '</td><td>' + esc(total.max == null ? '—' : us(total.max)) + '</td><td>' + esc(duration(r.durationMs)) + '</td><td>' + esc(m ? bytes(m.peak) : '—') + '</td><td>' + esc(m ? bytes(m.delta) : '—') + '</td></tr>';
    }).join('') || '<tr><td colspan="9"><div class="empty">No captures.</div></td></tr>';
    body.querySelectorAll('[data-report-index]').forEach(function (button) { button.addEventListener('click', function () { state.report = Number(button.getAttribute('data-report-index')) || 0; state.framePage = 0; state.eventPage = 0; render(); }); });
  };
  var renderDetails = function () {
    var r = report(); var s = summary(); var d = r.dropped || {}; var mem = memory(); var hasFrames = frames().length > 0; var cache = function (value) { return value == null || !hasFrames ? 'Unavailable' : bytes(value); };
    var cells = [['Mode', r.mode || '—'], ['Build', r.build || '—'], ['Platform', r.platform || '—'], ['Timeline', r.source || 'unavailable'], ['Frame budget', s.build == null || s.build.bud == null ? 'Unavailable' : us(s.build.bud)], ['Total p99', s.total == null || s.total.p99 == null ? 'Unavailable' : us(s.total.p99)], ['Retained frames', nf.format(frames().length)], ['Dropped frames', nf.format(number(d.frames))], ['Invalid frames', nf.format(number(d.badFrames))], ['Dropped events', nf.format(number(d.events))], ['Invalid events', nf.format(number(d.badEvents))], ['Max layer cache', cache(s.layerCache && s.layerCache.bytes)], ['Max picture cache', cache(s.pictureCache && s.pictureCache.bytes)]];
    if (mem && mem.summary) { cells.push(['Memory source', mem.source], ['Memory samples', nf.format(number(mem.summary.n))], ['Memory min', bytes(mem.summary.min)], ['Memory avg', bytes(mem.summary.avg)], ['Memory interval', duration(mem.intervalMs)], ['Memory dropped', nf.format(number(mem.dropped))]); }
    var dtools = r.devtools || null;
    if (dtools) {
      if (dtools.cpu) cells.push(['CPU samples', nf.format(number(dtools.cpu.n))], ['CPU period', us(number(dtools.cpu.period))], ['CPU depth', nf.format(number(dtools.cpu.depth))], ['CPU dropped', nf.format(number(dtools.cpu.dropped))]);
      if (dtools.gc) cells.push(['GC events', nf.format(number(dtools.gc.n))], ['GC timed', nf.format(number(dtools.gc.timed))], ['GC pause p90', dtools.gc.p90 == null ? 'Unavailable' : us(dtools.gc.p90)], ['GC pause max', dtools.gc.max == null ? 'Unavailable' : us(dtools.gc.max)]);
      if (dtools.heap) cells.push(['VM heap samples', nf.format((dtools.heap.samples || []).length)], ['VM heap interval', duration(dtools.heap.interval)], ['VM heap dropped', nf.format(number(dtools.heap.drop))], ['Allocation classes', nf.format((dtools.heap.classes || []).length)], ['Group heap before', dtools.heap.gb ? bytes(dtools.heap.gb.use) : 'Unavailable'], ['Group heap after', dtools.heap.ga ? bytes(dtools.heap.ga.use) : 'Unavailable'], ['Accumulator reset', dtools.heap.reset == null ? 'Unavailable' : String(dtools.heap.reset)], ['Last service GC', dtools.heap.gcAt == null ? 'Unavailable' : String(dtools.heap.gcAt)]);
      if (dtools.isolate) { var iso = dtools.isolate.after || dtools.isolate.before || {}; var isoBefore = Array.isArray(dtools.isolate.allB) ? dtools.isolate.allB : []; var isoAfter = Array.isArray(dtools.isolate.allA) ? dtools.isolate.allA : []; var isoBeforeIds = {}; isoBefore.forEach(function (item) { if (item && item.id) isoBeforeIds[String(item.id)] = true; }); var isoAfterIds = {}; isoAfter.forEach(function (item) { if (item && item.id) isoAfterIds[String(item.id)] = true; }); var isoStarted = isoAfter.filter(function (item) { return item && item.id && !isoBeforeIds[String(item.id)]; }).length; var isoStopped = isoBefore.filter(function (item) { return item && item.id && !isoAfterIds[String(item.id)]; }).length; cells.push(['Isolate', iso.name || '—'], ['Isolate group', iso.group || '—'], ['Live ports', iso.ports == null ? 'Unavailable' : nf.format(number(iso.ports))], ['Libraries', iso.libs == null ? 'Unavailable' : nf.format(number(iso.libs))], ['Extensions', iso.ext == null ? 'Unavailable' : nf.format(number(iso.ext))], ['Isolate snapshots', nf.format(isoBefore.length) + ' before / ' + nf.format(isoAfter.length) + ' after'], ['Isolate changes', '+' + nf.format(isoStarted) + ' started / −' + nf.format(isoStopped) + ' stopped']); if (iso.exit != null) cells.push(['Pause on exit', iso.exit ? 'yes' : 'no']); if (iso.ex) cells.push(['Exception pause', iso.ex]); if (iso.root) cells.push(['Root library', iso.root]); if (dtools.isolate.dropB || dtools.isolate.dropA) cells.push(['Isolate drops', nf.format(number(dtools.isolate.dropB)) + ' before / ' + nf.format(number(dtools.isolate.dropA)) + ' after']); }
      if (dtools.timeline) cells.push(['Timeline recorder', dtools.timeline.recorder || '—'], ['Recorded streams', nf.format((dtools.timeline.recorded || []).length)], ['Available streams', nf.format((dtools.timeline.available || []).length)]);
      if (Array.isArray(dtools.log) && (dtools.log.length || dtools.dropLog)) cells.push(['VM logs', nf.format(dtools.log.length)], ['VM log drops', nf.format(number(dtools.dropLog))]);
      if (Array.isArray(dtools.dbg) && (dtools.dbg.length || dtools.dropDbg)) cells.push(['Debug events', nf.format(dtools.dbg.length)], ['Debug drops', nf.format(number(dtools.dropDbg))]);
      if (dtools.display) cells.push(['Display refresh', dtools.display.hz == null ? 'Unavailable' : Number(dtools.display.hz).toFixed(1) + ' Hz'], ['Display budget', dtools.display.bud == null ? 'Unavailable' : us(dtools.display.bud)], ['Flutter view', dtools.display.view || 'Default']);
      if (dtools.rebuild) cells.push(['Rebuild frames', nf.format((dtools.rebuild.frames || []).length)], ['Rebuild locations', nf.format((dtools.rebuild.loc || []).length)], ['Rebuild totals', nf.format((dtools.rebuild.tot || []).length)], ['Unresolved locations', nf.format(number(dtools.rebuild.unknown))], ['Rebuild drops', nf.format(number(dtools.rebuild.dropF) + number(dtools.rebuild.dropE))]);
      if (dtools.vmem) {
        var vmBefore = dtools.vmem.before && dtools.vmem.before.root ? dtools.vmem.before.root : null;
        var vmAfter = dtools.vmem.after && dtools.vmem.after.root ? dtools.vmem.after.root : null;
        if (vmBefore) cells.push(['VM memory before', bytes(vmBefore.s)], ['VM buckets before', nf.format((vmBefore.c || []).length)]);
        if (vmAfter) cells.push(['VM memory after', bytes(vmAfter.s)], ['VM buckets after', nf.format((vmAfter.c || []).length)]);
        if (vmBefore && vmAfter) cells.push(['VM memory Δ', bytes(number(vmAfter.s) - number(vmBefore.s))]);
      }
    }
    var gcAnalysis = (reports[state.report].analysis || {}).gc || null;
    if (gcAnalysis && number(gcAnalysis.count) > 0) {
      if (!r.devtools || !r.devtools.gc) cells.push(['GC events', nf.format(number(gcAnalysis.count))], ['GC timed', nf.format(number(gcAnalysis.timed))], ['GC pause p90', gcAnalysis.p90 == null ? 'Unavailable' : us(gcAnalysis.p90)], ['GC pause max', gcAnalysis.max == null ? 'Unavailable' : us(gcAnalysis.max)]);
    }
    var pipeline = pipelineSamples();
    if (pipeline.length) cells.push(['Pipeline samples', nf.format(pipeline.length)], ['Build wait p90', us(percentile(pipeline.map(function (item) { return item.buildWait; }), .9))], ['Raster wait p90', us(percentile(pipeline.map(function (item) { return item.rasterWait; }), .9))]);
    if (startup) { cells.push(['Startup source', startup.source || 'harness'], ['App build', duration(startup.appMs)], ['First frame', duration(startup.firstMs)], ['Ready', duration(startup.readyMs)]); }
    el('detail-grid').innerHTML = cells.map(function (cell) { return '<div class="detail-cell"><span>' + esc(cell[0]) + '</span><strong>' + esc(cell[1]) + '</strong></div>'; }).join('');
    el('raw-json').textContent = JSON.stringify(r, null, 2);
  };
  var sortedFrames = function () { var list = frames().slice(); if (state.frameSort === 'total') list.sort(function (a, b) { return number(b.s) - number(a.s); }); if (state.frameSort === 'build') list.sort(function (a, b) { return number(b.b) - number(a.b); }); if (state.frameSort === 'raster') list.sort(function (a, b) { return number(b.r) - number(a.r); }); return list; };
  var renderFrames = function () {
    var list = sortedFrames(); var pages = Math.max(1, Math.ceil(list.length / framePageSize)); state.framePage = clamp(state.framePage, 0, pages - 1); var start = state.framePage * framePageSize; var slice = list.slice(start, start + framePageSize); var budget = number(summary().build && summary().build.bud);
    el('frame-body').innerHTML = slice.length ? slice.map(function (f) { var bad = number(f.s) > budget; var warn = !bad && (number(f.b) > budget || number(f.r) > budget); return '<tr><td>' + nf.format(number(f.i)) + '</td><td><code>' + esc(f.n == null ? '—' : f.n) + '</code></td><td><strong>' + esc(us(f.s)) + '</strong></td><td>' + esc(us(f.b)) + '</td><td>' + esc(us(f.r)) + '</td><td>' + esc(us(f.v)) + '</td><td>' + status(bad, warn) + '</td><td class="subtle">' + esc(number(f.l)) + ' layers · ' + esc(bytes(f.lb)) + '</td></tr>'; }).join('') : '<tr><td colspan="8"><div class="empty">No retained frame timings.</div></td></tr>';
    el('frame-page-label').textContent = list.length ? 'Showing ' + (start + 1) + '–' + Math.min(start + slice.length, list.length) + ' of ' + nf.format(list.length) : 'No frames'; el('frame-prev').disabled = state.framePage === 0; el('frame-next').disabled = state.framePage >= pages - 1;
  };
  var filteredEvents = function () { var q = state.eventQuery.toLowerCase(); return events().filter(function (e) { var category = String(e.c || 'uncategorized'); var args = e.a && typeof e.a === 'object' ? Object.keys(e.a).join(' ') : ''; var text = String(e.n || '') + ' ' + category + ' ' + args; return (!q || text.toLowerCase().indexOf(q) >= 0) && (!state.eventCategory || category === state.eventCategory); }).slice().sort(function (a, b) { return number(b.t) - number(a.t); }); };
  var renderEvents = function () {
    var list = filteredEvents(); var pages = Math.max(1, Math.ceil(list.length / eventPageSize)); state.eventPage = clamp(state.eventPage, 0, pages - 1); var start = state.eventPage * eventPageSize; var slice = list.slice(start, start + eventPageSize);
    el('event-body').innerHTML = slice.length ? slice.map(function (e) { var args = e.a && Object.keys(e.a).length ? '<details><summary>View args</summary><div class="detail-body"><pre class="json-view">' + esc(JSON.stringify(e.a, null, 2)) + '</pre></div></details>' : '<span class="subtle">—</span>'; return '<tr><td><code>' + esc(relativeUs(e.t, eventOrigin())) + '</code></td><td><strong>' + esc(e.n || 'Unnamed event') + '</strong></td><td>' + esc(e.c || 'uncategorized') + '</td><td>' + esc(e.d ? us(e.d) : 'Instant') + '</td><td>' + esc(e.p || '—') + '</td><td>' + args + '</td></tr>'; }).join('') : '<tr><td colspan="6"><div class="empty">No events match the current filter.</div></td></tr>';
    el('event-page-label').textContent = list.length ? 'Showing ' + (start + 1) + '–' + Math.min(start + slice.length, list.length) + ' of ' + nf.format(list.length) : 'No matching events'; el('event-prev').disabled = state.eventPage === 0; el('event-next').disabled = state.eventPage >= pages - 1;
  };
  var renderCategories = function () { var values = {}; events().forEach(function (e) { values[String(e.c || 'uncategorized')] = true; }); var select = el('event-category'); select.innerHTML = '<option value="">All categories</option>' + Object.keys(values).sort().map(function (value) { return '<option value="' + esc(value) + '">' + esc(value) + '</option>'; }).join(''); select.value = state.eventCategory; };
  var renderSelector = function () { var select = el('report-select'); select.innerHTML = reports.map(function (item, index) { return '<option value="' + index + '">' + esc(item.label || ('Capture ' + (index + 1))) + '</option>'; }).join(''); select.value = state.report; };
  var render = function () { hideTooltip(); renderSelector(); renderMeta(); renderHealth(); renderMetrics(); renderStartup(); renderCoverage(); renderDevTools(); renderEventSummary(); renderStalls(); renderCategories(); renderResources(); renderComparison(); renderDetails(); renderFrames(); renderEvents(); renderCodeEvidence(); renderHotspots(); drawStartupChart(); drawFrameChart(); drawEventChart(); drawPhaseChart(); drawResourceChart(); drawCacheChart(); drawJankChart(); drawCadenceChart(); drawCacheTrendChart(); drawPipelineChart(); drawGcChart(); drawCategoryCostChart(); drawHotspotChart(); drawFlameChart(); drawCpuChart(); drawHeapChart(); drawHeapTrendChart(); drawVmMemoryChart(); drawRebuildChart(); };
  el('report-select').addEventListener('change', function (event) { state.report = Number(event.target.value) || 0; state.framePage = 0; state.eventPage = 0; state.eventQuery = ''; state.eventCategory = ''; el('event-search').value = ''; render(); });
  el('frame-sort').addEventListener('change', function (event) { state.frameSort = event.target.value; state.framePage = 0; renderFrames(); });
  el('frame-prev').addEventListener('click', function () { state.framePage -= 1; renderFrames(); }); el('frame-next').addEventListener('click', function () { state.framePage += 1; renderFrames(); });
  el('event-prev').addEventListener('click', function () { state.eventPage -= 1; renderEvents(); }); el('event-next').addEventListener('click', function () { state.eventPage += 1; renderEvents(); });
  el('event-search').addEventListener('input', function (event) { state.eventQuery = event.target.value || ''; state.eventPage = 0; renderEvents(); }); el('event-category').addEventListener('change', function (event) { state.eventCategory = event.target.value || ''; state.eventPage = 0; renderEvents(); });
  el('raw-button').addEventListener('click', function (event) { var wrap = el('raw-wrap'); var show = wrap.classList.toggle('hidden'); event.target.textContent = show ? 'Show raw JSON' : 'Hide raw JSON'; });
  el('copy-button').addEventListener('click', function (event) { var text = JSON.stringify(report()); if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(text).then(function () { event.target.textContent = 'Copied'; setTimeout(function () { event.target.textContent = 'Copy report JSON'; }, 1200); }); } });
  el('download-button').addEventListener('click', function () { var blob = new Blob([JSON.stringify(data)], { type: 'application/json' }); var link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = fileStem(data.title) + '.full.json'; link.click(); setTimeout(function () { URL.revokeObjectURL(link.href); }, 1000); });
  el('timeline-button').addEventListener('click', function () { var blob = new Blob([JSON.stringify(timelinePayload())], { type: 'application/json' }); var link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = (reports[state.report].label || 'cockpit-performance') + '.timeline.json'; link.click(); setTimeout(function () { URL.revokeObjectURL(link.href); }, 1000); });
  el('perfetto-button').addEventListener('click', function () { var d = report().devtools && report().devtools.perfetto; if (!d) return; var stem = fileStem(reports[state.report].label || 'cockpit-performance'); if (d.cpu && d.cpu.data) downloadBase64(d.cpu.data, stem + '.cpu.pftrace'); if (d.timeline && d.timeline.data) setTimeout(function () { downloadBase64(d.timeline.data, stem + '.timeline.pftrace'); }, 120); });
  el('theme-button').addEventListener('click', function () { root.dataset.theme = root.dataset.theme === 'light' ? 'dark' : 'light'; drawStartupChart(); drawFrameChart(); drawEventChart(); drawPhaseChart(); drawResourceChart(); drawCacheChart(); drawJankChart(); drawCadenceChart(); drawCacheTrendChart(); drawPipelineChart(); drawGcChart(); drawCategoryCostChart(); drawHotspotChart(); drawFlameChart(); drawCpuChart(); drawHeapChart(); drawHeapTrendChart(); drawVmMemoryChart(); drawRebuildChart(); });
  window.addEventListener('scroll', hideTooltip, { passive: true });
  window.addEventListener('resize', function () { drawStartupChart(); drawFrameChart(); drawEventChart(); drawPhaseChart(); drawResourceChart(); drawCacheChart(); drawJankChart(); drawCadenceChart(); drawCacheTrendChart(); drawPipelineChart(); drawGcChart(); drawCategoryCostChart(); drawHotspotChart(); drawFlameChart(); drawCpuChart(); drawHeapChart(); drawHeapTrendChart(); drawVmMemoryChart(); drawRebuildChart(); });
  ['startup-chart', 'frame-chart', 'event-chart', 'phase-chart', 'resource-chart', 'cache-chart', 'jank-chart', 'cadence-chart', 'cache-trend-chart', 'pipeline-chart', 'gc-chart', 'category-cost-chart', 'hotspot-chart', 'flame-chart', 'cpu-chart', 'heap-chart', 'heap-trend-chart', 'vm-memory-chart', 'rebuild-chart'].forEach(bindChart);
  document.querySelectorAll('[data-details]').forEach(function (button) { button.addEventListener('click', function () { openDetails(button.getAttribute('data-details')); }); });
  el('details-copy').addEventListener('click', function (event) { if (!detailsPayload || !navigator.clipboard || !navigator.clipboard.writeText) return; navigator.clipboard.writeText(detailsPayload).then(function () { event.target.textContent = 'Copied'; setTimeout(function () { event.target.textContent = 'Copy details'; }, 1200); }); });
  render();
}());
</script>
</body>
</html>
''';
}

String _html(Object? value) => value
    .toString()
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String _scriptJson(Object? value) => jsonEncode(value)
    .replaceAll('&', r'\u0026')
    .replaceAll('<', r'\u003c')
    .replaceAll('>', r'\u003e')
    .replaceAll('\u2028', r'\u2028')
    .replaceAll('\u2029', r'\u2029');
