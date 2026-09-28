import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/session/cockpit_remote_auth_dart_define_file.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('the private define file feeds the protocol auth define', () async {
    const authToken = 'unit-dev-auth-token';
    final file = await CockpitRemoteAuthDartDefineFile.create(authToken);
    addTearDown(file.delete);

    final written =
        jsonDecode(File(file.path).readAsStringSync()) as Map<String, Object?>;
    final resolved = CockpitRemoteSessionConfiguration.resolve(
      defines: <String, String>{
        'FLUTTER_COCKPIT_REMOTE_ENABLED': 'true',
        ...written.cast<String, String>(),
      },
    );
    expect(resolved, isNotNull);
    expect(resolved!.enabled, isTrue);
    expect(resolved.authToken, authToken);
    expect(resolved.toJson().keys, isNot(contains('authToken')));
  });
}
