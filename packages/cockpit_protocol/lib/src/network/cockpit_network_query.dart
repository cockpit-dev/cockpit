import 'package:collection/collection.dart';

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
    return CockpitNetworkQuery(
      id: json['id'] as String?,
      before: json['before'] as String?,
      method: json['method'] as String?,
      uriContains: json['uriContains'] as String?,
      onlyFailures: json['onlyFailures'] as bool? ?? false,
      statusCodeAtLeast: json['statusCodeAtLeast'] as int?,
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
