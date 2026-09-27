import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test(
    'snapshot degradation round-trips and participates in value semantics',
    () {
      final snapshot = CockpitSnapshot(
        routeName: '/home',
        degradationReason: 'frameTimeout',
      );

      final decoded = CockpitSnapshot.fromJson(snapshot.toJson());

      expect(decoded, snapshot);
      expect(decoded.hashCode, snapshot.hashCode);
      expect(decoded.degradationReason, 'frameTimeout');
      expect(snapshot.copyWith(), snapshot);
      expect(snapshot.toJson()['degradationReason'], 'frameTimeout');
    },
  );

  test('healthy snapshots omit degradation from the wire format', () {
    final snapshot = CockpitSnapshot(routeName: '/home');

    expect(snapshot.degradationReason, isNull);
    expect(snapshot.toJson(), isNot(contains('degradationReason')));
  });
}
