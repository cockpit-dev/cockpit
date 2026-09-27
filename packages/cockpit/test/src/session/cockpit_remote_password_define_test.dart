import 'package:cockpit/src/session/cockpit_remote_password_dart_define_file.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('the private define file feeds the protocol password define', () async {
    const password = 'unit-dev-password';
    final file = await CockpitRemotePasswordDartDefineFile.create(password);
    addTearDown(file.delete);

    final resolved = CockpitRemoteSessionConfiguration.resolve(
      defines: const <String, String>{
        'FLUTTER_COCKPIT_REMOTE_ENABLED': 'true',
        cockpitRemotePasswordDartDefineName: password,
      },
    );
    expect(resolved, isNotNull);
    expect(resolved!.enabled, isTrue);
    expect(resolved.password, password);
    expect(resolved.toJson(), isNot(contains('password')));
  });
}
