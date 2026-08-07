import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test(
    'network diagnostics redact by default and allow explicit raw capture',
    () {
      const safe = CockpitHttpNetworkObserverConfiguration();
      const raw = CockpitHttpNetworkObserverConfiguration(redact: false);

      expect(safe.redact, isTrue);
      expect(raw.redact, isFalse);
      expect(safe, isNot(raw));
    },
  );
}
