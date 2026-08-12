import 'package:collection/collection.dart';

enum CockpitLocatorKind {
  cockpitId,
  semanticId,
  key,
  text,
  tooltip,
  type,
  route,
  registrationId,
  path,
  nativeId,
  testId,
  role,
  coordinate,
  visual;

  static CockpitLocatorKind fromJson(Object? json) {
    return values.byName(json! as String);
  }
}

typedef CockpitLocatorSignal = ({CockpitLocatorKind kind, String value});

enum CockpitTextMatchMode {
  exact,
  contains,
  fuzzy,
  regex;

  static CockpitTextMatchMode fromJson(Object? json) {
    if (json is String) {
      for (final mode in values) {
        if (mode.name == json) return mode;
      }
    }
    throw const FormatException(
      'Text match mode must be exact, contains, fuzzy, or regex.',
    );
  }
}

const double cockpitFuzzyTextMatchThreshold = 0.72;

bool cockpitFuzzyTextMatches(String actual, String expected) {
  final normalizedExpected = _normalizeFuzzyText(expected);
  if (normalizedExpected.isEmpty) return false;
  if (normalizedExpected.runes.length < 3) {
    return _normalizeFuzzyText(actual) == normalizedExpected;
  }
  return cockpitFuzzyTextSimilarity(actual, expected) >=
      cockpitFuzzyTextMatchThreshold;
}

double cockpitFuzzyTextSimilarity(String actual, String expected) {
  final normalizedActual = _normalizeFuzzyText(actual);
  final normalizedExpected = _normalizeFuzzyText(expected);
  if (normalizedActual == normalizedExpected) return 1;
  if (normalizedActual.isEmpty || normalizedExpected.isEmpty) return 0;

  final actualRunes = normalizedActual.runes.toList(growable: false);
  final expectedRunes = normalizedExpected.runes.toList(growable: false);
  final fullSimilarity = _fuzzyRuneSimilarity(actualRunes, expectedRunes);
  if (expectedRunes.length < 5 || actualRunes.length <= expectedRunes.length) {
    return fullSimilarity;
  }
  final substringDistance = _fuzzySubstringDistance(actualRunes, expectedRunes);
  final substringSimilarity = (1 - (substringDistance / expectedRunes.length))
      .clamp(0, 1)
      .toDouble();
  return substringSimilarity > fullSimilarity
      ? substringSimilarity
      : fullSimilarity;
}

double _fuzzyRuneSimilarity(List<int> actualRunes, List<int> expectedRunes) {
  final shorterLength = actualRunes.length < expectedRunes.length
      ? actualRunes.length
      : expectedRunes.length;
  final longerLength = actualRunes.length > expectedRunes.length
      ? actualRunes.length
      : expectedRunes.length;
  final actual = String.fromCharCodes(actualRunes);
  final expected = String.fromCharCodes(expectedRunes);
  final contains = actual.contains(expected) || expected.contains(actual);
  if (contains) {
    return 0.80 + (0.19 * shorterLength / longerLength);
  }

  final distance = _damerauLevenshteinDistance(actualRunes, expectedRunes);
  return (1 - (distance / longerLength)).clamp(0, 1).toDouble();
}

String _normalizeFuzzyText(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

int _damerauLevenshteinDistance(List<int> left, List<int> right) {
  final rows = List<List<int>>.generate(
    left.length + 1,
    (row) => List<int>.filled(right.length + 1, 0),
    growable: false,
  );
  for (var row = 0; row <= left.length; row += 1) {
    rows[row][0] = row;
  }
  for (var column = 0; column <= right.length; column += 1) {
    rows[0][column] = column;
  }
  for (var row = 1; row <= left.length; row += 1) {
    for (var column = 1; column <= right.length; column += 1) {
      final substitutionCost = left[row - 1] == right[column - 1] ? 0 : 1;
      var distance = <int>[
        rows[row - 1][column] + 1,
        rows[row][column - 1] + 1,
        rows[row - 1][column - 1] + substitutionCost,
      ].reduce((minimum, value) => value < minimum ? value : minimum);
      if (row > 1 &&
          column > 1 &&
          left[row - 1] == right[column - 2] &&
          left[row - 2] == right[column - 1]) {
        final transposed = rows[row - 2][column - 2] + 1;
        if (transposed < distance) distance = transposed;
      }
      rows[row][column] = distance;
    }
  }
  return rows[left.length][right.length];
}

int _fuzzySubstringDistance(List<int> actual, List<int> expected) {
  var previous = List<int>.filled(actual.length + 1, 0);
  var beforePrevious = previous;
  for (
    var expectedIndex = 1;
    expectedIndex <= expected.length;
    expectedIndex += 1
  ) {
    final current = List<int>.filled(actual.length + 1, 0);
    current[0] = expectedIndex;
    for (var actualIndex = 1; actualIndex <= actual.length; actualIndex += 1) {
      final substitutionCost =
          expected[expectedIndex - 1] == actual[actualIndex - 1] ? 0 : 1;
      var distance = <int>[
        previous[actualIndex] + 1,
        current[actualIndex - 1] + 1,
        previous[actualIndex - 1] + substitutionCost,
      ].reduce((minimum, value) => value < minimum ? value : minimum);
      if (expectedIndex > 1 &&
          actualIndex > 1 &&
          expected[expectedIndex - 1] == actual[actualIndex - 2] &&
          expected[expectedIndex - 2] == actual[actualIndex - 1]) {
        final transposed = beforePrevious[actualIndex - 2] + 1;
        if (transposed < distance) distance = transposed;
      }
      current[actualIndex] = distance;
    }
    beforePrevious = previous;
    previous = current;
  }
  return previous.reduce((minimum, value) => value < minimum ? value : minimum);
}

final class CockpitLocator {
  /// Creates a CockpitLocator.
  const CockpitLocator({
    this.cockpitId,
    this.semanticId,
    this.key,
    this.text,
    this.tooltip,
    this.type,
    this.route,
    this.registrationId,
    this.path,
    this.matchMode = CockpitTextMatchMode.exact,
    this.index,
    this.ancestor,
    this.fallbacks = const [],
  });

  final String? cockpitId;
  final String? semanticId;
  final String? key;
  final String? text;
  final String? tooltip;
  final String? type;
  final String? route;
  final String? registrationId;
  final String? path;
  final CockpitTextMatchMode matchMode;
  final int? index;
  final CockpitLocator? ancestor;
  final List<CockpitLocator> fallbacks;

  static const ListEquality<CockpitLocator> _fallbackListEquality =
      ListEquality<CockpitLocator>();

  CockpitLocatorKind get kind {
    final primary = primarySignal;
    if (primary != null) {
      return primary.kind;
    }
    throw StateError('CockpitLocator does not define a primary signal.');
  }

  String get value {
    final primary = primarySignal;
    if (primary != null) {
      return primary.value;
    }
    throw StateError('CockpitLocator does not define a primary signal.');
  }

  CockpitLocatorSignal? get primarySignal {
    for (final signal in signals) {
      return signal;
    }
    return null;
  }

  bool get hasSignals => signals.isNotEmpty || ancestor != null;

  Iterable<CockpitLocatorSignal> get signals sync* {
    final emittedKinds = <CockpitLocatorKind>{};
    Iterable<CockpitLocatorSignal> emit(
      CockpitLocatorKind kind,
      String? candidate,
    ) sync* {
      final normalized = _normalizeSignal(candidate);
      if (normalized == null || !emittedKinds.add(kind)) {
        return;
      }
      yield (kind: kind, value: normalized);
    }

    yield* emit(CockpitLocatorKind.cockpitId, cockpitId);
    yield* emit(CockpitLocatorKind.semanticId, semanticId);
    yield* emit(CockpitLocatorKind.key, key);
    yield* emit(CockpitLocatorKind.text, text);
    yield* emit(CockpitLocatorKind.tooltip, tooltip);
    yield* emit(CockpitLocatorKind.type, type);
    yield* emit(CockpitLocatorKind.route, route);
    yield* emit(CockpitLocatorKind.registrationId, registrationId);
    yield* emit(CockpitLocatorKind.path, path);
  }

  Map<String, String> get signalMap {
    final map = <String, String>{};
    for (final signal in signals) {
      map[signal.kind.name] = signal.value;
    }
    return Map<String, String>.unmodifiable(map);
  }

  /// Encodes this CockpitLocator as a JSON object.
  Map<String, Object?> toJson() {
    final signals = signalMap;
    return <String, Object?>{
      'cockpitId': ?signals[CockpitLocatorKind.cockpitId.name],
      'semanticId': ?signals[CockpitLocatorKind.semanticId.name],
      'key': ?signals[CockpitLocatorKind.key.name],
      'text': ?signals[CockpitLocatorKind.text.name],
      'tooltip': ?signals[CockpitLocatorKind.tooltip.name],
      'type': ?signals[CockpitLocatorKind.type.name],
      'route': ?signals[CockpitLocatorKind.route.name],
      'registrationId': ?signals[CockpitLocatorKind.registrationId.name],
      'path': ?signals[CockpitLocatorKind.path.name],
      if (matchMode != CockpitTextMatchMode.exact) 'matchMode': matchMode.name,
      if (index != null) 'index': index,
      if (ancestor != null) 'ancestor': ancestor!.toJson(),
      'fallbacks': fallbacks.map((fallback) => fallback.toJson()).toList(),
    };
  }

  /// Decodes a CockpitLocator from a JSON object.
  factory CockpitLocator.fromJson(Map<String, Object?> json) {
    if (json.containsKey('kind') || json.containsKey('value')) {
      throw const FormatException(
        'CockpitLocator JSON no longer supports legacy kind/value fields.',
      );
    }
    final fallbacks = (json['fallbacks'] as List<Object?>? ?? const <Object?>[])
        .cast<Map<Object?, Object?>>()
        .map((item) => CockpitLocator.fromJson(Map<String, Object?>.from(item)))
        .toList(growable: false);
    final ancestorJson = json['ancestor'] as Map<Object?, Object?>?;
    final matchMode = json['matchMode'] == null
        ? CockpitTextMatchMode.exact
        : CockpitTextMatchMode.fromJson(json['matchMode']);
    final text = json['text'] as String?;
    final tooltip = json['tooltip'] as String?;
    if (matchMode != CockpitTextMatchMode.exact &&
        text == null &&
        tooltip == null) {
      throw const FormatException(
        'Locator matchMode requires a text or tooltip signal.',
      );
    }
    if (matchMode == CockpitTextMatchMode.regex) {
      for (final pattern in <String?>[text, tooltip]) {
        if (pattern != null) RegExp(pattern);
      }
    }

    return CockpitLocator(
      cockpitId: json['cockpitId'] as String?,
      semanticId: json['semanticId'] as String?,
      key: json['key'] as String?,
      text: text,
      tooltip: tooltip,
      type: json['type'] as String?,
      route: json['route'] as String?,
      registrationId: json['registrationId'] as String?,
      path: json['path'] as String?,
      matchMode: matchMode,
      index: (json['index'] as num?)?.toInt(),
      ancestor: ancestorJson == null
          ? null
          : CockpitLocator.fromJson(Map<String, Object?>.from(ancestorJson)),
      fallbacks: fallbacks,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitLocator &&
            const MapEquality<String, String>().equals(
              other.signalMap,
              signalMap,
            ) &&
            other.matchMode == matchMode &&
            other.index == index &&
            other.ancestor == ancestor &&
            _fallbackListEquality.equals(other.fallbacks, fallbacks);
  }

  @override
  int get hashCode => Object.hash(
    const MapEquality<String, String>().hash(signalMap),
    matchMode,
    index,
    ancestor,
    _fallbackListEquality.hash(fallbacks),
  );

  static String? _normalizeSignal(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
