import 'dart:math';

const String _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
const int _tokenLength = 10;

final Random _random = Random.secure();
final Set<String> _issued = <String>{};

String cockpitShortId(String prefix) {
  if (prefix.length != 1 ||
      prefix.codeUnitAt(0) < 0x61 ||
      prefix.codeUnitAt(0) > 0x7a) {
    throw ArgumentError.value(prefix, 'prefix', 'Use one lowercase letter.');
  }
  for (var attempt = 0; attempt < 32; attempt += 1) {
    final token = String.fromCharCodes(
      List<int>.generate(
        _tokenLength,
        (_) => _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
        growable: false,
      ),
    );
    final id = '$prefix$token';
    if (_issued.add(id)) return id;
  }
  throw StateError('Could not generate a unique resource identifier.');
}
