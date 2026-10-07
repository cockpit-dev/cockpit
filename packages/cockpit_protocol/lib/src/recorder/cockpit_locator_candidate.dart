import '../foundation/cockpit_foundation_value_reader.dart';

const Set<String> _knownKinds = <String>{
  'key',
  'semanticId',
  'text',
  'tooltip',
  'type',
};

final class CockpitLocatorCandidate {
  /// Creates a CockpitLocatorCandidate.
  CockpitLocatorCandidate({
    required this.kind,
    required this.selector,
    required this.score,
  }) {
    if (!_knownKinds.contains(kind)) {
      throw ArgumentError.value(
        kind,
        'kind',
        'Expected one of ${_knownKinds.join(', ')}.',
      );
    }
    if (selector.isEmpty) {
      throw ArgumentError.value(selector, 'selector', 'Selector is empty.');
    }
  }

  /// Locator signal kind: `key`, `semanticId`, `text`, `tooltip`, or `type`.
  final String kind;

  /// Canonical `CockpitSelector.format` output for the matched signal.
  final String selector;

  /// Registry precedence score: 4 for `key` down to 0 for `type`.
  final int score;

  /// Encodes this CockpitLocatorCandidate as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'selector': selector,
    'score': score,
  };

  /// Decodes a CockpitLocatorCandidate from a JSON object.
  factory CockpitLocatorCandidate.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('Expected an object at $path.');
    }
    final json = Map<String, Object?>.from(value);
    for (final field in const <String>['kind', 'selector', 'score']) {
      if (!json.containsKey(field)) {
        throw FormatException('Missing required field $path.$field.');
      }
    }
    final kind = CockpitFoundationValueReader.string(
      json['kind'],
      '$path.kind',
    );
    if (!_knownKinds.contains(kind)) {
      throw FormatException(
        'Unsupported locator candidate kind "$kind" at $path.kind.',
      );
    }
    return CockpitLocatorCandidate(
      kind: kind,
      selector: CockpitFoundationValueReader.string(
        json['selector'],
        '$path.selector',
      ),
      score: CockpitFoundationValueReader.integer(json['score'], '$path.score'),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitLocatorCandidate &&
            other.kind == kind &&
            other.selector == selector &&
            other.score == score;
  }

  @override
  int get hashCode => Object.hash(kind, selector, score);
}
