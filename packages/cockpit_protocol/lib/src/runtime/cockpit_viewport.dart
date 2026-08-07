final class CockpitViewportResizeRequest {
  /// Creates a CockpitViewportResizeRequest.
  const CockpitViewportResizeRequest({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;

  /// Encodes this CockpitViewportResizeRequest as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'width': width,
    'height': height,
  };

  /// Decodes a CockpitViewportResizeRequest from a JSON object.
  factory CockpitViewportResizeRequest.fromJson(Map<String, Object?> json) {
    final width = json['width'];
    final height = json['height'];
    if (width is! int || height is! int) {
      throw const FormatException(
        'Viewport width and height must be integers.',
      );
    }
    if (width < 200 || width > 8192 || height < 200 || height > 8192) {
      throw const FormatException(
        'Viewport width and height must be between 200 and 8192.',
      );
    }
    return CockpitViewportResizeRequest(width: width, height: height);
  }
}

final class CockpitViewportResizeResult {
  /// Creates a CockpitViewportResizeResult.
  CockpitViewportResizeResult({
    required this.available,
    required this.changed,
    required this.requestedWidth,
    required this.requestedHeight,
    required this.platform,
    this.logicalWidth,
    this.logicalHeight,
    this.physicalWidth,
    this.physicalHeight,
    this.devicePixelRatio,
    this.reason,
    List<String> alternatives = const <String>[],
  }) : alternatives = List<String>.unmodifiable(alternatives);

  final bool available;
  final bool changed;
  final int requestedWidth;
  final int requestedHeight;
  final String platform;
  final double? logicalWidth;
  final double? logicalHeight;
  final int? physicalWidth;
  final int? physicalHeight;
  final double? devicePixelRatio;
  final String? reason;
  final List<String> alternatives;

  /// Encodes this CockpitViewportResizeResult as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'available': available,
    'changed': changed,
    'requested': <String, Object?>{
      'logicalWidth': requestedWidth,
      'logicalHeight': requestedHeight,
    },
    'platform': platform,
    if (logicalWidth != null && logicalHeight != null)
      'logical': <String, Object?>{
        'width': logicalWidth,
        'height': logicalHeight,
      },
    if (physicalWidth != null && physicalHeight != null)
      'physical': <String, Object?>{
        'width': physicalWidth,
        'height': physicalHeight,
      },
    if (devicePixelRatio != null) 'devicePixelRatio': devicePixelRatio,
    if (reason != null) 'reason': reason,
    if (alternatives.isNotEmpty) 'alternatives': alternatives,
  };

  /// Decodes a CockpitViewportResizeResult from a JSON object.
  factory CockpitViewportResizeResult.fromJson(Map<String, Object?> json) {
    final requested = _object(json['requested'], 'requested');
    final logical = _optionalObject(json['logical'], 'logical');
    final physical = _optionalObject(json['physical'], 'physical');
    return CockpitViewportResizeResult(
      available: _boolean(json['available'], 'available'),
      changed: _boolean(json['changed'], 'changed'),
      requestedWidth: _integer(requested['logicalWidth'], 'logicalWidth'),
      requestedHeight: _integer(requested['logicalHeight'], 'logicalHeight'),
      platform: _string(json['platform'], 'platform'),
      logicalWidth: logical == null
          ? null
          : _number(logical['width'], 'logical.width'),
      logicalHeight: logical == null
          ? null
          : _number(logical['height'], 'logical.height'),
      physicalWidth: physical == null
          ? null
          : _integer(physical['width'], 'physical.width'),
      physicalHeight: physical == null
          ? null
          : _integer(physical['height'], 'physical.height'),
      devicePixelRatio: json['devicePixelRatio'] == null
          ? null
          : _number(json['devicePixelRatio'], 'devicePixelRatio'),
      reason: json['reason'] as String?,
      alternatives:
          (json['alternatives'] as List<Object?>? ?? const <Object?>[])
              .map((value) => _string(value, 'alternatives[]'))
              .toList(growable: false),
    );
  }
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$name must be an object.');
  }
  return Map<String, Object?>.from(value);
}

Map<String, Object?>? _optionalObject(Object? value, String name) =>
    value == null ? null : _object(value, name);

bool _boolean(Object? value, String name) {
  if (value is! bool) throw FormatException('$name must be a boolean.');
  return value;
}

int _integer(Object? value, String name) {
  if (value is! int) throw FormatException('$name must be an integer.');
  return value;
}

double _number(Object? value, String name) {
  if (value is! num) throw FormatException('$name must be a number.');
  return value.toDouble();
}

String _string(Object? value, String name) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$name must be a non-empty string.');
  }
  return value;
}
