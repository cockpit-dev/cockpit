import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:lon/lon.dart';
import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';

import '../application/cockpit_compact_json.dart';

enum CockpitCliFormat { lon, json, yaml, jsonl, path, none }

enum CockpitCliOutputDetail { minimal, standard, full }

void cockpitAddCliOutputOptions(ArgParser parser) {
  parser
    ..addOption(
      'format',
      allowed: CockpitCliFormat.values.map((value) => value.name),
      defaultsTo: CockpitCliFormat.lon.name,
      help:
          'Output encoding: lon by default; json/yaml/jsonl for structured '
          'pipelines; path prints the primary artifact or --output path; '
          'none stays silent.',
    )
    ..addOption(
      'verbosity',
      allowed: CockpitCliOutputDetail.values.map((value) => value.name),
      defaultsTo: CockpitCliOutputDetail.minimal.name,
      help:
          'Response density: minimal for the next decision, standard for '
          'diagnosis, full for the complete semantic response.',
    )
    ..addOption(
      'output',
      help:
          'Atomically write the selected LON/JSON/YAML/JSONL projection. Stdout '
          'prints only the verified output path; none stays silent. Use '
          '--verbosity full for the complete response.',
    );
}

final class CockpitCliOutputSelection {
  const CockpitCliOutputSelection({
    this.format = CockpitCliFormat.lon,
    this.detail = CockpitCliOutputDetail.minimal,
    this.outputPath,
  });

  factory CockpitCliOutputSelection.fromArguments(ArgResults arguments) {
    return CockpitCliOutputSelection(
      format: CockpitCliFormat.values.byName(arguments.option('format')!),
      detail: CockpitCliOutputDetail.values.byName(
        arguments.option('verbosity')!,
      ),
      outputPath: arguments.option('output'),
    );
  }

  factory CockpitCliOutputSelection.fromRawArguments(List<String> arguments) {
    CockpitCliFormat format = CockpitCliFormat.lon;
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
      final formatValue = optionValue('format', index);
      if (formatValue != null) {
        format =
            CockpitCliFormat.values
                .where((value) => value.name == formatValue)
                .firstOrNull ??
            format;
      }
      final detailValue = optionValue('verbosity', index);
      if (detailValue != null) {
        detail =
            CockpitCliOutputDetail.values
                .where((value) => value.name == detailValue)
                .firstOrNull ??
            detail;
      }
    }
    return CockpitCliOutputSelection(format: format, detail: detail);
  }

  final CockpitCliFormat format;
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
  }) => cockpitCompactJsonText(
    _semanticValue(command: command, data: data, detail: detail),
  );

  String renderYaml({
    required String command,
    required Object? data,
    required CockpitCliOutputDetail detail,
  }) {
    final editor = YamlEditor('');
    editor.update(
      const <Object?>[],
      _semanticValue(command: command, data: data, detail: detail),
    );
    return editor.toString();
  }

  String renderAi({
    required String command,
    required Object? data,
    required CockpitCliOutputDetail detail,
  }) =>
      lon.encode(_semanticValue(command: command, data: data, detail: detail));

  Object? _semanticValue({
    required String command,
    required Object? data,
    required CockpitCliOutputDetail detail,
  }) {
    if (detail == CockpitCliOutputDetail.full) {
      return cockpitCompactJsonValue(_conciseCliValue(data));
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
      final value = cockpitCompactJsonValue(
        _conciseCliValue(
          _withProjectionMetadata(projected, projection.omitted),
        ),
      );
      if (utf8.encode(lon.encode(value)).length <= maximumBytes) return value;
    }
    return cockpitCompactJsonValue(
      _conciseCliValue(<String, Object?>{
        'command': command,
        'truncated': true,
        'reason': 'outputBudgetExceeded',
        'maximumBytes': maximumBytes,
      }),
    );
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
    final omitted = <String, int>{};
    final renderedMessage = message.length <= maximumMessageLength
        ? message
        : '${message.substring(0, maximumMessageLength)}...';
    if (renderedMessage.length != message.length) {
      omitted[r'$.error.message'] = message.length - maximumMessageLength;
    }
    final projection = detail == CockpitCliOutputDetail.full
        ? null
        : _Projection(
            detail == CockpitCliOutputDetail.minimal
                ? const _ProjectionLimits(2, 8, 256, 3)
                : const _ProjectionLimits(4, 12, 512, 4),
          );
    final renderedDetails = projection?.value(details, r'$.error.details');
    if (projection != null) omitted.addAll(projection.omitted);
    return lon.encode(
      _conciseCliValue(
        _withProjectionMetadata(<String, Object?>{
          'error': <String, Object?>{
            'code': code,
            'message': renderedMessage,
            'retryable': retryable,
            'category': ?category,
            'responsibleLayer': ?responsibleLayer,
            if (details.isNotEmpty) 'details': renderedDetails ?? details,
          },
        }, omitted),
      ),
    );
  }
}

Object? _withProjectionMetadata(Object? value, Map<String, int> omitted) {
  if (omitted.isEmpty) return value;
  final metadata = <String, Object?>{
    'more': true,
    'skipped': omitted.values.fold<int>(0, (total, count) => total + count),
  };
  return switch (value) {
    Map<Object?, Object?>() => <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key! as String: entry.value,
      '_meta': metadata,
    },
    List<Object?>() => <String, Object?>{'items': value, '_meta': metadata},
    _ => <String, Object?>{'value': value, '_meta': metadata},
  };
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
    _rejectInlineArtifactContent(data);
    CockpitCliFileReceipt? receipt;
    if (selection.outputPath case final path?) {
      final encoded = _encode(
        command: command,
        data: data,
        format: selection.format,
        detail: selection.detail,
        forFile: true,
      );
      receipt = await _writeFile(
        path,
        '${encoded.text}\n',
        mediaType: encoded.mediaType,
      );
    }
    if (receipt != null) {
      writeReceipt(
        receipt: receipt,
        selection: CockpitCliOutputSelection(
          format: selection.format,
          detail: CockpitCliOutputDetail.minimal,
        ),
      );
      return;
    }
    if (selection.format == CockpitCliFormat.path) {
      final primaryPath = _primaryArtifactPath(command, data);
      if (primaryPath == null) {
        throw const FormatException(
          '--format path requires a command artifact or --output.',
        );
      }
      final file = File(primaryPath);
      if (!p.isAbsolute(primaryPath) || !await file.exists()) {
        throw const FormatException(
          'The command artifact path is not an existing absolute file.',
        );
      }
      stdoutSink.writeln(p.normalize(await file.resolveSymbolicLinks()));
      return;
    }
    switch (selection.format) {
      case CockpitCliFormat.none:
        return;
      case CockpitCliFormat.path:
        throw StateError('Path output was not resolved.');
      case CockpitCliFormat.json || CockpitCliFormat.jsonl:
        stdoutSink.writeln(
          _renderer.renderJson(
            command: command,
            data: data,
            detail: selection.detail,
          ),
        );
      case CockpitCliFormat.yaml:
        stdoutSink.writeln(
          _renderer.renderYaml(
            command: command,
            data: data,
            detail: selection.detail,
          ),
        );
      case CockpitCliFormat.lon:
        stdoutSink.writeln(
          _renderer.renderAi(
            command: command,
            data: data,
            detail: selection.detail,
          ),
        );
    }
  }

  void writeJsonLine({
    required String command,
    required Object? data,
    required CockpitCliOutputSelection selection,
  }) {
    if (selection.format != CockpitCliFormat.jsonl ||
        selection.outputPath != null) {
      throw StateError('Streaming JSONL requires stdout JSONL output.');
    }
    _rejectInlineArtifactContent(data);
    stdoutSink.writeln(
      _renderer.renderJson(
        command: command,
        data: data,
        detail: selection.detail,
      ),
    );
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
    switch (selection.format) {
      case CockpitCliFormat.json || CockpitCliFormat.jsonl:
        stderrSink.writeln(
          _renderer.renderJson(
            command: 'error',
            data: value,
            detail: selection.detail,
          ),
        );
      case CockpitCliFormat.yaml:
        stderrSink.writeln(
          _renderer.renderYaml(
            command: 'error',
            data: value,
            detail: selection.detail,
          ),
        );
      case CockpitCliFormat.lon ||
          CockpitCliFormat.path ||
          CockpitCliFormat.none:
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
    switch (selection.format) {
      case CockpitCliFormat.none:
        return;
      case CockpitCliFormat.path:
        stdoutSink.writeln(receipt.path);
      case CockpitCliFormat.json || CockpitCliFormat.jsonl:
        stdoutSink.writeln(
          _renderer.renderJson(
            command: 'output.receipt',
            data: receipt.toJson(),
            detail: selection.detail,
          ),
        );
      case CockpitCliFormat.yaml:
        stdoutSink.writeln(
          _renderer.renderYaml(
            command: 'output.receipt',
            data: receipt.toJson(),
            detail: selection.detail,
          ),
        );
      case CockpitCliFormat.lon:
        stdoutSink.writeln(receipt.render());
    }
  }

  Future<CockpitCliFileReceipt> _writeFile(
    String requested,
    String text, {
    required String mediaType,
  }) async {
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
      if (await destination.length() != bytes.length) {
        throw FileSystemException(
          'Output size changed after atomic replacement.',
          destination.path,
        );
      }
      await destination.resolveSymbolicLinks();
      return CockpitCliFileReceipt(
        path: destination.path,
        mediaType: mediaType,
        sizeBytes: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      );
    } finally {
      await handle?.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  _CockpitEncodedOutput _encode({
    required String command,
    required Object? data,
    required CockpitCliFormat format,
    required CockpitCliOutputDetail detail,
    required bool forFile,
  }) {
    return switch (format) {
      CockpitCliFormat.lon => _CockpitEncodedOutput(
        text: _renderer.renderAi(command: command, data: data, detail: detail),
        mediaType: 'application/vnd.lon+text',
      ),
      CockpitCliFormat.json => _CockpitEncodedOutput(
        text: _renderer.renderJson(
          command: command,
          data: data,
          detail: detail,
        ),
        mediaType: 'application/json',
      ),
      CockpitCliFormat.jsonl => _CockpitEncodedOutput(
        text: _renderer.renderJson(
          command: command,
          data: data,
          detail: detail,
        ),
        mediaType: 'application/x-ndjson',
      ),
      CockpitCliFormat.yaml => _CockpitEncodedOutput(
        text: _renderer.renderYaml(
          command: command,
          data: data,
          detail: detail,
        ),
        mediaType: 'application/yaml',
      ),
      CockpitCliFormat.path ||
      CockpitCliFormat.none when forFile => _CockpitEncodedOutput(
        text: _renderer.renderJson(
          command: command,
          data: data,
          detail: detail,
        ),
        mediaType: 'application/json',
      ),
      CockpitCliFormat.path || CockpitCliFormat.none => throw StateError(
        'Path-only output requires a destination file.',
      ),
    };
  }
}

final class _CockpitEncodedOutput {
  const _CockpitEncodedOutput({required this.text, required this.mediaType});

  final String text;
  final String mediaType;
}

String? _primaryArtifactPath(String command, Object? data) {
  if (data is! Map<Object?, Object?>) return null;
  final evidence = data['evidence'];
  if (evidence is! Map<Object?, Object?>) return null;
  if (command == 'dev.network') {
    final paths = evidence.values
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    return paths.length == 1 ? paths.single : null;
  }
  if (command != 'dev.screenshot') return null;
  final actual = evidence['actual'];
  if (actual is! Map<Object?, Object?>) return null;
  final path = actual['path'];
  return path is String && path.isNotEmpty ? path : null;
}

void _rejectInlineArtifactContent(Object? value, {String path = r'$'}) {
  if (value is Uint8List || value is ByteData) {
    throw FormatException(
      'Artifact bytes are forbidden in CLI output at $path.',
    );
  }
  if (value case final Map<Object?, Object?> map) {
    for (final entry in map.entries) {
      final key = '${entry.key}';
      final normalized = key
          .replaceAll(RegExp('[^a-zA-Z0-9]'), '')
          .toLowerCase();
      if (_inlineArtifactKeys.any(normalized.contains) && entry.value != null) {
        throw FormatException(
          'Artifact or file content is forbidden in CLI output at $path.$key.',
        );
      }
      _rejectInlineArtifactContent(entry.value, path: '$path.$key');
    }
    return;
  }
  if (value case final Iterable<Object?> items) {
    var index = 0;
    for (final item in items) {
      _rejectInlineArtifactContent(item, path: '$path[$index]');
      index += 1;
    }
    return;
  }
  if (value case final String text when _dataUriPattern.hasMatch(text)) {
    throw FormatException('Data URIs are forbidden in CLI output at $path.');
  }
}

const Set<String> _inlineArtifactKeys = <String>{
  'artifactpayload',
  'archivebytes',
  'base64',
  'filecontent',
  'imagebytes',
  'payloadbytes',
  'recordingbytes',
  'screenshotbytes',
};

final RegExp _dataUriPattern = RegExp(
  r'^data:[^;,]{1,127}(?:;[^,]{0,127})?;base64,',
  caseSensitive: false,
);

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

  Map<String, Object?> toJson() => <String, Object?>{'path': path};

  String render() => lon.encode(toJson());
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
    if (command.startsWith('dev.') && data is Map<Object?, Object?>) {
      return projection.value(
        _compactDevEnvelope(
          data,
          standard: detail == CockpitCliOutputDetail.standard,
        ),
        path,
      );
    }
    if (command == 'op.list' && data is List<Object?>) {
      if (data.length == 1 && data.single is Map<Object?, Object?>) {
        return projection.value(
          _pick(
            data.single! as Map<Object?, Object?>,
            detail == CockpitCliOutputDetail.standard
                ? const <String>[
                    'kind',
                    'title',
                    'description',
                    'scope',
                    'mutationClass',
                    'idempotency',
                    'executionMode',
                    'defaultTimeoutMs',
                    'maximumTimeoutMs',
                    'safetyEffects',
                    'requestSchemaRef',
                    'responseSchemaRef',
                  ]
                : const <String>[
                    'kind',
                    'scope',
                    'mutationClass',
                    'idempotency',
                    'executionMode',
                    'defaultTimeoutMs',
                    'maximumTimeoutMs',
                    'safetyEffects',
                  ],
          ),
          path,
        );
      }
      if (data.isEmpty) {
        return const <String, Object?>{
          'operationCount': 0,
          'items': <Object?>[],
        };
      }
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
    if (command == 'explain' && data is Map<Object?, Object?>) {
      return projection.value(
        _compactExplain(
          data,
          standard: detail == CockpitCliOutputDetail.standard,
        ),
        path,
      );
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
    if (command == 'op.run' && data is Map<Object?, Object?>) {
      return projection.value(
        _compactOperationResult(
          data,
          standard: detail == CockpitCliOutputDetail.standard,
        ),
        path,
      );
    }
    if (command == 'session.show' && data is Map<Object?, Object?>) {
      return projection.value(
        _compactSession(
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
                  'auth',
                  'processId',
                  'diagnostic',
                ]
              : const <String>[
                  'running',
                  'healthy',
                  'auth',
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
      final output = data['output'];
      if (output is Map<Object?, Object?>) {
        return projection.value(<String, Object?>{
          ..._compactTargetInspection(
            output,
            standard: detail == CockpitCliOutputDetail.standard,
          ),
          if (data['outcome'] != null && data['outcome'] != 'succeeded')
            'outcome': data['outcome'],
          if (data['failure'] is Map<Object?, Object?>)
            'failure': _compactFailure(
              data['failure']! as Map<Object?, Object?>,
            ),
        }, path);
      }
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
        command == 'run.events' &&
        data['items'] is List<Object?>) {
      return projection.value(
        _compactRunEvents(
          data,
          standard: detail == CockpitCliOutputDetail.standard,
        ),
        path,
      );
    }
    if (data is Map<Object?, Object?> && command == 'run.events') {
      return projection.value(
        _compactRunStreamItem(
          data,
          standard: detail == CockpitCliOutputDetail.standard,
        ),
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

Map<String, Object?> _compactExplain(
  Map<Object?, Object?> value, {
  required bool standard,
}) {
  final operation = value['operation'];
  return <String, Object?>{
    if (operation is Map<Object?, Object?>)
      'operation': _pick(operation, const <String>[
        'kind',
        'scope',
        'mutationClass',
        'idempotency',
        'executionMode',
        'defaultTimeoutMs',
        'maximumTimeoutMs',
        'safetyEffects',
      ]),
    ..._pick(value, const <String>['resolvedScope', 'workspaceId', 'session']),
    if (value['inputContract'] is Map<Object?, Object?>)
      'inputContract': _compactExplainContract(
        value['inputContract']! as Map<Object?, Object?>,
        standard: standard,
      ),
    if (value['outputContract'] is Map<Object?, Object?>)
      'outputContract': _compactExplainContract(
        value['outputContract']! as Map<Object?, Object?>,
        standard: standard,
        includeFields: standard,
      ),
    ..._pick(value, const <String>[
      'recommendedCommand',
      'op',
      'opUnavailable',
    ]),
  };
}

Map<String, Object?> _compactExplainContract(
  Map<Object?, Object?> value, {
  required bool standard,
  bool includeFields = true,
}) {
  final schema = value['schema'];
  final schemaMap = schema is Map<Object?, Object?> ? schema : null;
  final properties = schemaMap?['properties'];
  return <String, Object?>{
    ..._pick(value, const <String>['available', 'schemaRef', 'precision']),
    if (schemaMap != null)
      'schema': <String, Object?>{
        ..._pick(schemaMap, const <String>[
          'type',
          'required',
          'additionalProperties',
        ]),
        if (includeFields && properties is Map<Object?, Object?>)
          'fields': <String, Object?>{
            for (final entry in properties.entries)
              if (entry.key is String && entry.value is Map<Object?, Object?>)
                entry.key! as String: _compactExplainField(
                  entry.value! as Map<Object?, Object?>,
                  standard: standard,
                ),
          },
      },
  };
}

Map<String, Object?> _compactExplainField(
  Map<Object?, Object?> value, {
  required bool standard,
}) {
  final enumValues = value['enum'];
  return <String, Object?>{
    ..._pick(value, const <String>[
      'type',
      'format',
      'default',
      'const',
      'pattern',
      'minimum',
      'maximum',
      'x-cockpit-injected-by',
    ]),
    if (enumValues is List<Object?>)
      'values': enumValues.map((item) => '$item').join('|'),
    if (standard) ..._pick(value, const <String>['description']),
  };
}

Map<String, Object?> _compactDevEnvelope(
  Map<Object?, Object?> value, {
  required bool standard,
}) {
  final action = value['action'];
  final state = value['state'];
  final compactState = state is Map<Object?, Object?>
      ? _compactDevState('$action', state, standard: standard)
      : state;
  final changed = value['changed'];
  final evidence = value['evidence'];
  final stateOwnsEvidence =
      action == 'network' &&
      compactState is Map<Object?, Object?> &&
      compactState['body'] is Map<Object?, Object?>;
  return <String, Object?>{
    ..._pick(value, const <String>['ok', 'session']),
    if (compactState != null &&
        (compactState is! Map<Object?, Object?> || compactState.isNotEmpty))
      'state': compactState,
    if (changed != null && changed != 'none') 'changed': changed,
    if (!stateOwnsEvidence && evidence is Map<Object?, Object?>)
      'evidence': _compactDevEvidence(evidence, standard: standard),
    if (value['errors'] is List<Object?>)
      'errors': _compactDevErrors(value['errors']! as List<Object?>),
    ..._pick(value, const <String>['next']),
  };
}

Object? _compactDevState(
  String action,
  Map<Object?, Object?> state, {
  required bool standard,
}) {
  return switch (action) {
    'status' || 'diagnose' => _compactDevStatus(state, standard: standard),
    'inspect' => _compactDevInspect(state, standard: standard),
    'tap' ||
    'type' ||
    'press' ||
    'scroll' => _compactDevCommand(state, standard: standard),
    'wait' => <String, Object?>{
      ..._pick(state, const <String>['idle']),
      if (state['includeNetworkIdle'] == true) 'network': true,
      if (standard) ..._pick(state, const <String>['durationMs']),
    },
    'viewport' => <String, Object?>{
      ..._pick(state, const <String>['available', 'reason', 'alternatives']),
      if (standard)
        ..._pick(state, const <String>[
          'width',
          'height',
          'logicalWidth',
          'logicalHeight',
        ]),
    },
    'reload' || 'restart' || 'stop' => _compactDevLifecycle(state),
    'screenshot' => _compactDevScreenshot(state, standard: standard),
    'network' => _compactDevNetwork(state, standard: standard),
    _ =>
      standard
          ? Map<String, Object?>.from(state)
          : _pick(state, const [
              'lifecycle',
              'ready',
              'selected',
              'reused',
              'platform',
            ]),
  };
}

Map<String, Object?> _compactDevStatus(
  Map<Object?, Object?> state, {
  required bool standard,
}) {
  final ui = state['ui'];
  final target = state['target'];
  final network = state['network'];
  final errors = state['runtimeErrors'] ?? state['errors'];
  final result = <String, Object?>{
    ..._pick(state, const <String>[
      'lifecycle',
      'projectPath',
      'entrypoint',
      'platform',
      'deviceId',
      'flavor',
    ]),
    if (standard) ..._pick(state, const <String>['checkoutPath']),
    if (ui is Map<Object?, Object?>) ..._pick(ui, const <String>['routeName']),
    if (target is Map<Object?, Object?>)
      ..._pick(target, const <String>['platform', 'targetKind']),
    if (errors != null) 'errorCount': _devErrorCount(errors),
    if (network != null)
      'networkFailureCount': _devNetworkFailureCount(network),
  };
  if (standard) {
    result['ui'] = ui is Map<Object?, Object?>
        ? _compactUiOutput(ui, standard: false)
        : ui;
    result['target'] = target is Map<Object?, Object?>
        ? _compactTargetInspection(target, standard: false)
        : target;
    result['errors'] = errors is Map<Object?, Object?>
        ? _compactErrorsOutput(errors, standard: true)
        : errors;
    result['network'] = network is Map<Object?, Object?>
        ? _compactNetworkOutput(network, standard: false)
        : network;
    final logs = state['logs'];
    if (logs is Map<Object?, Object?>) {
      result['logs'] = _compactLogsOutput(logs, standard: true);
    }
  }
  return result;
}

Map<String, Object?> _compactDevInspect(
  Map<Object?, Object?> state, {
  required bool standard,
}) {
  final summary = state['uiSummary'];
  if (summary is! Map<Object?, Object?>) {
    return standard
        ? Map<String, Object?>.from(state)
        : _pick(state, const <String>[
            'routeName',
            'diagnosticLevel',
            'truncated',
            'matches',
            'items',
          ]);
  }
  return <String, Object?>{
    ..._pick(state, const <String>['routeName', 'truncated']),
    ..._pick(summary, const <String>[
      'visibleTargetCount',
      'runtimeErrorCount',
      'networkFailureCount',
    ]),
    if (summary['textPreviews'] is List<Object?>)
      'textPreviews': (summary['textPreviews']! as List<Object?>)
          .take(4)
          .toList(growable: false),
    if (standard)
      ..._pick(state, const <String>[
        'diagnosticLevel',
        'diagnostics',
        'snapshotRef',
      ]),
  };
}

Map<String, Object?> _compactDevCommand(
  Map<Object?, Object?> state, {
  required bool standard,
}) {
  final operation = state['command'];
  final nested = operation is Map<Object?, Object?>
      ? operation['command']
      : null;
  final result = nested is Map<Object?, Object?> ? nested : operation;
  if (result is! Map<Object?, Object?>) {
    return standard ? Map<String, Object?>.from(state) : const {};
  }
  final locator = result['locatorResolution'] ?? result['locator'];
  return <String, Object?>{
    if (result['error'] != null) 'error': result['error'],
    if (standard) ...<String, Object?>{
      ..._pick(result, const <String>[
        'commandType',
        'commandId',
        'durationMs',
        'captureProfile',
        'captureKind',
        'usedFallback',
      ]),
      'locator': ?locator,
    },
  };
}

Map<String, Object?> _compactDevLifecycle(Map<Object?, Object?> state) {
  final lifecycle = state['lifecycle'];
  final source = lifecycle is Map<Object?, Object?> ? lifecycle : state;
  final status = source['status'];
  final statusMap = status is Map<Object?, Object?> ? status : null;
  return <String, Object?>{
    if (statusMap != null)
      ..._pick(statusMap, const <String>[
        'state',
        'reloadGeneration',
        'lastReloadMode',
        'lastReloadSucceeded',
      ])
    else
      ..._pick(source, const <String>['state', 'lifecycle']),
  };
}

Map<String, Object?> _compactDevScreenshot(
  Map<Object?, Object?> state, {
  required bool standard,
}) => <String, Object?>{
  if (state['comparison'] is Map<Object?, Object?>)
    'comparison': _pick(
      state['comparison']! as Map<Object?, Object?>,
      const <String>['matched', 'dimensionMismatch', 'changedPixelCount'],
    ),
  if (standard)
    ..._pick(state, const <String>[
      'capture',
      'fallback',
      'degraded',
      'plane',
      'width',
      'height',
    ])
  else if (state['fallback'] == true)
    ..._pick(state, const <String>['capture', 'fallback', 'degraded']),
};

Map<String, Object?> _compactDevEvidence(
  Map<Object?, Object?> evidence, {
  required bool standard,
}) {
  final networkPaths = <String, Object?>{
    for (final key in const <String>['request', 'response'])
      if (evidence[key] is String) key: evidence[key],
  };
  if (networkPaths.isNotEmpty) return networkPaths;
  final actual = evidence['actual'];
  final baseline = evidence['baseline'];
  final diff = evidence['diff'];
  return <String, Object?>{
    if (actual is Map<Object?, Object?>) 'path': actual['path'],
    if (standard && baseline is Map<Object?, Object?>)
      'baseline': baseline['path'],
    if (standard && diff is Map<Object?, Object?>) 'diff': diff['path'],
  };
}

Map<String, Object?> _compactDevNetwork(
  Map<Object?, Object?> state, {
  required bool standard,
}) => <String, Object?>{
  ..._compactNetworkOutput(state, standard: standard),
  if (state['body'] is Map<Object?, Object?>)
    'body': Map<String, Object?>.from(state['body']! as Map<Object?, Object?>),
  if (state['absent'] is List<Object?>) 'absent': state['absent'],
  if (state['continuing'] == true) 'continuing': true,
};

List<Object?> _compactDevErrors(List<Object?> errors) => <Object?>[
  for (final error in errors.take(2))
    if (error is Map<Object?, Object?>)
      _pick(error, const <String>['code', 'message', 'primary'])
    else
      error,
];

int _devErrorCount(Object? value) {
  if (value is! Map<Object?, Object?>) return 0;
  final summary = value['summary'];
  if (summary is Map<Object?, Object?>) {
    final count = summary['errorCount'] ?? summary['totalCount'];
    if (count is int) return count;
  }
  final count = value['errorCount'];
  if (count is int) return count;
  final errors = value['errors'];
  return errors is List<Object?> ? errors.length : 0;
}

int _devNetworkFailureCount(Object? value) {
  if (value is! Map<Object?, Object?>) return 0;
  final summary = value['summary'];
  if (summary is Map<Object?, Object?> && summary['failureCount'] is int) {
    return summary['failureCount']! as int;
  }
  final count = value['failureCount'];
  return count is int ? count : 0;
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
      'sessionHandle',
      'idempotencyKey',
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
}) {
  final entries = output['entries'];
  final failures = output['recentFailures'];
  final endpoints = output['endpointSummaries'];
  final summary = output['summary'];
  return <String, Object?>{
    ..._pick(output, const <String>['available', 'routeName']),
    if (summary is Map<Object?, Object?>)
      'summary': <String, Object?>{
        'total': summary['totalEntryCount'],
        'captured': summary['capturedEntryCount'],
        'failed': summary['failureCount'],
        'active': summary['inFlightCount'],
        if (summary['truncated'] == true) 'truncated': true,
        if (standard && summary['query'] != null) 'query': summary['query'],
      },
    if (endpoints is List<Object?> && endpoints.isNotEmpty)
      'endpoints': <Object?>[
        for (final endpoint in endpoints)
          if (endpoint is Map<Object?, Object?>)
            <String, Object?>{
              'method': endpoint['method'],
              'uri': endpoint['uriPattern'],
              'count': endpoint['requestCount'],
              if ((endpoint['failureCount'] as num? ?? 0) > 0)
                'failed': endpoint['failureCount'],
              'avgMs': endpoint['averageDurationMs'],
              if (standard) 'status': endpoint['lastStatusCode'],
            },
      ],
    if (entries is List<Object?> && entries.isNotEmpty)
      'entries': <Object?>[
        for (final entry in entries)
          if (entry is Map<Object?, Object?>)
            _compactNetworkEntry(entry, standard: standard),
      ]
    else if (failures is List<Object?> && failures.isNotEmpty)
      'failures': <Object?>[
        for (final entry in failures)
          if (entry is Map<Object?, Object?>)
            _compactNetworkEntry(entry, standard: standard),
      ],
    if (standard)
      ..._pick(output, const <String>['source', 'endpointSummariesTruncated']),
  };
}

Map<String, Object?> _compactNetworkEntry(
  Map<Object?, Object?> entry, {
  required bool standard,
}) {
  final webSocket = entry['webSocket'];
  return <String, Object?>{
    'id': entry['requestId'],
    'method': entry['method'],
    'uri': entry['uri'],
    if (entry['protocol'] != null && entry['protocol'] != 'http')
      'protocol': entry['protocol'],
    if (entry['statusCode'] != null) 'status': entry['statusCode'],
    'state': entry['state'],
    if (entry['durationMs'] != null) 'ms': entry['durationMs'],
    if (entry['error'] != null) 'error': entry['error'],
    if (webSocket is Map<Object?, Object?>)
      'socket': standard
          ? Map<String, Object?>.from(webSocket)
          : _pick(webSocket, const <String>[
              'sentFrameCount',
              'receivedFrameCount',
              'sentBytes',
              'receivedBytes',
              'lastDirection',
              'lastType',
              'lastTextPreview',
            ]),
    if (standard)
      ..._pick(entry, const <String>[
        'startedAt',
        'updatedAt',
        'requestBodyTruncated',
        'responseBodyTruncated',
      ]),
  };
}

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
}) {
  final command = output['command'];
  final commandMap = command is Map<Object?, Object?> ? command : null;
  final successful = commandMap?['success'] != false;
  final usedFallback = commandMap?['usedCaptureFallback'] == true;
  final changed = output['changed'];
  return <String, Object?>{
    if (commandMap != null)
      'command': _pick(
        commandMap,
        standard
            ? const <String>[
                'commandId',
                'commandType',
                'success',
                'durationMs',
                'locatorResolution',
                'usedCaptureFallback',
                'degradationReason',
                'changed',
                'error',
              ]
            : <String>[
                'commandType',
                if (!successful) 'success',
                'durationMs',
                if (usedFallback) 'usedCaptureFallback',
                'degradationReason',
                'error',
              ],
      ),
    ..._pick(output, const <String>['selectedPlane']),
    if (standard || usedFallback || !successful)
      ..._pick(output, const <String>['fallbackTrail']),
    if (changed is bool) 'changed': changed,
    ..._pick(output, const <String>['whatMatters']),
    if (standard || !successful) ..._pick(output, const <String>['uiSummary']),
    if (_nonEmpty(output['delta'])) 'delta': output['delta'],
    ..._pick(output, const <String>['snapshotRef', 'recommendedNextStep']),
    if (_nonEmpty(output['artifacts'])) 'artifacts': output['artifacts'],
    if (standard)
      ..._pick(output, const <String>[
        'diagnostics',
        'runtimeSteps',
        'snapshot',
      ]),
  };
}

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
      'success',
      'ready',
      'processId',
      'platform',
      'routeName',
      'reloadGeneration',
      'message',
    ]),
  };
  final status = output['status'];
  if (status is Map<Object?, Object?>) {
    final compactStatus = _pick(
      status,
      standard
          ? const <String>[
              'state',
              'developmentSessionId',
              'appReachable',
              'remoteSessionReachable',
              'reloadGeneration',
              'lastReloadSucceeded',
              'lastStatusAt',
              'error',
            ]
          : const <String>[
              'state',
              'developmentSessionId',
              'appReachable',
              'remoteSessionReachable',
              'reloadGeneration',
              'lastReloadSucceeded',
              'error',
            ],
    );
    _removeRepeatedDevelopmentIdentity(compactStatus, result);
    if (compactStatus.isNotEmpty) result['status'] = compactStatus;
  }
  for (final key in const <String>['app', 'target', 'sessionHandle']) {
    final child = output[key];
    if (child is! Map<Object?, Object?>) continue;
    final compactChild = _pick(
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
    _removeRepeatedDevelopmentIdentity(compactChild, result);
    if (compactChild.isNotEmpty) result[key] = compactChild;
  }
  if (output['capabilities'] is Map<Object?, Object?>) {
    result['capabilities'] = _compactCapabilities(
      output['capabilities']! as Map<Object?, Object?>,
      standard: standard,
    );
  }
  return result;
}

void _removeRepeatedDevelopmentIdentity(
  Map<String, Object?> child,
  Map<String, Object?> parent,
) {
  for (final key in const <String>[
    'appId',
    'sessionId',
    'targetId',
    'processId',
    'reloadGeneration',
  ]) {
    if (child[key] != null && child[key] == parent[key]) child.remove(key);
  }
  if (child['developmentSessionId'] != null &&
      child['developmentSessionId'] == parent['sessionId']) {
    child.remove('developmentSessionId');
  }
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
    ..._pick(value, <String>[
      if (standard) 'targetId',
      'platform',
      'targetKind',
      'foregroundSurface',
      'selectedPlane',
      'currentRouteName',
    ]),
    if (standard && value['fallbackTrail'] != null)
      'fallbackTrail': value['fallbackTrail'],
    if (capability is Map<Object?, Object?>)
      'capabilities': _compactCapabilities(capability, standard: standard),
    if (standard && value['uiSummary'] != null) 'uiSummary': value['uiSummary'],
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
      if (standard) ...<String>['modifiedAt', 'cases'],
    ],
    'session.list' => <String>[
      'handleId',
      'projectPath',
      'entrypoint',
      'platform',
      'deviceId',
      'flavor',
      'lastState',
      if (standard) ...<String>[
        'sessionId',
        'workspaceId',
        'targetId',
        'appId',
        'checkoutPath',
        'updatedAt',
      ],
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
      'entrypoint',
      if (standard) ...<String>['flavor', 'wdaUrl'],
    ],
    'artifact.list' => <String>[
      'artifactId',
      'attemptId',
      'stepExecutionId',
      'kind',
      'relativePath',
      'mediaType',
      if (standard) ...<String>['createdAt', 'role'],
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

Map<String, Object?> _compactRunEvents(
  Map<Object?, Object?> value, {
  required bool standard,
}) {
  final rawItems = value['items']! as List<Object?>;
  final events = <Map<String, Object?>>[];
  final controls = <Map<String, Object?>>[];
  for (final item in rawItems) {
    if (item is! Map<Object?, Object?>) continue;
    if (item['type'] == 'event' && item['event'] is Map<Object?, Object?>) {
      events.add(
        _compactRunEvent(
          item['event']! as Map<Object?, Object?>,
          standard: standard,
        ),
      );
      continue;
    }
    controls.add(
      _pick(item, const <String>['type', 'afterSequence', 'boundary']),
    );
  }
  final failures = events
      .where((event) => event['failure'] != null)
      .toList(growable: false);
  final finalEvents = events
      .where(
        (event) =>
            event['kind'] == 'run.completed' ||
            event['kind'] == 'run.cancelled' ||
            event['kind'] == 'run.interrupted',
      )
      .toList(growable: false);
  final control = controls.isEmpty ? null : controls.last;
  return <String, Object?>{
    'eventCount': events.length,
    if (control != null) 'stream': control['type'],
    if (control?['afterSequence'] != null)
      'afterSequence': control!['afterSequence'],
    if (control?['boundary'] != null) 'boundary': control!['boundary'],
    if (failures.isNotEmpty) 'failures': failures,
    if (finalEvents.isNotEmpty) 'final': finalEvents.last,
    if (finalEvents.isEmpty && events.isNotEmpty) 'latest': events.last,
    if (standard) 'items': <Object?>[...events, ...controls],
  };
}

Map<String, Object?> _compactRunStreamItem(
  Map<Object?, Object?> item, {
  required bool standard,
}) {
  if (item['type'] == 'event' && item['event'] is Map<Object?, Object?>) {
    return <String, Object?>{
      'type': 'event',
      'event': _compactRunEvent(
        item['event']! as Map<Object?, Object?>,
        standard: standard,
      ),
    };
  }
  return _pick(item, const <String>['type', 'afterSequence', 'boundary']);
}

Map<String, Object?> _compactRunEvent(
  Map<Object?, Object?> event, {
  required bool standard,
}) {
  final artifacts = event['artifacts'];
  return <String, Object?>{
    ..._pick(event, <String>[
      'sequence',
      'kind',
      'entityKind',
      'caseId',
      'attemptId',
      'stepExecutionId',
      'status',
      'lifecycle',
      'outcome',
      'stability',
      'requestedPlane',
      'actualPlane',
      if (standard) ...<String>['timestamp', 'targetId', 'durationMs'],
    ]),
    if (event['failure'] is Map<Object?, Object?>)
      'failure': _compactFailure(event['failure']! as Map<Object?, Object?>),
    if (artifacts is List<Object?> && artifacts.isNotEmpty)
      'artifactCount': artifacts.length,
  };
}

Map<String, Object?> _compactSession(
  Map<Object?, Object?> value, {
  required bool standard,
}) {
  final live = value['live'];
  final liveMap = live is Map<Object?, Object?> ? live : null;
  final status = liveMap?['status'];
  final statusMap = status is Map<Object?, Object?> ? status : null;
  final runtime = liveMap?['runtime'];
  final runtimeMap = runtime is Map<Object?, Object?> ? runtime : null;
  return <String, Object?>{
    ..._pick(value, const <String>[
      'handleId',
      'projectPath',
      'entrypoint',
      'platform',
      'deviceId',
      'flavor',
      'lifecycle',
      'reachable',
    ]),
    if (statusMap != null)
      'status': _pick(statusMap, const <String>[
        'state',
        'appReachable',
        'remoteSessionReachable',
        'reloadGeneration',
        'lastReloadSucceeded',
        'lastError',
      ]),
    if (standard) ...<String, Object?>{
      ..._pick(value, const <String>[
        'sessionId',
        'workspaceId',
        'targetId',
        'appId',
        'checkoutPath',
        'updatedAt',
      ]),
      'runtime': ?runtimeMap,
      if (value['errors'] != null) 'errors': value['errors'],
    },
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
    if (value['valid'] != null) 'valid': value['valid'],
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

Object? _conciseCliValue(Object? value, {bool schema = false}) {
  if (schema) return value;
  if (value is List<Object?>) {
    return value.map(_conciseCliValue).toList(growable: false);
  }
  if (value is! Map<Object?, Object?>) return value;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) continue;
    final original = entry.key! as String;
    final key = original.startsWith(r'$')
        ? _conciseCliPath(original)
        : _conciseCliFieldNames[original] ?? original;
    result[key] = _conciseCliValue(entry.value, schema: original == 'schema');
  }
  return result;
}

String _conciseCliPath(String path) {
  var result = path;
  for (final entry in _conciseCliFieldNames.entries) {
    result = result.replaceAll('.${entry.key}', '.${entry.value}');
  }
  return result;
}

const Map<String, String> _conciseCliFieldNames = <String, String>{
  'authorizationMode': 'auth',
  'apiVersion': 'api',
  'engineVersion': 'engine',
  'startedAt': 'started',
  'processId': 'pid',
  'routeName': 'route',
  'currentRouteName': 'route',
  'targetKind': 'target',
  'errorCount': 'errors',
  'runtimeErrorCount': 'errors',
  'networkFailureCount': 'netFailures',
  'visibleTargetCount': 'visible',
  'textPreviews': 'text',
  'reloadGeneration': 'generation',
  'lastReloadMode': 'mode',
  'lastReloadSucceeded': 'reloadOk',
  'includeNetworkIdle': 'network',
  'durationMs': 'ms',
  'commandType': 'type',
  'detail': 'verbosity',
  'maximumBytes': 'maxBytes',
  'responsibleLayer': 'layer',
  'selectedPlane': 'plane',
  'fallbackTrail': 'fallback',
  'recommendedNextStep': 'next',
  'whatMatters': 'note',
  'defaultTimeoutMs': 'timeoutMs',
  'maximumTimeoutMs': 'maxTimeoutMs',
  'requestSchemaRef': 'inputSchema',
  'responseSchemaRef': 'outputSchema',
  'requiredFeatures': 'requires',
  'resolvedScope': 'scope',
  'inputContract': 'input',
  'outputContract': 'output',
  'schemaRef': 'ref',
  'recommendedCommand': 'devCommand',
  'sessionHandle': 'session',
  'handleId': 'session',
  'projectPath': 'path',
  'checkoutPath': 'checkoutPath',
  'entrypoint': 'entry',
  'deviceId': 'device',
  'developmentSessionId': 'runtimeId',
  'runtimeErrors': 'errors',
  'requestedCaptureProfile': 'captureProfile',
  'resolvedCaptureKind': 'captureKind',
  'usedCaptureFallback': 'usedFallback',
  'degradationReason': 'degraded',
  'locatorResolution': 'locator',
  'launchTimeoutMilliseconds': 'launchTimeoutMs',
  'checkoutIdentity': 'checkout',
  'omittedLineCount': 'omittedLines',
  'operationCount': 'count',
  'availableActionCount': 'availableCount',
  'blockedActionCount': 'blockedCount',
  'actionableCount': 'actionable',
  'dimensionMismatch': 'sizeMismatch',
  'changedPixelCount': 'changedPixels',
  'totalPixelCount': 'pixels',
  'pixelTolerance': 'tolerance',
  'maximumChangedPixels': 'maxChangedPixels',
  'mediaType': 'type',
  'sizeBytes': 'bytes',
};

int _priority(String key) {
  const ordered = <String>[
    'schemaVersion',
    'operationId',
    'sessionHandle',
    'idempotencyKey',
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
