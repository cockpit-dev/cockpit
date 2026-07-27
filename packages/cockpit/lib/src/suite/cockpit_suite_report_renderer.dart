import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';

final class CockpitSuiteReportRenderer {
  const CockpitSuiteReportRenderer();

  String json(CockpitTestSuiteReport report) =>
      const JsonEncoder.withIndent('  ').convert(report.toJson());

  String junit(CockpitTestSuiteReport report) {
    final counts = report.counts;
    final failures = counts.failed + counts.blocked;
    final suiteErrors = report.failure == null ? 0 : 1;
    final errors =
        counts.cancelled +
        counts.interrupted +
        counts.internalError +
        suiteErrors;
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..write(
        '<testsuite name="${_xml(report.suiteId)}" '
        'tests="${counts.total + suiteErrors}" failures="$failures" errors="$errors" '
        'skipped="${counts.skipped}" '
        'time="${_seconds(report.durationMs)}">',
      )
      ..writeln()
      ..writeln(
        '  <properties><property name="cockpit.runId" '
        'value="${_xml(report.runId)}"/></properties>',
      );
    for (final testCase in report.cases) {
      final duration = testCase.attempts.fold<int>(
        0,
        (total, attempt) => total + attempt.durationMs,
      );
      buffer.write(
        '  <testcase classname="${_xml(report.suiteId)}" '
        'name="${_xml(_caseName(testCase))}" '
        'time="${_seconds(duration)}">',
      );
      switch (testCase.outcome) {
        case CockpitRunOutcome.passed:
          break;
        case CockpitRunOutcome.skipped:
          buffer.write('<skipped/>');
        case CockpitRunOutcome.failed || CockpitRunOutcome.blocked:
          buffer.write(
            '<failure type="${testCase.outcome.name}" '
            'message="${_xml(_failureMessage(testCase))}"/>',
          );
        case CockpitRunOutcome.cancelled ||
            CockpitRunOutcome.interrupted ||
            CockpitRunOutcome.internalError:
          buffer.write(
            '<error type="${testCase.outcome.name}" '
            'message="${_xml(_failureMessage(testCase))}"/>',
          );
      }
      buffer.writeln('</testcase>');
    }
    if (report.failure case final failure?) {
      buffer
        ..write(
          '  <testcase classname="${_xml(report.suiteId)}" '
          'name="[suite cleanup]" time="0.000">',
        )
        ..write(
          '<error type="suiteCleanup" '
          'message="${_xml(failure.primary.message)}"/>',
        )
        ..writeln('</testcase>');
    }
    buffer.writeln('</testsuite>');
    return buffer.toString();
  }

  String summary(CockpitTestReportBundle bundle) {
    final report = bundle.report;
    final counts = report.counts;
    final buffer = StringBuffer()
      ..writeln('# Cockpit regression summary')
      ..writeln()
      ..writeln('- Run: `${report.runId}`')
      ..writeln('- Suite: `${report.suiteId}`')
      ..writeln('- Outcome: `${report.outcome.name}`')
      ..writeln('- Stability: `${report.stability.name}`')
      ..writeln('- Duration: `${report.durationMs} ms`')
      ..writeln(
        '- Counts: ${counts.passed} passed, ${counts.failed} failed, '
        '${counts.blocked} blocked, ${counts.skipped} skipped, '
        '${counts.flaky} flaky',
      )
      ..writeln('- Executions: ${bundle.executions.length}')
      ..writeln(
        '- Evidence files: ${bundle.executions.fold<int>(0, (total, item) => total + item.artifacts.length)}',
      );
    if (report.failure case final failure?) {
      buffer
        ..writeln()
        ..writeln('## Suite failure')
        ..writeln()
        ..writeln('- `${failure.primary.code}`: ${failure.primary.message}');
    }
    final actionable = report.cases.where(
      (item) =>
          item.outcome != CockpitRunOutcome.passed &&
          item.outcome != CockpitRunOutcome.skipped,
    );
    if (actionable.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Failures');
      for (final item in actionable) {
        buffer.writeln(
          '- `${item.entryId}` on `${item.targetId}`: '
          '`${item.outcome.name}`. ${_failureMessage(item)}',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('## Offline report')
      ..writeln()
      ..writeln('- Open `index.html` for the complete interactive report.')
      ..writeln('- Use `report.json` as the canonical rendering input.')
      ..writeln('- Verify every exported file with `manifest.json`.');
    return buffer.toString();
  }

  String eventsJsonl(CockpitTestReportBundle bundle) {
    final events = <Map<String, Object?>>[];
    final report = bundle.report;
    events.add(<String, Object?>{
      'schemaVersion': 'cockpit.report.event/v2',
      'timestamp': report.startedAt.toUtc().toIso8601String(),
      'kind': 'run.started',
      'runId': report.runId,
      'suiteId': report.suiteId,
    });
    for (final execution in bundle.executions) {
      final result = execution.result;
      events.add(<String, Object?>{
        'schemaVersion': 'cockpit.report.event/v2',
        'timestamp': result.startedAt.toUtc().toIso8601String(),
        'kind': 'attempt.started',
        'runId': report.runId,
        'caseId': result.context.caseId,
        'attemptId': result.context.attemptId,
        'role': execution.role.name,
      });
      for (final step in result.steps) {
        events.add(<String, Object?>{
          'schemaVersion': 'cockpit.report.event/v2',
          'timestamp': step.startedAt.toUtc().toIso8601String(),
          'kind': 'step.${step.status.name}',
          'runId': report.runId,
          'caseId': result.context.caseId,
          'attemptId': result.context.attemptId,
          'stepId': step.stepId,
          'stepExecutionId': step.executionId,
          'section': step.section,
          'durationMs': step.durationMs,
          if (step.error != null) 'error': step.error!.toJson(),
          if (step.evidence.isNotEmpty)
            'evidence': <Object?>[
              for (final evidenceId in step.evidence)
                execution.artifacts
                    .singleWhere(
                      (artifact) => artifact.evidenceId == evidenceId,
                    )
                    .toJson(),
            ],
        });
      }
      events.add(<String, Object?>{
        'schemaVersion': 'cockpit.report.event/v2',
        'timestamp': result.finishedAt.toUtc().toIso8601String(),
        'kind': 'attempt.completed',
        'runId': report.runId,
        'caseId': result.context.caseId,
        'attemptId': result.context.attemptId,
        'outcome': result.outcome.name,
        'durationMs': result.durationMs,
      });
    }
    events.add(<String, Object?>{
      'schemaVersion': 'cockpit.report.event/v2',
      'timestamp': report.finishedAt.toUtc().toIso8601String(),
      'kind': 'run.completed',
      'runId': report.runId,
      'suiteId': report.suiteId,
      'outcome': report.outcome.name,
      'stability': report.stability.name,
      'durationMs': report.durationMs,
    });
    events.sort(
      (left, right) => (left['timestamp']! as String).compareTo(
        right['timestamp']! as String,
      ),
    );
    return '${events.map(jsonEncode).join('\n')}\n';
  }

  String html(CockpitTestReportBundle bundle) => _htmlReport(bundle);
}

String _caseName(CockpitTestCaseReport report) {
  final matrix = report.matrix.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join(', ');
  return <String>[
    report.entryId,
    if (matrix.isNotEmpty) '[$matrix]',
    '@ ${report.targetId}',
  ].join(' ');
}

String _failureMessage(CockpitTestCaseReport report) {
  for (final attempt in report.attempts.reversed) {
    final message = attempt.failure?.primary.message;
    if (message != null) return message;
  }
  return 'The case did not produce a successful attempt.';
}

String _seconds(int milliseconds) => (milliseconds / 1000).toStringAsFixed(3);

String _xml(Object? value) => value
    .toString()
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _htmlReport(CockpitTestReportBundle bundle) {
  final report = bundle.report;
  final counts = report.counts;
  final reportTitle = report.definition.name ?? report.suiteId;
  final decision =
      report.outcome == CockpitRunOutcome.passed &&
          report.stability != CockpitRunStability.flaky
      ? 'Ready'
      : 'Review required';
  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_html(reportTitle)} regression report</title>
<style>
:root{color-scheme:light;--bg:#f4f6f7;--surface:#fff;--ink:#182124;--muted:#5b686e;--line:#d5dcdf;--line-strong:#aeb9be;--accent:#176b55;--accent-soft:#e1f2eb;--pass:#176b55;--fail:#b42318;--fail-soft:#fce8e6;--warn:#8a5700;--warn-soft:#fff0d5;--info:#315e91;--info-soft:#e6eef8}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}button,input{font:inherit}a{color:var(--accent);text-underline-offset:2px}.shell{width:min(1480px,100%);margin:0 auto;padding:24px}header{background:var(--surface);border-bottom:1px solid var(--line)}.title-row{display:flex;align-items:flex-start;justify-content:space-between;gap:24px}h1{margin:0;font-size:24px;line-height:1.25;letter-spacing:0}.meta,.subtle{color:var(--muted);overflow-wrap:anywhere}.meta{margin:7px 0 0}.report-description{max-width:72ch;margin:8px 0 0;color:#344148}.decision{min-width:150px;padding:10px 12px;border:1px solid var(--line-strong);border-radius:4px;background:#fafbfb}.decision strong,.decision span{display:block}.decision span{color:var(--muted);font-size:12px}.metrics{display:grid;grid-template-columns:repeat(11,minmax(90px,1fr));gap:1px;margin-top:22px;border:1px solid var(--line);border-radius:6px;overflow:hidden;background:var(--line)}.metric{min-width:0;padding:11px 13px;background:#fafbfb}.metric dt{color:var(--muted);font-size:11px;text-transform:uppercase}.metric dd{margin:2px 0 0;font-size:18px;font-weight:680}.lens-bar{position:sticky;top:0;z-index:10;background:rgba(244,246,247,.96);border-bottom:1px solid var(--line);backdrop-filter:blur(8px)}.lens-tabs{display:flex;gap:4px;overflow:auto;padding-top:10px;padding-bottom:10px}.lens-tab{white-space:nowrap;border:1px solid transparent;background:transparent;color:var(--muted);padding:7px 11px;border-radius:5px;cursor:pointer}.lens-tab:hover{background:#e9edef;color:var(--ink)}.lens-tab:focus-visible{outline:2px solid var(--info);outline-offset:2px}.lens-tab[aria-selected="true"]{background:var(--surface);border-color:var(--line-strong);color:var(--ink);font-weight:650}.lens{display:none}.lens.active{display:block}main.shell{padding-top:26px;padding-bottom:34px}.section{margin:0 0 30px}.section-head{display:flex;align-items:end;justify-content:space-between;gap:20px;margin-bottom:11px}h2{margin:0;font-size:18px;letter-spacing:0}h3{margin:0;font-size:15px;letter-spacing:0}.alert{padding:13px 15px;border:1px solid #e6aaa5;border-radius:4px;background:var(--fail-soft);margin-bottom:22px}.alert p{margin:3px 0 0}.table-wrap{overflow:auto;background:var(--surface);border:1px solid var(--line);border-radius:6px}table{width:100%;border-collapse:collapse;min-width:860px}th,td{padding:10px 12px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}th{background:#edf1f2;color:#344148;font-size:12px;font-weight:650}tbody tr:last-child td{border-bottom:0}.identity{display:block;color:var(--muted);font:12px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}.status,.stability{display:inline-block;padding:2px 7px;border-radius:999px;font-size:12px;font-weight:650}.status-passed{background:var(--accent-soft);color:var(--pass)}.status-failed,.status-internalError{background:var(--fail-soft);color:var(--fail)}.status-blocked,.status-interrupted{background:var(--warn-soft);color:var(--warn)}.status-cancelled,.status-skipped{background:#e8edf2;color:#3f4d55}.stability{margin-left:5px;background:var(--info-soft);color:var(--info)}.case-list{background:var(--surface);border:1px solid var(--line);border-radius:6px}.case-row{padding:15px 16px;border-bottom:1px solid var(--line)}.case-row:last-child{border-bottom:0}.case-row-head{display:flex;justify-content:space-between;gap:16px}.case-description{max-width:72ch;margin:8px 0 0;color:#344148}.case-meta{display:flex;flex-wrap:wrap;gap:6px 16px;margin-top:7px;color:var(--muted);font-size:12px}.tag-list{display:flex;flex-wrap:wrap;gap:5px;margin-top:9px}.tag{padding:2px 7px;border-radius:999px;background:#e8edf2;color:#3f4d55;font-size:11px}.gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:10px;margin-top:13px}.media{margin:0;min-width:0}.media img,.media video{display:block;width:100%;aspect-ratio:16/10;object-fit:contain;background:#101415;border:1px solid var(--line);border-radius:4px}.media figcaption{margin-top:4px;color:var(--muted);font-size:11px;overflow-wrap:anywhere}.execution{background:var(--surface);border:1px solid var(--line);border-radius:6px;margin-bottom:10px}.execution>summary{display:flex;align-items:center;gap:10px;cursor:pointer;padding:12px 14px;font-weight:650}.execution>summary::marker{color:var(--muted)}.execution-body{padding:0 14px 14px}.step-list{border-top:1px solid var(--line)}.step{display:grid;grid-template-columns:minmax(180px,1.2fr) 100px 90px minmax(220px,2fr);gap:12px;padding:9px 0;border-bottom:1px solid var(--line);align-items:start}.step:last-child{border-bottom:0}.step-error{color:var(--fail)}.artifact-links{display:flex;flex-wrap:wrap;gap:5px 12px}.machine-files{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px}.machine-file{display:block;background:var(--surface);border:1px solid var(--line);border-radius:6px;padding:13px;text-decoration:none}.machine-file strong,.machine-file span{display:block}.machine-file span{margin-top:3px;color:var(--muted);font-size:12px}code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px}footer{padding-top:0!important;color:var(--muted);font-size:12px}@media(max-width:1100px){.metrics{grid-template-columns:repeat(4,minmax(105px,1fr))}}@media(max-width:900px){.step{grid-template-columns:1fr 90px}.step>*:last-child{grid-column:1/-1}}@media(max-width:620px){.shell{padding:17px 13px}.title-row{display:block}.decision{margin-top:14px}.metrics{grid-template-columns:repeat(2,minmax(105px,1fr))}.case-row-head{display:block}.case-row-head .status{margin-top:7px}.gallery{grid-template-columns:1fr}.step{display:block}.step>*{display:block;margin-bottom:5px}}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important}}@media print{body{background:#fff}.lens-bar{display:none}.lens{display:block!important;break-before:page}.shell{width:100%;padding:12px 0}.table-wrap{overflow:visible}.execution{break-inside:avoid}.gallery{grid-template-columns:repeat(3,1fr)}}
</style>
</head>
<body>
<header><div class="shell">
  <div class="title-row"><div><h1>${_html(reportTitle)} regression report</h1><p class="meta">Suite <code>${_html(report.suiteId)}</code> · Run <code>${_html(report.runId)}</code> · ${_html(report.startedAt.toUtc().toIso8601String())} · ${_html(_duration(report.durationMs))}</p>${report.definition.description == null ? '' : '<p class="report-description">${_html(report.definition.description!)}</p>'}</div><div class="decision"><span>Release decision</span><strong>${_html(decision)}</strong></div></div>
  <dl class="metrics"><div class="metric"><dt>Outcome</dt><dd>${_html(report.outcome.name)}</dd></div><div class="metric"><dt>Total</dt><dd>${counts.total}</dd></div><div class="metric"><dt>Passed</dt><dd>${counts.passed}</dd></div><div class="metric"><dt>Failed</dt><dd>${counts.failed}</dd></div><div class="metric"><dt>Blocked</dt><dd>${counts.blocked}</dd></div><div class="metric"><dt>Skipped</dt><dd>${counts.skipped}</dd></div><div class="metric"><dt>Cancelled</dt><dd>${counts.cancelled}</dd></div><div class="metric"><dt>Interrupted</dt><dd>${counts.interrupted}</dd></div><div class="metric"><dt>Internal error</dt><dd>${counts.internalError}</dd></div><div class="metric"><dt>Flaky</dt><dd>${counts.flaky}</dd></div><div class="metric"><dt>Evidence</dt><dd>${_artifactCount(bundle)}</dd></div></dl>
</div></header>
<nav class="lens-bar" aria-label="Report views"><div class="shell lens-tabs" role="tablist"><button class="lens-tab" id="tab-overview" role="tab" aria-controls="overview" aria-selected="true" tabindex="0" data-lens="overview">Overview</button><button class="lens-tab" id="tab-product" role="tab" aria-controls="product" aria-selected="false" tabindex="-1" data-lens="product">Product</button><button class="lens-tab" id="tab-quality" role="tab" aria-controls="quality" aria-selected="false" tabindex="-1" data-lens="quality">Quality</button><button class="lens-tab" id="tab-engineering" role="tab" aria-controls="engineering" aria-selected="false" tabindex="-1" data-lens="engineering">Engineering</button><button class="lens-tab" id="tab-machine" role="tab" aria-controls="machine" aria-selected="false" tabindex="-1" data-lens="machine">Machine</button></div></nav>
<main class="shell">
  <section class="lens active" id="overview" role="tabpanel" aria-labelledby="tab-overview">${_overview(bundle)}</section>
  <section class="lens" id="product" role="tabpanel" aria-labelledby="tab-product">${_product(bundle)}</section>
  <section class="lens" id="quality" role="tabpanel" aria-labelledby="tab-quality">${_quality(bundle)}</section>
  <section class="lens" id="engineering" role="tabpanel" aria-labelledby="tab-engineering">${_engineering(bundle)}</section>
  <section class="lens" id="machine" role="tabpanel" aria-labelledby="tab-machine">${_machine(bundle)}</section>
</main>
<footer class="shell">Cockpit ${_html(bundle.schemaVersion)} · Source <code>${_html(report.sourceSha256)}</code> · Complete ${bundle.complete}</footer>
<script id="cockpit-report-data" type="application/json">${_scriptJson(bundle.toJson())}</script>
<script>(function(){var tabs=[].slice.call(document.querySelectorAll('.lens-tab'));function show(id,updateHash,moveFocus){tabs.forEach(function(tab){var active=tab.getAttribute('data-lens')===id;tab.setAttribute('aria-selected',String(active));tab.tabIndex=active?0:-1;document.getElementById(tab.getAttribute('data-lens')).classList.toggle('active',active);if(active&&moveFocus){tab.focus()}});if(updateHash){history.replaceState(null,'','#'+id)}}tabs.forEach(function(tab,index){tab.addEventListener('click',function(){show(tab.getAttribute('data-lens'),true,false)});tab.addEventListener('keydown',function(event){var next=index;if(event.key==='ArrowRight'){next=(index+1)%tabs.length}else if(event.key==='ArrowLeft'){next=(index+tabs.length-1)%tabs.length}else if(event.key==='Home'){next=0}else if(event.key==='End'){next=tabs.length-1}else{return}event.preventDefault();show(tabs[next].getAttribute('data-lens'),true,true)})});var initial=location.hash.slice(1);if(tabs.some(function(tab){return tab.getAttribute('data-lens')===initial})){show(initial,false,false)}})();</script>
</body>
</html>
''';
}

String _overview(CockpitTestReportBundle bundle) {
  final report = bundle.report;
  final failure = report.failure;
  final alert = failure == null
      ? ''
      : '<div class="alert"><h3>Suite failure</h3><p><code>${_html(failure.primary.code)}</code> ${_html(failure.primary.message)}</p></div>';
  return '''$alert<section class="section"><div class="section-head"><h2>Case results</h2><span class="subtle">${report.cases.length} cases · ${bundle.executions.length} executions</span></div>${_caseTable(report)}</section>
<section class="section"><div class="section-head"><h2>Action required</h2></div>${_actionTable(report)}</section>
<section class="section"><div class="section-head"><h2>Run context</h2><span class="subtle">Execution authority and environment</span></div>${_contextTable(report)}</section>''';
}

String _contextTable(CockpitTestSuiteReport report) {
  final rows = <MapEntry<String, Object?>>[
    MapEntry<String, Object?>('Project', report.projectId),
    MapEntry<String, Object?>('Workspace', report.workspaceId),
    MapEntry<String, Object?>('Suite', report.suiteId),
    MapEntry<String, Object?>('Source SHA-256', report.sourceSha256),
    ...report.environment.entries,
  ];
  return '<div class="table-wrap"><table><tbody>${rows.map((entry) => '<tr><th>${_html(entry.key)}</th><td><code>${_html(_compactValue(entry.value))}</code></td></tr>').join()}</tbody></table></div>';
}

String _caseTable(CockpitTestSuiteReport report) {
  final rows = StringBuffer();
  for (final testCase in report.cases) {
    final duration = testCase.attempts.fold<int>(
      0,
      (total, attempt) => total + attempt.durationMs,
    );
    final matrix = testCase.matrix.isEmpty
        ? 'None'
        : testCase.matrix.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join(', ');
    rows.write(
      '''<tr><td><strong>${_html(testCase.entryId)}</strong><span class="identity">${_html(testCase.caseId)}</span></td><td>${_status(testCase.outcome.name)}${testCase.stability == CockpitRunStability.flaky ? '<span class="stability">flaky</span>' : ''}</td><td>${_html(testCase.targetId)}</td><td>${_html(matrix)}</td><td>${testCase.attempts.length}</td><td>${_html(_duration(duration))}</td></tr>''',
    );
  }
  return '''<div class="table-wrap"><table><thead><tr><th>Case</th><th>Result</th><th>Target</th><th>Matrix</th><th>Attempts</th><th>Duration</th></tr></thead><tbody>$rows</tbody></table></div>''';
}

String _actionTable(CockpitTestSuiteReport report) {
  final actionable = report.cases
      .where(
        (item) =>
            item.outcome != CockpitRunOutcome.passed ||
            item.stability == CockpitRunStability.flaky,
      )
      .toList(growable: false);
  if (actionable.isEmpty) {
    return '<div class="case-list"><div class="case-row"><strong>No action required</strong><div class="subtle">All selected cases passed without retries.</div></div></div>';
  }
  final rows = StringBuffer();
  for (final testCase in actionable) {
    rows.write(
      '''<tr><td><strong>${_html(testCase.entryId)}</strong><span class="identity">${_html(testCase.caseId)}</span></td><td>${_status(testCase.outcome.name)}</td><td>${_html(_failureMessage(testCase))}</td><td>${testCase.attempts.length}</td></tr>''',
    );
  }
  return '''<div class="table-wrap"><table><thead><tr><th>Case</th><th>Result</th><th>Reason</th><th>Attempts</th></tr></thead><tbody>$rows</tbody></table></div>''';
}

String _product(CockpitTestReportBundle bundle) {
  final report = bundle.report;
  final content = StringBuffer();
  for (final testCase in report.cases) {
    final definition = testCase.definition;
    final executionIds = testCase.attempts
        .map((attempt) => attempt.attemptId)
        .toSet();
    final executions = bundle.executions
        .where(
          (execution) =>
              execution.entryId == testCase.entryId &&
              executionIds.contains(execution.result.context.attemptId),
        )
        .toList(growable: false);
    final visual = <CockpitTestReportArtifact>[
      for (final execution in executions)
        ...execution.artifacts.where(
          (artifact) =>
              artifact.mediaType.startsWith('image/') ||
              artifact.mediaType.startsWith('video/'),
        ),
    ];
    final matrix = testCase.matrix.entries
        .map((entry) => '${entry.key}=${_compactValue(entry.value)}')
        .join(', ');
    final tags = definition.tags.isEmpty
        ? ''
        : '<div class="tag-list">${definition.tags.map((tag) => '<span class="tag">${_html(tag)}</span>').join()}</div>';
    content.write(
      '''<article class="case-row"><div class="case-row-head"><div><h3>${_html(definition.name ?? testCase.entryId)}</h3><span class="identity">${_html(testCase.entryId)} · ${_html(testCase.caseId)}</span></div><div>${_status(testCase.outcome.name)}${testCase.stability == CockpitRunStability.flaky ? '<span class="stability">flaky</span>' : ''}</div></div>${definition.description == null ? '' : '<p class="case-description">${_html(definition.description!)}</p>'}<div class="case-meta"><span>Target ${_html(testCase.targetId)}</span><span>${testCase.attempts.length} attempt${testCase.attempts.length == 1 ? '' : 's'}</span>${matrix.isEmpty ? '' : '<span>Matrix ${_html(matrix)}</span>'}<span>${_html(_failureMessageForProduct(testCase))}</span></div>$tags${_gallery(visual)}</article>''',
    );
  }
  return '''<section class="section"><div class="section-head"><h2>Business flows</h2><span class="subtle">Outcome and visual evidence</span></div><div class="case-list">$content</div></section>''';
}

String _gallery(List<CockpitTestReportArtifact> artifacts) {
  if (artifacts.isEmpty) return '';
  final content = StringBuffer();
  for (final artifact in artifacts) {
    final source = _attribute(artifact.relativePath);
    final media = artifact.mediaType.startsWith('video/')
        ? '<video controls preload="metadata" src="$source"></video>'
        : '<a href="$source"><img loading="lazy" src="$source" alt="${_attribute(artifact.kind)} evidence"></a>';
    content.write(
      '''<figure class="media">$media<figcaption>${_html(artifact.kind)} · ${_html(_bytes(artifact.sizeBytes))}</figcaption></figure>''',
    );
  }
  return '<div class="gallery">$content</div>';
}

String _quality(CockpitTestReportBundle bundle) {
  final content = StringBuffer();
  for (final execution in bundle.executions) {
    final result = execution.result;
    final passed = result.steps
        .where((step) => step.status == CockpitTestStepStatus.passed)
        .length;
    content.write(
      '''<details class="execution"><summary>${_status(result.outcome.name)} <span>${_html(execution.entryId ?? result.context.caseId)}</span><span class="subtle">${_html(execution.role.name)} · $passed/${result.steps.length} steps · ${_html(_duration(result.durationMs))}</span></summary><div class="execution-body"><div class="case-meta"><span>Attempt <code>${_html(result.context.attemptId)}</code></span><span>Target <code>${_html(result.targetId)}</code></span><span>Platform ${_html(result.platform)}</span></div>${_steps(execution, engineering: false)}</div></details>''',
    );
  }
  if (content.isEmpty) {
    content.write(
      '<div class="alert"><h3>No execution trace</h3><p>The run completed before an attempt manifest was published.</p></div>',
    );
  }
  return '''<section class="section"><div class="section-head"><h2>Execution trace</h2><span class="subtle">Setup, main, finally, retries and loops</span></div>$content</section>''';
}

String _engineering(CockpitTestReportBundle bundle) {
  final prioritized = bundle.executions.toList(growable: false)
    ..sort((left, right) {
      final leftFailed = left.result.outcome == CockpitTestOutcome.passed
          ? 1
          : 0;
      final rightFailed = right.result.outcome == CockpitTestOutcome.passed
          ? 1
          : 0;
      final outcome = leftFailed.compareTo(rightFailed);
      return outcome != 0
          ? outcome
          : left.result.startedAt.compareTo(right.result.startedAt);
    });
  final content = StringBuffer();
  for (final execution in prioritized) {
    final result = execution.result;
    final primary = result.primaryError;
    content.write(
      '''<details class="execution" ${primary == null ? '' : 'open'}><summary>${_status(result.outcome.name)} <span>${_html(execution.entryId ?? result.context.caseId)}</span><span class="subtle">${_html(result.requestedPlane.name)} → ${_html(result.actualPlane?.name ?? 'unresolved')}</span></summary><div class="execution-body">${primary == null ? '' : '<div class="alert"><h3>${_html(primary.code.name)}</h3><p>${_html(primary.message)}</p></div>'}<div class="case-meta"><span>Attempt <code>${_html(result.context.attemptId)}</code></span><span>Target <code>${_html(result.targetId)}</code></span><span>${_html(result.platform)}</span><span>${_html(_duration(result.durationMs))}</span></div>${_steps(execution, engineering: true)}${_artifactLinks(execution.artifacts)}</div></details>''',
    );
  }
  return '''<section class="section"><div class="section-head"><h2>Diagnostics</h2><span class="subtle">Failures, drivers, locators and evidence</span></div>$content</section>''';
}

String _steps(
  CockpitTestReportExecution execution, {
  required bool engineering,
}) {
  if (execution.result.steps.isEmpty) {
    return '<p class="subtle">No executable step completed.</p>';
  }
  final content = StringBuffer('<div class="step-list">');
  for (final step in execution.result.steps) {
    final evidence = <CockpitTestReportArtifact>[
      for (final evidenceId in step.evidence)
        execution.artifacts.singleWhere(
          (artifact) => artifact.evidenceId == evidenceId,
        ),
    ];
    final diagnostic = engineering
        ? <String>[
            if (step.driverId != null) 'driver=${step.driverId}',
            if (step.actualPlane != null) 'plane=${step.actualPlane!.name}',
            if (step.locatorResolution case final locator?)
              'locator=${locator.matchedKind.name}:${locator.matchedValue}',
            if (step.locatorResolution?.matchedSignals case final signals?
                when signals.isNotEmpty)
              'signals=${signals.entries.map((entry) => '${entry.key}=${entry.value}').join(',')}',
            if (step.degradationReason != null)
              'degraded=${step.degradationReason}',
          ].join(' · ')
        : '${step.section}${step.occurrence.retryAttempt == null ? '' : ' · retry ${step.occurrence.retryAttempt}'}${step.occurrence.loopIteration == null ? '' : ' · loop ${step.occurrence.loopIteration}'}';
    final identity = <String>[
      step.executionId,
      if (step.operation != null) step.operation!,
      if (step.timeoutMs != null) 'timeout=${step.timeoutMs}ms',
      if (step.definitionPath != null) step.definitionPath!,
    ].join(' · ');
    content.write(
      '''<div class="step"><div><strong>${_html(step.description ?? step.stepId)}</strong>${step.description == null ? '' : '<span class="subtle">${_html(step.stepId)}</span>'}<span class="identity">${_html(identity)}</span></div><div>${_status(step.status.name)}</div><div>${_html(_duration(step.durationMs))}</div><div><span class="subtle">${_html(diagnostic)}</span>${step.error == null ? '' : '<div class="step-error"><code>${_html(step.error!.code.name)}</code> ${_html(step.error!.message)}</div>'}${_artifactLinks(evidence)}</div></div>''',
    );
  }
  content.write('</div>');
  return content.toString();
}

String _artifactLinks(List<CockpitTestReportArtifact> artifacts) {
  if (artifacts.isEmpty) return '';
  return '<div class="artifact-links">${artifacts.map((artifact) => '<a href="${_attribute(artifact.relativePath)}">${_html(artifact.kind)}</a>').join()}</div>';
}

String _machine(CockpitTestReportBundle bundle) {
  const files = <(String, String, String)>[
    (
      'report.json',
      'Canonical report',
      'Complete fact graph and evidence index',
    ),
    (
      'manifest.json',
      'Integrity manifest',
      'Path, ownership, size and SHA-256',
    ),
    ('junit.xml', 'JUnit', 'CI test result interchange'),
    ('summary.md', 'Summary', 'Portable human-readable regression summary'),
    ('run/run.json', 'Run', 'Run-level facts and environment'),
    ('run/events.jsonl', 'Events', 'Chronological machine-readable trace'),
  ];
  final links = files
      .map(
        (file) =>
            '<a class="machine-file" href="${_attribute(file.$1)}"><strong>${_html(file.$2)}</strong><span>${_html(file.$1)} · ${_html(file.$3)}</span></a>',
      )
      .join();
  return '''<section class="section"><div class="section-head"><h2>Machine exports</h2><span class="subtle">${_html(bundle.schemaVersion)}</span></div><div class="machine-files">$links</div></section><section class="section"><div class="section-head"><h2>Contract</h2></div><div class="table-wrap"><table><tbody><tr><th>Run</th><td><code>${_html(bundle.report.runId)}</code></td></tr><tr><th>Workspace</th><td><code>${_html(bundle.report.workspaceId)}</code></td></tr><tr><th>Source SHA-256</th><td><code>${_html(bundle.report.sourceSha256)}</code></td></tr><tr><th>Executions</th><td>${bundle.executions.length}</td></tr><tr><th>Evidence files</th><td>${_artifactCount(bundle)}</td></tr><tr><th>Complete</th><td>${bundle.complete}</td></tr></tbody></table></div></section>''';
}

String _status(String value) =>
    '<span class="status status-${_attribute(value)}">${_html(value)}</span>';

String _failureMessageForProduct(CockpitTestCaseReport report) =>
    report.outcome == CockpitRunOutcome.passed
    ? 'Completed'
    : _failureMessage(report);

int _artifactCount(CockpitTestReportBundle bundle) => bundle.executions
    .fold<int>(0, (total, execution) => total + execution.artifacts.length);

String _duration(int milliseconds) {
  if (milliseconds < 1000) return '$milliseconds ms';
  final seconds = milliseconds / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(2)} s';
  final minutes = seconds ~/ 60;
  final remainder = (seconds - minutes * 60).toStringAsFixed(1);
  return '$minutes min $remainder s';
}

String _bytes(int value) {
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
}

String _compactValue(Object? value) =>
    value is String ? value : const JsonEncoder().convert(value);

String _scriptJson(Object? value) => jsonEncode(value)
    .replaceAll('<', r'\u003c')
    .replaceAll('>', r'\u003e')
    .replaceAll('&', r'\u0026')
    .replaceAll('\u2028', r'\u2028')
    .replaceAll('\u2029', r'\u2029');

String _html(Object? value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value.toString());

String _attribute(Object? value) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(value.toString());
