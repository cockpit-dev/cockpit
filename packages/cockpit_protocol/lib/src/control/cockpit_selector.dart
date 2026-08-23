import 'dart:convert';

import '../runtime/cockpit_target_ref.dart';
import 'cockpit_locator.dart';

/// Compact, deterministic syntax for one [CockpitLocator].
final class CockpitSelector {
  const CockpitSelector._();

  static const int maxLength = 4096;
  static const int maxDepth = 16;

  /// Whether [source] uses unambiguous selector syntax rather than free text.
  static bool isExplicit(String source) {
    final normalized = source.trim();
    if (normalized.isEmpty) return false;
    if (normalized.startsWith('#') ||
        normalized.startsWith(':') ||
        normalized.startsWith('@') ||
        normalized.startsWith('[') ||
        normalized.contains('>>') ||
        normalized.contains(':nth(')) {
      return true;
    }
    return RegExp(
      r'^[A-Za-z_$][A-Za-z0-9_.$]*\s*(?:#|@|\[(?:"|(?:id|sem|key|text|tip|type|route|path)\s*(?:=|\*=|~=)))',
    ).hasMatch(normalized);
  }

  /// Parses a selector into the typed locator used by every Cockpit executor.
  static CockpitLocator parse(String source) {
    final normalized = source.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Selector cannot be empty.');
    }
    if (normalized.length > maxLength) {
      throw const FormatException('Selector is too long.');
    }
    final segments = _split(normalized);
    if (segments.length > maxDepth) {
      throw const FormatException('Selector has too many ancestor scopes.');
    }
    if (segments.length > 1 &&
        segments.any((segment) => segment.startsWith(':'))) {
      throw const FormatException(
        'A live target ref cannot be used in an ancestor chain.',
      );
    }

    CockpitLocator? locator;
    for (var index = 0; index < segments.length; index += 1) {
      final segment = _SegmentParser(
        segments[index],
        bareType: index < segments.length - 1,
      ).parse();
      locator = _copy(segment, ancestor: locator);
    }
    return locator!;
  }

  /// Returns the shortest canonical selector that preserves [locator].
  static String format(CockpitLocator locator) {
    if (!locator.hasSignals) {
      throw const FormatException('Locator has no selector signals.');
    }
    if (locator.fallbacks.isNotEmpty) {
      throw const FormatException(
        'Selector does not encode locator fallbacks.',
      );
    }
    if (locator.ref != null) {
      if (locator.signals.length != 1 || locator.ancestor != null) {
        throw const FormatException(
          'A live target ref cannot be combined with other selector signals.',
        );
      }
      return ':${locator.ref}';
    }
    final chain = <CockpitLocator>[];
    CockpitLocator? current = locator;
    while (current != null) {
      if (chain.length == maxDepth) {
        throw const FormatException('Locator has too many ancestor scopes.');
      }
      if (current.registrationId != null) {
        throw const FormatException(
          'Selector does not encode internal registration IDs.',
        );
      }
      if (current.matchMode == CockpitTextMatchMode.regex) {
        throw const FormatException(
          'Selector does not encode regular-expression matching.',
        );
      }
      chain.add(current);
      current = current.ancestor;
    }
    return chain.reversed.indexed
        .map(
          (entry) =>
              _formatSegment(entry.$2, ancestor: entry.$1 < chain.length - 1),
        )
        .join(' >> ');
  }

  static List<String> _split(String source) {
    final segments = <String>[];
    var start = 0;
    var bracketDepth = 0;
    var quoted = false;
    var escaped = false;
    for (var index = 0; index < source.length; index += 1) {
      final unit = source.codeUnitAt(index);
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == 0x22) {
          quoted = false;
        }
        continue;
      }
      if (unit == 0x22) {
        quoted = true;
      } else if (unit == 0x5b) {
        bracketDepth += 1;
      } else if (unit == 0x5d) {
        bracketDepth -= 1;
        if (bracketDepth < 0) {
          throw FormatException('Unexpected ] at position $index.');
        }
      } else if (unit == 0x3e &&
          index + 1 < source.length &&
          source.codeUnitAt(index + 1) == 0x3e &&
          bracketDepth == 0) {
        final segment = source.substring(start, index).trim();
        if (segment.isEmpty) {
          throw FormatException('Empty selector before position $index.');
        }
        segments.add(segment);
        start = index + 2;
        index += 1;
      }
    }
    if (quoted) {
      throw const FormatException('Selector contains an unterminated string.');
    }
    if (bracketDepth != 0) {
      throw const FormatException('Selector contains an unterminated filter.');
    }
    final finalSegment = source.substring(start).trim();
    if (finalSegment.isEmpty) {
      throw const FormatException('Selector cannot end with >>.');
    }
    segments.add(finalSegment);
    return segments;
  }

  static CockpitLocator _copy(
    CockpitLocator locator, {
    required CockpitLocator? ancestor,
  }) => CockpitLocator(
    ref: locator.ref,
    cockpitId: locator.cockpitId,
    semanticId: locator.semanticId,
    key: locator.key,
    text: locator.text,
    tooltip: locator.tooltip,
    type: locator.type,
    route: locator.route,
    registrationId: locator.registrationId,
    path: locator.path,
    matchMode: locator.matchMode,
    index: locator.index,
    ancestor: ancestor,
  );
}

final class _SegmentParser {
  _SegmentParser(this.source, {required this.bareType});

  final String source;
  final bool bareType;
  var offset = 0;
  final _Fields fields = _Fields();

  CockpitLocator parse() {
    if (source.startsWith(':')) {
      return _reference();
    }
    final prefix = _readUntilSpecial().trim();
    if (offset == source.length) {
      if (prefix.isEmpty) _fail('Selector segment cannot be empty.');
      if (bareType) {
        fields.set('type', prefix);
      } else {
        fields.set('text', prefix);
      }
      return fields.locator();
    }
    if (prefix.isNotEmpty) {
      if (!_simpleType.hasMatch(prefix)) {
        _fail('Widget type "$prefix" is not valid.');
      }
      fields.set('type', prefix);
    }

    while (offset < source.length) {
      _skipSpaces();
      if (offset == source.length) break;
      if (_take('#')) {
        fields.set('cockpitId', _token('Cockpit ID'));
        continue;
      }
      if (_take('@')) {
        fields.set('key', _token('Flutter key'));
        continue;
      }
      if (_take('[')) {
        _filter();
        continue;
      }
      if (_take(':')) {
        _nth();
        _skipSpaces();
        if (offset != source.length) {
          _fail('Nothing may follow :nth().');
        }
        break;
      }
      _fail('Expected #id, @key, a filter, or :nth().');
    }
    return fields.locator();
  }

  CockpitLocator _reference() {
    offset = 1;
    final start = offset;
    while (offset < source.length &&
        RegExp(r'[A-Za-z0-9]').hasMatch(source[offset])) {
      offset += 1;
    }
    if (start == offset || offset != source.length) {
      _fail('Live target refs use : followed by letters or digits.');
    }
    final ref = source.substring(start, offset).toLowerCase();
    if (ref.length < cockpitTargetRefMinimumLength) {
      _fail(
        'Live target refs require at least '
        '$cockpitTargetRefMinimumLength characters.',
      );
    }
    return CockpitLocator(ref: ref);
  }

  String _readUntilSpecial() {
    final start = offset;
    while (offset < source.length &&
        !const <String>{'#', '@', '[', ':'}.contains(source[offset])) {
      offset += 1;
    }
    return source.substring(start, offset);
  }

  String _token(String label) {
    final start = offset;
    while (offset < source.length &&
        !RegExp(r'[\s#@\[:]').hasMatch(source[offset])) {
      offset += 1;
    }
    if (start == offset) _fail('$label cannot be empty.');
    return source.substring(start, offset);
  }

  void _filter() {
    _skipSpaces();
    String? name;
    final operatorStart = offset;
    while (offset < source.length &&
        RegExp(r'[A-Za-z]').hasMatch(source[offset])) {
      offset += 1;
    }
    if (offset > operatorStart) {
      name = source.substring(operatorStart, offset).toLowerCase();
      _skipSpaces();
    }
    final mode = name == null && offset < source.length && source[offset] == '"'
        ? CockpitTextMatchMode.exact
        : _operator();
    _skipSpaces();
    final value = _string();
    _skipSpaces();
    _expect(']', 'Filter must end with ].');

    if (name == null) {
      fields.setText('text', value, mode);
      return;
    }
    switch (name) {
      case 'id':
        _exactOnly(name, mode);
        fields.set('cockpitId', value);
        return;
      case 'sem':
        fields.setText('semanticId', value, mode);
        return;
      case 'key':
        _exactOnly(name, mode);
        fields.set('key', value);
        return;
      case 'text':
        fields.setText('text', value, mode);
        return;
      case 'tip':
        fields.setText('tooltip', value, mode);
        return;
      case 'type':
        _exactOnly(name, mode);
        fields.set('type', value);
        return;
      case 'route':
        _exactOnly(name, mode);
        fields.set('route', value);
        return;
      case 'path':
        _exactOnly(name, mode);
        fields.set('path', value);
        return;
      default:
        _fail('Unknown selector field "$name".');
    }
  }

  CockpitTextMatchMode _operator() {
    if (_take('*=')) return CockpitTextMatchMode.contains;
    if (_take('~=')) return CockpitTextMatchMode.fuzzy;
    if (_take('=')) return CockpitTextMatchMode.exact;
    _fail('Expected =, *=, or ~=.');
  }

  String _string() {
    if (offset >= source.length || source[offset] != '"') {
      _fail('Selector values must be JSON strings.');
    }
    final start = offset;
    offset += 1;
    var escaped = false;
    while (offset < source.length) {
      final unit = source.codeUnitAt(offset);
      offset += 1;
      if (escaped) {
        escaped = false;
      } else if (unit == 0x5c) {
        escaped = true;
      } else if (unit == 0x22) {
        final encoded = source.substring(start, offset);
        final value = jsonDecode(encoded);
        if (value is! String || value.trim().isEmpty) {
          _fail('Selector values cannot be empty.');
        }
        return value;
      }
    }
    _fail('Selector contains an unterminated string.');
  }

  void _nth() {
    const prefix = 'nth(';
    if (!source.startsWith(prefix, offset)) {
      _fail('Only :nth(N) is supported.');
    }
    offset += prefix.length;
    final start = offset;
    while (offset < source.length &&
        RegExp(r'[0-9]').hasMatch(source[offset])) {
      offset += 1;
    }
    if (start == offset) _fail(':nth() requires a positive integer.');
    final ordinal = int.parse(source.substring(start, offset));
    if (ordinal < 1) _fail(':nth() is 1-based.');
    _expect(')', ':nth() must end with ).');
    fields.index = ordinal - 1;
  }

  void _exactOnly(String name, CockpitTextMatchMode mode) {
    if (mode != CockpitTextMatchMode.exact) {
      _fail('$name supports exact matching only.');
    }
  }

  bool _take(String value) {
    if (!source.startsWith(value, offset)) return false;
    offset += value.length;
    return true;
  }

  void _expect(String value, String message) {
    if (!_take(value)) _fail(message);
  }

  void _skipSpaces() {
    while (offset < source.length && RegExp(r'\s').hasMatch(source[offset])) {
      offset += 1;
    }
  }

  Never _fail(String message) {
    throw FormatException('$message (position $offset in "$source")');
  }
}

final class _Fields {
  final values = <String, String>{};
  CockpitTextMatchMode matchMode = CockpitTextMatchMode.exact;
  int? index;

  void set(String name, String value) {
    if (values.containsKey(name)) {
      throw FormatException('Selector field "$name" is repeated.');
    }
    values[name] = value;
  }

  void setText(String name, String value, CockpitTextMatchMode mode) {
    if (values.containsKey(name)) {
      throw FormatException('Selector field "$name" is repeated.');
    }
    final alreadyHasText =
        values.containsKey('semanticId') ||
        values.containsKey('text') ||
        values.containsKey('tooltip');
    if (alreadyHasText && matchMode != mode) {
      throw const FormatException(
        'Semantic, text, and tooltip filters must use the same match operator.',
      );
    }
    matchMode = mode;
    values[name] = value;
  }

  CockpitLocator locator() {
    if (values.isEmpty) {
      throw const FormatException('Selector segment has no conditions.');
    }
    return CockpitLocator(
      cockpitId: values['cockpitId'],
      semanticId: values['semanticId'],
      key: values['key'],
      text: values['text'],
      tooltip: values['tooltip'],
      type: values['type'],
      route: values['route'],
      registrationId: values['registrationId'],
      path: values['path'],
      matchMode: matchMode,
      index: index,
    );
  }
}

String _formatSegment(CockpitLocator locator, {required bool ancestor}) {
  final parts = <String>[];
  final signals = locator.signalMap;
  final type = signals[CockpitLocatorKind.type.name];
  final signalCount = signals.length;
  final prefixType =
      type != null &&
      _simpleType.hasMatch(type) &&
      (ancestor || signalCount > 1);
  if (prefixType) parts.add(type);

  final cockpitId = signals[CockpitLocatorKind.cockpitId.name];
  if (cockpitId != null && _simpleToken.hasMatch(cockpitId)) {
    parts.add('#$cockpitId');
  }
  final key = signals[CockpitLocatorKind.key.name];
  if (key != null && cockpitId == null && _simpleToken.hasMatch(key)) {
    parts.add('@$key');
  }

  final text = signals[CockpitLocatorKind.text.name];
  final onlyPlainText =
      !ancestor &&
      signalCount == 1 &&
      text != null &&
      locator.matchMode == CockpitTextMatchMode.exact &&
      locator.index == null &&
      _plainText(text);
  if (onlyPlainText) return text;

  if (cockpitId != null && !_simpleToken.hasMatch(cockpitId)) {
    parts.add(_filter('id', cockpitId));
  }
  final semanticId = signals[CockpitLocatorKind.semanticId.name];
  if (semanticId != null) {
    parts.add(_filter('sem', semanticId, mode: locator.matchMode));
  }
  if (key != null && (cockpitId != null || !_simpleToken.hasMatch(key))) {
    parts.add(_filter('key', key));
  }
  if (text != null) {
    parts.add(_filter('', text, mode: locator.matchMode));
  }
  final tooltip = signals[CockpitLocatorKind.tooltip.name];
  if (tooltip != null) {
    parts.add(_filter('tip', tooltip, mode: locator.matchMode));
  }
  if (type != null && !prefixType) parts.add(_filter('type', type));
  final route = signals[CockpitLocatorKind.route.name];
  if (route != null) parts.add(_filter('route', route));
  final path = signals[CockpitLocatorKind.path.name];
  if (path != null) parts.add(_filter('path', path));
  if (locator.index case final index?) parts.add(':nth(${index + 1})');
  return parts.join();
}

String _filter(
  String name,
  String value, {
  CockpitTextMatchMode mode = CockpitTextMatchMode.exact,
}) {
  final operator = switch (mode) {
    CockpitTextMatchMode.exact => '=',
    CockpitTextMatchMode.contains => '*=',
    CockpitTextMatchMode.fuzzy => '~=',
    CockpitTextMatchMode.regex => throw const FormatException(
      'Selector does not encode regular-expression matching.',
    ),
  };
  final effectiveOperator = name.isEmpty && mode == CockpitTextMatchMode.exact
      ? ''
      : operator;
  return '[$name$effectiveOperator${jsonEncode(value)}]';
}

bool _plainText(String value) =>
    value.trim() == value &&
    value.isNotEmpty &&
    !value.contains(RegExp(r'[#@\[\]:]')) &&
    !value.contains('>>') &&
    !value.contains(RegExp(r'[\x00-\x1f]'));

final RegExp _simpleToken = RegExp(r'^[A-Za-z0-9_.-]+$');
final RegExp _simpleType = RegExp(r'^[A-Za-z_$][A-Za-z0-9_.$]*$');
