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
          'json preserves the complete protocol envelope.',
    )
    ..addOption(
      'detail',
      allowed: CockpitCliOutputDetail.values.map((value) => value.name),
      defaultsTo: CockpitCliOutputDetail.standard.name,
      help: 'AI output detail. This does not change runtime evidence capture.',
    )
    ..addOption(
      'output',
      help: 'Atomically write the complete JSON response to this file.',
    );
}

final class CockpitCliOutputSelection {
  const CockpitCliOutputSelection({
    this.stdoutFormat = CockpitCliStdoutFormat.auto,
    this.detail = CockpitCliOutputDetail.standard,
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
    CockpitCliOutputDetail detail = CockpitCliOutputDetail.standard;
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
    this.minimalMaximumBytes = 4 * 1024,
    this.standardMaximumBytes = 16 * 1024,
  }) : assert(minimalMaximumBytes > 0),
       assert(standardMaximumBytes > 0);

  final int minimalMaximumBytes;
  final int standardMaximumBytes;

  String renderJson({required Object? data}) =>
      cockpitCompactJsonText(<String, Object?>{'ok': true, 'data': data});

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
            _ProjectionLimits(8, 12, 512, 6),
            _ProjectionLimits(4, 8, 256, 4),
            _ProjectionLimits(2, 6, 128, 3),
          ]
        : const <_ProjectionLimits>[
            _ProjectionLimits(50, 64, 2048, 10),
            _ProjectionLimits(20, 40, 1024, 8),
            _ProjectionLimits(10, 24, 512, 6),
            _ProjectionLimits(5, 12, 256, 4),
          ];
    for (final limits in attempts) {
      final projection = _Projection(limits);
      final projected = _projectForCommand(
        command,
        data,
        projection,
        r'$.data',
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
      'cockpit.v=2 command=${_scalar(command)} status=${_status(data)} '
          'detail=${detail.name}',
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
  }) {
    final state = <String>[
      'code=${_scalar(code)}',
      'retryable=$retryable',
      if (category != null) 'category=${_scalar(category)}',
      if (responsibleLayer != null)
        'responsibleLayer=${_scalar(responsibleLayer)}',
      'message=${_scalar(message)}',
    ];
    return <String>[
      'cockpit.v=2 status=error',
      'error ${state.join(' ')}',
      if (details.isNotEmpty) 'details ${_inlineMap(details)}',
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
      final fullText = _renderer.renderJson(data: data);
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
        stdoutSink.writeln(_renderer.renderJson(data: data));
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
      'ok': false,
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
        stderrSink.writeln(cockpitCompactJsonText(value));
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
        stdoutSink.writeln(_renderer.renderJson(data: receipt.toJson()));
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

Object? _projectForCommand(
  String command,
  Object? data,
  _Projection projection,
  String path,
) {
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
    if (data['healthy'] == true) return 'healthy';
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
    if (data['running'] == false) return 'stopped';
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
  final lines = <String>[
    'cockpit.v=2 command=${_scalar(command)} status=${_status(data)} '
        'detail=${detail.name}',
  ];
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
  final handled = <String>{
    ...collectionKeys,
    ...issueKeys,
    ...resultKeys,
    ...summaryKeys,
  };
  final state = <String>[];
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || handled.contains(key) || entry.value == null) {
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
    }
  }
  for (final key in issueKeys) {
    final child = value[key];
    if (child == null) continue;
    lines.add('issues $key=${_inline(child)}');
  }
  for (final key in resultKeys) {
    final child = value[key];
    if (child == null) continue;
    lines.add('result $key=${_inline(child)}');
  }
  for (final key in collectionKeys) {
    final child = value[key];
    if (child is List<Object?> && child.isNotEmpty) {
      _renderSemanticList(lines, key, child);
    }
  }

  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || handled.contains(key) || entry.value == null) {
      continue;
    }
    if (entry.value is Map<Object?, Object?> || entry.value is List<Object?>) {
      lines.add('$key ${_inline(entry.value)}');
    }
  }
}

void _renderSemanticList(List<String> lines, String key, List<Object?> values) {
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
