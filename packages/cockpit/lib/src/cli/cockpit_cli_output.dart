import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../application/cockpit_compact_json.dart';

enum CockpitCliStdoutFormat { auto, ai, json, jsonl, path, none }

enum CockpitCliOutputDetail { minimal, standard, full }

void cockpitAddCliOutputOptions(ArgParser parser) {
  parser
    ..addOption(
      'stdout-format',
      allowed: CockpitCliStdoutFormat.values.map((value) => value.name),
      defaultsTo: CockpitCliStdoutFormat.auto.name,
      help:
          'Terminal output: auto selects an AI projection or an output receipt; '
          'json uses the selected detail level.',
    )
    ..addOption(
      'detail',
      allowed: CockpitCliOutputDetail.values.map((value) => value.name),
      defaultsTo: CockpitCliOutputDetail.minimal.name,
      help:
          'AI information density: minimal for the next decision, standard '
          'for diagnosis, full for the complete semantic response.',
    )
    ..addOption(
      'output',
      help:
          'Atomically write the selected JSON projection to this file. Use '
          '--detail full for the complete response.',
    );
}

final class CockpitCliOutputSelection {
  const CockpitCliOutputSelection({
    this.stdoutFormat = CockpitCliStdoutFormat.auto,
    this.detail = CockpitCliOutputDetail.minimal,
    this.outputPath,
  });

  factory CockpitCliOutputSelection.fromArguments(ArgResults arguments) {
    return CockpitCliOutputSelection(
      stdoutFormat: CockpitCliStdoutFormat.values.byName(
        arguments.option('stdout-format')!,
      ),
      detail: CockpitCliOutputDetail.values.byName(arguments.option('detail')!),
      outputPath: arguments.option('output'),
    );
  }

  factory CockpitCliOutputSelection.fromRawArguments(List<String> arguments) {
    CockpitCliStdoutFormat stdoutFormat = CockpitCliStdoutFormat.auto;
    CockpitCliOutputDetail detail = CockpitCliOutputDetail.minimal;
    String? optionValue(String name, int index) {
      final argument = arguments[index];
      final prefix = '--$name=';
      if (argument.startsWith(prefix)) return argument.substring(prefix.length);
      if (argument == '--$name' && index + 1 < arguments.length) {
        return arguments[index + 1];
      }
      return null;
    }

    for (var index = 0; index < arguments.length; index += 1) {
      final stdoutValue = optionValue('stdout-format', index);
      if (stdoutValue != null) {
        stdoutFormat =
            CockpitCliStdoutFormat.values
                .where((value) => value.name == stdoutValue)
                .firstOrNull ??
            stdoutFormat;
      }
      final detailValue = optionValue('detail', index);
      if (detailValue != null) {
        detail =
            CockpitCliOutputDetail.values
                .where((value) => value.name == detailValue)
                .firstOrNull ??
            detail;
      }
    }
    return CockpitCliOutputSelection(
      stdoutFormat: stdoutFormat,
      detail: detail,
    );
  }

  final CockpitCliStdoutFormat stdoutFormat;
  final CockpitCliOutputDetail detail;
  final String? outputPath;
}

final class CockpitCliOutputRenderer {
  const CockpitCliOutputRenderer({
    this.minimalMaximumBytes = 2 * 1024,
    this.standardMaximumBytes = 6 * 1024,
    this.presenter = const CockpitCliAiPresenter(),
  }) : assert(minimalMaximumBytes > 0),
       assert(standardMaximumBytes > 0);

  final int minimalMaximumBytes;
  final int standardMaximumBytes;
  final CockpitCliAiPresenter presenter;

  String renderJson({
    required String command,
    required Object? data,
    required CockpitCliOutputDetail detail,
  }) {
    if (detail == CockpitCliOutputDetail.full) {
      return cockpitCompactJsonText(data);
    }
    final projection = _Projection(
      detail == CockpitCliOutputDetail.minimal
          ? const _ProjectionLimits(8, 16, 1024, 6)
          : const _ProjectionLimits(32, 64, 4096, 10),
    );
    final projected = presenter._present(
      command: command,
      data: data,
      projection: projection,
      detail: detail,
      path: r'$',
    );
    if (projection.omitted.isEmpty) {
      return cockpitCompactJsonText(projected);
    }
    final metadata = <String, Object?>{
      'detail': detail.name,
      'truncated': true,
      'omitted': projection.omitted,
    };
    return cockpitCompactJsonText(
      projected is Map<Object?, Object?>
          ? <String, Object?>{
              ...Map<String, Object?>.from(projected),
              '_meta': metadata,
            }
          : <String, Object?>{'items': projected, '_meta': metadata},
    );
  }

  String renderAi({
    required String command,
    required Object? data,
    required CockpitCliOutputDetail detail,
  }) {
    if (detail == CockpitCliOutputDetail.full) {
      return _renderSemantic(
        command: command,
        data: cockpitCompactJsonValue(data),
        detail: detail,
      );
    }
    final maximumBytes = detail == CockpitCliOutputDetail.minimal
        ? minimalMaximumBytes
        : standardMaximumBytes;
    final attempts = detail == CockpitCliOutputDetail.minimal
        ? const <_ProjectionLimits>[
            _ProjectionLimits(4, 10, 512, 5),
            _ProjectionLimits(2, 8, 256, 4),
            _ProjectionLimits(1, 6, 128, 3),
          ]
        : const <_ProjectionLimits>[
            _ProjectionLimits(16, 32, 1024, 7),
            _ProjectionLimits(8, 24, 512, 6),
            _ProjectionLimits(4, 16, 256, 4),
            _ProjectionLimits(2, 10, 128, 3),
          ];
    for (final limits in attempts) {
      final projection = _Projection(limits);
      final projected = presenter._present(
        command: command,
        data: data,
        projection: projection,
        detail: detail,
        path: r'$.data',
      );
      final text = _renderSemantic(
        command: command,
        data: projected,
        detail: detail,
        omitted: projection.omitted,
      );
      if (utf8.encode(text).length <= maximumBytes) return text;
    }
    return <String>[
      'status=${_status(data)}',
      'data available=true '
          'message=${_scalar('Result exceeds the selected AI output budget.')}',
      'truncated=true',
      'omitted ${_scalar(r'$.data')}=${_collectionSize(data) ?? 1}',
    ].join('\n');
  }

  String renderError({
    required String code,
    required String message,
    required bool retryable,
    String? category,
    String? responsibleLayer,
    Map<String, Object?> details = const <String, Object?>{},
    CockpitCliOutputDetail detail = CockpitCliOutputDetail.standard,
  }) {
    final maximumMessageLength = switch (detail) {
      CockpitCliOutputDetail.minimal => 512,
      CockpitCliOutputDetail.standard => 1536,
      CockpitCliOutputDetail.full => message.length,
    };
    final renderedMessage = message.length <= maximumMessageLength
        ? message
        : '${message.substring(0, maximumMessageLength)}...';
    final projection = detail == CockpitCliOutputDetail.full
        ? null
        : _Projection(
            detail == CockpitCliOutputDetail.minimal
                ? const _ProjectionLimits(2, 8, 256, 3)
                : const _ProjectionLimits(4, 12, 512, 4),
          );
    final renderedDetails = projection?.value(details, r'$.error.details');
    final state = <String>[
      'code=${_scalar(code)}',
      'retryable=$retryable',
      if (category != null) 'category=${_scalar(category)}',
      if (responsibleLayer != null)
        'responsibleLayer=${_scalar(responsibleLayer)}',
      'message=${_scalar(renderedMessage)}',
    ];
    return <String>[
      'status=error',
      'error ${state.join(' ')}',
      if (details.isNotEmpty)
        'details ${_inlineMap((renderedDetails ?? details) as Map<Object?, Object?>)}',
      if (projection?.omitted.isNotEmpty ?? false) 'truncated=true',
    ].join('\n');
  }
}

final class CockpitCliOutputWriter {
  CockpitCliOutputWriter({
    StringSink? stdoutSink,
    String? workingDirectory,
    CockpitCliOutputRenderer renderer = const CockpitCliOutputRenderer(),
  }) : stdoutSink = stdoutSink ?? stdout,
       workingDirectory = workingDirectory ?? Directory.current.path,
       _renderer = renderer;

  final StringSink stdoutSink;
  final String workingDirectory;
  final CockpitCliOutputRenderer _renderer;

  Future<void> writeSuccess({
    required String command,
    required Object? data,
    required CockpitCliOutputSelection selection,
  }) async {
    CockpitCliFileReceipt? receipt;
    if (selection.outputPath case final path?) {
      final fullText = _renderer.renderJson(
        command: command,
        data: data,
        detail: selection.detail,
      );
      receipt = await _writeFile(path, '$fullText\n');
    }
    final effectiveFormat =
        selection.stdoutFormat == CockpitCliStdoutFormat.auto
        ? CockpitCliStdoutFormat.ai
        : selection.stdoutFormat;
    switch (effectiveFormat) {
      case CockpitCliStdoutFormat.none:
        return;
      case CockpitCliStdoutFormat.path:
        if (receipt == null) {
          throw const FormatException(
            '--stdout-format path requires --output.',
          );
        }
        stdoutSink.writeln(receipt.path);
      case CockpitCliStdoutFormat.json || CockpitCliStdoutFormat.jsonl:
        stdoutSink.writeln(
          _renderer.renderJson(
            command: command,
            data: data,
            detail: selection.detail,
          ),
        );
      case CockpitCliStdoutFormat.ai || CockpitCliStdoutFormat.auto:
        if (receipt != null) {
          stdoutSink.writeln(receipt.render());
          return;
        }
        stdoutSink.writeln(
          _renderer.renderAi(
            command: command,
            data: data,
            detail: selection.detail,
          ),
        );
    }
  }

  void writeError({
    required String code,
    required String message,
    required bool retryable,
    String? category,
    String? responsibleLayer,
    Map<String, Object?> details = const <String, Object?>{},
    required CockpitCliOutputSelection selection,
    required StringSink stderrSink,
  }) {
    final value = <String, Object?>{
      'error': <String, Object?>{
        'code': code,
        'message': message,
        'retryable': retryable,
        'category': ?category,
        'responsibleLayer': ?responsibleLayer,
        if (details.isNotEmpty) 'details': details,
      },
    };
    switch (selection.stdoutFormat) {
      case CockpitCliStdoutFormat.json || CockpitCliStdoutFormat.jsonl:
        stderrSink.writeln(
          _renderer.renderJson(
            command: 'error',
            data: value,
            detail: selection.detail,
          ),
        );
      case CockpitCliStdoutFormat.auto ||
          CockpitCliStdoutFormat.ai ||
          CockpitCliStdoutFormat.path ||
          CockpitCliStdoutFormat.none:
        stderrSink.writeln(
          _renderer.renderError(
            code: code,
            message: message,
            retryable: retryable,
            category: category,
            responsibleLayer: responsibleLayer,
            details: details,
            detail: selection.detail,
          ),
        );
    }
  }

  void writeReceipt({
    required CockpitCliFileReceipt receipt,
    required CockpitCliOutputSelection selection,
  }) {
    switch (selection.stdoutFormat) {
      case CockpitCliStdoutFormat.none:
        return;
      case CockpitCliStdoutFormat.path:
        stdoutSink.writeln(receipt.path);
      case CockpitCliStdoutFormat.json || CockpitCliStdoutFormat.jsonl:
        stdoutSink.writeln(
          _renderer.renderJson(
            command: 'output.receipt',
            data: receipt.toJson(),
            detail: selection.detail,
          ),
        );
      case CockpitCliStdoutFormat.auto || CockpitCliStdoutFormat.ai:
        stdoutSink.writeln(receipt.render());
    }
  }

  Future<CockpitCliFileReceipt> _writeFile(
    String requested,
    String text,
  ) async {
    final resolved = p.normalize(
      p.isAbsolute(requested) ? requested : p.join(workingDirectory, requested),
    );
    final destination = File(resolved);
    await destination.parent.create(recursive: true);
    final token =
        '${pid}_${DateTime.now().microsecondsSinceEpoch}_'
        '${Random.secure().nextInt(1 << 32)}';
    final temporary = File(
      p.join(destination.parent.path, '.${p.basename(resolved)}.$token.tmp'),
    );
    RandomAccessFile? handle;
    try {
      final bytes = utf8.encode(text);
      await temporary.create(exclusive: true);
      handle = await temporary.open(mode: FileMode.write);
      await handle.writeFrom(bytes);
      await handle.flush();
      await handle.close();
      handle = null;
      await temporary.rename(destination.path);
      return CockpitCliFileReceipt(
        path: destination.path,
        mediaType: 'application/json',
        sizeBytes: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      );
    } finally {
      await handle?.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

final class CockpitCliFileReceipt {
  const CockpitCliFileReceipt({
    required this.path,
    required this.mediaType,
    required this.sizeBytes,
    required this.sha256,
  });

  final String path;
  final String mediaType;
  final int sizeBytes;
  final String sha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'mediaType': mediaType,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
  };

  String render() =>
      'output=${_scalar(path)} mediaType=$mediaType sizeBytes=$sizeBytes '
      'sha256=$sha256';
}

final class _ProjectionLimits {
  const _ProjectionLimits(
    this.maximumListItems,
    this.maximumMapKeys,
    this.maximumStringLength,
    this.maximumDepth,
  );

  final int maximumListItems;
  final int maximumMapKeys;
  final int maximumStringLength;
  final int maximumDepth;
}

final class _Projection {
  _Projection(this.limits);

  final _ProjectionLimits limits;
  final Map<String, int> omitted = <String, int>{};

  Object? value(Object? source, String path, {int depth = 0}) {
    if (source is String) {
      if (source.length <= limits.maximumStringLength) return source;
      omitted[path] = source.length - limits.maximumStringLength;
      return '${source.substring(0, limits.maximumStringLength)}...';
    }
    if (source is List<Object?>) {
      if (depth >= limits.maximumDepth) {
        omitted[path] = source.length;
        return const <Object?>[];
      }
      final count = min(source.length, limits.maximumListItems);
      if (count < source.length) omitted[path] = source.length - count;
      return <Object?>[
        for (var index = 0; index < count; index += 1)
          value(source[index], '$path[$index]', depth: depth + 1),
      ];
    }
    if (source is Map<Object?, Object?>) {
      if (depth >= limits.maximumDepth) {
        omitted[path] = source.length;
        return const <String, Object?>{};
      }
      final entries = source.entries
          .where((entry) => entry.key is String && entry.value != null)
          .toList(growable: false);
      final indexed = entries.indexed.toList(growable: false)
        ..sort((left, right) {
          final leftKey = left.$2.key! as String;
          final rightKey = right.$2.key! as String;
          final rank = _priority(leftKey).compareTo(_priority(rightKey));
          return rank != 0 ? rank : left.$1.compareTo(right.$1);
        });
      final count = min(entries.length, limits.maximumMapKeys);
      if (count < entries.length) omitted[path] = entries.length - count;
      final result = <String, Object?>{};
      for (final indexedEntry in indexed.take(count)) {
        final entry = indexedEntry.$2;
        final key = entry.key! as String;
        result[key] = value(entry.value, '$path.$key', depth: depth + 1);
      }
      return result;
    }
    return source;
  }
}

final class CockpitCliAiPresenter {
  const CockpitCliAiPresenter();

  Object? _present({
    required String command,
    required Object? data,
    required _Projection projection,
    required CockpitCliOutputDetail detail,
    required String path,
  }) {
    if (command == 'operation.list' &&
        data is List<Object?> &&
        data.length > 1) {
      final kinds =
          data
              .whereType<Map<Object?, Object?>>()
              .map((operation) => operation['kind'])
              .whereType<String>()
              .toList(growable: false)
            ..sort();
      if (detail == CockpitCliOutputDetail.standard) {
        return projection.value(<String, Object?>{
          'operationCount': data.length,
          'items': <Map<String, Object?>>[
            for (final operation in data.whereType<Map<Object?, Object?>>())
              _pick(operation, const <String>[
                'kind',
                'scope',
                'mutationClass',
                'executionMode',
                'defaultTimeoutMs',
                'maximumTimeoutMs',
              ]),
          ],
        }, path);
      }
      return <String, Object?>{
        'operationCount': data.length,
        'kinds': kinds.join(','),
      };
    }
    if (command == 'daemon.logs' && data is Map<Object?, Object?>) {
      final lines = data['lines'];
      if (lines is List<Object?>) {
        final start = max(0, lines.length - projection.limits.maximumListItems);
        return projection.value(<String, Object?>{
          ...Map<String, Object?>.from(data),
          if (start > 0) 'omittedLineCount': start,
          'order': 'newestFirst',
          'lines': lines
              .skip(start)
              .map(_compactDaemonLogLine)
              .toList(growable: false)
              .reversed
              .toList(growable: false),
        }, path);
      }
    }
    if (command == 'operation.run' && data is Map<Object?, Object?>) {
      return projection.value(
        _compactOperationResult(
          data,
          standard: detail == CockpitCliOutputDetail.standard,
        ),
        path,
      );
    }
    if (data is Map<Object?, Object?> &&
        const <String>{
          'daemon.start',
          'daemon.status',
          'daemon.restart',
        }.contains(command)) {
      return projection.value(
        _pick(
          data,
          detail == CockpitCliOutputDetail.minimal
              ? const <String>[
                  'running',
                  'healthy',
                  'authorizationMode',
                  'processId',
                  'diagnostic',
                ]
              : const <String>[
                  'running',
                  'healthy',
                  'authorizationMode',
                  'processId',
                  'endpoint',
                  'engineVersion',
                  'apiVersion',
                  'startedAt',
                  'diagnostic',
                ],
        ),
        path,
      );
    }
    if (data is Map<Object?, Object?> && command == 'target.inspect') {
      return projection.value(
        _compactTargetInspection(
          data,
          standard: detail == CockpitCliOutputDetail.standard,
        ),
        path,
      );
    }
    if (data is Map<Object?, Object?> && command == 'run.get') {
      return projection.value(
        _compactRun(data, standard: detail == CockpitCliOutputDetail.standard),
        path,
      );
    }
    if (data is Map<Object?, Object?> &&
        (command == 'case.run' || command == 'suite.run')) {
      return projection.value(
        _pick(data, const <String>['runId', 'replayed']),
        path,
      );
    }
    if (data is Map<Object?, Object?> && data['items'] is List<Object?>) {
      final compacted = _compactCollection(command, data, detail);
      if (compacted != null) return projection.value(compacted, path);
    }
    if (data is List<Object?>) {
      final compacted = _compactCollection(command, <String, Object?>{
        'totalCount': data.length,
        'items': data,
      }, detail);
      if (compacted != null) return projection.value(compacted, path);
    }
    if ((command == 'case.validate' || command == 'suite.validate') &&
        data is Map<Object?, Object?>) {
      return projection.value(
        _compactValidationResult(
          data,
          standard: detail == CockpitCliOutputDetail.standard,
        ),
        path,
      );
    }
    if (command == 'suite.report' && data is Map<Object?, Object?>) {
      final report = Map<String, Object?>.from(data);
      final rawCases = report['cases'];
      if (rawCases is List<Object?>) {
        final ordered = rawCases.indexed.toList(growable: false)
          ..sort((left, right) {
            final rank = _caseRank(left.$2).compareTo(_caseRank(right.$2));
            return rank != 0 ? rank : left.$1.compareTo(right.$1);
          });
        report['cases'] = <Object?>[
          for (final item in ordered) _compactReportCase(item.$2),
        ];
      }
      return projection.value(report, path);
    }
    return projection.value(data, path);
  }
}

Map<String, Object?> _pick(
  Map<Object?, Object?> source,
  Iterable<String> keys,
) => <String, Object?>{
  for (final key in keys)
    if (source[key] != null) key: source[key],
};

Map<String, Object?> _compactOperationResult(
  Map<Object?, Object?> value, {
  required bool standard,
}) {
  final output = value['output'];
  final kind = value['kind'];
  final startedAt = DateTime.tryParse('${value['startedAt'] ?? ''}');
  final finishedAt = DateTime.tryParse('${value['finishedAt'] ?? ''}');
  return <String, Object?>{
    ..._pick(value, const <String>[
      'operationId',
      'kind',
      'lifecycle',
      'outcome',
    ]),
    if (standard) ..._pick(value, const <String>['rootId', 'workspaceId']),
    if (standard && startedAt != null && finishedAt != null)
      'durationMs': finishedAt.difference(startedAt).inMilliseconds,
    if (output is Map<Object?, Object?>)
      'output': _compactOperationPayload(
        kind is String ? kind : '',
        output,
        operation: value,
        standard: standard,
      )
    else
      'output': ?output,
    if (value['failure'] is Map<Object?, Object?>)
      'failure': _compactFailure(value['failure']! as Map<Object?, Object?>),
  };
}

Map<String, Object?> _compactOperationPayload(
  String kind,
  Map<Object?, Object?> output, {
  required Map<Object?, Object?> operation,
  required bool standard,
}) {
  final compacted = switch (kind) {
    'analyze.files' => _compactAnalysisOutput(output, standard: standard),
    'analyze.workspace' ||
    'fix.workspace' ||
    'format.workspace' ||
    'test.workspace' ||
    'package.pub' ||
    'shell.run' => _compactProcessOutput(output, standard: standard),
    'lsp.request' => _compactLspOutput(output, standard: standard),
    'ui.inspect' => _compactUiOutput(output, standard: standard),
    'surface.inspect' => _compactSurfaceOutput(output, standard: standard),
    'logs.read' ||
    'session.logs.read' => _compactLogsOutput(output, standard: standard),
    'network.read' => _compactNetworkOutput(output, standard: standard),
    'errors.read' => _compactErrorsOutput(output, standard: standard),
    'command.run' || 'command.remote.execute' => _compactInteractiveOutput(
      output,
      standard: standard,
    ),
    'command.batch' || 'command.remote.batch' => _compactInteractiveBatchOutput(
      output,
      standard: standard,
    ),
    'app.reload' ||
    'app.restart' ||
    'session.development.launch' ||
    'session.development.get' ||
    'session.development.reload' ||
    'session.development.stop' ||
    'app.launch' ||
    'target.launch' => _compactDevelopmentOutput(output, standard: standard),
    'development.probe.collect' => _compactProbeOutput(
      output,
      standard: standard,
    ),
    'development.probe.compare' => _compactProbeComparisonOutput(
      output,
      standard: standard,
    ),
    'lease.list' => _compactLeaseListOutput(output, standard: standard),
    _ => _compactGenericOperationOutput(output, standard: standard),
  };
  compacted.removeWhere(
    (key, child) => _repeatsOperationIdentity(key, child, operation),
  );
  return compacted;
}

Map<String, Object?> _compactAnalysisOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) {
  final rawDiagnostics = output['diagnostics'];
  final diagnostics = rawDiagnostics is List<Object?>
      ? rawDiagnostics.whereType<Map<Object?, Object?>>().toList(
          growable: false,
        )
      : const <Map<Object?, Object?>>[];
  diagnostics.sort((left, right) {
    final severity = _diagnosticRank(
      left['severity'],
    ).compareTo(_diagnosticRank(right['severity']));
    if (severity != 0) return severity;
    return '${left['path']}:${left['line']}:${left['column']}'.compareTo(
      '${right['path']}:${right['line']}:${right['column']}',
    );
  });
  return <String, Object?>{
    ..._pick(output, const <String>[
      'success',
      'clean',
      'summary',
      'totalDiagnostics',
      'severityCounts',
      'diagnosticsTruncated',
    ]),
    if (standard) ..._pick(output, const <String>['toolchain', 'paths']),
    if (diagnostics.isNotEmpty)
      'diagnostics': <Map<String, Object?>>[
        for (final diagnostic in diagnostics)
          _pick(
            diagnostic,
            standard
                ? const <String>[
                    'severity',
                    'code',
                    'message',
                    'path',
                    'line',
                    'column',
                    'endLine',
                    'endColumn',
                    'correction',
                  ]
                : const <String>[
                    'severity',
                    'code',
                    'message',
                    'path',
                    'line',
                    'column',
                  ],
          ),
      ],
    if (output['success'] != true)
      ..._pick(output, const <String>['stderrPreview', 'stdoutPreview']),
    if (standard) ..._pick(output, const <String>['command', 'exitCode']),
  };
}

int _diagnosticRank(Object? severity) => switch ('$severity'.toLowerCase()) {
  'error' => 0,
  'warning' => 1,
  'info' => 2,
  _ => 3,
};

Map<String, Object?> _compactProcessOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) => <String, Object?>{
  ..._pick(output, const <String>['success', 'exitCode']),
  if (standard) ..._pick(output, const <String>['command']),
  if (_nonEmpty(output['stderr'])) 'stderr': output['stderr'],
  if (_nonEmpty(output['stdout'])) 'stdout': output['stdout'],
};

Map<String, Object?> _compactLspOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) => <String, Object?>{
  ..._pick(output, const <String>[
    'command',
    'summary',
    'found',
    'path',
    'line',
    'column',
    'contents',
    'signature',
    'locations',
    'symbols',
    'items',
  ]),
  if (standard)
    for (final entry in output.entries)
      if (entry.key is String &&
          entry.key != 'workspaceRoot' &&
          entry.value != null)
        entry.key! as String: entry.value,
};

Map<String, Object?> _compactUiOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) => <String, Object?>{
  if (output['app'] is Map<Object?, Object?>)
    'app': _pick(output['app']! as Map<Object?, Object?>, const <String>[
      'appId',
      'targetId',
      'platform',
      'state',
    ]),
  ..._pick(output, const <String>[
    'routeName',
    'diagnosticLevel',
    'truncated',
    'uiSummary',
    'delta',
    'snapshotRef',
  ]),
  if (standard) ..._pick(output, const <String>['diagnostics', 'snapshot']),
};

Map<String, Object?> _compactSurfaceOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) => <String, Object?>{
  if (output['target'] is Map<Object?, Object?>)
    'target': _pick(
      output['target']! as Map<Object?, Object?>,
      standard
          ? const <String>[
              'targetId',
              'platform',
              'deviceId',
              'targetKind',
              'environment',
              'state',
            ]
          : const <String>['targetId', 'platform', 'targetKind', 'state'],
    ),
  ..._pick(output, const <String>[
    'surfaceKind',
    'selectedPlane',
    'routeName',
    'recommendedNextStep',
    'diagnosticLevel',
    'truncated',
    'uiSummary',
    'delta',
    'snapshotRef',
  ]),
  if (output['capabilityProfile'] is Map<Object?, Object?>)
    'capabilities': _compactCapabilities(
      output['capabilityProfile']! as Map<Object?, Object?>,
      standard: standard,
    ),
  if (standard) ..._pick(output, const <String>['diagnostics', 'snapshot']),
};

Map<String, Object?> _compactLogsOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) {
  final rawLines = output['lines'];
  final lines = rawLines is List<Object?> ? rawLines : const <Object?>[];
  final maximum = standard ? 32 : 8;
  final start = max(0, lines.length - maximum);
  return <String, Object?>{
    ..._pick(output, const <String>[
      'appId',
      'source',
      'available',
      'routeName',
      'missingReason',
      'truncated',
    ]),
    'lineCount': lines.length,
    if (start > 0) 'omittedLineCount': start,
    if (lines.isNotEmpty) 'order': 'newestFirst',
    if (lines.isNotEmpty)
      'lines': lines
          .skip(start)
          .toList(growable: false)
          .reversed
          .toList(growable: false),
  };
}

Map<String, Object?> _compactNetworkOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) => <String, Object?>{
  ..._pick(output, const <String>[
    'appId',
    'source',
    'available',
    'routeName',
    'summary',
    'recentFailures',
  ]),
  if (standard)
    ..._pick(output, const <String>[
      'endpointSummaries',
      'endpointSummariesTruncated',
      'entries',
    ]),
};

Map<String, Object?> _compactErrorsOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) {
  final rawErrors = output['errors'];
  final errors = rawErrors is List<Object?> ? rawErrors : const <Object?>[];
  return <String, Object?>{
    ..._pick(output, const <String>[
      'appId',
      'source',
      'routeName',
      'hasErrors',
    ]),
    'errorCount': errors.length,
    if (errors.isNotEmpty)
      'errors': <Object?>[
        for (final error in errors.take(standard ? 20 : 4))
          if (error is Map<Object?, Object?>)
            _pick(
              error,
              standard
                  ? const <String>[
                      'kind',
                      'message',
                      'source',
                      'routeName',
                      'recordedAt',
                    ]
                  : const <String>['kind', 'message', 'routeName'],
            )
          else
            error,
      ],
  };
}

Map<String, Object?> _compactInteractiveOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) => <String, Object?>{
  if (output['command'] is Map<Object?, Object?>)
    'command': _pick(
      output['command']! as Map<Object?, Object?>,
      standard
          ? const <String>[
              'commandId',
              'commandType',
              'success',
              'durationMs',
              'locatorResolution',
              'usedCaptureFallback',
              'degradationReason',
              'error',
            ]
          : const <String>[
              'commandType',
              'success',
              'durationMs',
              'usedCaptureFallback',
              'degradationReason',
              'error',
            ],
    ),
  ..._pick(output, const <String>[
    'selectedPlane',
    'fallbackTrail',
    'whatChanged',
    'whatMatters',
    'uiSummary',
    'delta',
    'snapshotRef',
    'recommendedNextStep',
    'artifacts',
  ]),
  if (standard)
    ..._pick(output, const <String>['diagnostics', 'runtimeSteps', 'snapshot']),
};

Map<String, Object?> _compactInteractiveBatchOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) => <String, Object?>{
  ..._pick(output, const <String>[
    'summary',
    'recordingResult',
    'finalSnapshot',
  ]),
  if (output['results'] is List<Object?>)
    'results': <Object?>[
      for (final result in output['results']! as List<Object?>)
        if (result is Map<Object?, Object?>)
          _compactInteractiveOutput(result, standard: standard)
        else
          result,
    ],
};

Map<String, Object?> _compactDevelopmentOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) {
  final result = <String, Object?>{
    ..._pick(output, const <String>[
      'appId',
      'sessionId',
      'targetId',
      'state',
      'status',
      'success',
      'ready',
      'processId',
      'platform',
      'routeName',
      'reloadGeneration',
      'message',
    ]),
  };
  for (final key in const <String>['app', 'target', 'sessionHandle']) {
    final child = output[key];
    if (child is Map<Object?, Object?>) {
      result[key] = _pick(
        child,
        standard
            ? const <String>[
                'appId',
                'sessionId',
                'targetId',
                'platform',
                'deviceId',
                'targetKind',
                'state',
                'status',
                'processId',
                'mode',
                'reloadGeneration',
              ]
            : const <String>[
                'appId',
                'sessionId',
                'targetId',
                'platform',
                'state',
                'status',
                'processId',
              ],
      );
    }
  }
  if (output['capabilities'] is Map<Object?, Object?>) {
    result['capabilities'] = _compactCapabilities(
      output['capabilities']! as Map<Object?, Object?>,
      standard: standard,
    );
  }
  return result;
}

Map<String, Object?> _compactProbeOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) {
  final probe = output['probe'];
  return <String, Object?>{
    if (probe is Map<Object?, Object?>)
      'probe': standard
          ? Map<String, Object?>.from(probe)
          : _pick(probe, const <String>[
              'probeId',
              'capturedAt',
              'reason',
              'checkpoint',
              'routeName',
              'reloadGeneration',
              'ui',
              'network',
              'runtime',
              'screenshot',
            ]),
    ..._pick(output, const <String>['warnings']),
  };
}

Map<String, Object?> _compactProbeComparisonOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) => <String, Object?>{
  if (output['fromProbe'] is Map<Object?, Object?>)
    'fromProbeId': (output['fromProbe']! as Map<Object?, Object?>)['probeId'],
  if (output['toProbe'] is Map<Object?, Object?>)
    'toProbeId': (output['toProbe']! as Map<Object?, Object?>)['probeId'],
  ..._pick(output, const <String>['delta']),
  if (standard) ..._pick(output, const <String>['fromProbe', 'toProbe']),
};

Map<String, Object?> _compactCapabilities(
  Map<Object?, Object?> capabilities, {
  required bool standard,
}) => standard
    ? _pick(capabilities, const <String>[
        'surfaceKinds',
        'supportedCommands',
        'actionCapabilities',
        'evidenceCapabilities',
        'qualityFlags',
      ])
    : <String, Object?>{
        'surfaceCount': _listLength(capabilities['surfaceKinds']),
        'commandCount': _listLength(capabilities['supportedCommands']),
        'actionCount': _listLength(capabilities['actionCapabilities']),
        'evidenceCount': _listLength(capabilities['evidenceCapabilities']),
        ..._pick(capabilities, const <String>['qualityFlags']),
      };

Map<String, Object?> _compactLeaseListOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) {
  final rawItems = output['items'];
  final items = rawItems is List<Object?>
      ? rawItems.whereType<Map<Object?, Object?>>().toList(growable: false)
      : const <Map<Object?, Object?>>[];
  final counts = <String, int>{};
  for (final item in items) {
    final state = item['state'];
    if (state is String) counts[state] = (counts[state] ?? 0) + 1;
  }
  final actionable = items.where((item) => item['state'] != 'released').toList()
    ..sort((left, right) {
      final rank = _leaseStateRank(
        left['state'],
      ).compareTo(_leaseStateRank(right['state']));
      if (rank != 0) return rank;
      return '${right['requestedAt']}'.compareTo('${left['requestedAt']}');
    });
  return <String, Object?>{
    'counts': counts,
    'actionableCount': actionable.length,
    if (actionable.isNotEmpty)
      'items': <Map<String, Object?>>[
        for (final item in actionable)
          _pick(
            item,
            standard
                ? item.keys.whereType<String>()
                : const <String>[
                    'leaseId',
                    'resourceKind',
                    'resourceId',
                    'state',
                    'ownerId',
                    'requestedAt',
                    'expiresAt',
                  ],
          ),
      ],
  };
}

Map<String, Object?> _compactGenericOperationOutput(
  Map<Object?, Object?> output, {
  required bool standard,
}) {
  if (standard) {
    return <String, Object?>{
      for (final entry in output.entries)
        if (entry.key is String && entry.value != null)
          entry.key! as String: entry.value,
    };
  }
  const preferred = <String>[
    'success',
    'valid',
    'available',
    'found',
    'state',
    'status',
    'summary',
    'message',
    'count',
    'totalCount',
    'items',
    'failure',
    'error',
    'recommendedNextStep',
  ];
  final result = _pick(output, preferred);
  if (result.isNotEmpty) return result;
  return <String, Object?>{
    for (final entry in output.entries.take(8))
      if (entry.key is String && entry.value != null)
        entry.key! as String: entry.value,
  };
}

bool _nonEmpty(Object? value) => value is String
    ? value.trim().isNotEmpty
    : value is Iterable<Object?>
    ? value.isNotEmpty
    : value != null;

bool _repeatsOperationIdentity(
  String key,
  Object? child,
  Map<Object?, Object?> operation,
) =>
    const <String>{'operationId', 'rootId', 'workspaceId'}.contains(key) &&
    child == operation[key];

Map<String, Object?> _compactTargetInspection(
  Map<Object?, Object?> value, {
  required bool standard,
}) {
  final capability = value['capabilityProfile'];
  final system = value['systemControl'];
  return <String, Object?>{
    ..._pick(value, const <String>[
      'targetId',
      'platform',
      'targetKind',
      'foregroundSurface',
      'selectedPlane',
      'currentRouteName',
    ]),
    if (standard && value['fallbackTrail'] != null)
      'fallbackTrail': value['fallbackTrail'],
    if (capability is Map<Object?, Object?>)
      'capabilities': _pick(capability, const <String>[
        'surfaceKinds',
        'actionCapabilities',
        'evidenceCapabilities',
        'qualityFlags',
      ]),
    if (value['uiSummary'] != null) 'uiSummary': value['uiSummary'],
    if (value['whatMatters'] != null) 'whatMatters': value['whatMatters'],
    if (system is Map<Object?, Object?>)
      'systemControl': standard
          ? _pick(system, const <String>[
              'adapter',
              'preferredPlane',
              'fallbackOrder',
              'availableActions',
              'blockedActions',
              'actionGroups',
              'recommendedNextStep',
            ])
          : <String, Object?>{
              ..._pick(system, const <String>['adapter', 'preferredPlane']),
              'availableActionCount': _listLength(system['availableActions']),
              'blockedActionCount': _listLength(system['blockedActions']),
            },
    if (standard && value['snapshotRef'] != null)
      'snapshotRef': value['snapshotRef'],
    if (standard && value['snapshot'] != null) 'snapshot': value['snapshot'],
    if (value['recommendedNextStep'] != null)
      'recommendedNextStep': value['recommendedNextStep'],
  };
}

Map<String, Object?> _compactRun(
  Map<Object?, Object?> value, {
  required bool standard,
}) => <String, Object?>{
  ..._pick(value, const <String>[
    'runId',
    'documentKind',
    'documentId',
    'lifecycle',
    'outcome',
    'stability',
  ]),
  if (standard)
    ..._pick(value, const <String>[
      'workspaceId',
      'submittedAt',
      'startedAt',
      'finishedAt',
      'caseIds',
      'activeAttemptIds',
    ]),
  if (!standard) 'caseCount': _listLength(value['caseIds']),
  if (!standard && _listLength(value['activeAttemptIds']) > 0)
    'activeAttemptCount': _listLength(value['activeAttemptIds']),
  if (value['failure'] is Map<Object?, Object?>)
    'failure': _compactFailure(value['failure']! as Map<Object?, Object?>),
};

int _listLength(Object? value) => value is List<Object?> ? value.length : 0;

Object? _compactDaemonLogLine(Object? value) {
  if (value is! String) return value;
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map<Object?, Object?>) return value;
    final fields = decoded['fields'];
    final fieldMap = fields is Map<Object?, Object?> ? fields : null;
    Map<Object?, Object?>? nested;
    final nestedLine = fieldMap?['line'];
    if (nestedLine is String) {
      try {
        final nestedDecoded = jsonDecode(nestedLine);
        if (nestedDecoded is Map<Object?, Object?>) nested = nestedDecoded;
      } on FormatException {
        // Keep the bounded outer log record when a worker line is plain text.
      }
    }
    final nestedFields = nested?['fields'];
    final nestedFieldMap = nestedFields is Map<Object?, Object?>
        ? nestedFields
        : null;
    return <String, Object?>{
      if (decoded['timestamp'] != null) 'timestamp': decoded['timestamp'],
      if ((nested?['level'] ?? decoded['level']) != null)
        'level': nested?['level'] ?? decoded['level'],
      if ((nested?['message'] ?? decoded['message']) != null)
        'message': nested?['message'] ?? decoded['message'],
      if (nested != null) 'source': 'workspaceWorker',
      for (final key in const <String>['workspaceId', 'processId'])
        if (fieldMap?[key] != null) key: fieldMap![key],
      for (final key in const <String>['operationKind', 'errorType', 'error'])
        if ((nestedFieldMap?[key] ?? fieldMap?[key]) != null)
          key: nestedFieldMap?[key] ?? fieldMap?[key],
    };
  } on FormatException {
    return value;
  }
}

int _leaseStateRank(Object? state) => switch (state) {
  'quarantined' => 0,
  'active' || 'acquired' => 1,
  'queued' || 'requested' => 2,
  'expired' => 3,
  _ => 4,
};

Map<String, Object?>? _compactCollection(
  String command,
  Map<Object?, Object?> value,
  CockpitCliOutputDetail detail,
) {
  final standard = detail == CockpitCliOutputDetail.standard;
  final keys = switch (command) {
    'root.list' => <String>[
      'rootId',
      'state',
      'label',
      'canonicalPath',
      if (standard) 'createdAt',
    ],
    'workspace.list' => <String>[
      'workspaceId',
      'projectId',
      'rootId',
      'state',
      'canonicalPath',
      if (standard) ...<String>['engineVersion', 'createdAt', 'updatedAt'],
    ],
    'workspace.documents' || 'case.list' || 'suite.list' => <String>[
      'documentId',
      'kind',
      'relativePath',
      'authoredId',
      'caseId',
      'title',
      if (standard) ...<String>['sha256', 'modifiedAt', 'cases'],
    ],
    'target.discover' || 'target.list' => <String>[
      'targetId',
      'platform',
      'deviceId',
      'targetKind',
      'environment',
      'mode',
      'appId',
      'state',
      if (standard) ...<String>['flavor', 'entrypoint', 'wdaUrl'],
    ],
    'artifact.list' => <String>[
      'artifactId',
      'attemptId',
      'stepExecutionId',
      'kind',
      'relativePath',
      'mediaType',
      'sizeBytes',
      if (standard) ...<String>['sha256', 'createdAt', 'role'],
    ],
    'run.events' => <String>[
      'sequence',
      'kind',
      'caseId',
      'stepExecutionId',
      'status',
      'lifecycle',
      'outcome',
      'stability',
      'requestedPlane',
      'actualPlane',
      if (standard) ...<String>[
        'timestamp',
        'message',
        'durationMs',
        'failure',
        'artifacts',
      ],
    ],
    _ => null,
  };
  if (keys == null) return null;
  final rawItems = value['items']! as List<Object?>;
  return <String, Object?>{
    ..._pick(value, const <String>[
      'totalCount',
      'requestedRelativePath',
      'workspaceRoot',
      'hint',
    ]),
    'items': <Object?>[
      for (final item in rawItems)
        if (item is Map<Object?, Object?>)
          <String, Object?>{
            for (final key in keys)
              if (item[key] != null) key: item[key],
            if (item['cases'] is List<Object?> &&
                (item['cases']! as List<Object?>).isNotEmpty)
              'caseCount': (item['cases']! as List<Object?>).length,
            if (item['failure'] is Map<Object?, Object?>)
              'failure': _compactFailure(
                item['failure']! as Map<Object?, Object?>,
              ),
          }
        else
          item,
    ],
  };
}

Map<String, Object?> _compactFailure(Map<Object?, Object?> failure) {
  final primary = failure['primary'];
  final source = primary is Map<Object?, Object?> ? primary : failure;
  return <String, Object?>{
    for (final key in const <String>[
      'code',
      'category',
      'message',
      'retryable',
      'responsibleLayer',
    ])
      if (source[key] != null) key: source[key],
  };
}

Map<String, Object?> _compactValidationResult(
  Map<Object?, Object?> value, {
  required bool standard,
}) {
  final document = value['document'];
  final sourceMap = value['sourceMap'];
  return <String, Object?>{
    for (final key in <String>['valid', if (standard) 'sourceSha256'])
      if (value[key] != null) key: value[key],
    if (document is Map<Object?, Object?>)
      'document': _compactValidatedDocument(document, standard: standard),
    if (value['diagnostics'] != null) 'diagnostics': value['diagnostics'],
    if (sourceMap is List<Object?>) 'sourceMapEntries': sourceMap.length,
  };
}

Map<String, Object?> _compactValidatedDocument(
  Map<Object?, Object?> value, {
  required bool standard,
}) {
  int lengthOf(String key) => switch (value[key]) {
    List<Object?> items => items.length,
    Map<Object?, Object?> items => items.length,
    _ => 0,
  };

  final kind = value['kind'];
  return <String, Object?>{
    for (final key in <String>[
      'schemaVersion',
      'kind',
      'id',
      'name',
      if (standard) ...<String>[
        'description',
        'tags',
        'target',
        'defaults',
        'execution',
        'report',
        'matrix',
      ],
    ])
      if (value[key] != null) key: value[key],
    'counts': kind == 'suite'
        ? <String, Object?>{
            'cases': lengthOf('cases'),
            'fixtures': lengthOf('fixtures'),
            'matrixAxes': switch (value['matrix']) {
              Map<Object?, Object?> matrix => switch (matrix['axes']) {
                Map<Object?, Object?> axes => axes.length,
                _ => 0,
              },
              _ => 0,
            },
          }
        : <String, Object?>{
            'setupSteps': lengthOf('setup'),
            'mainSteps': lengthOf('steps'),
            'finallySteps': lengthOf('finally'),
            'fragments': lengthOf('fragments'),
            'variables': lengthOf('variables'),
          },
  };
}

Object? _compactReportCase(Object? value) {
  if (value is! Map<Object?, Object?>) return value;
  final outcome = value['outcome'];
  final stability = value['stability'];
  final attempts = value['attempts'];
  return <String, Object?>{
    for (final key in const <String>[
      'entryId',
      'caseId',
      'outcome',
      'stability',
      'targetId',
      'matrix',
    ])
      if (value[key] != null) key: value[key],
    if ((outcome != 'passed' || stability == 'flaky') &&
        attempts is List<Object?> &&
        attempts.isNotEmpty)
      'attempt': attempts.last,
  };
}

int _caseRank(Object? value) {
  if (value is! Map<Object?, Object?>) return 4;
  return switch (value['outcome']) {
    'failed' || 'blocked' || 'internalError' => 0,
    'cancelled' || 'interrupted' => 1,
    _ when value['stability'] == 'flaky' => 2,
    'passed' => 3,
    _ => 4,
  };
}

int _priority(String key) {
  const ordered = <String>[
    'schemaVersion',
    'operationId',
    'projectId',
    'workspaceId',
    'rootId',
    'runId',
    'suiteId',
    'entryId',
    'caseId',
    'targetId',
    'artifactId',
    'kind',
    'lifecycle',
    'outcome',
    'status',
    'state',
    'stability',
    'healthy',
    'running',
    'valid',
    'success',
    'counts',
    'failure',
    'error',
    'message',
    'output',
    'items',
    'cases',
    'artifacts',
    'sha256',
    'sizeBytes',
  ];
  final index = ordered.indexOf(key);
  return index < 0 ? ordered.length : index;
}

String _status(Object? data) {
  if (data is Map<Object?, Object?>) {
    if (data['running'] == false) return 'stopped';
    if (data['healthy'] == false) return 'unhealthy';
    if (data['healthy'] == true) return 'healthy';
    if (data['valid'] == true) return 'valid';
    if (data['success'] == true) return 'succeeded';
    if (data['success'] == false || data['valid'] == false) return 'failed';
    for (final key in const <String>[
      'outcome',
      'lifecycle',
      'status',
      'state',
    ]) {
      final value = data[key];
      if (value is String && value.isNotEmpty) return value;
    }
  }
  return 'ok';
}

int? _collectionSize(Object? value) => switch (value) {
  List<Object?>() => value.length,
  Map<Object?, Object?>() => value.length,
  String() => value.length,
  _ => null,
};

String _renderSemantic({
  required String command,
  required Object? data,
  required CockpitCliOutputDetail detail,
  Map<String, int> omitted = const <String, int>{},
}) {
  final lines = <String>['status=${_status(data)}'];
  if (data is Map<Object?, Object?>) {
    _renderSemanticMap(lines, data);
  } else if (data is List<Object?>) {
    _renderSemanticList(lines, 'items', data);
  } else {
    lines.add('data value=${_scalar(data)}');
  }
  if (omitted.isNotEmpty) {
    lines.add('truncated=true');
    lines.add(
      'omitted ${omitted.entries.map((entry) => '${_scalar(entry.key)}=${entry.value}').join(' ')}',
    );
  }
  return lines.join('\n');
}

void _renderSemanticMap(List<String> lines, Map<Object?, Object?> value) {
  const collectionKeys = <String>['items', 'cases', 'artifacts', 'lines'];
  const issueKeys = <String>['failure', 'error', 'errors', 'failures'];
  const resultKeys = <String>['output', 'result'];
  const summaryKeys = <String>['counts', 'summary'];
  const statusKeys = <String>{
    'healthy',
    'success',
    'valid',
    'outcome',
    'lifecycle',
    'status',
    'state',
    'running',
  };
  final handled = <String>{
    ...collectionKeys,
    ...issueKeys,
    ...resultKeys,
    ...summaryKeys,
  };
  final state = <String>[];
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String ||
        handled.contains(key) ||
        statusKeys.contains(key) ||
        entry.value == null) {
      continue;
    }
    if (entry.value is String || entry.value is num || entry.value is bool) {
      state.add('$key=${_scalar(entry.value)}');
    }
  }
  if (state.isNotEmpty) lines.add('state ${state.join(' ')}');

  for (final key in summaryKeys) {
    final child = value[key];
    if (child is Map<Object?, Object?> && child.isNotEmpty) {
      lines.add('$key ${_inlineMap(child)}');
    } else if (child != null) {
      lines.add('$key=${_inline(child)}');
    }
  }
  for (final key in issueKeys) {
    final child = value[key];
    if (child == null) continue;
    final label = key == 'failure' || key == 'error' ? 'issue' : 'issues';
    if (child is Map<Object?, Object?>) {
      _renderSemanticSection(lines, label, child);
    } else if (child is List<Object?>) {
      _renderSemanticList(lines, label, child);
    } else {
      lines.add('$label ${_inline(child)}');
    }
  }
  for (final key in resultKeys) {
    final child = value[key];
    if (child == null) continue;
    if (child is Map<Object?, Object?>) {
      _renderSemanticSection(lines, 'result', child);
    } else if (child is List<Object?>) {
      _renderSemanticList(lines, 'result', child);
    } else {
      lines.add('result ${_inline(child)}');
    }
  }
  for (final key in collectionKeys) {
    final child = value[key];
    if (child is List<Object?> && child.isNotEmpty) {
      _renderSemanticList(lines, key, child);
    }
  }

  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String ||
        handled.contains(key) ||
        statusKeys.contains(key) ||
        entry.value == null) {
      continue;
    }
    if (entry.value is Map<Object?, Object?> || entry.value is List<Object?>) {
      if (entry.value is Map<Object?, Object?>) {
        _renderSemanticSection(
          lines,
          key,
          entry.value! as Map<Object?, Object?>,
        );
      } else {
        _renderSemanticList(lines, key, entry.value! as List<Object?>);
      }
    }
  }
}

void _renderSemanticSection(
  List<String> lines,
  String label,
  Map<Object?, Object?> value,
) {
  final scalars = <String>[];
  for (final entry in value.entries) {
    if (entry.key is String &&
        entry.value != null &&
        (entry.value is String || entry.value is num || entry.value is bool)) {
      scalars.add('${entry.key}=${_scalar(entry.value)}');
    }
  }
  if (scalars.isNotEmpty) lines.add('$label ${scalars.join(' ')}');
  for (final entry in value.entries) {
    final key = entry.key;
    final child = entry.value;
    if (key is! String || child == null) continue;
    if (child is Map<Object?, Object?>) {
      _renderSemanticSection(lines, '$label.$key', child);
    } else if (child is List<Object?> && child.isNotEmpty) {
      _renderSemanticList(lines, '$label.$key', child);
    }
  }
}

void _renderSemanticList(List<String> lines, String key, List<Object?> values) {
  final maps = values.whereType<Map<Object?, Object?>>().toList(
    growable: false,
  );
  if (values.length > 1 && maps.length == values.length) {
    final fields = <String>[];
    for (final item in maps) {
      for (final candidate in item.keys.whereType<String>()) {
        if (!fields.contains(candidate)) fields.add(candidate);
      }
    }
    fields.sort((left, right) {
      final rank = _priority(left).compareTo(_priority(right));
      return rank != 0 ? rank : left.compareTo(right);
    });
    lines.add('$key[${values.length}]{${fields.join('|')}}');
    for (final item in maps) {
      lines.add(
        '  ${fields.map((field) => item[field] == null ? '-' : _inline(item[field])).join(' | ')}',
      );
    }
    return;
  }
  lines.add('$key count=${values.length}');
  for (var index = 0; index < values.length; index += 1) {
    final item = values[index];
    lines.add(
      '  [$index] ${item is Map<Object?, Object?> ? _inlineMap(item) : _inline(item)}',
    );
  }
}

String _inline(Object? value) => switch (value) {
  Map<Object?, Object?>() => '{${_inlineMap(value)}}',
  List<Object?>() => '[${value.map(_inline).join('|')}]',
  _ => _scalar(value),
};

String _inlineMap(Map<Object?, Object?> value) {
  final entries = value.entries
      .where((entry) => entry.key is String && entry.value != null)
      .toList(growable: false);
  final indexed = entries.indexed.toList(growable: false)
    ..sort((left, right) {
      final rank = _priority(
        left.$2.key! as String,
      ).compareTo(_priority(right.$2.key! as String));
      return rank != 0 ? rank : left.$1.compareTo(right.$1);
    });
  return indexed
      .map((entry) => '${entry.$2.key}=${_inline(entry.$2.value)}')
      .join(' ');
}

String _scalar(Object? value) {
  if (value == null) return 'null';
  if (value is num || value is bool) return '$value';
  final text = '$value';
  return RegExp(r'^[A-Za-z0-9_./:@,+-]+$').hasMatch(text)
      ? text
      : jsonEncode(text);
}
