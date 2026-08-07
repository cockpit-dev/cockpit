import 'dart:convert';

import 'cockpit_test_value_reader.dart';

final class CockpitTestMatrix {
  /// Creates a CockpitTestMatrix.
  CockpitTestMatrix({
    Map<String, List<Object?>> axes = const <String, List<Object?>>{},
    Iterable<Map<String, Object?>> include = const <Map<String, Object?>>[],
    Iterable<Map<String, Object?>> exclude = const <Map<String, Object?>>[],
    this.maxCombinations = 256,
  }) : axes = _axes(axes),
       include = _rows(include, r'$.include'),
       exclude = _rows(exclude, r'$.exclude') {
    if (maxCombinations < 1 || maxCombinations > 4096) {
      throw const FormatException(
        'Matrix maxCombinations must be between 1 and 4096.',
      );
    }
    _validateRows(this.include, r'$.include');
    _validateRows(this.exclude, r'$.exclude');
    var product = this.axes.isEmpty ? 1 : 1;
    for (final values in this.axes.values) {
      product *= values.length;
      if (product > maxCombinations) {
        throw const FormatException(
          'Matrix cartesian product exceeds its bound.',
        );
      }
    }
    if (product + this.include.length > maxCombinations) {
      throw const FormatException('Matrix expansion exceeds its bound.');
    }
  }

  static final empty = CockpitTestMatrix();

  final Map<String, List<Object?>> axes;
  final List<Map<String, Object?>> include;
  final List<Map<String, Object?>> exclude;
  final int maxCombinations;

  /// Encodes this CockpitTestMatrix as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'axes': axes,
    if (include.isNotEmpty) 'include': include,
    if (exclude.isNotEmpty) 'exclude': exclude,
    'maxCombinations': maxCombinations,
  };

  /// Decodes a CockpitTestMatrix from a JSON object.
  factory CockpitTestMatrix.fromJson(Object? value, {required String path}) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(json, const <String>{
      'axes',
      'include',
      'exclude',
      'maxCombinations',
    }, path);
    return CockpitTestMatrix(
      axes: json['axes'] == null
          ? const <String, List<Object?>>{}
          : _readAxes(json['axes'], '$path.axes'),
      include: _readRows(json['include'], '$path.include'),
      exclude: _readRows(json['exclude'], '$path.exclude'),
      maxCombinations: json['maxCombinations'] == null
          ? 256
          : CockpitTestValueReader.integer(
              json['maxCombinations'],
              '$path.maxCombinations',
              minimum: 1,
              maximum: 4096,
            ),
    );
  }

  void _validateRows(List<Map<String, Object?>> rows, String path) {
    final seen = <String>{};
    for (var index = 0; index < rows.length; index += 1) {
      final row = rows[index];
      for (final entry in row.entries) {
        final values = axes[entry.key];
        if (values == null) {
          throw FormatException(
            'Unknown matrix axis $path[$index].${entry.key}.',
          );
        }
        final encoded = _canonical(entry.value);
        if (!values.any((value) => _canonical(value) == encoded)) {
          throw FormatException(
            'Matrix row value is outside axis $path[$index].${entry.key}.',
          );
        }
      }
      if (!seen.add(_canonical(row))) {
        throw FormatException('Duplicate matrix row at $path[$index].');
      }
    }
  }
}

Map<String, List<Object?>> _readAxes(Object? value, String path) {
  final json = CockpitTestValueReader.object(value, path);
  return <String, List<Object?>>{
    for (final entry in json.entries)
      CockpitTestValueReader.string(entry.key, path, id: true): <Object?>[
        for (
          var index = 0;
          index <
              CockpitTestValueReader.list(
                entry.value,
                '$path.${entry.key}',
              ).length;
          index += 1
        )
          CockpitTestValueReader.jsonValue(
            CockpitTestValueReader.list(
              entry.value,
              '$path.${entry.key}',
            )[index],
            '$path.${entry.key}[$index]',
          ),
      ],
  };
}

List<Map<String, Object?>> _readRows(Object? value, String path) {
  if (value == null) return const <Map<String, Object?>>[];
  final raw = CockpitTestValueReader.list(value, path);
  return <Map<String, Object?>>[
    for (var index = 0; index < raw.length; index += 1)
      Map<String, Object?>.from(
        CockpitTestValueReader.object(
          CockpitTestValueReader.jsonValue(raw[index], '$path[$index]'),
          '$path[$index]',
        ),
      ),
  ];
}

Map<String, List<Object?>> _axes(Map<String, List<Object?>> source) {
  final result = <String, List<Object?>>{};
  for (final entry in source.entries) {
    final name = CockpitTestValueReader.string(entry.key, r'$.axes', id: true);
    if (entry.value.isEmpty || entry.value.length > 128) {
      throw FormatException('Matrix axis $name must contain 1 to 128 values.');
    }
    final values = <Object?>[];
    final seen = <String>{};
    for (var index = 0; index < entry.value.length; index += 1) {
      final value = CockpitTestValueReader.jsonValue(
        entry.value[index],
        '\$.axes.$name[$index]',
      );
      if (!seen.add(_canonical(value))) {
        throw FormatException(
          'Duplicate matrix value at \$.axes.$name[$index].',
        );
      }
      values.add(value);
    }
    result[name] = List<Object?>.unmodifiable(values);
  }
  return Map<String, List<Object?>>.unmodifiable(result);
}

List<Map<String, Object?>> _rows(
  Iterable<Map<String, Object?>> source,
  String path,
) => List<Map<String, Object?>>.unmodifiable(<Map<String, Object?>>[
  for (var index = 0; index < source.length; index += 1)
    Map<String, Object?>.unmodifiable(
      CockpitTestValueReader.object(
        CockpitTestValueReader.jsonValue(
          source.elementAt(index),
          '$path[$index]',
        ),
        '$path[$index]',
      ),
    ),
]);

String _canonical(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  Map<Object?, Object?> map => <String, Object?>{
    for (final key in map.keys.cast<String>().toList()..sort())
      key: _sorted(map[key]),
  },
  List<Object?> list => list.map(_sorted).toList(growable: false),
  _ => value,
};
