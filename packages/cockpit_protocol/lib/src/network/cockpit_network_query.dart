import 'package:collection/collection.dart';

import '../foundation/cockpit_foundation_value_reader.dart';

final class CockpitNetworkQuery {
  /// Creates a CockpitNetworkQuery.
  const CockpitNetworkQuery({
    this.id,
    this.before,
    this.method,
    this.uriContains,
    this.onlyFailures = false,
    this.statusCodeAtLeast,
  });

  final String? id;
  final String? before;
  final String? method;
  final String? uriContains;
  final bool onlyFailures;
  final int? statusCodeAtLeast;

  static const MapEquality<String, Object?> _mapEquality =
      MapEquality<String, Object?>();

  bool get isEmpty =>
      (id == null || id!.isEmpty) &&
      (before == null || before!.isEmpty) &&
      (method == null || method!.isEmpty) &&
      (uriContains == null || uriContains!.isEmpty) &&
      !onlyFailures &&
      statusCodeAtLeast == null;

  /// Encodes this CockpitNetworkQuery as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    if (id != null) 'id': id,
    if (before != null) 'before': before,
    if (method != null) 'method': method,
    if (uriContains != null) 'uriContains': uriContains,
    'onlyFailures': onlyFailures,
    if (statusCodeAtLeast != null) 'statusCodeAtLeast': statusCodeAtLeast,
  };

  /// Decodes a CockpitNetworkQuery from a JSON object.
  factory CockpitNetworkQuery.fromJson(Map<String, Object?> json) {
    CockpitFoundationValueReader.keys(json, const <String>{
      'id',
      'before',
      'method',
      'uriContains',
      'onlyFailures',
      'statusCodeAtLeast',
    }, r'$');
    return CockpitNetworkQuery(
      id: _requestId(json['id'], r'$.id'),
      before: _requestId(json['before'], r'$.before'),
      method: json['method'] == null
          ? null
          : CockpitFoundationValueReader.string(
              json['method'],
              r'$.method',
              maximum: 32,
            ),
      uriContains: json['uriContains'] == null
          ? null
          : CockpitFoundationValueReader.string(
              json['uriContains'],
              r'$.uriContains',
              maximum: 512,
            ),
      onlyFailures: json['onlyFailures'] == null
          ? false
          : CockpitFoundationValueReader.boolean(
              json['onlyFailures'],
              r'$.onlyFailures',
            ),
      statusCodeAtLeast: json['statusCodeAtLeast'] == null
          ? null
          : CockpitFoundationValueReader.integer(
              json['statusCodeAtLeast'],
              r'$.statusCodeAtLeast',
              min: 100,
              max: 599,
            ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitNetworkQuery &&
            _mapEquality.equals(other.toJson(), toJson());
  }

  @override
  int get hashCode => _mapEquality.hash(toJson());
}

String? _requestId(Object? value, String path) {
  if (value == null) return null;
  final result = CockpitFoundationValueReader.string(value, path, maximum: 19);
  if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(result)) {
    throw FormatException('Expected a numeric network request id at $path.');
  }
  return result;
}
