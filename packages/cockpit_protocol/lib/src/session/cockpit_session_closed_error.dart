/// Thrown when step recording targets a session that has already finished.
///
/// Extends [StateError] so callers written against earlier versions that
/// caught `StateError` keep working, while runtime observers can tolerate
/// session closure specifically without masking unrelated invariant errors.
final class CockpitSessionClosedError extends StateError {
  CockpitSessionClosedError() : super('Cockpit session is already closed.');
}
