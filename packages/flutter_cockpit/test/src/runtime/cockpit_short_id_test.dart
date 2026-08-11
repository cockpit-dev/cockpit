import 'package:flutter_cockpit/src/runtime/cockpit_short_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generates compact lowercase Base36 identifiers', () {
    final ids = <String>{
      for (var index = 0; index < 4096; index += 1) cockpitShortId('e'),
    };

    expect(ids, hasLength(4096));
    expect(ids, everyElement(matches(RegExp(r'^e[a-z0-9]{10}$'))));
  });
}
