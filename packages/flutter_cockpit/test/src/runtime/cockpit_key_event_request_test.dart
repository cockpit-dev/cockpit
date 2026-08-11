import 'package:flutter/services.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses logical and physical keys from json-like input', () {
    final request = CockpitKeyEventRequest.fromJson(const <String, Object?>{
      'logicalKey': 'enter',
      'physicalKey': 'enter',
      'character': '\n',
    });

    expect(request.logicalKey, LogicalKeyboardKey.enter);
    expect(request.physicalKey, PhysicalKeyboardKey.enter);
    expect(request.character, '\n');
  });

  test('accepts numeric key ids for logical key lookup', () {
    final request = CockpitKeyEventRequest.fromJson(<String, Object?>{
      'logicalKey': LogicalKeyboardKey.tab.keyId,
    });

    expect(request.logicalKey, LogicalKeyboardKey.tab);
    expect(request.physicalKey, isNotNull);
  });

  test('accepts compact and separated logical key names', () {
    for (final name in <String>['arrowLeft', 'arrow-left', 'arrow_left']) {
      final request = CockpitKeyEventRequest.fromJson(<String, Object?>{
        'logicalKey': name,
      });

      expect(request.logicalKey, LogicalKeyboardKey.arrowLeft);
      expect(request.physicalKey, PhysicalKeyboardKey.arrowLeft);
    }
  });
}
