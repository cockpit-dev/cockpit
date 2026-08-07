import 'dart:convert';
import 'dart:math';

enum CockpitIdKind { root, workspace, checkout, project, lease, cleanup }

extension CockpitIdKindPrefix on CockpitIdKind {
  String get prefix => switch (this) {
    CockpitIdKind.root => 'rt',
    CockpitIdKind.workspace => 'ws',
    CockpitIdKind.checkout => 'co',
    CockpitIdKind.project => 'pj',
    CockpitIdKind.lease => 'le',
    CockpitIdKind.cleanup => 'cl',
  };
}

const String _resourceIdAlphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const int _resourceIdTokenLength = 16;

String _nextResourceIdToken(Random random) {
  final codeUnits = List<int>.generate(
    _resourceIdTokenLength,
    (_) => _resourceIdAlphabet.codeUnitAt(
      random.nextInt(_resourceIdAlphabet.length),
    ),
    growable: false,
  );
  return String.fromCharCodes(codeUnits);
}

abstract interface class CockpitIdGenerator {
  String next(CockpitIdKind kind);
}

final class CockpitSecureIdGenerator implements CockpitIdGenerator {
  CockpitSecureIdGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String next(CockpitIdKind kind) {
    return '${kind.prefix}-${_nextResourceIdToken(_random)}';
  }
}

abstract interface class CockpitTokenGenerator {
  String nextToken({int byteLength = 32});
}

abstract interface class CockpitResourceIdTokenGenerator {
  String nextIdToken();
}

extension CockpitResourceIdTokens on CockpitTokenGenerator {
  String nextResourceIdToken() {
    final generator = this;
    if (generator is CockpitResourceIdTokenGenerator) {
      return (generator as CockpitResourceIdTokenGenerator).nextIdToken();
    }
    return generator.nextToken(byteLength: 16);
  }
}

final class CockpitSecureTokenGenerator
    implements CockpitTokenGenerator, CockpitResourceIdTokenGenerator {
  CockpitSecureTokenGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String nextIdToken() => _nextResourceIdToken(_random);

  @override
  String nextToken({int byteLength = 32}) {
    if (byteLength < 16 || byteLength > 64) {
      throw ArgumentError.value(byteLength, 'byteLength');
    }
    final bytes = List<int>.generate(byteLength, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
