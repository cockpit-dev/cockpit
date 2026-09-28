import 'cockpit_errors.dart';
import 'cockpit_json.dart';

const int _cockpitExpectValueBound = 1024;

/// Asserts [actual] deeply equals [expected].
///
/// Numbers, strings, booleans, and null compare with `==`. Lists, sets, and
/// maps compare recursively, so decoded JSON payloads behave the way test
/// authors expect. A mismatch throws [CockpitTestAssertionException], which
/// the programmatic runner reports as a failed assertion rather than an
/// internal error.
void cockpitExpectEquals(Object? actual, Object? expected, {String? reason}) {
  if (cockpitDeepEquals(actual, expected)) return;
  _fail(
    'Expected ${_display(expected)} but got ${_display(actual)}.',
    reason: reason,
    details: <String, Object?>{
      'actual': _jsonSafe(actual),
      'expected': _jsonSafe(expected),
    },
  );
}

/// Asserts [condition] is true.
void cockpitExpectTrue(bool condition, {String? reason}) {
  if (condition) return;
  _fail('Expected the condition to hold.', reason: reason);
}

/// Asserts [value] is not null.
void cockpitExpectNotNull(Object? value, {String? reason}) {
  if (value != null) return;
  _fail('Expected a non-null value.', reason: reason);
}

/// Asserts [container] contains [value].
///
/// [container] may be a [String] (substring), an [Iterable] (membership), or
/// a [Map] (key membership). Anything else fails the assertion.
void cockpitExpectContains(Object container, Object? value, {String? reason}) {
  final holds = switch (container) {
    String() => value is String && container.contains(value),
    Iterable<Object?>() => container.contains(value),
    Map<Object?, Object?>() => container.containsKey(value),
    _ => false,
  };
  if (holds) return;
  _fail(
    'Expected ${_display(container)} to contain ${_display(value)}.',
    reason: reason,
    details: <String, Object?>{
      'container': _jsonSafe(container),
      'value': _jsonSafe(value),
    },
  );
}

/// Structural equality for JSON-shaped values: primitives use `==`, and
/// lists, sets, and maps compare recursively. Sets match iterables with the
/// same members regardless of order.
bool cockpitDeepEquals(Object? actual, Object? expected) {
  if (identical(actual, expected)) return true;
  if (actual is num && expected is num) {
    // `1 == 1.0` is true in Dart; keep int/double interchangeable like JSON.
    return actual == expected;
  }
  if (actual is Set<Object?> && expected is Set<Object?>) {
    return actual.length == expected.length && actual.every(expected.contains);
  }
  if (actual is Iterable<Object?> && expected is Iterable<Object?>) {
    return _iterablesEqual(actual, expected);
  }
  if (actual is Map<Object?, Object?> && expected is Map<Object?, Object?>) {
    return actual.length == expected.length &&
        actual.entries.every((entry) {
          if (!expected.containsKey(entry.key)) return false;
          return cockpitDeepEquals(entry.value, expected[entry.key]);
        });
  }
  return actual == expected;
}

bool _iterablesEqual(Iterable<Object?> actual, Iterable<Object?> expected) {
  final actualIterator = actual.iterator;
  final expectedIterator = expected.iterator;
  while (true) {
    final actualAdvanced = actualIterator.moveNext();
    final expectedAdvanced = expectedIterator.moveNext();
    if (!actualAdvanced || !expectedAdvanced) {
      return actualAdvanced == expectedAdvanced;
    }
    if (!cockpitDeepEquals(actualIterator.current, expectedIterator.current)) {
      return false;
    }
  }
}

Never _fail(String message, {String? reason, Map<String, Object?>? details}) {
  final suffix = reason == null || reason.isEmpty ? '' : ' $reason';
  throw CockpitTestAssertionException(
    message: '$message$suffix',
    details: details == null
        ? const <String, Object?>{}
        : freezeCockpitJson(details, path: r'$.details'),
  );
}

String _display(Object? value) {
  final text = value == null ? 'null' : '$value';
  return _bounded(text, quote: value is String);
}

Object? _jsonSafe(Object? value) {
  if (value == null || value is num || value is bool) return value;
  if (value is String) return _bounded(value);
  return _bounded('$value');
}

String _bounded(String text, {bool quote = false}) {
  const ellipsis = '...';
  if (text.length <= _cockpitExpectValueBound) {
    return quote ? "'${text.replaceAll("'", r"\'")}'" : text;
  }
  final clipped =
      '${text.substring(0, _cockpitExpectValueBound - ellipsis.length)}$ellipsis';
  return quote ? "'$clipped'" : clipped;
}
