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

String _failureCode(CockpitTestCaseReport report) {
  for (final attempt in report.attempts.reversed) {
    final code = attempt.failure?.primary.code;
    if (code != null) return code;
  }
  return report.outcome.name;
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
  final gatePassed =
      report.outcome == CockpitRunOutcome.passed &&
      report.stability != CockpitRunStability.flaky &&
      report.complete &&
      bundle.complete;
  final decision = gatePassed ? 'Gate passed' : 'Review required';
  final attentionCount = report.cases.where(_caseRequiresAttention).length;
  final stepCount = bundle.executions.fold<int>(
    0,
    (total, execution) => total + execution.result.steps.length,
  );
  final passRate = counts.total == 0
      ? '0%'
      : '${(counts.passed * 100 / counts.total).toStringAsFixed(1)}%';
  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_html(reportTitle)} | Cockpit report</title>
<script>document.documentElement.classList.add('js')</script>
<style>
:root{color-scheme:light;--canvas:#f3f5f5;--surface:#fff;--surface-muted:#f8f9f9;--ink:#172124;--ink-soft:#344247;--muted:#65747a;--line:#d9dfe1;--line-strong:#b6c0c4;--accent:#08745d;--accent-soft:#e3f3ed;--pass:#08745d;--pass-soft:#e3f3ed;--fail:#b42318;--fail-soft:#fdebea;--warn:#8a5700;--warn-soft:#fff1d6;--info:#285f91;--info-soft:#e8f0f8;--shadow:0 1px 2px rgba(23,33,36,.05)}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--canvas);color:var(--ink);font:14px/1.5 system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-variant-numeric:tabular-nums}button,input,select{font:inherit;letter-spacing:0}a{color:var(--accent);text-underline-offset:3px}a:hover{text-decoration-thickness:2px}:focus-visible{outline:3px solid rgba(40,95,145,.38);outline-offset:2px}.shell{width:min(1520px,100%);margin:0 auto;padding-left:28px;padding-right:28px}.report-header{background:var(--surface);border-bottom:1px solid var(--line)}.header-inner{padding-top:22px;padding-bottom:22px}.brand-line{display:flex;align-items:center;gap:10px;color:var(--muted);font-size:12px;font-weight:650}.brand-mark{display:grid;width:28px;height:28px;place-items:center;border-radius:6px;background:var(--ink);color:#fff;font-size:14px;font-weight:760}.brand-divider{width:1px;height:15px;background:var(--line-strong)}.title-row{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:28px;align-items:end;margin-top:18px}h1{margin:0;font-size:25px;line-height:1.22;letter-spacing:0}.meta,.subtle{color:var(--muted);overflow-wrap:anywhere}.meta{display:flex;flex-wrap:wrap;gap:5px 14px;margin:8px 0 0}.report-description{max-width:75ch;margin:9px 0 0;color:var(--ink-soft)}.decision{min-width:190px;padding:13px 15px;border:1px solid var(--line-strong);border-radius:6px;background:var(--surface-muted);box-shadow:var(--shadow)}.decision-pass{border-color:#9bc9ba;background:var(--pass-soft)}.decision-review{border-color:#e0bc73;background:var(--warn-soft)}.decision strong,.decision span{display:block}.decision strong{margin-top:2px;font-size:16px}.decision span{color:var(--muted);font-size:11px}.metrics{display:grid;grid-template-columns:repeat(6,minmax(110px,1fr));margin:21px 0 0;border:1px solid var(--line);border-radius:6px;overflow:hidden;background:var(--line);gap:1px}.metric{min-width:0;padding:11px 13px;background:var(--surface-muted)}.metric dt{color:var(--muted);font-size:11px;text-transform:uppercase}.metric dd{margin:1px 0 0;font-size:18px;font-weight:700}.metric-attention dd{color:var(--warn)}.workspace{display:grid;grid-template-columns:214px minmax(0,1fr);gap:32px;padding-top:24px;padding-bottom:36px}.lens-bar{align-self:start;position:sticky;top:18px}.nav-kicker{padding:0 10px 8px;color:var(--muted);font-size:11px;font-weight:650}.lens-tabs{display:flex;flex-direction:column;gap:3px}.lens-tab{display:flex;width:100%;align-items:center;justify-content:space-between;gap:12px;border:1px solid transparent;background:transparent;color:var(--muted);padding:8px 10px;border-radius:6px;cursor:pointer;text-align:left}.lens-tab:hover{background:#e9eded;color:var(--ink)}.lens-tab[aria-selected="true"]{background:var(--surface);border-color:var(--line);color:var(--ink);font-weight:680;box-shadow:var(--shadow)}.nav-count{min-width:24px;color:var(--muted);font-size:11px;text-align:right}.integrity{margin:18px 10px 0;padding-top:14px;border-top:1px solid var(--line);color:var(--muted);font-size:11px}.integrity strong{display:block;color:var(--ink-soft);font-size:12px}.integrity-dot{display:inline-block;width:7px;height:7px;margin-right:6px;border-radius:50%;background:var(--pass)}.integrity-dot.incomplete{background:var(--warn)}.report-main{min-width:0}.lens{display:block}.js .lens{display:none}.js .lens.active{display:block}.section{margin:0 0 30px;scroll-margin-top:20px}.section-head{display:flex;align-items:end;justify-content:space-between;gap:20px;margin-bottom:12px}.section-head p{margin:3px 0 0;color:var(--muted)}h2{margin:0;font-size:19px;line-height:1.3;letter-spacing:0}h3{margin:0;font-size:15px;letter-spacing:0}.alert{padding:14px 16px;border:1px solid #ebaaa5;border-radius:6px;background:var(--fail-soft);margin-bottom:22px}.alert p{margin:4px 0 0}.summary-band{display:grid;grid-template-columns:minmax(210px,.8fr) minmax(0,2fr);border:1px solid var(--line);border-radius:6px;background:var(--surface);overflow:hidden;box-shadow:var(--shadow)}.summary-verdict{padding:20px;border-right:1px solid var(--line)}.summary-verdict strong{display:block;margin-top:3px;font-size:22px}.summary-verdict p{margin:6px 0 0;color:var(--muted)}.count-grid{display:grid;grid-template-columns:repeat(4,minmax(90px,1fr))}.count-item{padding:14px 16px;border-right:1px solid var(--line);border-bottom:1px solid var(--line)}.count-item:nth-child(4n){border-right:0}.count-item:nth-last-child(-n+4){border-bottom:0}.count-item span,.count-item strong{display:block}.count-item span{color:var(--muted);font-size:11px}.count-item strong{margin-top:2px;font-size:17px}.filter-bar{display:flex;align-items:end;gap:10px;margin-bottom:12px;padding:10px;border:1px solid var(--line);border-radius:6px;background:var(--surface)}.field{display:grid;gap:4px}.field-search{min-width:240px;flex:1}.field span{color:var(--muted);font-size:11px;font-weight:650}input[type="search"],select{min-height:36px;border:1px solid var(--line-strong);border-radius:5px;background:#fff;color:var(--ink);padding:7px 10px}input[type="search"]{width:100%}.filter-count{margin-left:auto;padding:8px 4px;color:var(--muted);white-space:nowrap}.button-group{display:flex;gap:6px}.quiet-button{min-height:36px;border:1px solid var(--line-strong);border-radius:5px;background:var(--surface);color:var(--ink-soft);padding:7px 10px;cursor:pointer}.quiet-button:hover{background:#eef1f1}.table-wrap{overflow:auto;background:var(--surface);border:1px solid var(--line);border-radius:6px;box-shadow:var(--shadow)}table{width:100%;border-collapse:collapse;min-width:800px}th,td{padding:10px 12px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}th{background:#eef1f1;color:var(--ink-soft);font-size:11px;font-weight:680;text-transform:uppercase}tbody tr:last-child td{border-bottom:0}tbody tr:hover td{background:#fbfcfc}.identity{display:block;color:var(--muted);font:11px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}.status,.stability{display:inline-flex;align-items:center;padding:2px 7px;border:1px solid transparent;border-radius:999px;font-size:11px;font-weight:700}.status::before{content:"";width:6px;height:6px;margin-right:5px;border-radius:50%;background:currentColor}.status-passed{background:var(--pass-soft);color:var(--pass)}.status-failed,.status-internalError{background:var(--fail-soft);color:var(--fail)}.status-blocked,.status-interrupted{background:var(--warn-soft);color:var(--warn)}.status-cancelled,.status-skipped,.status-pending,.status-running{background:#e9edef;color:#46575d}.stability{margin-left:5px;background:var(--info-soft);color:var(--info)}.case-list{background:var(--surface);border:1px solid var(--line);border-radius:6px;box-shadow:var(--shadow)}.case-row{padding:16px;border-bottom:1px solid var(--line);scroll-margin-top:20px}.case-row:last-child{border-bottom:0}.case-row:target,.execution:target{box-shadow:inset 1px 0 var(--accent)}.case-row-head{display:flex;justify-content:space-between;gap:16px}.case-row h3 a{color:inherit;text-decoration:none}.case-row h3 a:hover{color:var(--accent)}.case-description{max-width:75ch;margin:8px 0 0;color:var(--ink-soft)}.case-meta{display:flex;flex-wrap:wrap;gap:6px 16px;margin-top:8px;color:var(--muted);font-size:12px}.tag-list{display:flex;flex-wrap:wrap;gap:5px;margin-top:9px}.tag{padding:2px 7px;border-radius:999px;background:#e9edef;color:#46575d;font-size:11px}.gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:12px;margin-top:14px}.media{min-width:0;margin:0;border:1px solid var(--line);border-radius:6px;background:var(--surface);overflow:hidden}.media-frame{display:grid;min-height:140px;place-items:center;background:#161b1d}.media img,.media video{display:block;width:100%;height:auto;max-height:440px;object-fit:contain}.media figcaption{padding:9px 10px;color:var(--muted);font-size:11px;overflow-wrap:anywhere}.media figcaption strong{display:block;color:var(--ink-soft);font-size:12px}.execution{background:var(--surface);border:1px solid var(--line);border-radius:6px;margin-bottom:9px;scroll-margin-top:20px;box-shadow:var(--shadow)}.execution>summary{display:grid;grid-template-columns:auto minmax(160px,1fr) minmax(180px,auto);align-items:center;gap:10px;cursor:pointer;padding:12px 14px;font-weight:650}.execution>summary::marker{color:var(--muted)}.execution[open]>summary{border-bottom:1px solid var(--line)}.execution-body{padding:13px 14px 15px}.step-list{margin-top:12px;border-top:1px solid var(--line)}.step{display:grid;grid-template-columns:minmax(190px,1.2fr) 95px 82px minmax(230px,2fr);gap:12px;padding:10px 0;border-bottom:1px solid var(--line);align-items:start;scroll-margin-top:20px}.step:last-child{border-bottom:0}.step-error{margin-top:5px;color:var(--fail)}.artifact-links{display:flex;flex-wrap:wrap;gap:5px 12px;margin-top:6px}.artifact-links a{overflow-wrap:anywhere}.empty-filter{display:none;padding:24px;border:1px dashed var(--line-strong);border-radius:6px;background:var(--surface);color:var(--muted);text-align:center}.machine-files{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:10px}.machine-file{display:block;background:var(--surface);border:1px solid var(--line);border-radius:6px;padding:13px;text-decoration:none;box-shadow:var(--shadow)}.machine-file:hover{border-color:var(--accent)}.machine-file strong,.machine-file span{display:block}.machine-file span{margin-top:3px;color:var(--muted);font-size:11px}.json-view{max-height:420px;overflow:auto;margin:0;border:1px solid var(--line);border-radius:6px;background:#202729;color:#eef4f3;padding:14px;font:11px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace;white-space:pre-wrap;overflow-wrap:anywhere}code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px}.report-footer{padding-top:8px;border-top:1px solid var(--line);color:var(--muted);font-size:11px}.report-footer code{overflow-wrap:anywhere}
/* Cockpit report visual system: high-signal hierarchy for repeated triage. */
.report-header{background:#182124;color:#f7faf9;border-bottom:0}.header-inner{padding-top:24px;padding-bottom:26px}.brand-line{flex-wrap:wrap;color:#c4cfcc}.brand-mark{background:#16a47d;color:#071f19}.brand-divider{background:#53605e}.title-row{margin-top:22px;align-items:center}h1{font-size:30px;text-wrap:balance}.report-header .meta,.report-header .report-description{color:#c4cfcc}.report-header code{color:#eef5f3}.decision{box-shadow:none;background:#232d2f;border-color:#53605e}.decision span{color:#b5c0bd}.decision-pass{background:#173c32;border-color:#3b8f76}.decision-review{background:#3b311d;border-color:#a87b2f}.metrics{margin-top:24px;border-color:#3a4648;background:#3a4648;box-shadow:0 1px 0 rgba(255,255,255,.04)}.metric{padding:13px 15px;background:#222c2e}.metric dt{color:#aeb9b6;letter-spacing:0}.metric dd{color:#f7faf9;font-size:19px}.metric-attention dd{color:#ffd078}.workspace{gap:38px;padding-top:30px}.nav-kicker{padding-left:11px;font-weight:700}.lens-tab{min-height:38px;padding:9px 11px}.lens-tab:hover{background:#e7ecea}.lens-tab[aria-selected="true"]{background:#1f292b;border-color:#1f292b;color:#fff;box-shadow:none}.lens-tab[aria-selected="true"] .nav-count{color:#91dac5}.integrity{margin-top:20px}.integrity strong{margin-bottom:3px}.section{margin-bottom:34px}.section-head{margin-bottom:14px}.section-head p{max-width:72ch}.alert{padding:16px 18px;border-color:#e6a29c;background:#fff0ef}.summary-band{border-color:#cbd4d2;box-shadow:none}.summary-verdict{padding:22px;background:#f6f8f7}.summary-verdict strong{font-size:24px}.count-item{padding:15px 17px}.count-item strong{font-size:19px}.outcome-block{grid-column:1/-1;padding:13px 16px;border-top:1px solid var(--line);background:#fbfcfc}.outcome-label{display:flex;justify-content:space-between;gap:16px;margin-bottom:7px;color:var(--muted);font-size:11px}.outcome-track{display:flex;height:8px;overflow:hidden;border-radius:4px;background:#e6ebea}.outcome-segment{min-width:3px}.outcome-passed{background:var(--pass)}.outcome-failed,.outcome-internalError{background:var(--fail)}.outcome-blocked,.outcome-interrupted{background:var(--warn)}.outcome-cancelled{background:#6c7a80}.outcome-skipped{background:#aeb9bc}.filter-bar{padding:12px;border-color:#cbd4d2;box-shadow:none}.field span{font-weight:700}input[type="search"],select{background:#fff;border-color:#aebbb8}.quiet-button{font-weight:650}.quiet-button:hover{background:#e8eeec}.table-wrap,.case-list,.execution,.machine-file{border-color:#cbd4d2;box-shadow:none}th{background:#e9eeec;color:#354440;letter-spacing:0}tbody tr:hover td{background:#f4f8f6}.case-row{padding:18px}.case-row:target,.execution:target{box-shadow:inset 0 0 0 2px #70bca6}.media{border-color:#cbd4d2}.media-frame{background:#11191b}.execution>summary{padding:14px 15px}.step{padding:12px 0}.machine-file{padding:15px}.machine-file:hover{background:#f6faf8}.json-view{background:#151e20;color:#e9f1ef;border-color:#151e20}.report-footer{padding-top:14px}
@media(max-width:1100px){.workspace{grid-template-columns:minmax(0,1fr);gap:20px;padding-top:0}.lens-bar{position:sticky;top:0;z-index:20;margin-left:-28px;margin-right:-28px;padding:8px 28px;border-bottom:1px solid var(--line);background:rgba(243,245,245,.97);backdrop-filter:blur(10px)}.nav-kicker,.integrity{display:none}.lens-tabs{flex-direction:row;overflow:auto}.lens-tab{width:auto;min-height:44px;white-space:nowrap}.metrics{grid-template-columns:repeat(3,minmax(110px,1fr))}.report-main{padding-top:4px}}
@media(max-width:760px){.shell{padding-left:16px;padding-right:16px}.header-inner{padding-top:16px;padding-bottom:17px}.title-row{grid-template-columns:1fr;margin-top:14px}.decision{min-width:0}.metrics{grid-template-columns:repeat(2,minmax(100px,1fr))}.workspace{padding-bottom:24px}.lens-bar{margin-left:-16px;margin-right:-16px;padding-left:16px;padding-right:16px}.section-head{display:block}.section-head>.subtle{display:block;margin-top:4px}.summary-band{grid-template-columns:1fr}.summary-verdict{border-right:0;border-bottom:1px solid var(--line)}.count-grid{grid-template-columns:repeat(2,minmax(90px,1fr))}.count-item:nth-child(2n){border-right:0}.count-item:nth-child(odd){border-right:1px solid var(--line)}.count-item:nth-last-child(-n+4){border-bottom:1px solid var(--line)}.count-item:nth-last-child(-n+2){border-bottom:0}.filter-bar{align-items:stretch;flex-direction:column}.field-search{min-width:0}.filter-count{margin-left:0;padding:0}input[type="search"],select,.quiet-button{min-height:44px}.button-group{flex-wrap:wrap}.case-row-head{display:block}.case-row-head>div:last-child{margin-top:7px}.gallery{grid-template-columns:1fr}.execution>summary{grid-template-columns:auto 1fr}.execution>summary>*:last-child{grid-column:2}.step{display:block}.step>*{display:block;margin-bottom:6px}.table-wrap{margin-right:-16px;border-right:0;border-radius:6px 0 0 6px}}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}*{transition:none!important}}
@media print{body{background:#fff}.report-header{border-bottom:2px solid #000}.workspace{display:block;padding:12px 0}.lens-bar,.filter-bar,.button-group{display:none!important}.js .lens{display:block!important;break-before:page}.shell{width:100%;padding-left:0;padding-right:0}.table-wrap{overflow:visible;box-shadow:none}.execution{break-inside:avoid;box-shadow:none}.gallery{grid-template-columns:repeat(2,1fr)}.report-footer{margin-top:24px}}
</style>
</head>
<body>
<header class="report-header"><div class="shell header-inner">
  <div class="brand-line"><span class="brand-mark" aria-hidden="true">C</span><span>Cockpit regression report</span><span class="brand-divider" aria-hidden="true"></span><span>Generated <time datetime="${_attribute(bundle.generatedAt.toIso8601String())}">${_html(bundle.generatedAt.toIso8601String())}</time></span></div>
  <div class="title-row"><div><h1>${_html(reportTitle)}</h1><p class="meta"><span>Suite <code>${_html(report.suiteId)}</code></span><span>Run <code>${_html(report.runId)}</code></span><span><time datetime="${_attribute(report.startedAt.toUtc().toIso8601String())}">${_html(report.startedAt.toUtc().toIso8601String())}</time></span></p>${report.definition.description == null ? '' : '<p class="report-description">${_html(report.definition.description!)}</p>'}</div><div class="decision ${gatePassed ? 'decision-pass' : 'decision-review'}"><span>Release gate</span><strong>${_html(decision)}</strong></div></div>
  <dl class="metrics"><div class="metric"><dt>Outcome</dt><dd>${_html(_humanize(report.outcome.name))}</dd></div><div class="metric"><dt>Pass rate</dt><dd>$passRate</dd></div><div class="metric metric-attention"><dt>Needs attention</dt><dd>$attentionCount</dd></div><div class="metric"><dt>Executions</dt><dd>${bundle.executions.length}</dd></div><div class="metric"><dt>Steps</dt><dd>$stepCount</dd></div><div class="metric"><dt>Duration</dt><dd>${_html(_duration(report.durationMs))}</dd></div></dl>
</div></header>
<div class="workspace shell">
<nav class="lens-bar" aria-label="Report sections"><div class="nav-kicker">Report sections</div><div class="lens-tabs" role="tablist" aria-orientation="vertical"><button class="lens-tab" id="tab-summary" role="tab" aria-controls="summary" aria-selected="true" tabindex="0" data-lens="summary"><span>Summary</span><span class="nav-count">1</span></button><button class="lens-tab" id="tab-coverage" role="tab" aria-controls="coverage" aria-selected="false" tabindex="-1" data-lens="coverage"><span>Coverage</span><span class="nav-count">${counts.total}</span></button><button class="lens-tab" id="tab-executions" role="tab" aria-controls="executions" aria-selected="false" tabindex="-1" data-lens="executions"><span>Executions</span><span class="nav-count">${bundle.executions.length}</span></button><button class="lens-tab" id="tab-evidence" role="tab" aria-controls="evidence" aria-selected="false" tabindex="-1" data-lens="evidence"><span>Evidence</span><span class="nav-count">${_artifactCount(bundle)}</span></button><button class="lens-tab" id="tab-diagnostics" role="tab" aria-controls="diagnostics" aria-selected="false" tabindex="-1" data-lens="diagnostics"><span>Diagnostics</span><span class="nav-count">$attentionCount</span></button><button class="lens-tab" id="tab-environment" role="tab" aria-controls="environment" aria-selected="false" tabindex="-1" data-lens="environment"><span>Environment &amp; files</span></button></div><div class="integrity"><strong><span class="integrity-dot${report.complete && bundle.complete ? '' : ' incomplete'}"></span>${report.complete && bundle.complete ? 'Bundle declared complete' : 'Bundle incomplete'}</strong>${report.complete && bundle.complete ? 'Verify exported files against manifest.json.' : 'Inspect missing terminal data and bundle files.'}</div></nav>
<main class="report-main">
  <section class="lens active" id="summary" role="tabpanel" aria-labelledby="tab-summary">${_overview(bundle, gatePassed: gatePassed)}</section>
  <section class="lens" id="coverage" role="tabpanel" aria-labelledby="tab-coverage">${_coverage(bundle)}</section>
  <section class="lens" id="executions" role="tabpanel" aria-labelledby="tab-executions">${_executions(bundle)}</section>
  <section class="lens" id="evidence" role="tabpanel" aria-labelledby="tab-evidence">${_evidence(bundle)}</section>
  <section class="lens" id="diagnostics" role="tabpanel" aria-labelledby="tab-diagnostics">${_diagnostics(bundle)}</section>
  <section class="lens" id="environment" role="tabpanel" aria-labelledby="tab-environment">${_machine(bundle)}</section>
  <footer class="report-footer">Cockpit ${_html(bundle.schemaVersion)} · Source <code>${_html(report.sourceSha256)}</code> · Complete ${bundle.complete}</footer>
</main></div>
<script id="cockpit-report-data" type="application/json">${_scriptJson(bundle.toJson())}</script>
<script>(function(){
var tabs=[].slice.call(document.querySelectorAll('.lens-tab'));
var tablist=document.querySelector('.lens-tabs'),compact=window.matchMedia('(max-width:1100px)');
function orientation(){tablist.setAttribute('aria-orientation',compact.matches?'horizontal':'vertical')}
function show(id,updateHash,moveFocus){tabs.forEach(function(tab){var active=tab.dataset.lens===id;tab.setAttribute('aria-selected',String(active));tab.tabIndex=active?0:-1;document.getElementById(tab.dataset.lens).classList.toggle('active',active);if(active&&moveFocus){tab.focus()}});if(updateHash){history.replaceState(null,'','#'+id)}}
function revealHash(){var id=location.hash.slice(1),node=id&&document.getElementById(id);if(!node){return}var panel=node.classList.contains('lens')?node:node.closest('.lens');if(panel){show(panel.id,false,false)}if(node!==panel){requestAnimationFrame(function(){node.scrollIntoView({block:'start'})})}}
tabs.forEach(function(tab,index){tab.addEventListener('click',function(){show(tab.dataset.lens,true,false)});tab.addEventListener('keydown',function(event){var next=index;if(event.key==='ArrowRight'||event.key==='ArrowDown'){next=(index+1)%tabs.length}else if(event.key==='ArrowLeft'||event.key==='ArrowUp'){next=(index+tabs.length-1)%tabs.length}else if(event.key==='Home'){next=0}else if(event.key==='End'){next=tabs.length-1}else{return}event.preventDefault();show(tabs[next].dataset.lens,true,true)})});
document.querySelectorAll('[data-filter-root]').forEach(function(root){var input=root.querySelector('[data-filter-input]'),select=root.querySelector('[data-filter-status]'),items=[].slice.call(root.querySelectorAll('[data-filter-item]')),count=root.querySelector('[data-filter-count]'),empty=root.querySelector('[data-filter-empty]');function apply(){var query=(input.value||'').trim().toLowerCase(),status=select.value,visible=0;items.forEach(function(item){var matchText=!query||(item.dataset.search||'').toLowerCase().indexOf(query)>=0,matchStatus=!status||item.dataset.status===status,showItem=matchText&&matchStatus;item.hidden=!showItem;if(showItem){visible++}});count.textContent=visible+' of '+items.length;empty.style.display=visible?'none':'block'}input.addEventListener('input',apply);select.addEventListener('change',apply);apply()});
document.querySelectorAll('[data-details-action]').forEach(function(button){button.addEventListener('click',function(){var panel=document.getElementById(button.dataset.detailsTarget),open=button.dataset.detailsAction==='open';panel.querySelectorAll('details.execution:not([hidden])').forEach(function(item){item.open=open})})});
document.querySelectorAll('time[datetime]').forEach(function(node){var value=new Date(node.getAttribute('datetime'));if(!isNaN(value.getTime())){node.textContent=value.toLocaleString()}});
if(compact.addEventListener){compact.addEventListener('change',orientation)}orientation();window.addEventListener('hashchange',revealHash);revealHash();
})();</script>
</body>
</html>
''';
}

String _overview(CockpitTestReportBundle bundle, {required bool gatePassed}) {
  final report = bundle.report;
  final counts = report.counts;
  final failure = report.failure;
  final alert = failure == null
      ? ''
      : '<div class="alert"><h3>Suite failure</h3><p><code>${_html(failure.primary.code)}</code> ${_html(failure.primary.message)}</p></div>';
  return '''$alert<section class="section"><div class="summary-band"><div class="summary-verdict"><span class="subtle">Release gate</span><strong>${gatePassed ? 'Passed' : 'Needs review'}</strong><p>${gatePassed ? 'No failed, blocked, incomplete, or flaky cases.' : 'Open diagnostics before accepting this run.'}</p></div><div class="count-grid"><div class="count-item"><span>Passed</span><strong>${counts.passed}</strong></div><div class="count-item"><span>Failed</span><strong>${counts.failed}</strong></div><div class="count-item"><span>Blocked</span><strong>${counts.blocked}</strong></div><div class="count-item"><span>Flaky</span><strong>${counts.flaky}</strong></div><div class="count-item"><span>Skipped</span><strong>${counts.skipped}</strong></div><div class="count-item"><span>Cancelled</span><strong>${counts.cancelled}</strong></div><div class="count-item"><span>Interrupted</span><strong>${counts.interrupted}</strong></div><div class="count-item"><span>Internal error</span><strong>${counts.internalError}</strong></div></div>${_outcomeDistribution(report)}</div></section>
<section class="section"><div class="section-head"><div><h2>Action required</h2><p>Failures, blocks, and unstable results ordered for triage.</p></div><span class="subtle">${report.cases.length} cases · ${bundle.executions.length} executions</span></div>${_actionTable(report)}</section>
<section class="section"><div class="section-head"><div><h2>Case results</h2><p>Complete suite outcome at a glance.</p></div><a href="#coverage">Explore coverage</a></div>${_caseTable(report)}</section>''';
}

String _outcomeDistribution(CockpitTestSuiteReport report) {
  final counts = report.counts;
  final outcomes = <(String, String, int)>[
    ('passed', 'Passed', counts.passed),
    ('failed', 'Failed', counts.failed),
    ('blocked', 'Blocked', counts.blocked),
    ('skipped', 'Skipped', counts.skipped),
    ('cancelled', 'Cancelled', counts.cancelled),
    ('interrupted', 'Interrupted', counts.interrupted),
    ('internalError', 'Internal error', counts.internalError),
  ].where((item) => item.$3 > 0).toList(growable: false);
  final label = outcomes.map((item) => '${item.$2} ${item.$3}').join(', ');
  final segments = outcomes
      .map(
        (item) =>
            '<span class="outcome-segment outcome-${_attribute(item.$1)}" style="flex-grow:${item.$3}" title="${_attribute('${item.$2}: ${item.$3}')}"></span>',
      )
      .join();
  return '''<div class="outcome-block"><div class="outcome-label"><span>Outcome distribution</span><span>${counts.total} total</span></div><div class="outcome-track" role="img" aria-label="${_attribute(label.isEmpty ? 'No case outcomes' : label)}">$segments</div></div>''';
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
    final caseAnchor = _caseAnchor(testCase);
    rows.write(
      '''<tr><td><strong><a href="#$caseAnchor">${_html(testCase.entryId)}</a></strong><span class="identity">${_html(testCase.caseId)}</span></td><td>${_status(testCase.outcome.name)}${testCase.stability == CockpitRunStability.flaky ? '<span class="stability">flaky</span>' : ''}</td><td>${_html(testCase.targetId)}</td><td>${_html(matrix)}</td><td>${testCase.attempts.length}</td><td>${_html(_duration(duration))}</td></tr>''',
    );
  }
  return '''<div class="table-wrap"><table><thead><tr><th>Case</th><th>Result</th><th>Target</th><th>Matrix</th><th>Attempts</th><th>Duration</th></tr></thead><tbody>$rows</tbody></table></div>''';
}

String _actionTable(CockpitTestSuiteReport report) {
  final actionable = report.cases
      .where(_caseRequiresAttention)
      .toList(growable: false);
  if (actionable.isEmpty) {
    return '<div class="case-list"><div class="case-row"><strong>No action required</strong><div class="subtle">No failed, blocked, or unstable cases require triage. Skipped cases remain visible in coverage.</div></div></div>';
  }
  final rows = StringBuffer();
  for (final testCase in actionable) {
    final caseAnchor = _caseAnchor(testCase);
    rows.write(
      '''<tr><td><strong><a href="#$caseAnchor">${_html(testCase.entryId)}</a></strong><span class="identity">${_html(testCase.caseId)}</span></td><td>${_status(testCase.outcome.name)}${testCase.stability == CockpitRunStability.flaky ? '<span class="stability">flaky</span>' : ''}</td><td><code>${_html(_failureCode(testCase))}</code><span class="identity">${_html(_failureMessage(testCase))}</span></td><td>${testCase.attempts.length}</td></tr>''',
    );
  }
  return '''<div class="table-wrap"><table><thead><tr><th>Case</th><th>Result</th><th>Reason</th><th>Attempts</th></tr></thead><tbody>$rows</tbody></table></div>''';
}

String _coverage(CockpitTestReportBundle bundle) {
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
    final status = testCase.stability == CockpitRunStability.flaky
        ? 'flaky'
        : testCase.outcome.name;
    final search = <Object?>[
      definition.name,
      definition.description,
      testCase.entryId,
      testCase.caseId,
      testCase.targetId,
      matrix,
      ...definition.tags,
    ].whereType<Object>().join(' ');
    final caseAnchor = _caseAnchor(testCase);
    content.write(
      '''<article class="case-row" id="$caseAnchor" data-filter-item data-status="${_attribute(status)}" data-search="${_attribute(search)}"><div class="case-row-head"><div><h3><a href="#$caseAnchor">${_html(definition.name ?? testCase.entryId)}</a></h3><span class="identity">${_html(testCase.entryId)} · ${_html(testCase.caseId)}</span></div><div>${_status(testCase.outcome.name)}${testCase.stability == CockpitRunStability.flaky ? '<span class="stability">flaky</span>' : ''}</div></div>${definition.description == null ? '' : '<p class="case-description">${_html(definition.description!)}</p>'}<div class="case-meta"><span>Target ${_html(testCase.targetId)}</span><span>${testCase.attempts.length} attempt${testCase.attempts.length == 1 ? '' : 's'}</span>${matrix.isEmpty ? '' : '<span>Matrix ${_html(matrix)}</span>'}<span>${_html(_caseOutcomeMessage(testCase))}</span></div>$tags${_gallery(visual)}</article>''',
    );
  }
  return '''<section class="section" data-filter-root><div class="section-head"><div><h2>Cases and user journeys</h2><p>Search every selected flow, matrix row, target, and result.</p></div><span class="subtle">${report.cases.length} cases</span></div>${_filterBar('coverage', total: report.cases.length, statuses: const <(String, String)>[('passed', 'Passed'), ('failed', 'Failed'), ('blocked', 'Blocked'), ('flaky', 'Flaky'), ('skipped', 'Skipped'), ('cancelled', 'Cancelled'), ('interrupted', 'Interrupted'), ('internalError', 'Internal error')])}<div class="case-list">$content</div><div class="empty-filter" data-filter-empty>No cases match this filter.</div></section>''';
}

String _gallery(
  List<CockpitTestReportArtifact> artifacts, {
  bool filterable = false,
}) {
  if (artifacts.isEmpty) return '';
  final content = StringBuffer();
  for (final artifact in artifacts) {
    final source = _attribute(artifact.relativePath);
    final mediaKind = artifact.mediaType.startsWith('image/')
        ? 'image'
        : artifact.mediaType.startsWith('video/')
        ? 'video'
        : 'other';
    final media = artifact.mediaType.startsWith('video/')
        ? '<video controls preload="metadata" src="$source"></video>'
        : '<a href="$source"><img loading="lazy" src="$source" alt="${_attribute(artifact.kind)} evidence"></a>';
    final filterAttributes = filterable
        ? ' data-filter-item data-status="$mediaKind" data-search="${_attribute('${artifact.kind} ${artifact.relativePath} ${artifact.attemptId} ${artifact.stepExecutionId ?? ''}')}"'
        : '';
    content.write(
      '''<figure class="media"$filterAttributes><div class="media-frame">$media</div><figcaption><strong>${_html(_humanize(artifact.kind))}</strong>${_html(_bytes(artifact.sizeBytes))} · ${_html(artifact.mediaType)}<span class="identity">${_html(artifact.attemptId)}${artifact.stepExecutionId == null ? '' : ' · ${_html(artifact.stepExecutionId!)}'}</span></figcaption></figure>''',
    );
  }
  return '<div class="gallery">$content</div>';
}

String _evidence(CockpitTestReportBundle bundle) {
  final artifacts = <CockpitTestReportArtifact>[
    for (final execution in bundle.executions) ...execution.artifacts,
  ]..sort((left, right) => left.createdAt.compareTo(right.createdAt));
  if (artifacts.isEmpty) {
    return '''<section class="section"><div class="section-head"><div><h2>No evidence files</h2></div></div><div class="alert"><h3>No evidence was published</h3><p>Inspect the suite evidence policy and completed execution manifests.</p></div></section>''';
  }
  final visual = artifacts
      .where(
        (artifact) =>
            artifact.mediaType.startsWith('image/') ||
            artifact.mediaType.startsWith('video/'),
      )
      .toList(growable: false);
  final rows = artifacts
      .map(
        (artifact) =>
            '<tr><td><a href="${_attribute(artifact.relativePath)}"><strong>${_html(_humanize(artifact.kind))}</strong></a><span class="identity">${_html(artifact.relativePath)}</span></td><td>${_html(artifact.mediaType)}</td><td>${_html(_bytes(artifact.sizeBytes))}</td><td><code>${_html(artifact.attemptId)}</code>${artifact.stepExecutionId == null ? '' : '<span class="identity">${_html(artifact.stepExecutionId!)}</span>'}</td><td><time datetime="${_attribute(artifact.createdAt.toIso8601String())}">${_html(artifact.createdAt.toIso8601String())}</time></td><td><code>${_html(artifact.sha256)}</code></td></tr>',
      )
      .join();
  final gallery = visual.isEmpty
      ? '<div class="empty-filter" style="display:block">No image or video evidence was published.</div>'
      : '${_filterBar('evidence', total: visual.length, statuses: const <(String, String)>[('image', 'Images'), ('video', 'Videos')])}${_gallery(visual, filterable: true)}<div class="empty-filter" data-filter-empty>No visual evidence matches this filter.</div>';
  return '''<section class="section" data-filter-root><div class="section-head"><div><h2>Visual evidence</h2><p>Original dimensions are preserved; open any item for the source file.</p></div><span class="subtle">${visual.length} visual · ${artifacts.length} total</span></div>$gallery</section><section class="section"><div class="section-head"><div><h2>Artifact index</h2><p>Ownership, media type, size, timestamp, and integrity digest.</p></div></div><div class="table-wrap"><table><thead><tr><th>Artifact</th><th>Media type</th><th>Size</th><th>Owner</th><th>Created</th><th>SHA-256</th></tr></thead><tbody>$rows</tbody></table></div></section>''';
}

String _filterBar(
  String scope, {
  required int total,
  required List<(String, String)> statuses,
}) {
  final options = statuses
      .map(
        (item) =>
            '<option value="${_attribute(item.$1)}">${_html(item.$2)}</option>',
      )
      .join();
  return '''<div class="filter-bar"><label class="field field-search"><span>Search</span><input type="search" data-filter-input placeholder="Search $scope" autocomplete="off"></label><label class="field"><span>Status</span><select data-filter-status><option value="">All</option>$options</select></label><output class="filter-count" data-filter-count aria-live="polite">$total of $total</output></div>''';
}

String _executions(CockpitTestReportBundle bundle) {
  final content = StringBuffer();
  for (final execution in bundle.executions) {
    final result = execution.result;
    final passed = result.steps
        .where((step) => step.status == CockpitTestStepStatus.passed)
        .length;
    final title = execution.entryId ?? result.context.caseId;
    final executionAnchor = _domId('execution', result.context.attemptId);
    final search = <String>[
      title,
      result.context.caseId,
      result.context.attemptId,
      result.targetId,
      result.platform,
      execution.role.name,
      result.requestedPlane.name,
      result.actualPlane?.name ?? '',
      for (final step in result.steps)
        '${step.stepId} ${step.description ?? ''} ${step.operation ?? ''} ${step.error?.message ?? ''}',
    ].join(' ');
    content.write(
      '''<details class="execution" id="$executionAnchor" data-filter-item data-status="${_attribute(result.outcome.name)}" data-search="${_attribute(search)}"><summary>${_status(result.outcome.name)} <span>${_html(title)}</span><span class="subtle">${_html(_humanize(execution.role.name))} · $passed/${result.steps.length} steps · ${_html(_duration(result.durationMs))}</span></summary><div class="execution-body"><div class="case-meta"><span>Attempt <code>${_html(result.context.attemptId)}</code></span><span>Target <code>${_html(result.targetId)}</code></span><span>${_html(result.platform)}</span><span>${_html(result.requestedPlane.name)} → ${_html(result.actualPlane?.name ?? 'unresolved')}</span><span>${_html(_humanize(result.context.authorizationMode.name))} authorization</span></div>${_primaryError(result)}${_steps(execution, diagnostic: false)}${_cleanupErrors(result)}</div></details>''',
    );
  }
  if (content.isEmpty) {
    content.write(
      '<div class="alert"><h3>No execution trace</h3><p>The run completed before an attempt manifest was published.</p></div>',
    );
  }
  return '''<section class="section" data-filter-root><div class="section-head"><div><h2>Attempts and steps</h2><p>Setup, main, finally, retries, loops, calls, and evidence in execution order.</p></div><div class="button-group"><button class="quiet-button" type="button" data-details-action="open" data-details-target="executions">Expand all</button><button class="quiet-button" type="button" data-details-action="close" data-details-target="executions">Collapse all</button></div></div>${_filterBar('executions', total: bundle.executions.length, statuses: const <(String, String)>[('passed', 'Passed'), ('failed', 'Failed'), ('blocked', 'Blocked'), ('skipped', 'Skipped'), ('cancelled', 'Cancelled'), ('interrupted', 'Interrupted'), ('internalError', 'Internal error')])}$content<div class="empty-filter" data-filter-empty>No executions match this filter.</div></section>''';
}

String _diagnostics(CockpitTestReportBundle bundle) {
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
    final title = execution.entryId ?? result.context.caseId;
    final diagnosticAnchor = _domId('diagnostic', result.context.attemptId);
    final search = <String>[
      title,
      result.context.caseId,
      result.context.attemptId,
      result.targetId,
      result.platform,
      result.requestedPlane.name,
      result.actualPlane?.name ?? '',
      primary?.code.name ?? '',
      primary?.message ?? '',
      for (final step in result.steps)
        '${step.stepId} ${step.description ?? ''} ${step.operation ?? ''} ${step.driverId ?? ''} ${step.degradationReason ?? ''} ${step.error?.message ?? ''}',
    ].join(' ');
    content.write(
      '''<details class="execution" id="$diagnosticAnchor" data-filter-item data-status="${_attribute(result.outcome.name)}" data-search="${_attribute(search)}" ${primary == null && result.cleanupErrors.isEmpty ? '' : 'open'}><summary>${_status(result.outcome.name)} <span>${_html(title)}</span><span class="subtle">${_html(result.requestedPlane.name)} → ${_html(result.actualPlane?.name ?? 'unresolved')} · ${_html(_duration(result.durationMs))}</span></summary><div class="execution-body">${_primaryError(result)}<div class="case-meta"><span>Attempt <code>${_html(result.context.attemptId)}</code></span><span>Target <code>${_html(result.targetId)}</code></span><span>${_html(result.platform)}</span><span>Engine ${_html(result.context.engineVersion)}</span><span>${_html(_humanize(result.context.authorizationMode.name))} authorization</span></div>${_steps(execution, diagnostic: true)}${_cleanupErrors(result)}${_artifactLinks(execution.artifacts)}</div></details>''',
    );
  }
  return '''<section class="section" data-filter-root><div class="section-head"><div><h2>Drivers, locators, and failures</h2><p>Failed executions are first; successful traces remain available for comparison.</p></div><div class="button-group"><button class="quiet-button" type="button" data-details-action="open" data-details-target="diagnostics">Expand all</button><button class="quiet-button" type="button" data-details-action="close" data-details-target="diagnostics">Collapse all</button></div></div>${_filterBar('diagnostics', total: prioritized.length, statuses: const <(String, String)>[('passed', 'Passed'), ('failed', 'Failed'), ('blocked', 'Blocked'), ('skipped', 'Skipped'), ('cancelled', 'Cancelled'), ('interrupted', 'Interrupted'), ('internalError', 'Internal error')])}$content<div class="empty-filter" data-filter-empty>No diagnostics match this filter.</div></section>''';
}

String _primaryError(CockpitTestAttemptResult result) {
  final primary = result.primaryError;
  if (primary == null) return '';
  return '<div class="alert"><h3>${_html(_humanize(primary.code.name))}</h3><p>${_html(primary.message)}</p></div>';
}

String _cleanupErrors(CockpitTestAttemptResult result) {
  if (result.cleanupErrors.isEmpty) return '';
  final rows = result.cleanupErrors
      .map(
        (error) =>
            '<tr><td><code>${_html(_humanize(error.code.name))}</code></td><td>${_html(error.message)}</td></tr>',
      )
      .join();
  return '<div class="section"><h3>Cleanup errors</h3><div class="table-wrap"><table><thead><tr><th>Code</th><th>Message</th></tr></thead><tbody>$rows</tbody></table></div></div>';
}

String _steps(
  CockpitTestReportExecution execution, {
  required bool diagnostic,
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
    final context = diagnostic
        ? <String>[
            'requested=${step.requestedPlane?.name ?? execution.result.requestedPlane.name}',
            if (step.driverId != null) 'driver=${step.driverId}',
            if (step.actualPlane != null) 'plane=${step.actualPlane!.name}',
            if (step.locatorResolution case final locator?)
              'locator=${locator.matchedKind.name}:${locator.matchedValue}',
            if (step.locatorResolution?.matchedSignals case final signals?
                when signals.isNotEmpty)
              'signals=${signals.entries.map((entry) => '${entry.key}=${entry.value}').join(',')}',
            if (step.degradationReason != null)
              'degraded=${step.degradationReason}',
            if (step.sourceLocation != null)
              'source=${_compactValue(step.sourceLocation!.toJson())}',
          ].join(' · ')
        : <String>[
            step.section,
            if (step.occurrence.retryAttempt != null)
              'retry ${step.occurrence.retryAttempt}',
            if (step.occurrence.loopIteration != null)
              'loop ${step.occurrence.loopIteration}',
            if (step.occurrence.callPath.isNotEmpty)
              'call ${step.occurrence.callPath.join(' → ')}',
          ].join(' · ');
    final identity = <String>[
      step.executionId,
      if (step.operation != null) step.operation!,
      if (step.timeoutMs != null) 'timeout=${step.timeoutMs}ms',
      if (step.definitionPath != null) step.definitionPath!,
    ].join(' · ');
    final stepAnchor = _domId(
      diagnostic ? 'diagnostic-step' : 'execution-step',
      '${execution.result.context.attemptId}:${step.executionId}',
    );
    content.write(
      '''<div class="step" id="$stepAnchor"><div><strong>${_html(step.description ?? step.stepId)}</strong>${step.description == null ? '' : '<span class="subtle">${_html(step.stepId)}</span>'}<span class="identity">${_html(identity)}</span></div><div>${_status(step.status.name)}</div><div>${_html(_duration(step.durationMs))}</div><div><span class="subtle">${_html(context)}</span><span class="identity"><time datetime="${_attribute(step.startedAt.toUtc().toIso8601String())}">${_html(step.startedAt.toUtc().toIso8601String())}</time></span>${step.error == null ? '' : '<div class="step-error"><code>${_html(_humanize(step.error!.code.name))}</code> ${_html(step.error!.message)}</div>'}${_artifactLinks(evidence)}</div></div>''',
    );
  }
  content.write('</div>');
  return content.toString();
}

String _artifactLinks(List<CockpitTestReportArtifact> artifacts) {
  if (artifacts.isEmpty) return '';
  return '<div class="artifact-links">${artifacts.map((artifact) => '<a href="${_attribute(artifact.relativePath)}">${_html(_humanize(artifact.kind))} (${_html(_bytes(artifact.sizeBytes))})</a>').join()}</div>';
}

String _machine(CockpitTestReportBundle bundle) {
  final report = bundle.report;
  final formats = report.reportPolicy.formats.toSet();
  final files = <(String, String, String)>[
    (
      'manifest.json',
      'Integrity manifest',
      'Path, ownership, size and SHA-256',
    ),
    if (formats.contains(CockpitTestReportFormat.json))
      (
        'report.json',
        'Canonical report',
        'Complete fact graph and evidence index',
      ),
    if (formats.contains(CockpitTestReportFormat.junit))
      ('junit.xml', 'JUnit', 'CI test result interchange'),
    if (formats.contains(CockpitTestReportFormat.summary))
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
  final platforms = bundle.executions
      .map((execution) => execution.result.platform)
      .toSet()
      .join(', ');
  final targets = bundle.executions
      .map((execution) => execution.result.targetId)
      .toSet()
      .join(', ');
  final stepCount = bundle.executions.fold<int>(
    0,
    (total, execution) => total + execution.result.steps.length,
  );
  final effectiveConfiguration = <String, Object?>{
    'suiteDefinition': report.definition.toJson(),
    'executionPolicy': report.execution.toJson(),
    'reportPolicy': report.reportPolicy.toJson(),
    'matrixAxes': report.matrixAxes,
  };
  return '''<section class="section"><div class="section-head"><div><h2>Run identity and context</h2><p>Authority, source, selected platforms, targets, and injected metadata.</p></div></div>${_contextTable(report)}<div class="case-meta"><span>Platforms ${_html(platforms.isEmpty ? 'Not reported' : platforms)}</span><span>Targets ${_html(targets.isEmpty ? 'Not reported' : targets)}</span></div></section><section class="section"><div class="section-head"><div><h2>Effective configuration</h2><p>Suite definition and policies used for this run.</p></div></div><pre class="json-view">${_html(_prettyJson(effectiveConfiguration))}</pre></section><section class="section"><div class="section-head"><div><h2>Offline files</h2><p>Portable exports generated from the same immutable fact graph.</p></div><span class="subtle">${_html(bundle.schemaVersion)}</span></div><div class="machine-files">$links</div></section><section class="section"><div class="section-head"><div><h2>Bundle contract</h2><p>Completeness and trace cardinality.</p></div></div><div class="table-wrap"><table><tbody><tr><th>Run</th><td><code>${_html(report.runId)}</code></td></tr><tr><th>Workspace</th><td><code>${_html(report.workspaceId)}</code></td></tr><tr><th>Source SHA-256</th><td><code>${_html(report.sourceSha256)}</code></td></tr><tr><th>Generated at</th><td><time datetime="${_attribute(bundle.generatedAt.toIso8601String())}">${_html(bundle.generatedAt.toIso8601String())}</time></td></tr><tr><th>Cases</th><td>${report.cases.length}</td></tr><tr><th>Executions</th><td>${bundle.executions.length}</td></tr><tr><th>Steps</th><td>$stepCount</td></tr><tr><th>Evidence files</th><td>${_artifactCount(bundle)}</td></tr><tr><th>Complete</th><td>${bundle.complete}</td></tr></tbody></table></div></section>''';
}

String _status(String value) =>
    '<span class="status status-${_attribute(value)}">${_html(_humanize(value))}</span>';

String _caseOutcomeMessage(CockpitTestCaseReport report) =>
    report.outcome == CockpitRunOutcome.passed
    ? 'Completed'
    : _failureMessage(report);

bool _caseRequiresAttention(CockpitTestCaseReport report) =>
    report.stability == CockpitRunStability.flaky ||
    report.outcome != CockpitRunOutcome.passed &&
        report.outcome != CockpitRunOutcome.skipped;

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

String _prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

String _domId(String prefix, String value) =>
    '$prefix-${base64Url.encode(utf8.encode(value)).replaceAll('=', '')}';

String _caseAnchor(CockpitTestCaseReport report) => _domId(
  'case',
  '${report.entryId}\u0000${report.caseId}\u0000${report.targetId}\u0000${jsonEncode(report.matrix)}',
);

String _humanize(String value) {
  final spaced = value
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll(RegExp(r'[._-]+'), ' ')
      .trim();
  if (spaced.isEmpty) return value;
  return '${spaced.substring(0, 1).toUpperCase()}${spaced.substring(1)}';
}

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
