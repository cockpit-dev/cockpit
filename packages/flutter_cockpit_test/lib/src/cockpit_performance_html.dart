import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_startup_report.dart';

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

    final payload = <String, Object?>{
      'title': normalizedTitle,
      if (startup != null) 'startup': startup.toJson(),
      'reports': <Object?>[
        for (var index = 0; index < reports.length; index += 1)
          <String, Object?>{
            'id': 'p$index',
            'label': reports[index].stepId?.trim().isNotEmpty == true
                ? reports[index].stepId
                : 'Capture ${index + 1}',
            'report': reports[index].toJson(),
          },
      ],
    };
    return _document(normalizedTitle, _scriptJson(payload));
  }
}

String _document(String title, String payload) {
  final safeTitle = _html(title);
  return '''<!doctype html>
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
.brand-mark { display: grid; place-items: center; width: 30px; height: 30px; border-radius: 9px; background: var(--accent); color: #08251c; font-weight: 850; letter-spacing: -.06em; }
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
.panel { min-width: 0; margin-top: 15px; padding: 19px; border: 1px solid var(--line); border-radius: 14px; background: var(--surface); box-shadow: var(--shadow); }
.panel-head { display: flex; align-items: end; justify-content: space-between; gap: 18px; margin-bottom: 14px; }
.panel-head h2 { margin: 0; font-size: 17px; letter-spacing: -.01em; }
.panel-head p { margin: 4px 0 0; color: var(--muted); font-size: 12px; }
.panel-tools { display: flex; align-items: center; gap: 8px; }
.chart-grid, .insight-grid { display: grid; grid-template-columns: minmax(0, 1.65fr) minmax(280px, .9fr); gap: 15px; }
.chart-grid .panel { margin-top: 0; }
.insight-grid { margin-top: 15px; }
.insight-grid .panel { margin-top: 0; }
.chart-wrap { position: relative; height: 310px; border: 1px solid var(--line); border-radius: 10px; background: var(--surface-2); overflow: hidden; }
.chart-wrap canvas { display: block; width: 100%; height: 100%; }
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
th, td { padding: 10px 12px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
th { position: sticky; top: 0; z-index: 1; background: var(--surface-3); color: var(--text-soft); font-size: 10px; font-weight: 750; letter-spacing: .04em; text-transform: uppercase; }
tbody tr:last-child td { border-bottom: 0; }
tbody tr:hover td { background: color-mix(in srgb, var(--accent-soft) 35%, var(--surface)); }
td { color: var(--text-soft); font-size: 12px; }
.comparison-table { min-width: 900px; }
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
.footer { margin-top: 23px; padding-top: 14px; border-top: 1px solid var(--line); color: var(--muted); font-size: 11px; }
.hidden { display: none !important; }
@media (max-width: 1120px) {
  .metric-grid { grid-template-columns: repeat(4, minmax(0, 1fr)); }
  .hero-grid, .chart-grid, .insight-grid { grid-template-columns: 1fr; }
  .health { min-height: 200px; }
}
@media (max-width: 700px) {
  .shell { padding-left: 16px; padding-right: 16px; }
  .topbar-inner { min-height: 58px; }
  .brand-copy span { display: none; }
  .hero { padding-top: 24px; }
  h1 { font-size: 32px; }
  .metric-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .startup-strip { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .toolbar, .panel-head { display: block; }
  .toolbar-actions, .panel-tools { margin-top: 10px; flex-wrap: wrap; }
  .control { min-width: 0; }
  .panel { padding: 14px; border-radius: 11px; }
  .chart-wrap { height: 250px; }
  .event-summary, .detail-grid, .resource-summary { grid-template-columns: repeat(2, minmax(0, 1fr)); }
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
  <div class="brand"><span class="brand-mark" aria-hidden="true">C</span><div class="brand-copy"><strong>Cockpit performance</strong><span>Offline report · exact retained data</span></div></div>
  <div class="top-actions"><button class="icon-button" id="theme-button" type="button" title="Toggle theme" aria-label="Toggle theme">☼</button><button class="quiet-button" id="download-button" type="button">Download JSON</button></div>
</div></header>
<div class="shell">
  <section class="hero">
    <div class="hero-grid">
      <div><div class="eyebrow">Flutter runtime evidence</div><h1 id="report-title">$safeTitle</h1><p class="hero-copy">Frame pacing, raster pressure, cache growth, garbage collection, and VM timeline activity in one file you can inspect without a server.</p><div class="meta-row" id="report-meta"></div></div>
      <aside class="health"><div class="health-head"><h2>Capture health</h2><span class="subtle" id="health-label">—</span></div><div><div class="health-score" id="health-score">—</div><p class="health-note" id="health-note">Select a capture to inspect its retained samples.</p><div class="meter" aria-hidden="true"><span id="health-meter" style="width:0%"></span></div></div><div class="health-foot"><span id="health-left">—</span><span id="health-right">—</span></div></aside>
    </div>
    <div class="metric-grid" id="metric-grid"></div>
    <div class="startup-strip" id="startup-strip"></div>
  </section>
  <main class="workspace">
    <div class="toolbar"><div class="control"><label for="report-select">Capture</label><select id="report-select"></select></div><div class="toolbar-actions"><button class="quiet-button" id="copy-button" type="button">Copy report JSON</button><button class="quiet-button" id="raw-button" type="button">Show raw JSON</button></div></div>
    <section class="chart-grid">
      <div class="panel"><div class="panel-head"><div><h2>Frame pacing</h2><p>Total frame span against the display budget. Jank is marked in place.</p></div><span class="subtle" id="frame-range">—</span></div><div class="chart-wrap"><canvas id="frame-chart" aria-label="Frame pacing chart"></canvas></div><div class="chart-legend"><span class="legend-item"><i class="legend-swatch total"></i>Total</span><span class="legend-item"><i class="legend-swatch build"></i>Build</span><span class="legend-item"><i class="legend-swatch raster"></i>Raster</span><span class="legend-item"><i class="legend-swatch budget"></i>Budget</span></div></div>
      <div class="panel"><div class="panel-head"><div><h2>VM timeline</h2><p>Retained event volume and category mix.</p></div></div><div class="event-summary" id="event-summary"></div><div class="chart-wrap" style="height:160px;margin-top:14px"><canvas id="event-chart" aria-label="VM timeline chart"></canvas></div><div class="category-list" id="category-list"></div></div>
    </section>
    <section class="insight-grid">
      <div class="panel"><div class="panel-head"><div><h2>Phase latency</h2><p>Percentiles make long-tail build and raster pressure visible.</p></div></div><div class="chart-wrap" style="height:250px"><canvas id="phase-chart" aria-label="Frame phase latency chart"></canvas></div><div class="chart-legend"><span class="legend-item"><i class="legend-swatch total"></i>p50</span><span class="legend-item"><i class="legend-swatch build"></i>p90</span><span class="legend-item"><i class="legend-swatch raster"></i>p99</span><span class="legend-item"><i class="legend-swatch budget"></i>max</span></div></div>
      <div class="panel"><div class="panel-head"><div><h2>Memory, cache and GC</h2><p>Process RSS trend beside Flutter cache peaks and collector activity.</p></div></div><div class="chart-wrap" style="height:250px"><canvas id="resource-chart" aria-label="Memory, cache and garbage collection chart"></canvas></div><div class="resource-summary" id="resource-summary"></div></div>
    </section>
    <section class="panel"><div class="panel-head"><div><h2>Frame explorer</h2><p>Inspect retained engine timings without rendering every sample at once.</p></div><div class="panel-tools"><select id="frame-sort" aria-label="Sort frames"><option value="index">Capture order</option><option value="total">Slowest total</option><option value="build">Slowest build</option><option value="raster">Slowest raster</option></select></div></div><div class="table-wrap"><table><thead><tr><th>#</th><th>Frame</th><th>Total</th><th>Build</th><th>Raster</th><th>Vsync</th><th>Budget</th><th>Cache</th></tr></thead><tbody id="frame-body"></tbody></table></div><div class="pager"><span id="frame-page-label">—</span><div class="pager-actions"><button class="quiet-button" id="frame-prev" type="button">Previous</button><button class="quiet-button" id="frame-next" type="button">Next</button></div></div></section>
    <section class="panel"><div class="panel-head"><div><h2>Capture comparison</h2><p>Compare every capture in this file without switching context.</p></div></div><div class="table-wrap"><table class="comparison-table"><thead><tr><th>Capture</th><th>Frames</th><th>Jank</th><th>FPS</th><th>Total p90</th><th>Total max</th><th>Duration</th><th>RSS peak</th><th>RSS Δ</th></tr></thead><tbody id="comparison-body"></tbody></table></div></section>
    <section class="panel"><div class="panel-head"><div><h2>Timeline events</h2><p>Search and filter retained VM events. Arguments stay collapsed until needed.</p></div><div class="panel-tools"><div class="control"><label for="event-search">Search</label><input id="event-search" type="search" placeholder="Name or category"></div><select id="event-category" aria-label="Filter event category"><option value="">All categories</option></select></div></div><div class="table-wrap"><table><thead><tr><th>When</th><th>Event</th><th>Category</th><th>Duration</th><th>Phase</th><th>Arguments</th></tr></thead><tbody id="event-body"></tbody></table></div><div class="pager"><span id="event-page-label">—</span><div class="pager-actions"><button class="quiet-button" id="event-prev" type="button">Previous</button><button class="quiet-button" id="event-next" type="button">Next</button></div></div></section>
    <section class="panel"><div class="panel-head"><div><h2>Capture details</h2><p>Retention boundaries and interpretation context are kept beside the measurements.</p></div></div><div class="detail-grid" id="detail-grid"></div><div id="raw-wrap" class="hidden" style="margin-top:14px"><pre class="json-view" id="raw-json"></pre></div></section>
    <div class="footer">Generated by <strong>Cockpit</strong>. JSON remains the canonical machine-readable payload. This viewer is self-contained and works offline.</div>
  </main>
</div>
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
  var report = function () { return reports[state.report] && reports[state.report].report || {}; };
  var summary = function () { return report().summary || {}; };
  var frames = function () { return Array.isArray(report().frames) ? report().frames : []; };
  var events = function () { return Array.isArray(report().events) ? report().events : []; };
  var memory = function () { return report().memory || null; };
  var phase = function (name) { return summary()[name] || {}; };
  var number = function (value, fallback) { return Number.isFinite(Number(value)) ? Number(value) : (fallback || 0); };
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
    var width = Math.max(1, Math.round(rect.width * dpr));
    var height = Math.max(1, Math.round(rect.height * dpr));
    if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
    var ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    painter(ctx, rect.width, rect.height);
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
    draw(el('frame-chart'), function (ctx, width, height) {
      var budget = number(summary().build && summary().build.bud);
      var max = Math.max(budget, 1, list.reduce(function (m, f) { return Math.max(m, number(f.s)); }, 0));
      max = max * 1.12;
      var area = grid(ctx, width, height, max, budget);
      if (!list.length) { ctx.fillStyle = css('--muted'); ctx.fillText('No retained frame timings', area.left, height / 2); return; }
      var stride = Math.max(1, Math.ceil(list.length / Math.max(1, Math.floor(area.plotW))));
      var sample = list.filter(function (_, i) { return i % stride === 0; });
      var path = function (key, color, lineWidth) {
        ctx.strokeStyle = color; ctx.lineWidth = lineWidth; ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.beginPath();
        sample.forEach(function (f, i) { var x = area.left + (sample.length === 1 ? .5 : i / (sample.length - 1)) * area.plotW; var y = area.top + area.plotH * (1 - number(f[key]) / max); if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); });
        ctx.stroke();
      };
      path('s', css('--accent'), 2.2); path('b', css('--blue'), 1.15); path('r', css('--warning'), 1.15);
      ctx.fillStyle = css('--danger');
      sample.forEach(function (f, i) { if (number(f.s) <= budget) return; var x = area.left + (sample.length === 1 ? .5 : i / (sample.length - 1)) * area.plotW; var y = area.top + area.plotH * (1 - number(f.s) / max); ctx.beginPath(); ctx.arc(x, y, 2.7, 0, Math.PI * 2); ctx.fill(); });
      ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('0', area.left, height - 8); ctx.fillText(nf.format(list.length) + ' frames', Math.max(area.left, width - 92), height - 8);
    });
  };
  var hashColor = function (value) { var colors = [css('--accent'), css('--blue'), css('--warning'), '#d79aff', '#8bd4ff', '#ff9da4']; var hash = 0; for (var i = 0; i < value.length; i += 1) hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0; return colors[Math.abs(hash) % colors.length]; };
  var drawEventChart = function () {
    var list = events();
    draw(el('event-chart'), function (ctx, width, height) {
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      if (!list.length) { ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif'; ctx.fillText('No retained VM events', 15, height / 2); return; }
      var min = list.reduce(function (m, e) { return Math.min(m, number(e.t)); }, Infinity); var max = list.reduce(function (m, e) { return Math.max(m, number(e.t) + number(e.d)); }, -Infinity); var span = Math.max(1, max - min);
      var lanes = {}; list.forEach(function (e) { var key = String(e.c || 'uncategorized'); if (!lanes[key]) lanes[key] = []; lanes[key].push(e); });
      var laneNames = Object.keys(lanes).sort(function (a, b) { return lanes[b].length - lanes[a].length; }).slice(0, 7); var left = 12; var labelW = Math.min(105, Math.max(58, width * .22)); var plotLeft = left + labelW; var plotW = width - plotLeft - 12; var plotTop = 10; var plotBottom = 22; var rowH = Math.max(14, (height - plotTop - plotBottom) / Math.max(1, laneNames.length));
      ctx.font = '10px system-ui, sans-serif';
      laneNames.forEach(function (lane, laneIndex) { var y = plotTop + laneIndex * rowH; ctx.fillStyle = css('--muted'); ctx.fillText(lane.length > 16 ? lane.slice(0, 15) + '…' : lane, left, y + rowH * .65); var laneEvents = lanes[lane]; var stride = Math.max(1, Math.ceil(laneEvents.length / Math.max(1, Math.floor(plotW / 2)))); laneEvents.forEach(function (e, i) { if (i % stride !== 0) return; var x = plotLeft + ((number(e.t) - min) / span) * plotW; var w = Math.max(2, (number(e.d) / span) * plotW); ctx.fillStyle = hashColor(lane); ctx.globalAlpha = .88; ctx.fillRect(x, y + 2, Math.min(w, plotLeft + plotW - x), Math.max(5, rowH - 6)); ctx.globalAlpha = 1; }); });
      ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(plotLeft, height - plotBottom + 3); ctx.lineTo(plotLeft + plotW, height - plotBottom + 3); ctx.stroke();
      ctx.fillStyle = css('--muted'); ctx.fillText(nf.format(list.length) + ' retained · ' + us(span) + ' span', left, height - 8);
    });
  };
  var drawPhaseChart = function () {
    draw(el('phase-chart'), function (ctx, width, height) {
      ctx.clearRect(0, 0, width, height); ctx.fillStyle = css('--surface-2'); ctx.fillRect(0, 0, width, height);
      var names = [['Build', phase('build')], ['Raster', phase('raster')], ['Vsync', phase('vsync')], ['Total', phase('total')]]; var values = names.reduce(function (all, item) { var p = item[1]; return all.concat([number(p.p50), number(p.p90), number(p.p99), number(p.max)]); }, []); var max = Math.max(1, values.reduce(function (m, value) { return Math.max(m, value); }, 0)) * 1.15; var left = 54, right = 13, top = 19, bottom = 27; var plotW = width - left - right; var plotH = height - top - bottom; var rowH = plotH / names.length;
      ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.fillStyle = css('--muted'); ctx.font = '10px system-ui, sans-serif';
      for (var i = 0; i <= 4; i += 1) { var x = left + plotW * i / 4; ctx.beginPath(); ctx.moveTo(x, top); ctx.lineTo(x, top + plotH); ctx.stroke(); ctx.fillText(us(Math.round(max * i / 4)), x - (i === 0 ? 0 : 10), height - 8); }
      var bars = [['p50', css('--accent')], ['p90', css('--blue')], ['p99', css('--warning')], ['max', css('--danger')]];
      names.forEach(function (item, row) { var label = item[0], p = item[1], y = top + row * rowH + rowH * .5; ctx.fillStyle = css('--text-soft'); ctx.fillText(label, 10, y + 3); bars.forEach(function (bar, index) { var value = number(p[bar[0]]); var by = y - 17 + index * 8; ctx.fillStyle = bar[1]; ctx.globalAlpha = value ? .92 : .22; ctx.fillRect(left, by, Math.max(value ? 2 : 0, value / max * plotW), 5); ctx.globalAlpha = 1; }); });
      if (!values.some(function (value) { return value > 0; })) { ctx.fillStyle = css('--muted'); ctx.fillText('No phase aggregates retained', left, height / 2); }
    });
  };
  var drawResourceChart = function () {
    draw(el('resource-chart'), function (ctx, width, height) {
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
        ctx.fillStyle = css('--muted'); ctx.fillText('RSS', left, height - 8); ctx.fillText(nf.format(samples.length) + ' samples · ' + us(last), Math.max(left + 30, width - 145), height - 8);
        return;
      }
      var s = summary(); var layer = s.layerCache || {}; var picture = s.pictureCache || {}; var gc = s.gc || {}; var rows = [['Layer bytes', number(layer.bytes), css('--accent'), bytes(layer.bytes), 'bytes'], ['Picture bytes', number(picture.bytes), css('--blue'), bytes(picture.bytes), 'bytes'], ['Layer count', number(layer.count), css('--warning'), nf.format(number(layer.count)), 'count'], ['Picture count', number(picture.count), '#d79aff', nf.format(number(picture.count)), 'count'], ['New GC', number(gc.new), css('--danger'), nf.format(number(gc.new)), 'count'], ['Old GC', number(gc.old), '#ff9da4', nf.format(number(gc.old)), 'count']]; var byteMax = Math.max(1, rows.slice(0, 2).reduce(function (m, row) { return Math.max(m, row[1]); }, 0)); var countMax = Math.max(1, rows.slice(2).reduce(function (m, row) { return Math.max(m, row[1]); }, 0)); var left = 92, right = 50, top = 22, rowH = Math.min(32, (height - 35) / rows.length); ctx.font = '10px system-ui, sans-serif'; rows.forEach(function (row, index) { var y = top + index * rowH; var max = row[4] === 'bytes' ? byteMax : countMax; ctx.fillStyle = css('--muted'); ctx.fillText(row[0], 8, y + 11); ctx.fillStyle = css('--surface-3'); ctx.fillRect(left, y + 2, width - left - right, 12); ctx.fillStyle = row[2]; ctx.fillRect(left, y + 2, Math.max(row[1] ? 3 : 0, row[1] / max * (width - left - right)), 12); ctx.fillStyle = css('--text-soft'); ctx.fillText(row[3], width - right + 6, y + 12); });
      if (!rows.some(function (row) { return row[1] > 0; })) { ctx.fillStyle = css('--muted'); ctx.fillText('No memory, cache, or GC data retained', left, height / 2); }
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
    el('frame-range').textContent = count ? us(number(frames()[0].t)) + ' → ' + us(number(frames()[frames().length - 1].t)) : 'No samples';
  };
  var renderStartup = function () {
    var node = el('startup-strip');
    if (!startup) { node.classList.add('hidden'); return; }
    node.classList.remove('hidden'); node.innerHTML = '<div><span class="startup-title">Cold start milestones</span><span>' + esc(startup.source || 'harness') + ' clock</span></div><div><span>App build</span><strong>' + esc(duration(startup.appMs)) + '</strong></div><div><span>First frame</span><strong class="good">' + esc(duration(startup.firstMs)) + '</strong></div><div><span>Ready</span><strong>' + esc(duration(startup.readyMs)) + '</strong></div>';
  };
  var renderEventSummary = function () {
    var list = events(); var start = list.reduce(function (m, e) { return Math.min(m, number(e.t)); }, Infinity); var finish = list.reduce(function (m, e) { return Math.max(m, number(e.t) + number(e.d)); }, -Infinity); var traceSpan = list.length ? Math.max(0, finish - start) : 0; var categories = {}; list.forEach(function (e) { var key = String(e.c || 'uncategorized'); categories[key] = (categories[key] || 0) + 1; }); var top = Object.keys(categories).sort(function (a, b) { return categories[b] - categories[a]; })[0];
    el('event-summary').innerHTML = '<div class="event-stat"><span>Retained</span><strong>' + nf.format(list.length) + '</strong></div><div class="event-stat"><span>Categories</span><strong>' + nf.format(Object.keys(categories).length) + '</strong></div><div class="event-stat"><span>Trace span</span><strong>' + (traceSpan ? esc(us(traceSpan)) : 'Instant') + '</strong></div>';
    var max = top ? categories[top] : 1; el('category-list').innerHTML = Object.keys(categories).sort(function (a, b) { return categories[b] - categories[a]; }).slice(0, 6).map(function (key) { return '<div class="category-row"><span title="' + esc(key) + '">' + esc(key) + '</span><div class="category-track"><span style="width:' + Math.max(4, categories[key] / max * 100) + '%;background:' + hashColor(key) + '"></span></div><span>' + nf.format(categories[key]) + '</span></div>'; }).join('') || '<div class="empty">No categories retained.</div>';
  };
  var renderResources = function () {
    var s = summary(); var mem = memory(); var m = mem && mem.summary ? mem.summary : null; var layer = s.layerCache || {}; var picture = s.pictureCache || {}; var gc = s.gc || {};
    var cells = m ? [['RSS start', bytes(m.start)], ['RSS end', bytes(m.end)], ['RSS peak', bytes(m.peak)], ['RSS Δ', bytes(m.delta)], ['Samples', nf.format(number(m.n))], ['Source', mem.source || 'unavailable']] : [['RSS', 'Unavailable'], ['Layer cache', bytes(layer.bytes)], ['Picture cache', bytes(picture.bytes)], ['Layer count', nf.format(number(layer.count))], ['Picture count', nf.format(number(picture.count))], ['GC cycles', nf.format(number(gc.new) + number(gc.old))]];
    el('resource-summary').innerHTML = cells.map(function (cell) { return '<div><span>' + esc(cell[0]) + '</span><strong>' + esc(cell[1]) + '</strong></div>'; }).join('');
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
    var r = report(); var s = summary(); var d = r.dropped || {}; var mem = memory(); var cache = function (value) { return value == null ? '—' : bytes(value); };
    var cells = [['Mode', r.mode || '—'], ['Build', r.build || '—'], ['Platform', r.platform || '—'], ['Timeline', r.source || 'unavailable'], ['Frame budget', us(number(s.build && s.build.bud))], ['Total p99', us(number(s.total && s.total.p99))], ['Retained frames', nf.format(frames().length)], ['Dropped frames', nf.format(number(d.frames))], ['Invalid frames', nf.format(number(d.badFrames))], ['Dropped events', nf.format(number(d.events))], ['Invalid events', nf.format(number(d.badEvents))], ['Max layer cache', cache(s.layerCache && s.layerCache.bytes)], ['Max picture cache', cache(s.pictureCache && s.pictureCache.bytes)]];
    if (mem && mem.summary) { cells.push(['Memory source', mem.source], ['Memory samples', nf.format(number(mem.summary.n))], ['Memory interval', duration(mem.intervalMs)], ['Memory dropped', nf.format(number(mem.dropped))]); }
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
  var filteredEvents = function () { var q = state.eventQuery.toLowerCase(); return events().filter(function (e) { var category = String(e.c || 'uncategorized'); var args = e.a && typeof e.a === 'object' ? Object.keys(e.a).join(' ') : ''; var text = String(e.n || '') + ' ' + category + ' ' + args; return (!q || text.toLowerCase().indexOf(q) >= 0) && (!state.eventCategory || category === state.eventCategory); }); };
  var renderEvents = function () {
    var list = filteredEvents(); var pages = Math.max(1, Math.ceil(list.length / eventPageSize)); state.eventPage = clamp(state.eventPage, 0, pages - 1); var start = state.eventPage * eventPageSize; var slice = list.slice(start, start + eventPageSize);
    el('event-body').innerHTML = slice.length ? slice.map(function (e) { var args = e.a && Object.keys(e.a).length ? '<details><summary>View args</summary><div class="detail-body"><pre class="json-view">' + esc(JSON.stringify(e.a, null, 2)) + '</pre></div></details>' : '<span class="subtle">—</span>'; return '<tr><td><code>' + esc(us(e.t)) + '</code></td><td><strong>' + esc(e.n || 'Unnamed event') + '</strong></td><td>' + esc(e.c || 'uncategorized') + '</td><td>' + esc(e.d ? us(e.d) : 'Instant') + '</td><td>' + esc(e.p || '—') + '</td><td>' + args + '</td></tr>'; }).join('') : '<tr><td colspan="6"><div class="empty">No events match the current filter.</div></td></tr>';
    el('event-page-label').textContent = list.length ? 'Showing ' + (start + 1) + '–' + Math.min(start + slice.length, list.length) + ' of ' + nf.format(list.length) : 'No matching events'; el('event-prev').disabled = state.eventPage === 0; el('event-next').disabled = state.eventPage >= pages - 1;
  };
  var renderCategories = function () { var values = {}; events().forEach(function (e) { values[String(e.c || 'uncategorized')] = true; }); var select = el('event-category'); select.innerHTML = '<option value="">All categories</option>' + Object.keys(values).sort().map(function (value) { return '<option value="' + esc(value) + '">' + esc(value) + '</option>'; }).join(''); select.value = state.eventCategory; };
  var renderSelector = function () { var select = el('report-select'); select.innerHTML = reports.map(function (item, index) { return '<option value="' + index + '">' + esc(item.label || ('Capture ' + (index + 1))) + '</option>'; }).join(''); select.value = state.report; };
  var render = function () { renderSelector(); renderMeta(); renderHealth(); renderMetrics(); renderStartup(); renderEventSummary(); renderCategories(); renderResources(); renderComparison(); renderDetails(); renderFrames(); renderEvents(); drawFrameChart(); drawEventChart(); drawPhaseChart(); drawResourceChart(); };
  el('report-select').addEventListener('change', function (event) { state.report = Number(event.target.value) || 0; state.framePage = 0; state.eventPage = 0; state.eventQuery = ''; state.eventCategory = ''; el('event-search').value = ''; render(); });
  el('frame-sort').addEventListener('change', function (event) { state.frameSort = event.target.value; state.framePage = 0; renderFrames(); });
  el('frame-prev').addEventListener('click', function () { state.framePage -= 1; renderFrames(); }); el('frame-next').addEventListener('click', function () { state.framePage += 1; renderFrames(); });
  el('event-prev').addEventListener('click', function () { state.eventPage -= 1; renderEvents(); }); el('event-next').addEventListener('click', function () { state.eventPage += 1; renderEvents(); });
  el('event-search').addEventListener('input', function (event) { state.eventQuery = event.target.value || ''; state.eventPage = 0; renderEvents(); }); el('event-category').addEventListener('change', function (event) { state.eventCategory = event.target.value || ''; state.eventPage = 0; renderEvents(); });
  el('raw-button').addEventListener('click', function (event) { var wrap = el('raw-wrap'); var show = wrap.classList.toggle('hidden'); event.target.textContent = show ? 'Show raw JSON' : 'Hide raw JSON'; });
  el('copy-button').addEventListener('click', function (event) { var text = JSON.stringify(report(), null, 2); if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(text).then(function () { event.target.textContent = 'Copied'; setTimeout(function () { event.target.textContent = 'Copy report JSON'; }, 1200); }); } });
  el('download-button').addEventListener('click', function () { var blob = new Blob([JSON.stringify(report(), null, 2)], { type: 'application/json' }); var link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = (reports[state.report].label || 'cockpit-performance') + '.json'; link.click(); setTimeout(function () { URL.revokeObjectURL(link.href); }, 1000); });
  el('theme-button').addEventListener('click', function () { root.dataset.theme = root.dataset.theme === 'light' ? 'dark' : 'light'; drawFrameChart(); drawEventChart(); drawPhaseChart(); drawResourceChart(); });
  window.addEventListener('resize', function () { drawFrameChart(); drawEventChart(); drawPhaseChart(); drawResourceChart(); });
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
