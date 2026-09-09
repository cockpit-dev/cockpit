import 'dart:math';

const String _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
const int _tokenLength = 10;
const int _tokenSpace = 3656158440062976; // 36^10

final Random _random = Random.secure();
int _nextToken =
    ((_random.nextInt(1 << 26) << 26) | _random.nextInt(1 << 26)) % _tokenSpace;

String cockpitShortId(String prefix) {
  if (prefix.length != 1 ||
      prefix.codeUnitAt(0) < 0x61 ||
      prefix.codeUnitAt(0) > 0x7a) {
    throw ArgumentError.value(prefix, 'prefix', 'Use one lowercase letter.');
  }
  final value = _nextToken;
  _nextToken = (_nextToken + 1) % _tokenSpace;
  var remaining = value;
  final units = List<int>.filled(_tokenLength, _alphabet.codeUnitAt(0));
  for (var index = _tokenLength - 1; index >= 0; index -= 1) {
    units[index] = _alphabet.codeUnitAt(remaining % _alphabet.length);
    remaining ~/= _alphabet.length;
  }
  return '$prefix${String.fromCharCodes(units)}';
}
