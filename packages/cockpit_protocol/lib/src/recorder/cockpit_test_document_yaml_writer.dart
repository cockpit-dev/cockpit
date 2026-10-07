/// Renders a `cockpit.test/v2` document ([CockpitTestCase.toJson] output) to
/// YAML.
///
/// Write-only, hand-rolled, and dependency-free: the protocol package never
/// gains a YAML dependency for rendering. The output is deterministic — the
/// same map always renders to the identical string, with map keys emitted in
/// insertion order and list items in list order.
///
/// Scope and conventions:
///
/// - Values are the JSON value shapes (`null`, `bool`, `int`, `double`,
///   `String`, `List`, `Map`). Anything else is a caller bug and throws.
/// - Maps render as block mappings, lists as block sequences; empty
///   collections render as flow `[]` / `{}`.
/// - Strings render plain when safe and double-quoted otherwise (see
///   [_needsQuotes]). Multi-line strings never use block scalars: embedded
///   newlines are escaped as `\n`, so every rendered value stays on one line
///   and line-based source maps remain stable.
final class CockpitTestDocumentYamlWriter {
  /// Creates a CockpitTestDocumentYamlWriter.
  const CockpitTestDocumentYamlWriter();

  /// Renders [document] to a YAML string.
  String write(Map<String, Object?> document) {
    final buffer = StringBuffer();
    _writeMap(document, buffer, indent: 0);
    return buffer.toString();
  }

  void _writeMap(
    Map<String, Object?> map,
    StringBuffer buffer, {
    required int indent,
  }) {
    for (final entry in map.entries) {
      _writeEntry(entry.key, entry.value, buffer, indent: indent);
    }
  }

  void _writeEntry(
    String key,
    Object? value,
    StringBuffer buffer, {
    required int indent,
  }) {
    buffer.write(' ' * indent);
    _writeEntryContent(key, value, buffer, indent: indent);
  }

  /// Writes `key: value` without leading padding, so callers control the
  /// line start (inline after `- ` or padded by [_writeEntry]).
  void _writeEntryContent(
    String key,
    Object? value,
    StringBuffer buffer, {
    required int indent,
  }) {
    buffer.write(_scalar(key));
    buffer.write(':');
    switch (value) {
      case Map<String, Object?>() when value.isEmpty:
        buffer.writeln(' {}');
      case Map<String, Object?>():
        buffer.writeln();
        _writeMap(value, buffer, indent: indent + 2);
      case List<Object?>() when value.isEmpty:
        buffer.writeln(' []');
      case List<Object?>():
        buffer.writeln();
        _writeList(value, buffer, indent: indent);
      default:
        buffer.write(' ');
        buffer.write(_scalarValue(value));
        buffer.writeln();
    }
  }

  /// List items sit at the same indentation as the key owning the list.
  void _writeList(
    List<Object?> list,
    StringBuffer buffer, {
    required int indent,
  }) {
    final padding = ' ' * indent;
    for (final item in list) {
      buffer.write(padding);
      buffer.write('-');
      switch (item) {
        case Map<String, Object?>() when item.isEmpty:
          buffer.writeln(' {}');
        case Map<String, Object?>():
          buffer.write(' ');
          _writeInlineMap(item, buffer, indent: indent + 2);
        case List<Object?>() when item.isEmpty:
          buffer.writeln(' []');
        case List<Object?>():
          buffer.writeln();
          _writeList(item, buffer, indent: indent + 2);
        default:
          buffer.write(' ');
          buffer.write(_scalarValue(item));
          buffer.writeln();
      }
    }
  }

  /// Writes a map that starts inline after a sequence indicator: the first
  /// key follows the `- `, the remaining keys sit at [indent].
  void _writeInlineMap(
    Map<String, Object?> map,
    StringBuffer buffer, {
    required int indent,
  }) {
    var first = true;
    for (final entry in map.entries) {
      if (!first) {
        buffer.write(' ' * indent);
      }
      first = false;
      _writeEntryContent(entry.key, entry.value, buffer, indent: indent);
    }
  }

  String _scalarValue(Object? value) {
    if (value == null) return 'null';
    if (value is bool) return value ? 'true' : 'false';
    if (value is int) return value.toString();
    if (value is double) {
      if (!value.isFinite) {
        throw ArgumentError.value(value, 'document', 'Non-finite number.');
      }
      // Dart doubles always print with a fraction or exponent, so they can
      // never be mistaken for YAML integers.
      return value.toString();
    }
    if (value is String) return _scalar(value);
    throw ArgumentError.value(
      value,
      'document',
      'Unsupported YAML value of type ${value.runtimeType}.',
    );
  }

  String _scalar(String value) => _needsQuotes(value) ? _quote(value) : value;

  static final RegExp _ambiguousPlainScalar = RegExp(
    '^(?:null|true|false|yes|no|on|off|~)\$',
    caseSensitive: false,
  );
  static final RegExp _yamlNumber = RegExp(
    '^(?:[-+]?(?:0|[1-9][0-9]*|0[0-7]+|0[xX][0-9a-fA-F]+)'
    r'(?:\.[0-9]*)?(?:[eE][-+]?[0-9]+)?'
    r'|[-+]?\.(?:inf|Inf|INF)|\.(?:nan|NaN|NAN))$',
  );

  /// Whether [value] must be quoted to survive a plain-scalar round trip.
  /// Deliberately conservative: an unnecessary quote is harmless, a missing
  /// one silently changes the value's type or truncates the document.
  bool _needsQuotes(String value) {
    if (value.isEmpty) return true;
    if (value != value.trim()) return true;
    // Indicator characters are unsafe at the start of a plain scalar.
    const leadingIndicators = '#,[]{}&*!|>%@\'"`';
    final first = value[0];
    if (leadingIndicators.contains(first)) return true;
    if ((first == '-' || first == '?' || first == ':') &&
        (value.length == 1 || value[1] == ' ')) {
      return true;
    }
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (unit < 0x20) return true;
      if (unit == 0x22 || unit == 0x5c) return true;
    }
    if (value.contains(': ') || value.endsWith(':')) return true;
    if (value.contains(' #')) return true;
    if (_ambiguousPlainScalar.hasMatch(value)) return true;
    if (_yamlNumber.hasMatch(value)) return true;
    return false;
  }

  String _quote(String value) {
    final buffer = StringBuffer('"');
    for (final rune in value.runes) {
      switch (rune) {
        case 0x22:
          buffer.write(r'\"');
        case 0x5c:
          buffer.write(r'\\');
        case 0x0a:
          buffer.write(r'\n');
        case 0x0d:
          buffer.write(r'\r');
        case 0x09:
          buffer.write(r'\t');
        case _:
          if (rune < 0x20 || rune == 0x7f) {
            buffer.write(r'\u');
            buffer.write(rune.toRadixString(16).padLeft(4, '0'));
          } else {
            buffer.writeCharCode(rune);
          }
      }
    }
    buffer.write('"');
    return buffer.toString();
  }
}
