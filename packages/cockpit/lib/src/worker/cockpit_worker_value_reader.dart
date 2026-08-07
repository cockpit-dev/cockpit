import 'dart:convert';

const String cockpitWorkerProtocolVersion = 'cockpit.worker/v2';
const int cockpitWorkerMaximumPayloadBytes = 1048576;
const int cockpitWorkerMaximumJsonDepth = 64;
const int cockpitWorkerMaximumJsonNodes = 1048576;

final RegExp _workerIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
final RegExp _workerKindPattern = RegExp(
  r'^[a-z][a-z0-9]*(?:\.[a-z][a-zA-Z0-9]*)+$',
);
final RegExp _workerMethodPattern = RegExp(r'^[a-z][a-zA-Z0-9]{0,63}$');
const Set<String> cockpitWorkerMethods = <String>{
  'initialize',
  'capabilities',
  'operation',
  'cancel',
  'drain',
  'health',
  'shutdown',
  'replayEvents',
  'publishEventBatch',
  'publishArtifactBatch',
  'readSessionArtifact',
};

Map<String, Object?> workerObject(Object? value, String path) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('Expected object at $path.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('Expected string object key at $path.');
    }
    result[entry.key! as String] = entry.value;
  }
  workerValidateJsonValue(result, path);
  return result;
}

void workerKeys(
  Map<String, Object?> value,
  Set<String> allowed,
  String path, {
  Set<String> required = const <String>{},
}) {
  for (final key in value.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('Unknown field $path.$key.');
    }
  }
  for (final key in required) {
    if (!value.containsKey(key)) {
      throw FormatException('Missing required field $path.$key.');
    }
  }
}

String workerString(
  Object? value,
  String path, {
  int minimum = 1,
  int maximum = 4096,
}) {
  if (value is! String || value.length < minimum || value.length > maximum) {
    throw FormatException('Invalid string at $path.');
  }
  return value;
}

String workerId(Object? value, String path) {
  final result = workerString(value, path, maximum: 128);
  if (!_workerIdPattern.hasMatch(result)) {
    throw FormatException('Invalid identifier at $path.');
  }
  return result;
}

String workerKind(Object? value, String path) {
  final result = workerString(value, path, maximum: 128);
  if (!_workerKindPattern.hasMatch(result)) {
    throw FormatException('Invalid kind at $path.');
  }
  return result;
}

String workerMethod(Object? value, String path) {
  final result = workerMethodName(value, path);
  if (!cockpitWorkerMethods.contains(result)) {
    throw FormatException('Unsupported worker method at $path.');
  }
  return result;
}

String workerMethodName(Object? value, String path) {
  final result = workerString(value, path, maximum: 64);
  if (!_workerMethodPattern.hasMatch(result)) {
    throw FormatException('Invalid worker method at $path.');
  }
  return result;
}

int workerInteger(
  Object? value,
  String path, {
  int minimum = 0,
  int maximum = 2147483647,
}) {
  if (value is! int || value < minimum || value > maximum) {
    throw FormatException('Invalid integer at $path.');
  }
  return value;
}

bool workerBoolean(Object? value, String path) {
  if (value is! bool) throw FormatException('Invalid boolean at $path.');
  return value;
}

DateTime workerUtcDateTime(Object? value, String path) {
  final text = workerString(value, path, maximum: 64);
  final parsed = DateTime.tryParse(text);
  if (parsed == null || !text.endsWith('Z') || !parsed.isUtc) {
    throw FormatException('Invalid UTC timestamp at $path.');
  }
  return parsed;
}

DateTime workerUtcDateTimeValue(DateTime value, String path) {
  if (!value.isUtc) {
    throw FormatException('Invalid UTC timestamp at $path.');
  }
  return value;
}

List<Object?> workerList(Object? value, String path, {int maximum = 10000}) {
  if (value is! List<Object?> || value.length > maximum) {
    throw FormatException('Invalid list at $path.');
  }
  workerValidateJsonValue(value, path);
  return value;
}

Map<String, Object?> workerJsonObject(Object? value, String path) =>
    workerObject(value, path);

void workerValidateJsonValue(Object? value, String path) {
  var nodes = 0;
  void visit(Object? current, int depth) {
    nodes += 1;
    if (nodes > cockpitWorkerMaximumJsonNodes ||
        depth > cockpitWorkerMaximumJsonDepth) {
      throw FormatException('JSON value exceeds protocol bounds at $path.');
    }
    switch (current) {
      case null || bool() || String():
        return;
      case int():
        return;
      case double():
        if (!current.isFinite) {
          throw FormatException('JSON number is not finite at $path.');
        }
      case List<Object?>():
        for (final item in current) {
          visit(item, depth + 1);
        }
      case Map<Object?, Object?>():
        for (final entry in current.entries) {
          if (entry.key is! String) {
            throw FormatException('JSON object key is invalid at $path.');
          }
          visit(entry.value, depth + 1);
        }
      default:
        throw FormatException('Value is not JSON-compatible at $path.');
    }
  }

  visit(value, 0);
}

int workerEncodedSize(Object? value) => utf8.encode(jsonEncode(value)).length;
