import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../test/cockpit_test_secret_resolver.dart';
import 'cockpit_worker_logger.dart';
import 'cockpit_worker_value_reader.dart';

abstract interface class CockpitWorkerSecretProvider {
  String get providerId;

  Future<String> resolve(String providerReference);
}

final class CockpitAllowedWorkerSecretResolver
    implements CockpitTestSecretResolver {
  CockpitAllowedWorkerSecretResolver({
    required Iterable<CockpitWorkerSecretProvider> providers,
    required Iterable<String> allowedProviderIds,
    required CockpitWorkerLogRedactor redactor,
  }) : _redactor = redactor,
       _allowedProviderIds = Set<String>.unmodifiable(allowedProviderIds),
       _providers = <String, CockpitWorkerSecretProvider>{} {
    for (final providerId in _allowedProviderIds) {
      workerId(providerId, r'$.allowedProviderIds[]');
    }
    for (final provider in providers) {
      workerId(provider.providerId, r'$.providers[].providerId');
      if (_providers.putIfAbsent(provider.providerId, () => provider) !=
          provider) {
        throw FormatException(
          'Duplicate worker secret provider ${provider.providerId}.',
        );
      }
    }
    if (!_providers.keys.toSet().containsAll(_allowedProviderIds)) {
      throw const FormatException(
        'An allowed worker secret provider is not configured.',
      );
    }
  }

  final Map<String, CockpitWorkerSecretProvider> _providers;
  final Set<String> _allowedProviderIds;
  final CockpitWorkerLogRedactor _redactor;

  @override
  Future<String> resolve(String reference) async {
    final separator = reference.indexOf(':');
    if (separator < 1 || separator == reference.length - 1) {
      throw CockpitTestSecretResolutionException(
        CockpitTestError(
          code: CockpitTestErrorCode.secretResolutionFailed,
          message: 'Secret reference does not name an allowed provider.',
        ),
      );
    }
    final providerId = reference.substring(0, separator);
    final providerReference = reference.substring(separator + 1);
    if (!_allowedProviderIds.contains(providerId) ||
        providerReference.length > 512) {
      throw CockpitTestSecretResolutionException(
        CockpitTestError(
          code: CockpitTestErrorCode.secretResolutionFailed,
          message: 'Secret reference does not name an allowed provider.',
        ),
      );
    }
    final value = await _providers[providerId]!.resolve(providerReference);
    if (value.isEmpty || value.length > 65536) {
      throw CockpitTestSecretResolutionException(
        CockpitTestError(
          code: CockpitTestErrorCode.secretResolutionFailed,
          message: 'Secret provider returned an invalid value.',
        ),
      );
    }
    _redactor.registerSensitiveValue(value);
    return value;
  }
}

final class CockpitEnvironmentSecretProvider
    implements CockpitWorkerSecretProvider {
  CockpitEnvironmentSecretProvider({
    required Iterable<String> allowedNames,
    this.allowAllNames = false,
    required Map<String, String> environment,
  }) : _allowedNames = Set<String>.unmodifiable(allowedNames),
       _environment = Map<String, String>.unmodifiable(environment) {
    for (final name in _allowedNames) {
      if (!_environmentName.hasMatch(name)) {
        throw const FormatException(
          'Allowed environment secret name is invalid.',
        );
      }
    }
  }

  static final RegExp _environmentName = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_]{0,127}$',
  );

  @override
  String get providerId => 'env';

  final Set<String> _allowedNames;
  final bool allowAllNames;
  final Map<String, String> _environment;

  @override
  Future<String> resolve(String providerReference) async {
    if (!_environmentName.hasMatch(providerReference) ||
        !allowAllNames && !_allowedNames.contains(providerReference)) {
      throw CockpitTestSecretResolutionException(
        CockpitTestError(
          code: CockpitTestErrorCode.secretResolutionFailed,
          message: 'Environment secret is not allowed for this worker.',
        ),
      );
    }
    final value = _environment[providerReference];
    if (value == null) {
      throw CockpitTestSecretResolutionException(
        CockpitTestError(
          code: CockpitTestErrorCode.secretResolutionFailed,
          message: 'Environment secret is unavailable.',
        ),
      );
    }
    return value;
  }
}
