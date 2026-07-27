import 'package:cockpit/src/foundation/cockpit_storage_key.dart';
import 'package:test/test.dart';

void main() {
  test('storage keys are deterministic, bounded, and identity-specific', () {
    final first = cockpitStorageKey('workspace_alpha');
    final repeated = cockpitStorageKey('workspace_alpha');
    final second = cockpitStorageKey('workspace_beta');

    expect(first, hasLength(22));
    expect(first, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(repeated, first);
    expect(second, isNot(first));
  });
}
