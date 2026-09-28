import 'package:intl/intl.dart';

import 'cockpit_locale.dart';

/// A parsed ICU MessageFormat message covering the subset that Flutter's
/// `gen_l10n` tooling emits for everyday ARB catalogs:
///
/// - `{name}` placeholders;
/// - `{count, plural, =1 {...} one {...} other {...}}` with exact `=N` cases,
///   the six CLDR categories, and `#` referring to the current number;
/// - `{who, select, keyword {...} other {...}}` keyword choices, which also
///   covers ICU `gender` phrasing;
/// - nested constructs inside branches;
/// - ICU apostrophe quoting: `'{`, `'}`, `'#'`, and `''` escape syntax
///   characters; a lone `'` is a literal apostrophe.
///
/// `selectordinal` is recognized but rejected: the `intl` rule engine carries
/// cardinal rules only, and guessing ordinal categories would silently
/// mis-render expectations.
///
/// Plural categories are resolved by `Intl.pluralLogic`, the same CLDR rule
/// engine behind generated `AppLocalizations` code, so a scenario and the app
/// it tests agree on which branch a number selects. Exact `=N` selectors and
/// `select` keyword matching follow the ICU specification; bare category
/// branches never act as exact-number matches.
final class CockpitIcuMessage {
  CockpitIcuMessage._(this._nodes, this.placeholders);

  factory CockpitIcuMessage.parse(String template, {String path = r'$'}) {
    final parser = _IcuParser(template, path);
    final nodes = parser.parseMessage();
    return CockpitIcuMessage._(
      List<_IcuNode>.unmodifiable(nodes),
      Set<String>.unmodifiable(parser.placeholders),
    );
  }

  final List<_IcuNode> _nodes;

  /// Every parameter name the message reads, including the argument of each
  /// `plural` and `select` construct.
  final Set<String> placeholders;

  /// Resolves the message against [params] for [locale].
  ///
  /// A missing parameter, a non-number plural argument, or a select keyword
  /// without a matching or `other` branch raises a [FormatException] naming
  /// the offending path.
  String format(
    Map<String, Object?> params, {
    required CockpitLocaleProfile locale,
  }) {
    final buffer = StringBuffer();
    _formatNodes(
      _nodes,
      params,
      locale: locale,
      path: r'$',
      pluralValue: null,
      buffer: buffer,
    );
    return buffer.toString();
  }
}

void _formatNodes(
  List<_IcuNode> nodes,
  Map<String, Object?> params, {
  required CockpitLocaleProfile locale,
  required String path,
  required num? pluralValue,
  required StringBuffer buffer,
}) {
  for (final node in nodes) {
    switch (node) {
      case _IcuText(text: final text):
        buffer.write(text);
      case _IcuPlaceholder(name: final name):
        if (!params.containsKey(name)) {
          throw FormatException(
            'No parameter "$name" was provided for the message.',
            path,
          );
        }
        buffer.write(_stringify(params[name]!));
      case _IcuNumber():
        if (pluralValue == null) {
          throw const FormatException(
            '"#" may only appear inside a plural branch.',
            r'$',
          );
        }
        buffer.write(_stringify(pluralValue));
      case _IcuPlural():
        final value = params[node.argument];
        if (value is! num) {
          throw FormatException(
            'The plural argument "${node.argument}" must be a number, got '
            '${value == null ? 'null' : value.runtimeType}.',
            path,
          );
        }
        final branch =
            node.exact[value.truncate()] ??
            Intl.pluralLogic<_IcuBranch>(
              value,
              zero: node.categories['zero'],
              one: node.categories['one'],
              two: node.categories['two'],
              few: node.categories['few'],
              many: node.categories['many'],
              other: node.categories['other']!,
              locale: _intlLocale(locale),
              useExplicitNumberCases: false,
            );
        _formatNodes(
          branch.nodes,
          params,
          locale: locale,
          path: path,
          pluralValue: value,
          buffer: buffer,
        );
      case _IcuSelect():
        final value = params[node.argument];
        final branch =
            (value == null ? null : node.branches['$value']) ??
            node.branches['other']!;
        _formatNodes(
          branch.nodes,
          params,
          locale: locale,
          path: path,
          pluralValue: pluralValue,
          buffer: buffer,
        );
    }
  }
}

String _stringify(Object value) {
  if (value is num) {
    return value.isFinite && value == value.truncate()
        ? value.truncate().toString()
        : value.toString();
  }
  return '$value';
}

/// intl identifies locales with underscore ids (`en_US`) and its plural rule
/// table keys by language — occasionally by region, never by script.
String _intlLocale(CockpitLocaleProfile locale) {
  final region = locale.regionCode;
  return region == null
      ? locale.languageCode
      : '${locale.languageCode}_$region';
}

sealed class _IcuNode {
  const _IcuNode();
}

final class _IcuText extends _IcuNode {
  const _IcuText(this.text);

  final String text;
}

final class _IcuPlaceholder extends _IcuNode {
  const _IcuPlaceholder(this.name);

  final String name;
}

final class _IcuNumber extends _IcuNode {
  const _IcuNumber();
}

final class _IcuBranch {
  const _IcuBranch(this.nodes);

  final List<_IcuNode> nodes;
}

final class _IcuPlural extends _IcuNode {
  const _IcuPlural(this.argument, this.exact, this.categories);

  final String argument;
  final Map<int, _IcuBranch> exact;
  final Map<String, _IcuBranch> categories;
}

final class _IcuSelect extends _IcuNode {
  const _IcuSelect(this.argument, this.branches);

  final String argument;
  final Map<String, _IcuBranch> branches;
}

final class _IcuParser {
  _IcuParser(this.source, this.path);

  final String source;
  final String path;
  final Set<String> placeholders = <String>{};
  int _index = 0;

  List<_IcuNode> parseMessage() {
    final nodes = <_IcuNode>[];
    final text = StringBuffer();
    while (_index < source.length) {
      final char = source[_index];
      switch (char) {
        case '{':
          _index++;
          _flushText(nodes, text);
          nodes.add(_parseConstruct(inPlural: false));
        case "'":
          _readQuotedLiteral(text);
        default:
          text.write(char);
          _index++;
      }
    }
    _flushText(nodes, text);
    return nodes;
  }

  /// Parses message content until the closing `}`, which is consumed.
  ///
  /// Inside a plural branch a `#` becomes a number reference; anywhere else it
  /// stays a literal.
  List<_IcuNode> _parseBranchContent({required bool inPlural}) {
    final nodes = <_IcuNode>[];
    final text = StringBuffer();
    while (_index < source.length) {
      final char = source[_index];
      if (char == '}') {
        _index++;
        _flushText(nodes, text);
        return nodes;
      }
      switch (char) {
        case '{':
          _index++;
          _flushText(nodes, text);
          nodes.add(_parseConstruct(inPlural: inPlural));
        case '#':
          if (inPlural) {
            _flushText(nodes, text);
            nodes.add(const _IcuNumber());
          } else {
            text.write('#');
          }
          _index++;
        case "'":
          _readQuotedLiteral(text);
        default:
          text.write(char);
          _index++;
      }
    }
    throw FormatException(
      'Unterminated message: expected "}".',
      '$path@$_index',
    );
  }

  /// Reads an ICU quoted literal: apostrophes delimit spans in which every
  /// character — including `{`, `}`, and `#` — is literal. An adjacent pair of
  /// apostrophes always means one apostrophe, and an unterminated span runs
  /// to the end of the message, exactly as ICU `MessagePattern` parses.
  void _readQuotedLiteral(StringBuffer text) {
    if (_index + 1 < source.length && source[_index + 1] == "'") {
      text.write("'");
      _index += 2;
      return;
    }
    _index++;
    while (_index < source.length) {
      final char = source[_index];
      if (char == "'") {
        if (_index + 1 < source.length && source[_index + 1] == "'") {
          text.write("'");
          _index += 2;
          continue;
        }
        _index++;
        return;
      }
      text.write(char);
      _index++;
    }
  }

  void _flushText(List<_IcuNode> nodes, StringBuffer text) {
    if (text.isNotEmpty) {
      nodes.add(_IcuText(text.toString()));
      text.clear();
    }
  }

  _IcuNode _parseConstruct({required bool inPlural}) {
    final start = _index;
    _skipWhitespace();
    final argument = _readIdentifier();
    if (argument.isEmpty) {
      throw FormatException('Expected a placeholder name.', '$path@$start');
    }
    _skipWhitespace();
    if (_consume('}')) {
      placeholders.add(argument);
      return _IcuPlaceholder(argument);
    }
    if (!_consume(',')) {
      throw FormatException(
        'Expected "}" or "," after "$argument".',
        '$path@$_index',
      );
    }
    _skipWhitespace();
    final keyword = _readIdentifier();
    switch (keyword) {
      case 'plural':
        placeholders.add(argument);
        return _parsePlural(argument, start);
      case 'select':
      case 'gender':
        placeholders.add(argument);
        return _parseSelect(argument, keyword, start, inPlural: inPlural);
      case 'selectordinal':
        throw FormatException(
          '"selectordinal" is not supported: the intl rule engine carries '
              'cardinal plural rules only. Rewrite the message with "plural" or '
              'resolve it through the app catalog.',
          '$path@$start',
        );
      default:
        throw FormatException(
          'Unknown construct "$keyword"; expected "plural" or "select".',
          '$path@$_index',
        );
    }
  }

  _IcuNode _parsePlural(String argument, int start) {
    if (!_consume(',')) {
      throw FormatException('Expected "," after "plural".', '$path@$_index');
    }
    final exact = <int, _IcuBranch>{};
    final categories = <String, _IcuBranch>{};
    while (true) {
      _skipWhitespace();
      if (_consume('}')) {
        break;
      }
      final selectorStart = _index;
      final selector = _readSelector();
      if (selector.isEmpty) {
        throw FormatException(
          'Expected a branch selector like "=1" or "other".',
          '$path@$_index',
        );
      }
      _skipWhitespace();
      _expectBranchOpen();
      final branch = _IcuBranch(
        List<_IcuNode>.unmodifiable(_parseBranchContent(inPlural: true)),
      );
      if (selector.startsWith('=')) {
        final value = int.tryParse(selector.substring(1));
        if (value == null) {
          throw FormatException(
            '"$selector" is not an exact-number selector; expected "=<int>".',
            '$path@$selectorStart',
          );
        }
        if (exact.containsKey(value)) {
          throw FormatException(
            'Duplicate exact selector "$selector".',
            '$path@$selectorStart',
          );
        }
        exact[value] = branch;
      } else if (_pluralCategories.contains(selector)) {
        if (categories.containsKey(selector)) {
          throw FormatException(
            'Duplicate branch "$selector".',
            '$path@$selectorStart',
          );
        }
        categories[selector] = branch;
      } else {
        throw FormatException(
          '"$selector" is not a plural category; expected one of '
              '${_pluralCategories.join(', ')}, or an exact "=N".',
          '$path@$selectorStart',
        );
      }
    }
    if (!categories.containsKey('other')) {
      throw FormatException(
        'The plural for "$argument" must define an "other" branch.',
        '$path@$start',
      );
    }
    return _IcuPlural(argument, exact, categories);
  }

  _IcuNode _parseSelect(
    String argument,
    String keyword,
    int start, {
    required bool inPlural,
  }) {
    if (!_consume(',')) {
      throw FormatException('Expected "," after "$keyword".', '$path@$_index');
    }
    final branches = <String, _IcuBranch>{};
    while (true) {
      _skipWhitespace();
      if (_consume('}')) {
        break;
      }
      final selectorStart = _index;
      final selector = _readSelector();
      if (selector.isEmpty) {
        throw FormatException('Expected a branch selector.', '$path@$_index');
      }
      _skipWhitespace();
      _expectBranchOpen();
      final branch = _IcuBranch(
        List<_IcuNode>.unmodifiable(_parseBranchContent(inPlural: inPlural)),
      );
      if (branches.containsKey(selector)) {
        throw FormatException(
          'Duplicate branch "$selector".',
          '$path@$selectorStart',
        );
      }
      branches[selector] = branch;
    }
    if (!branches.containsKey('other')) {
      throw FormatException(
        'The select for "$argument" must define an "other" branch.',
        '$path@$start',
      );
    }
    return _IcuSelect(argument, branches);
  }

  /// Consumes the `{` that opens a branch after its selector.
  void _expectBranchOpen() {
    if (_index >= source.length || source[_index] != '{') {
      throw FormatException('Expected "{" to open a branch.', '$path@$_index');
    }
    _index++;
  }

  /// Reads a branch selector: identifier characters, optionally led by `=`.
  String _readSelector() {
    final start = _index;
    if (_index < source.length && source[_index] == '=') {
      _index++;
    }
    while (_index < source.length && _isIdentifierChar(source[_index])) {
      _index++;
    }
    return source.substring(start, _index);
  }

  String _readIdentifier() {
    final start = _index;
    while (_index < source.length && _isIdentifierChar(source[_index])) {
      _index++;
    }
    return source.substring(start, _index);
  }

  void _skipWhitespace() {
    while (_index < source.length && source[_index].trim().isEmpty) {
      _index++;
    }
  }

  bool _consume(String expected) {
    if (source.startsWith(expected, _index)) {
      _index += expected.length;
      return true;
    }
    return false;
  }

  static bool _isIdentifierChar(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 97 && code <= 122) ||
        (code >= 65 && code <= 90) ||
        (code >= 48 && code <= 57) ||
        code == 95;
  }
}

const Set<String> _pluralCategories = <String>{
  'zero',
  'one',
  'two',
  'few',
  'many',
  'other',
};
