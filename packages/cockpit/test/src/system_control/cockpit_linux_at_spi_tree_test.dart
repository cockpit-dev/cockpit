import 'package:cockpit/src/system_control/cockpit_linux_at_spi_tree.dart';
import 'package:dbus/dbus.dart';
import 'package:test/test.dart';

void main() {
  test('reads AT-SPI interfaces through the protocol method', () async {
    String? capturedInterface;
    String? capturedMethod;
    List<DBusValue>? capturedValues;
    DBusSignature? capturedReplySignature;

    final interfaces = await cockpitReadLinuxAtSpiInterfaces((
      interface,
      method,
      values, {
      replySignature,
    }) async {
      capturedInterface = interface;
      capturedMethod = method;
      capturedValues = values;
      capturedReplySignature = replySignature;
      return DBusMethodSuccessResponse(<DBusValue>[
        DBusArray.string(<String>[
          'org.a11y.atspi.Component',
          'org.a11y.atspi.Action',
        ]),
      ]);
    });

    expect(capturedInterface, 'org.a11y.atspi.Accessible');
    expect(capturedMethod, 'GetInterfaces');
    expect(capturedValues, isEmpty);
    expect(capturedReplySignature, DBusSignature('as'));
    expect(interfaces, <String>{'Component', 'Action'});
  });

  test(
    'falls back to canonical AT-SPI role when role names are unavailable',
    () async {
      final calls = <String>[];

      final role = await cockpitReadLinuxAtSpiRole((
        interface,
        method,
        values, {
        replySignature,
      }) async {
        calls.add(method);
        if (method == 'GetRoleName') throw StateError('optional method absent');
        expect(interface, 'org.a11y.atspi.Accessible');
        expect(values, isEmpty);
        expect(replySignature, DBusSignature('u'));
        return DBusMethodSuccessResponse(<DBusValue>[DBusUint32(43)]);
      });

      expect(calls, <String>['GetRoleName', 'GetRole']);
      expect(role, 'button');
    },
  );
}
