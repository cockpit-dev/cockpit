import 'cockpit_test_value_reader.dart';

enum CockpitTestSuiteRetryReason { blocked, interrupted, internalError }

enum CockpitTestSuiteIsolation { sharedSession, restartApp, resetAppData }

enum CockpitTestReportFormat { json, junit, html, summary }

final class CockpitTestSuiteRetryPolicy {
  /// Creates a CockpitTestSuiteRetryPolicy.
  CockpitTestSuiteRetryPolicy({
    this.maxAttempts = 1,
    this.delayMs = 0,
    Iterable<CockpitTestSuiteRetryReason> retryOn =
        const <CockpitTestSuiteRetryReason>[
          CockpitTestSuiteRetryReason.blocked,
          CockpitTestSuiteRetryReason.interrupted,
          CockpitTestSuiteRetryReason.internalError,
        ],
  }) : retryOn = Set<CockpitTestSuiteRetryReason>.unmodifiable(retryOn) {
    if (maxAttempts < 1 || maxAttempts > 10) {
      throw const FormatException(
        'Suite maxAttempts must be between 1 and 10.',
      );
    }
    if (delayMs < 0 || delayMs > 3600000) {
      throw const FormatException('Suite retry delayMs is invalid.');
    }
  }

  static final standard = CockpitTestSuiteRetryPolicy();

  final int maxAttempts;
  final int delayMs;
  final Set<CockpitTestSuiteRetryReason> retryOn;

  /// Encodes this CockpitTestSuiteRetryPolicy as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'maxAttempts': maxAttempts,
    'delayMs': delayMs,
    'retryOn': retryOn.map((reason) => reason.name).toList(growable: false),
  };

  /// Decodes a CockpitTestSuiteRetryPolicy from a JSON object.
  factory CockpitTestSuiteRetryPolicy.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(json, const <String>{
      'maxAttempts',
      'delayMs',
      'retryOn',
    }, path);
    final rawRetryOn = json['retryOn'] == null
        ? const <Object?>[]
        : CockpitTestValueReader.list(json['retryOn'], '$path.retryOn');
    final retryOn = <CockpitTestSuiteRetryReason>{};
    for (var index = 0; index < rawRetryOn.length; index += 1) {
      final reason = CockpitTestValueReader.enumeration(
        rawRetryOn[index],
        CockpitTestSuiteRetryReason.values,
        '$path.retryOn[$index]',
      );
      if (!retryOn.add(reason)) {
        throw FormatException(
          'Duplicate retry reason at $path.retryOn[$index].',
        );
      }
    }
    return CockpitTestSuiteRetryPolicy(
      maxAttempts: json['maxAttempts'] == null
          ? 1
          : CockpitTestValueReader.integer(
              json['maxAttempts'],
              '$path.maxAttempts',
              minimum: 1,
              maximum: 10,
            ),
      delayMs: json['delayMs'] == null
          ? 0
          : CockpitTestValueReader.integer(
              json['delayMs'],
              '$path.delayMs',
              minimum: 0,
              maximum: 3600000,
            ),
      retryOn: json['retryOn'] == null
          ? const <CockpitTestSuiteRetryReason>[
              CockpitTestSuiteRetryReason.blocked,
              CockpitTestSuiteRetryReason.interrupted,
              CockpitTestSuiteRetryReason.internalError,
            ]
          : retryOn,
    );
  }
}

final class CockpitTestSuiteExecutionPolicy {
  /// Creates a CockpitTestSuiteExecutionPolicy.
  CockpitTestSuiteExecutionPolicy({
    this.maxConcurrency = 1,
    this.failFast = false,
    this.isolation = CockpitTestSuiteIsolation.restartApp,
    CockpitTestSuiteRetryPolicy? retry,
  }) : retry = retry ?? CockpitTestSuiteRetryPolicy.standard {
    if (maxConcurrency < 1 || maxConcurrency > 64) {
      throw const FormatException(
        'Suite maxConcurrency must be between 1 and 64.',
      );
    }
  }

  static final standard = CockpitTestSuiteExecutionPolicy();

  final int maxConcurrency;
  final bool failFast;
  final CockpitTestSuiteIsolation isolation;
  final CockpitTestSuiteRetryPolicy retry;

  /// Encodes this CockpitTestSuiteExecutionPolicy as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'maxConcurrency': maxConcurrency,
    'failFast': failFast,
    'isolation': isolation.name,
    'retry': retry.toJson(),
  };

  /// Decodes a CockpitTestSuiteExecutionPolicy from a JSON object.
  factory CockpitTestSuiteExecutionPolicy.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(json, const <String>{
      'maxConcurrency',
      'failFast',
      'isolation',
      'retry',
    }, path);
    return CockpitTestSuiteExecutionPolicy(
      maxConcurrency: json['maxConcurrency'] == null
          ? 1
          : CockpitTestValueReader.integer(
              json['maxConcurrency'],
              '$path.maxConcurrency',
              minimum: 1,
              maximum: 64,
            ),
      failFast: json['failFast'] == null
          ? false
          : CockpitTestValueReader.boolean(json['failFast'], '$path.failFast'),
      isolation: json['isolation'] == null
          ? CockpitTestSuiteIsolation.restartApp
          : CockpitTestValueReader.enumeration(
              json['isolation'],
              CockpitTestSuiteIsolation.values,
              '$path.isolation',
            ),
      retry: json['retry'] == null
          ? CockpitTestSuiteRetryPolicy.standard
          : CockpitTestSuiteRetryPolicy.fromJson(
              json['retry'],
              path: '$path.retry',
            ),
    );
  }
}

final class CockpitTestSuiteReportPolicy {
  /// Creates a CockpitTestSuiteReportPolicy.
  CockpitTestSuiteReportPolicy({
    Iterable<CockpitTestReportFormat> formats = const <CockpitTestReportFormat>[
      CockpitTestReportFormat.json,
      CockpitTestReportFormat.junit,
      CockpitTestReportFormat.html,
      CockpitTestReportFormat.summary,
    ],
    this.includePassedAttempts = true,
  }) : formats = Set<CockpitTestReportFormat>.unmodifiable(formats) {
    if (!this.formats.contains(CockpitTestReportFormat.json)) {
      throw const FormatException('Suite reports must include canonical JSON.');
    }
  }

  static final standard = CockpitTestSuiteReportPolicy();

  final Set<CockpitTestReportFormat> formats;
  final bool includePassedAttempts;

  /// Encodes this CockpitTestSuiteReportPolicy as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'formats': formats.map((format) => format.name).toList(growable: false),
    'includePassedAttempts': includePassedAttempts,
  };

  /// Decodes a CockpitTestSuiteReportPolicy from a JSON object.
  factory CockpitTestSuiteReportPolicy.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(json, const <String>{
      'formats',
      'includePassedAttempts',
    }, path);
    final rawFormats = json['formats'] == null
        ? const <Object?>[]
        : CockpitTestValueReader.list(json['formats'], '$path.formats');
    final formats = <CockpitTestReportFormat>{};
    for (var index = 0; index < rawFormats.length; index += 1) {
      final format = CockpitTestValueReader.enumeration(
        rawFormats[index],
        CockpitTestReportFormat.values,
        '$path.formats[$index]',
      );
      if (!formats.add(format)) {
        throw FormatException(
          'Duplicate report format at $path.formats[$index].',
        );
      }
    }
    return CockpitTestSuiteReportPolicy(
      formats: json['formats'] == null
          ? const <CockpitTestReportFormat>[
              CockpitTestReportFormat.json,
              CockpitTestReportFormat.junit,
              CockpitTestReportFormat.html,
              CockpitTestReportFormat.summary,
            ]
          : formats,
      includePassedAttempts: json['includePassedAttempts'] == null
          ? true
          : CockpitTestValueReader.boolean(
              json['includePassedAttempts'],
              '$path.includePassedAttempts',
            ),
    );
  }
}
