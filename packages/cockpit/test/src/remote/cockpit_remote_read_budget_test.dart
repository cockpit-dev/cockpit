import 'dart:async';

import 'package:cockpit/src/remote/cockpit_remote_read_budget.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 9, 12);

  test('bounds child work while reserving response time', () {
    final budget = CockpitRemoteReadBudget(
      now.add(const Duration(seconds: 10)),
      utcNow: () => now,
    );

    expect(
      budget.bound(
        const Duration(seconds: 30),
        reserve: const Duration(seconds: 3),
      ),
      const Duration(seconds: 7),
    );
  });

  test('rejects child work when no response budget remains', () {
    final budget = CockpitRemoteReadBudget(
      now.add(const Duration(seconds: 2)),
      utcNow: () => now,
    );

    expect(
      () => budget.bound(
        const Duration(seconds: 30),
        reserve: const Duration(seconds: 3),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
