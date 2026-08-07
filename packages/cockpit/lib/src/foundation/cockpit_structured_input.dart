import 'dart:convert';

import 'package:lon/lon.dart' as lon_format;
import 'package:yaml/yaml.dart';

/// Decodes JSON, LON, or YAML into the same JSON-compatible value model.
Object? decodeCockpitStructuredInput(String source) {
  try {
    return jsonDecode(source);
  } on FormatException {
    try {
      return lon_format.lon.decode(source);
    } on FormatException {
      try {
        return jsonDecode(jsonEncode(loadYaml(source)));
      } on FormatException {
        throw const FormatException('Input must be valid LON, JSON, or YAML.');
      } on JsonUnsupportedObjectError {
        throw const FormatException(
          'YAML input must contain JSON-compatible values and string keys.',
        );
      }
    }
  }
}
