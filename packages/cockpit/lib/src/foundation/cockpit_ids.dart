import 'dart:convert';
import 'dart:math';

enum CockpitIdKind { root, workspace, checkout, project, lease, cleanup }

extension CockpitIdKindPrefix on CockpitIdKind {
  String get prefix => switch (this) {
    CockpitIdKind.root => 'r',
    CockpitIdKind.workspace => 'w',
    CockpitIdKind.checkout => 'c',
    CockpitIdKind.project => 'p',
    CockpitIdKind.lease => 'l',
    CockpitIdKind.cleanup => 'x',
  };
}

const String _resourceIdAlphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
const int _resourceIdTokenLength = 10;

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

String _nextUniqueResourceIdToken(Random random, Set<String> issued) {
  for (var attempt = 0; attempt < 32; attempt += 1) {
    final token = _nextResourceIdToken(random);
    if (issued.add(token)) return token;
  }
  throw StateError('Could not generate a unique resource identifier.');
}

abstract interface class CockpitIdGenerator {
  String next(CockpitIdKind kind);
}

final class CockpitSecureIdGenerator implements CockpitIdGenerator {
  CockpitSecureIdGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;
  final Set<String> _issued = <String>{};

  @override
  String next(CockpitIdKind kind) {
    return '${kind.prefix}${_nextUniqueResourceIdToken(_random, _issued)}';
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

  String nextResourceId(String prefix) {
    if (prefix.length != 1 ||
        prefix.codeUnitAt(0) < 0x61 ||
        prefix.codeUnitAt(0) > 0x7a) {
      throw ArgumentError.value(prefix, 'prefix', 'Use one lowercase letter.');
    }
    return '$prefix${nextResourceIdToken()}';
  }
}

final class CockpitSecureTokenGenerator
    implements CockpitTokenGenerator, CockpitResourceIdTokenGenerator {
  CockpitSecureTokenGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;
  final Set<String> _issuedIds = <String>{};

  @override
  String nextIdToken() => _nextUniqueResourceIdToken(_random, _issuedIds);

  @override
  String nextToken({int byteLength = 32}) {
    if (byteLength < 16 || byteLength > 64) {
      throw ArgumentError.value(byteLength, 'byteLength');
    }
    final bytes = List<int>.generate(byteLength, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
