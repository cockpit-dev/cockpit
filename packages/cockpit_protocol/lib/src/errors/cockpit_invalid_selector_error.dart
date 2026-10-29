/// Selector syntax error raised while filtering mounted targets. The remote
/// session endpoint turns this into a `400 invalidSelector` response so the
/// caller can correct the locator instead of seeing a generic transport error.
final class CockpitInvalidSelector implements Exception {
  /// Creates a selector error with a human-readable [message] and optional
  /// diagnostic [details].
  const CockpitInvalidSelector(
    this.message, {
    this.details = const <String, Object?>{},
  });

  /// Explanation for the invalid selector.
  final String message;

  /// Additional context the caller can use to fix the selector.
  final Map<String, Object?> details;

  @override
  String toString() => message;
}
