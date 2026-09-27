final class CockpitRemoteSessionConfiguration {
  /// Creates a CockpitRemoteSessionConfiguration.
  const CockpitRemoteSessionConfiguration({
    required this.enabled,
    this.autoStart = true,
    this.host = '127.0.0.1',
    this.port = 47331,
    this.routePrefix = '',
    this.launchId = '',
    this.password = '',
    this.allowedOrigin,
  });

  final bool enabled;
  final bool autoStart;
  final String host;
  final int port;
  final String routePrefix;
  final String launchId;

  /// Password the remote boundary requires, chosen by the operator that
  /// started the session. Empty means the boundary accepts unauthenticated
  /// requests.
  final String password;
  final String? allowedOrigin;

  static const String _defaultHost = '127.0.0.1';
  static const int _defaultPort = 47331;
  static const String _defaultRoutePrefix = '';
  static const String _enabledDefine = 'FLUTTER_COCKPIT_REMOTE_ENABLED';
  static const String _hostDefine = 'FLUTTER_COCKPIT_REMOTE_HOST';
  static const String _portDefine = 'FLUTTER_COCKPIT_REMOTE_PORT';
  static const String _routePrefixDefine =
      'FLUTTER_COCKPIT_REMOTE_ROUTE_PREFIX';
  static const String _launchIdDefine = 'FLUTTER_COCKPIT_REMOTE_LAUNCH_ID';
  static const String _passwordDefine = 'FLUTTER_COCKPIT_REMOTE_PASSWORD';
  static const String _allowedOriginDefine =
      'FLUTTER_COCKPIT_REMOTE_ALLOWED_ORIGIN';

  Uri get baseUri =>
      Uri(scheme: 'http', host: host, port: port, path: _normalizedRoutePrefix);

  String get normalizedRoutePrefix => _normalizedRoutePrefix;

  String get _normalizedRoutePrefix {
    if (routePrefix.isEmpty || routePrefix == '/') {
      return '';
    }

    final withLeadingSlash = routePrefix.startsWith('/')
        ? routePrefix
        : '/$routePrefix';
    return withLeadingSlash.endsWith('/')
        ? withLeadingSlash.substring(0, withLeadingSlash.length - 1)
        : withLeadingSlash;
  }

  /// Encodes this CockpitRemoteSessionConfiguration as a public JSON object.
  Map<String, Object?> toJson() => _toJson(includePassword: false);

  /// Encodes owner-only runtime state, including the password.
  Map<String, Object?> toPrivateJson() => _toJson(includePassword: true);

  Map<String, Object?> _toJson({required bool includePassword}) =>
      <String, Object?>{
        'enabled': enabled,
        'autoStart': autoStart,
        'host': host,
        'port': port,
        'routePrefix': routePrefix,
        if (launchId.isNotEmpty) 'launchId': launchId,
        if (includePassword && password.isNotEmpty) 'password': password,
        if (allowedOrigin != null) 'allowedOrigin': allowedOrigin,
      };

  /// Decodes a CockpitRemoteSessionConfiguration from a JSON object.
  factory CockpitRemoteSessionConfiguration.fromJson(
    Map<String, Object?> json,
  ) {
    return CockpitRemoteSessionConfiguration(
      enabled: json['enabled'] as bool? ?? false,
      autoStart: json['autoStart'] as bool? ?? true,
      host: json['host'] as String? ?? _defaultHost,
      port: json['port'] as int? ?? _defaultPort,
      routePrefix: json['routePrefix'] as String? ?? _defaultRoutePrefix,
      launchId: json['launchId'] as String? ?? '',
      password: json['password'] as String? ?? '',
      allowedOrigin: json['allowedOrigin'] as String?,
    );
  }

  static CockpitRemoteSessionConfiguration? resolve({
    CockpitRemoteSessionConfiguration? fallback,
    Map<String, String> defines = const <String, String>{},
  }) {
    final hasAnyOverrides =
        defines.containsKey(_enabledDefine) ||
        defines.containsKey(_hostDefine) ||
        defines.containsKey(_portDefine) ||
        defines.containsKey(_routePrefixDefine) ||
        defines.containsKey(_launchIdDefine) ||
        defines.containsKey(_passwordDefine) ||
        defines.containsKey(_allowedOriginDefine);
    if (!hasAnyOverrides) {
      return fallback;
    }

    final enabled = _parseBool(defines[_enabledDefine]) ?? fallback?.enabled;
    if (fallback == null && enabled != true) {
      return null;
    }

    return CockpitRemoteSessionConfiguration(
      enabled: enabled ?? false,
      autoStart: fallback?.autoStart ?? true,
      host: _readString(defines[_hostDefine]) ?? fallback?.host ?? _defaultHost,
      port: _readInt(defines[_portDefine]) ?? fallback?.port ?? _defaultPort,
      routePrefix:
          _readString(defines[_routePrefixDefine]) ??
          fallback?.routePrefix ??
          _defaultRoutePrefix,
      launchId:
          _readString(defines[_launchIdDefine]) ?? fallback?.launchId ?? '',
      password:
          _readString(defines[_passwordDefine]) ?? fallback?.password ?? '',
      allowedOrigin:
          _readString(defines[_allowedOriginDefine]) ?? fallback?.allowedOrigin,
    );
  }

  static CockpitRemoteSessionConfiguration? resolveFromEnvironment({
    CockpitRemoteSessionConfiguration? fallback,
  }) {
    return resolve(fallback: fallback, defines: _currentDartDefines());
  }

  static Map<String, String> _currentDartDefines() {
    final values = <String, String>{
      _enabledDefine: const String.fromEnvironment(_enabledDefine),
      _hostDefine: const String.fromEnvironment(_hostDefine),
      _portDefine: const String.fromEnvironment(_portDefine),
      _routePrefixDefine: const String.fromEnvironment(_routePrefixDefine),
      _launchIdDefine: const String.fromEnvironment(_launchIdDefine),
      _passwordDefine: const String.fromEnvironment(_passwordDefine),
      _allowedOriginDefine: const String.fromEnvironment(_allowedOriginDefine),
    };
    values.removeWhere((_, value) => value.isEmpty);
    return values;
  }

  static bool? _parseBool(String? value) {
    final normalized = _readString(value)?.toLowerCase();
    if (normalized == null) {
      return null;
    }
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
    return null;
  }

  static int? _readInt(String? value) {
    final normalized = _readString(value);
    if (normalized == null) {
      return null;
    }
    return int.tryParse(normalized);
  }

  static String? _readString(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRemoteSessionConfiguration &&
            other.enabled == enabled &&
            other.autoStart == autoStart &&
            other.host == host &&
            other.port == port &&
            other.routePrefix == routePrefix &&
            other.launchId == launchId &&
            other.password == password &&
            other.allowedOrigin == allowedOrigin;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    autoStart,
    host,
    port,
    routePrefix,
    launchId,
    password,
    allowedOrigin,
  );
}
