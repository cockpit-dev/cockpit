import 'dart:convert';
import 'dart:io';

import 'package:flutter_cockpit_test/flutter_cockpit_test_report.dart';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final reportPath = Platform.environment['COCKPIT_NATIVE_REPORT_PATH'];
  final htmlPath = Platform.environment['COCKPIT_NATIVE_HTML_PATH'];
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data == null) {
        return;
      }
      if (reportPath != null && reportPath.trim().isNotEmpty) {
        final file = File(reportPath);
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(data), flush: true);
      }
      if (htmlPath != null && htmlPath.trim().isNotEmpty) {
        await _writePerformanceHtml(data, htmlPath);
      }
    },
    writeResponseOnFailure: true,
  );
}

Future<void> _writePerformanceHtml(
  Map<String, dynamic> data,
  String outputPath,
) async {
  final reports = <CockpitPerformanceReport>[];
  for (final entry in data.entries) {
    if (!entry.key.startsWith('cockpit.performance.') || entry.value is! Map) {
      continue;
    }
    reports.add(CockpitPerformanceReport.fromJson(entry.value));
  }
  if (reports.isEmpty) return;

  final startupValue = data['cockpit'] is Map
      ? (data['cockpit'] as Map)['startup']
      : null;
  final startup = startupValue is Map
      ? CockpitStartupReport.fromJson(startupValue)
      : null;
  final file = File(outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    CockpitPerformanceHtml.renderMany(
      reports,
      title: 'Cockpit demo performance',
      startup: startup,
    ),
    flush: true,
  );
}
