import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final class CockpitBoundedLogLine {
  const CockpitBoundedLogLine(this.text, {required this.truncated});

  final String text;
  final bool truncated;
}

final class CockpitBoundedUtf8LineFramer
    extends StreamTransformerBase<List<int>, CockpitBoundedLogLine> {
  const CockpitBoundedUtf8LineFramer({this.maximumBytes = 8192});

  final int maximumBytes;

  @override
  Stream<CockpitBoundedLogLine> bind(Stream<List<int>> stream) {
    if (maximumBytes < 256 || maximumBytes > 1048576) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    }
    late StreamController<CockpitBoundedLogLine> controller;
    StreamSubscription<List<int>>? subscription;
    var bytes = BytesBuilder(copy: false);
    var length = 0;
    var truncated = false;

    void emit() {
      final lineBytes = bytes.takeBytes();
      bytes = BytesBuilder(copy: false);
      length = 0;
      var text = utf8.decode(lineBytes, allowMalformed: true);
      if (text.endsWith('\r')) text = text.substring(0, text.length - 1);
      controller.add(CockpitBoundedLogLine(text, truncated: truncated));
      truncated = false;
    }

    controller = StreamController<CockpitBoundedLogLine>(
      sync: true,
      onListen: () {
        subscription = stream.listen(
          (chunk) {
            for (final byte in chunk) {
              if (byte == 0x0A) {
                emit();
              } else if (length < maximumBytes) {
                bytes.addByte(byte);
                length += 1;
              } else {
                truncated = true;
              }
            }
          },
          onError: controller.addError,
          onDone: () {
            if (length > 0 || truncated) emit();
            unawaited(controller.close());
          },
          cancelOnError: false,
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}

final class CockpitWorkerLogRedactor {
  CockpitWorkerLogRedactor({
    Iterable<String> sensitiveValues = const <String>[],
  }) : _sensitiveValues = <String>{
         for (final value in sensitiveValues)
           if (value.isNotEmpty) value,
       };

  static const String redacted = '[REDACTED]';
  static final RegExp _sensitiveKey = RegExp(
    r'(?:authorization|bearer|cookie|password|secret|token|api[_-]?key|private[_-]?key)',
    caseSensitive: false,
  );
  static final RegExp _inlineCredential = RegExp(
    r'(bearer\s+|(?:password|secret|token|api[_-]?key)\s*[=:]\s*)([^\s,;]+)',
    caseSensitive: false,
  );

  final Set<String> _sensitiveValues;

  void registerSensitiveValue(String value) {
    if (value.isNotEmpty) _sensitiveValues.add(value);
  }

  String redactText(String value) => _redactString(value);

  bool containsSensitiveValue(String value) =>
      _sensitiveValues.any(value.contains);

  CockpitSensitiveByteScanner sensitiveByteScanner() =>
      CockpitSensitiveByteScanner(_sensitiveValues);

  Object? redact(Object? value, {String? key}) {
    if (key != null &&
        _sensitiveKey.hasMatch(key) &&
        !_isSecretReferenceDeclaration(value)) {
      return redacted;
    }
    return switch (value) {
      String() => _redactString(value),
      Map<Object?, Object?>() => <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': redact(entry.value, key: '${entry.key}'),
      },
      Iterable<Object?>() => value.map(redact).toList(growable: false),
      _ => value,
    };
  }

  String _redactString(String value) {
    var result = value.replaceAllMapped(
      _inlineCredential,
      (match) => '${match.group(1)}$redacted',
    );
    final sensitive = _sensitiveValues.toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    for (final item in sensitive) {
      result = result.replaceAll(item, redacted);
    }
    return result;
  }
}

bool _isSecretReferenceDeclaration(Object? value) =>
    value is Map &&
    value['source'] == 'secret' &&
    value['type'] == 'string' &&
    value['reference'] is String &&
    !value.containsKey('value') &&
    !value.containsKey('default');

final class CockpitSensitiveByteScanner {
  CockpitSensitiveByteScanner(Iterable<String> sensitiveValues) {
    var patternCount = 0;
    var aggregateBytes = 0;
    for (final value in sensitiveValues) {
      if (value.isEmpty) continue;
      final bytes = utf8.encode(value);
      patternCount += 1;
      aggregateBytes += bytes.length;
      if (patternCount > maximumPatterns ||
          aggregateBytes > maximumAggregatePatternBytes) {
        throw const FormatException(
          'Sensitive byte scan pattern bounds were exceeded.',
        );
      }
      var node = 0;
      for (final byte in bytes) {
        final transitions = _nodes[node].transitions;
        final existing = transitions[byte];
        if (existing != null) {
          node = existing;
          continue;
        }
        if (_nodes.length >= maximumAutomatonNodes) {
          throw const FormatException(
            'Sensitive byte scan automaton bounds were exceeded.',
          );
        }
        _nodes.add(_CockpitSensitiveByteNode());
        node = _nodes.length - 1;
        transitions[byte] = node;
      }
      _nodes[node].terminal = true;
    }
    _buildFailureTransitions();
  }

  static const int maximumPatterns = 4096;
  static const int maximumAggregatePatternBytes = 8 * 1024 * 1024;
  static const int maximumAutomatonNodes = 262144;

  final List<_CockpitSensitiveByteNode> _nodes = <_CockpitSensitiveByteNode>[
    _CockpitSensitiveByteNode(),
  ];

  Future<bool> contains(Stream<List<int>> source) async {
    if (_nodes.length == 1) {
      await source.drain<void>();
      return false;
    }
    var state = 0;
    await for (final chunk in source) {
      for (final byte in chunk) {
        while (state != 0 && !_nodes[state].transitions.containsKey(byte)) {
          state = _nodes[state].failure;
        }
        state = _nodes[state].transitions[byte] ?? 0;
        if (_nodes[state].terminal) return true;
      }
    }
    return false;
  }

  void _buildFailureTransitions() {
    final pending = Queue<int>();
    for (final child in _nodes.first.transitions.values) {
      pending.add(child);
    }
    while (pending.isNotEmpty) {
      final current = pending.removeFirst();
      for (final transition in _nodes[current].transitions.entries) {
        final byte = transition.key;
        final child = transition.value;
        var fallback = _nodes[current].failure;
        while (fallback != 0 &&
            !_nodes[fallback].transitions.containsKey(byte)) {
          fallback = _nodes[fallback].failure;
        }
        _nodes[child].failure = _nodes[fallback].transitions[byte] ?? 0;
        _nodes[child].terminal =
            _nodes[child].terminal || _nodes[_nodes[child].failure].terminal;
        pending.add(child);
      }
    }
  }
}

final class _CockpitSensitiveByteNode {
  final Map<int, int> transitions = <int, int>{};
  int failure = 0;
  bool terminal = false;
}

final class CockpitWorkerLogger {
  CockpitWorkerLogger({
    IOSink? stderrSink,
    CockpitWorkerLogRedactor? redactor,
    DateTime Function()? utcNow,
  }) : _stderr = stderrSink ?? stderr,
       redactor = redactor ?? CockpitWorkerLogRedactor(),
       _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  final IOSink _stderr;
  final CockpitWorkerLogRedactor redactor;
  final DateTime Function() _utcNow;

  void log(
    String level,
    String message, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final payload = redactor.redact(<String, Object?>{
      'timestamp': _utcNow().toIso8601String(),
      'level': level,
      'message': message,
      if (fields.isNotEmpty) 'fields': fields,
    });
    _stderr.writeln(jsonEncode(payload));
  }
}
